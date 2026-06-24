class QuickSendDeviceView {
  const QuickSendDeviceView({
    required this.id,
    required this.displayName,
    required this.platform,
    required this.avatarInitial,
    required this.avatarColor,
    required this.selected,
  });

  final String id;
  final String displayName;
  final String platform;
  final String avatarInitial;
  final String avatarColor;
  final bool selected;

  Map<String, Object?> toNativeMap() {
    return {
      'id': id,
      'displayName': displayName,
      'platform': platform,
      'avatarInitial': avatarInitial,
      'avatarColor': avatarColor,
      'selected': selected,
    };
  }
}
