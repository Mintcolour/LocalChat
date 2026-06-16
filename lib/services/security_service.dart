import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/protocol.dart';
import 'identity_service.dart';

class EncryptedFileChunk {
  const EncryptedFileChunk({
    required this.index,
    required this.plainLength,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  final int index;
  final int plainLength;
  final List<int> nonce;
  final List<int> cipherText;
  final List<int> mac;
}

class SecurityService {
  SecurityService(this._identityService);

  final IdentityService _identityService;
  final _signing = Ed25519();
  final _exchange = X25519();
  final _cipher = AesGcm.with256bits();
  final Set<String> _seenNonces = <String>{};

  Future<Map<String, Object?>> seal(
    Device peer,
    Map<String, Object?> payload,
  ) async {
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
    return {...signedPayload, 'signature': b64(signature.bytes)};
  }

  Future<Map<String, Object?>> open(
    Device peer,
    Map<String, Object?> json,
  ) async {
    final envelope = SecureEnvelope.fromJson(json);
    if (envelope.recipientDeviceId != _identityService.identity.deviceId) {
      throw const FormatException(
        'Envelope recipient does not match this device.',
      );
    }
    if (envelope.senderDeviceId != peer.id) {
      throw const FormatException('Envelope sender does not match peer.');
    }
    final age = DateTime.now().millisecondsSinceEpoch - envelope.timestamp;
    if (age.abs() > const Duration(minutes: 10).inMilliseconds) {
      throw const FormatException(
        'Envelope timestamp is outside the allowed window.',
      );
    }
    final nonceKey = '${peer.id}:${envelope.nonce}';
    if (_seenNonces.contains(nonceKey)) {
      throw const FormatException('Envelope nonce was already used.');
    }
    final publicKey = SimplePublicKey(
      unb64(peer.signingPublicKey),
      type: KeyPairType.ed25519,
    );
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

  Future<EncryptedFileChunk> encryptFileChunk(
    Device peer,
    int index,
    List<int> clearBytes,
  ) async {
    final secretBox = await _cipher.encrypt(
      clearBytes,
      secretKey: await _sharedSecret(peer),
    );
    return EncryptedFileChunk(
      index: index,
      plainLength: clearBytes.length,
      nonce: secretBox.nonce,
      cipherText: secretBox.cipherText,
      mac: secretBox.mac.bytes,
    );
  }

  Future<List<int>> decryptFileChunk(
    Device peer,
    EncryptedFileChunk chunk,
  ) async {
    return _cipher.decrypt(
      SecretBox(chunk.cipherText, nonce: chunk.nonce, mac: Mac(chunk.mac)),
      secretKey: await _sharedSecret(peer),
    );
  }

  Future<Map<String, String>> streamAuthHeaders(
    Device peer,
    String transferId,
  ) async {
    final identity = _identityService.identity;
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final nonce = randomNonce();
    final payload = _streamAuthPayload(
      senderDeviceId: identity.deviceId,
      recipientDeviceId: peer.id,
      transferId: transferId,
      timestamp: timestamp,
      nonce: nonce,
    );
    final signature = await _signing.sign(
      utf8.encode(jsonEncode(payload)),
      keyPair: _identityService.signingKeyPair,
    );
    return {
      'x-localchat-sender': identity.deviceId,
      'x-localchat-recipient': peer.id,
      'x-localchat-transfer-id': transferId,
      'x-localchat-timestamp': '$timestamp',
      'x-localchat-nonce': nonce,
      'x-localchat-signature': b64(signature.bytes),
    };
  }

  Future<void> verifyStreamAuth({
    required Device peer,
    required String recipientDeviceId,
    required String transferId,
    required int timestamp,
    required String nonce,
    required String signature,
  }) async {
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (age.abs() > const Duration(minutes: 10).inMilliseconds) {
      throw const FormatException(
        'Stream timestamp is outside the allowed window.',
      );
    }
    final nonceKey = 'stream:${peer.id}:$nonce';
    if (_seenNonces.contains(nonceKey)) {
      throw const FormatException('Stream nonce was already used.');
    }
    final publicKey = SimplePublicKey(
      unb64(peer.signingPublicKey),
      type: KeyPairType.ed25519,
    );
    final ok = await _signing.verify(
      utf8.encode(
        jsonEncode(
          _streamAuthPayload(
            senderDeviceId: peer.id,
            recipientDeviceId: recipientDeviceId,
            transferId: transferId,
            timestamp: timestamp,
            nonce: nonce,
          ),
        ),
      ),
      signature: Signature(unb64(signature), publicKey: publicKey),
    );
    if (!ok) {
      throw const FormatException('Stream signature is invalid.');
    }
    _seenNonces.add(nonceKey);
  }

  Future<SecretKey> _sharedSecret(Device peer) async {
    final remote = SimplePublicKey(
      unb64(peer.exchangePublicKey),
      type: KeyPairType.x25519,
    );
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

  Map<String, Object?> _streamAuthPayload({
    required String senderDeviceId,
    required String recipientDeviceId,
    required String transferId,
    required int timestamp,
    required String nonce,
  }) => {
    'kind': 'encrypted_stream_v2',
    'sender_device_id': senderDeviceId,
    'recipient_device_id': recipientDeviceId,
    'transfer_id': transferId,
    'timestamp': timestamp,
    'nonce': nonce,
  };
}
