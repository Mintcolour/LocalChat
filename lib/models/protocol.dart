import 'dart:convert';

const protocolVersion = 1;
const discoveryPort = 45871;
const legacyTransferChunkSize = 256 * 1024;
const encryptedStreamChunkSize = 4 * 1024 * 1024;
const encryptedStreamVersion = 2;
const encryptedStreamCapability = 'encrypted_stream_v2';

enum PeerPresence { trusted, discovered }

class LocalIdentity {
  const LocalIdentity({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.signingPrivateKey,
    required this.signingPublicKey,
    required this.exchangePrivateKey,
    required this.exchangePublicKey,
    required this.fingerprint,
    required this.avatarSeed,
    required this.avatarColor,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String signingPrivateKey;
  final String signingPublicKey;
  final String exchangePrivateKey;
  final String exchangePublicKey;
  final String fingerprint;
  final String avatarSeed;
  final String avatarColor;
}

class DiscoveredPeer {
  const DiscoveredPeer({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.host,
    required this.port,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    required this.fingerprint,
    required this.avatarSeed,
    required this.avatarColor,
    required this.lastSeen,
    this.capabilities = const <String>[
      'text',
      'files',
      'pairing',
      'encrypted_chunks',
      encryptedStreamCapability,
    ],
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String host;
  final int port;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String fingerprint;
  final String avatarSeed;
  final String avatarColor;
  final DateTime lastSeen;
  final List<String> capabilities;

  Map<String, Object?> toJson() => {
    'protocol_version': protocolVersion,
    'device_id': deviceId,
    'display_name': displayName,
    'nickname': displayName,
    'platform': platform,
    'listen_port': port,
    'capabilities': capabilities,
    'signing_public_key': signingPublicKey,
    'exchange_public_key': exchangePublicKey,
    'public_key_fingerprint': fingerprint,
    'avatar_seed': avatarSeed,
    'avatar_color': avatarColor,
    'timestamp': lastSeen.toIso8601String(),
  };

  static DiscoveredPeer? fromJson(Map<String, Object?> json, String host) {
    if (json['protocol_version'] != protocolVersion) return null;
    final deviceId = json['device_id'];
    final displayName = json['nickname'] ?? json['display_name'];
    final platform = json['platform'];
    final port = json['listen_port'];
    final signingPublicKey = json['signing_public_key'];
    final exchangePublicKey = json['exchange_public_key'];
    final fingerprint = json['public_key_fingerprint'];
    final avatarSeed = json['avatar_seed'];
    final avatarColor = json['avatar_color'];
    final capabilities = json['capabilities'];
    if (deviceId is! String ||
        displayName is! String ||
        platform is! String ||
        port is! int ||
        signingPublicKey is! String ||
        exchangePublicKey is! String ||
        fingerprint is! String) {
      return null;
    }
    return DiscoveredPeer(
      deviceId: deviceId,
      displayName: displayName,
      platform: platform,
      host: host,
      port: port,
      signingPublicKey: signingPublicKey,
      exchangePublicKey: exchangePublicKey,
      fingerprint: fingerprint,
      avatarSeed: avatarSeed is String && avatarSeed.isNotEmpty
          ? avatarSeed
          : fingerprint,
      avatarColor: avatarColor is String && avatarColor.isNotEmpty
          ? avatarColor
          : '#2563EB',
      lastSeen: DateTime.now(),
      capabilities: capabilities is List
          ? capabilities.whereType<String>().toList()
          : const <String>[],
    );
  }

  static DiscoveredPeer? fromDatagram(List<int> bytes, String host) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) {
        return DiscoveredPeer.fromJson(decoded, host);
      }
      if (decoded is Map) {
        return DiscoveredPeer.fromJson(decoded.cast<String, Object?>(), host);
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}

class SecureEnvelope {
  SecureEnvelope({
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.timestamp,
    required this.nonce,
    required this.cipherNonce,
    required this.cipherText,
    required this.cipherMac,
    required this.signature,
  });

  final String senderDeviceId;
  final String recipientDeviceId;
  final int timestamp;
  final String nonce;
  final String cipherNonce;
  final String cipherText;
  final String cipherMac;
  final String signature;

  Map<String, Object?> toSignedPayload() => {
    'sender_device_id': senderDeviceId,
    'recipient_device_id': recipientDeviceId,
    'timestamp': timestamp,
    'nonce': nonce,
    'cipher': 'aes-gcm-256',
    'cipher_nonce': cipherNonce,
    'cipher_text': cipherText,
    'cipher_mac': cipherMac,
  };

  Map<String, Object?> toJson() => {
    ...toSignedPayload(),
    'signature': signature,
  };

  static SecureEnvelope fromJson(Map<String, Object?> json) {
    String requireString(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Envelope field "$key" is missing.');
      }
      return value;
    }

    final timestamp = json['timestamp'];
    if (timestamp is! int) {
      throw const FormatException('Envelope timestamp is missing.');
    }
    return SecureEnvelope(
      senderDeviceId: requireString('sender_device_id'),
      recipientDeviceId: requireString('recipient_device_id'),
      timestamp: timestamp,
      nonce: requireString('nonce'),
      cipherNonce: requireString('cipher_nonce'),
      cipherText: requireString('cipher_text'),
      cipherMac: requireString('cipher_mac'),
      signature: requireString('signature'),
    );
  }
}

class PairRequest {
  const PairRequest({
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    required this.fingerprint,
    required this.avatarSeed,
    required this.avatarColor,
    required this.code,
  });

  final String deviceId;
  final String displayName;
  final String platform;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String fingerprint;
  final String avatarSeed;
  final String avatarColor;
  final String code;

  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'display_name': displayName,
    'nickname': displayName,
    'platform': platform,
    'signing_public_key': signingPublicKey,
    'exchange_public_key': exchangePublicKey,
    'public_key_fingerprint': fingerprint,
    'avatar_seed': avatarSeed,
    'avatar_color': avatarColor,
    'code': code,
  };
}

class PendingPairRequest {
  const PendingPairRequest({
    required this.id,
    required this.deviceId,
    required this.displayName,
    required this.platform,
    required this.host,
    required this.port,
    required this.signingPublicKey,
    required this.exchangePublicKey,
    required this.fingerprint,
    required this.avatarSeed,
    required this.avatarColor,
    required this.code,
    required this.createdAt,
  });

  final String id;
  final String deviceId;
  final String displayName;
  final String platform;
  final String host;
  final int port;
  final String signingPublicKey;
  final String exchangePublicKey;
  final String fingerprint;
  final String avatarSeed;
  final String avatarColor;
  final String code;
  final DateTime createdAt;
}
