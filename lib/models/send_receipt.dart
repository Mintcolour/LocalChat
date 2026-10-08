/// Identifiers assigned before an automation send starts. Persisted messages and
/// transfer groups are the source of truth; no separate automation queue exists.
class SendReceipt {
  const SendReceipt({
    required this.jobId,
    required this.targetDeviceId,
    this.messageIds = const [],
    this.transferIds = const [],
    this.groupId,
  });

  final String jobId;
  final String targetDeviceId;
  final List<String> messageIds;
  final List<String> transferIds;
  final String? groupId;

  Map<String, Object?> toJson() => {
    'jobId': jobId,
    'targetDeviceId': targetDeviceId,
    'messageIds': messageIds,
    'transferIds': transferIds,
    if (groupId != null) 'groupId': groupId,
  };
}
