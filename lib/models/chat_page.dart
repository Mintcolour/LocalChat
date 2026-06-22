import '../data/app_database.dart';

/// 分页加载游标：记录已加载的最旧消息，向前翻页时以此为边界。
class ChatPageCursor {
  const ChatPageCursor({this.beforeCreatedAt, this.beforeId});

  final DateTime? beforeCreatedAt;
  final String? beforeId;

  bool get hasPrevious => beforeCreatedAt != null && beforeId != null;

  ChatPageCursor fromOldest(ChatMessage oldest) =>
      ChatPageCursor(beforeCreatedAt: oldest.createdAt, beforeId: oldest.id);
}

/// 会话在设备列表中的摘要：最后一条消息预览、时间与未读数。
class ConversationSummary {
  const ConversationSummary({
    required this.conversation,
    required this.lastMessage,
    required this.unreadCount,
  });

  final Conversation conversation;
  final ChatMessage? lastMessage;
  final int unreadCount;
}
