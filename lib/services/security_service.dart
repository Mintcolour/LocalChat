import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import 'identity_service.dart';

class SecurityService {
  SecurityService(this._identityService);

  final IdentityService _identityService;
  final _signing = Ed25519();
  final _exchange = X25519();
  final _cipher = AesGcm.with256bits();
  final Set<String> _seenNonces = <String>{};

  Future<Map<String, Object?>> seal(Device peer, Map<String, Object?> payload) async {
    final identity = _identityService.identity;
    final nonce = _cipher.newNonce();
    final secretKey = await _sharedSecret(peer);
    final secretBox = await _cipher.encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
      nonce: nonce,
    );
    final envelope = SecureEnvelope(
      senderDeviceId: identity.deviceId,
      recipientDeviceId: peer.id,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      nonce: randomNonce(),
      cipherNonce: b64(secretBox.nonce),
      cipherText: b64(secretBox.cipherText),
      cipherMac: b64(secretBox.mac.bytes),
      signature: '',
    );
    final signedPayload = envelope.toSignedPayload();
    final signature = await _signing.sign(
      utf8.encode(jsonEncode(signedPayload)),
      keyPair: _identityService.signingKeyPair,
    );
    return {
      ...signedPayload,
      'signature': b64(signature.bytes),
    };
  }

  Future<Map<String, Object?>> open(Device peer, Map<String, Object?> json) async {
    final envelope = SecureEnvelope.fromJson(json);
    if (envelope.recipientDeviceId != _identityService.identity.deviceId) {
      throw const FormatException('Envelope recipient does not match this device.');
    }
    if (envelope.senderDeviceId != peer.id) {
      throw const FormatException('Envelope sender does not match peer.');
    }
    final age = DateTime.now().millisecondsSinceEpoch - envelope.timestamp;
    if (age.abs() > const Duration(minutes: 10).inMilliseconds) {
      throw const FormatException('Envelope timestamp is outside the allowed window.');
    }
    final nonceKey = '${peer.id}:${envelope.nonce}';
    if (_seenNonces.contains(nonceKey)) {
      throw const FormatException('Envelope nonce was already used.');
    }
    final publicKey = SimplePublicKey(unb64(peer.signingPublicKey), type: KeyPairType.ed25519);
    final ok = await _signing.verify(
      utf8.encode(jsonEncode(envelope.toSignedPayload())),
      signature: Signature(unb64(envelope.signature), publicKey: publicKey),
    );
    if (!ok) throw const FormatException('Envelope signature is invalid.');
    _seenNonces.add(nonceKey);
    final clear = await _cipher.decrypt(
      SecretBox(
        unb64(envelope.cipherText),
        nonce: unb64(envelope.cipherNonce),
        mac: Mac(unb64(envelope.cipherMac)),
      ),
      secretKey: await _sharedSecret(peer),
    );
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is Map<String, Object?>) return decoded;
    if (decoded is Map) return decoded.cast<String, Object?>();
    throw const FormatException('Envelope payload is not an object.');
  }

  Future<SecretKey> _sharedSecret(Device peer) async {
    final remote = SimplePublicKey(unb64(peer.exchangePublicKey), type: KeyPairType.x25519);
    final raw = await _exchange.sharedSecretKey(
      keyPair: _identityService.exchangeKeyPair,
      remotePublicKey: remote,
    );
    final bytes = await raw.extractBytes();
    final material = <int>[
      ...utf8.encode('localchat-v1/aes-gcm'),
      ...bytes,
      ..._orderedPeerBytes(_identityService.identity.deviceId, peer.id),
    ];
    return SecretKey(crypto.sha256.convert(material).bytes);
  }

  List<int> _orderedPeerBytes(String a, String b) {
    final values = [a, b]..sort();
    return utf8.encode(values.join(':'));
  }
}
