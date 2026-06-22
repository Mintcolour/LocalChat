import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/app_text.dart';
import '../core/formatters.dart';
import '../data/app_database.dart';
import '../models/transfer_views.dart';

/// 传输中心：按“进行中 / 已完成 / 失败”分组展示全部传输，支持查看进度、速度、
/// 预计剩余时间、失败原因，以及取消排队/活动中的出站任务或整组。
class TransferCenterPage extends StatefulWidget {
  const TransferCenterPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<TransferCenterPage> createState() => _TransferCenterPageState();
}

class _TransferCenterPageState extends State<TransferCenterPage> {
  List<TransferGroupView> _groups = const [];
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _reload();
    // 实时刷新进度与速度（内存态统计每 ~500ms 变化）。
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => _reload();

  Future<void> _reload() async {
    final groups = await widget.controller.buildTransferGroupViews();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.controller.text;
    final active = _groups.where((g) => g.groupKind == TransferGroupKind.active).toList();
    final completed = _groups
        .where((g) => g.groupKind == TransferGroupKind.completed)
        .toList();
    final failed = _groups.where((g) => g.groupKind == TransferGroupKind.failed).toList();

    return Scaffold(
      appBar: AppBar(title: Text(text.transferCenter)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
          ? Center(child: Text(text.noTransfers))
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (active.isNotEmpty)
                  _Section(
                    title: text.transfersActive,
                    groups: active,
                    controller: widget.controller,
                  ),
                if (failed.isNotEmpty)
                  _Section(
                    title: text.transfersFailed,
                    groups: failed,
                    controller: widget.controller,
                  ),
                if (completed.isNotEmpty)
                  _Section(
                    title: text.transfersCompleted,
                    groups: completed,
                    controller: widget.controller,
                  ),
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.groups,
    required this.controller,
  });

  final String title;
  final List<TransferGroupView> groups;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            '$title（${groups.length}）',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        for (final group in groups)
          _TransferGroupCard(group: group, controller: controller),
      ],
    );
  }
}

class _TransferGroupCard extends StatelessWidget {
  const _TransferGroupCard({required this.group, required this.controller});

  final TransferGroupView group;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    final isMulti = group.tasks.length > 1;
    final isActive = group.groupKind == TransferGroupKind.active;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isMulti
                        ? '${group.peerDisplayName} · ${group.tasks.length} 个文件'
                        : group.tasks.first.transfer.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (isActive)
                  IconButton(
                    tooltip: text.cancelGroup,
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    onPressed: () => controller.cancelTransferGroup(group.groupId),
                  ),
              ],
            ),
            if (isActive) ...[
              LinearProgressIndicator(value: group.progress),
              const SizedBox(height: 4),
              Text(
                '${formatBytes(group.sentBytes)} / ${formatBytes(group.totalBytes)}'
                '${group.tasks.any((t) => t.bytesPerSecond > 0) ? ' · ${text.transferSpeed(group.tasks.fold<double>(0, (s, t) => t.bytesPerSecond > s ? t.bytesPerSecond : s))}' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            for (final task in group.tasks)
              _TransferTaskRow(task: task, controller: controller),
          ],
        ),
      ),
    );
  }
}

class _TransferTaskRow extends StatelessWidget {
  const _TransferTaskRow({required this.task, required this.controller});

  final TransferTaskView task;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final text = controller.text;
    final isActive = task.groupKind == TransferGroupKind.active;
    final transfer = task.transfer;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            transfer.direction == 'out'
                ? Icons.upload_outlined
                : Icons.download_outlined,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transfer.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (isActive) ...[
                  const SizedBox(height: 2),
                  LinearProgressIndicator(value: task.progress),
                  const SizedBox(height: 2),
                  Text(
                    _progressDetail(text),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ] else
                  Text(
                    _terminalStatus(text),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: task.groupKind == TransferGroupKind.failed
                              ? Theme.of(context).colorScheme.error
                              : null,
                        ),
                  ),
              ],
            ),
          ),
          if (isActive && transfer.direction == 'out')
            _cancelButton(context, transfer),
        ],
      ),
    );
  }

  Widget _cancelButton(BuildContext context, Transfer transfer) {
    final peer = controller.devices
        .where((d) => d.id == transfer.peerDeviceId)
        .firstOrNull;
    final canCancel = peer == null || controller.peerSupportsCancel(peer);
    return IconButton(
      tooltip: canCancel
          ? controller.text.cancelTransfer
          : controller.text.transferCanceledHint,
      icon: const Icon(Icons.close, size: 18),
      onPressed: canCancel
          ? () => controller.cancelTransfer(transfer)
          : null,
    );
  }

  String _progressDetail(AppText text) {
    final parts = <String>[
      '${(task.progress * 100).toStringAsFixed(0)}%',
      '${formatBytes(task.sentBytes)} / ${formatBytes(task.totalBytes)}',
    ];
    if (task.bytesPerSecond > 0) {
      parts.add(text.transferSpeed(task.bytesPerSecond));
    }
    final eta = task.etaSeconds;
    if (eta != null && eta > 0) {
      parts.add(text.transferEta(eta));
    }
    return parts.join(' · ');
  }

  String _terminalStatus(AppText text) {
    if (task.groupKind == TransferGroupKind.failed) {
      final code = task.errorCode;
      if (code == 'canceled' || code == 'remote_canceled') {
        return text.en ? 'Canceled' : '已取消';
      }
      if (code == 'interrupted') {
        return text.en ? 'Interrupted' : '已中断';
      }
      return text.en
          ? 'Failed${code != null && code != 'unknown' ? ' ($code)' : ''}'
          : '失败${code != null && code != 'unknown' ? '（$code）' : ''}';
    }
    return messageStatusLabel(task.transfer.status);
  }
}
