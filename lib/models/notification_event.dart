import 'dart:convert';

enum AppNotificationType { message, file, pairRequest }

class AppNotificationEvent {
  const AppNotificationEvent({
    required this.type,
    required this.title,
    required this.privateBody,
    this.previewBody,
    this.deviceId,
    this.conversationId,
    this.requestId,
  });

  final AppNotificationType type;
  final String title;
  final String privateBody;
  final String? previewBody;
  final String? deviceId;
  final String? conversationId;
  final String? requestId;

  String body({required bool includePreview}) {
    if (includePreview && previewBody != null && previewBody!.isNotEmpty) {
      return previewBody!;
    }
    return privateBody;
  }

  String get payload => jsonEncode({
    'type': type.name,
    if (deviceId != null) 'deviceId': deviceId,
    if (conversationId != null) 'conversationId': conversationId,
    if (requestId != null) 'requestId': requestId,
  });
}

class AppNotificationPayload {
  const AppNotificationPayload({
    required this.type,
    this.deviceId,
    this.conversationId,
    this.requestId,
  });

  final AppNotificationType type;
  final String? deviceId;
  final String? conversationId;
  final String? requestId;

  static AppNotificationPayload? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final typeName = decoded['type'];
      if (typeName is! String) return null;
      final type = AppNotificationType.values
          .where((value) => value.name == typeName)
          .firstOrNull;
      if (type == null) return null;
      return AppNotificationPayload(
        type: type,
        deviceId: _nullableString(decoded['deviceId']),
        conversationId: _nullableString(decoded['conversationId']),
        requestId: _nullableString(decoded['requestId']),
      );
    } catch (_) {
      return null;
    }
  }

  static String? _nullableString(Object? value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }
}
