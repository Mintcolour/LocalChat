import 'dart:convert';

import '../core/formatters.dart';

const protocolVersion = 1;
const discoveryPort = 45871;
const legacyTransferChunkSize = 256 * 1024;
const encryptedStreamChunkSize = 4 * 1024 * 1024;
const encryptedStreamVersion = 2;
const encryptedStreamCapability = 'encrypted_stream_v2';
// 文件夹递归传输能力：对端在 /v1/transfers start 请求里携带 relative_path 字段，
// 接收端按相对路径镜像落盘。旧版本不广播此能力，发送时回退为纯平铺。
const folderCapability = 'folders_v1';

enum PeerPresence { trusted, discovered }

/// 由签名公钥（base64url 字符串）派生指纹：sha256(公钥原始字节) 的十六进制。
/// 与 [IdentityService] 生成本地身份时的算法一致。
String fingerprintFromSigningKey(String signingPublicKeyB64) {
  return sha256Hex(unb64(signingPublicKeyB64));
}

/// 对端身份自洽性校验失败（设备 ID、签名公钥、指纹三者不一致）。
/// 计划 P0：拒绝设备 ID、公钥、指纹不一致的数据。
class PeerIdentityMismatch implements Exception {
  const PeerIdentityMismatch(this.message);
  final String message;
  @override
  String toString() => 'PeerIdentityMismatch: $message';
}

/// 校验 [deviceId]、[signingPublicKey]、[fingerprint] 三者自洽：
/// 指纹必须由签名公钥派生，设备 ID 必须是指纹的前 20 位（与本地身份生成规则一致）。
/// 任一为空或不一致抛 [PeerIdentityMismatch]。该函数仅在“摄入对端身份”的网络路径
/// 调用，不影响数据库层的旧测试用例（旧用例直接操作 DB，不经此校验）。
void validatePeerIdentity({
  required String deviceId,
  required String signingPublicKey,
  required String fingerprint,
}) {
  if (deviceId.isEmpty || signingPublicKey.isEmpty || fingerprint.isEmpty) {
    throw const PeerIdentityMismatch('身份信息不完整');
  }
  final derived = fingerprintFromSigningKey(signingPublicKey);
  if (derived != fingerprint) {
    throw const PeerIdentityMismatch('指纹与签名公钥不匹配');
  }
  if (fingerprint.length < 20 || deviceId != fingerprint.substring(0, 20)) {
    throw const PeerIdentityMismatch('设备 ID 与指纹不一致');
  }
}

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
      folderCapability,
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
