import 'package:flutter/material.dart';

import 'package:localchat/app/app_controller.dart';
import 'package:localchat/core/device_profile.dart';
import 'package:localchat/core/formatters.dart';
import 'package:localchat/core/peer_status.dart';
import 'package:localchat/data/app_database.dart';
import 'package:localchat/ui/banners.dart';

class DevicePane extends StatelessWidget {
  const DevicePane({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final filter = controller.conversationFilter.toLowerCase();
    bool matches(Device device) =>
        filter.isEmpty ||
        controller.titleFor(device).toLowerCase().contains(filter);
    final trusted = controller.devices
        .where((device) => device.trusted && matches(device))
        .toList();
    final trustedOnline = trusted.where((d) => isPeerOnline(d)).toList();
    final trustedOffline = trusted.where((d) => !isPeerOnline(d)).toList();
    final discovered = controller.devices
        .where((device) => !device.trusted && matches(device))
        .toList();
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _LocalIdentityCard(controller: controller),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: controller.text.filterConversations,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => controller.setConversationFilter(value),
          ),
          const SizedBox(height: 16),
          if (trusted.isEmpty) ...[
            SectionTitle(title: controller.text.trustedDevices, count: 0),
            EmptyHint(text: controller.text.noTrustedDevices),
          ] else ...[
            SectionTitle(
              title: controller.text.trustedDevicesOnline,
              count: trustedOnline.length,
            ),
            if (trustedOnline.isEmpty)
              EmptyHint(text: controller.text.noOnlineDevices),
            for (final device in trustedOnline)
              _DeviceTile(controller: controller, device: device),
            if (trustedOffline.isNotEmpty) ...[
              const SizedBox(height: 16),
              SectionTitle(
                title: controller.text.trustedDevicesOffline,
                count: trustedOffline.length,
              ),
              for (final device in trustedOffline)
                _DeviceTile(controller: controller, device: device),
            ],
          ],
          const SizedBox(height: 16),
          SectionTitle(
            title: controller.text.discoveredDevices,
            count: discovered.length,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.rescan,
              icon: const Icon(Icons.travel_explore),
              label: Text(controller.text.rescan),
            ),
          ),
          if (discovered.isEmpty) EmptyHint(text: controller.text.listeningLan),
          for (final device in discovered)
            _DeviceTile(controller: controller, device: device),
        ],
      ),
    );
  }
}

class _LocalIdentityCard extends StatelessWidget {
  const _LocalIdentityCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final identity = controller.identity;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (identity != null)
                DeviceAvatar(
                  name: identity.displayName,
                  platform: identity.platform,
                  avatarSeed: identity.avatarSeed,
                  avatarColor: identity.avatarColor,
                ),
              if (identity != null) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  identity?.displayName ?? 'LocalChat',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            identity == null
                ? controller.text.identityStarting
                : '${identity.platform} · ${shortFingerprint(identity.fingerprint)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.controller, required this.device});

  final AppController controller;
  final Device device;

  @override
  Widget build(BuildContext context) {
    final selected = controller.selectedDevice?.id == device.id;
    final endpoint =
        device.host == null ||
            device.host!.isEmpty ||
            device.port == null ||
            device.port! <= 0
        ? controller.text.notConnected
        : displayHost(device.host, device.port);
    final conversation = controller.conversations
        .where((c) => c.peerDeviceId == device.id)
        .firstOrNull;
    final unread = conversation == null
        ? 0
        : (controller.unreadCounts[conversation.id] ?? 0);
    final lastMessage = conversation == null
        ? null
        : controller.lastMessages[conversation.id];
    final preview = controller.text.lastMessagePreview(
      lastMessage?.body,
      lastMessage?.fileName,
    );
    final statusLabel = controller.text.peerStatus(device);
    final hasPairRequest =
        controller.pendingPairRequestForDevice(device.id) != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ListTile(
        selected: selected,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            Opacity(
              opacity: isPeerOnline(device) ? 1.0 : 0.6,
              child: DeviceAvatar(
                name: controller.titleFor(device),
                platform: device.platform,
                avatarSeed: device.avatarSeed,
                avatarColor: device.avatarColor,
                trusted: device.trusted,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: _PeerStatusBadge(device: device, label: statusLabel),
            ),
            if (unread > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    '$unread',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Tooltip(
          message: controller.titleFor(device),
          child: Text(
            controller.titleFor(device),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
        subtitle: Text(
          preview.isEmpty ? '${device.platform} · $endpoint' : preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: device.trusted
            ? (unread > 0
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : const Icon(Icons.chevron_right))
            : hasPairRequest
            ? Tooltip(
                message: controller.text.pairRequestPending,
                child: const Icon(Icons.lock_outline),
              )
            : FilledButton.tonal(
                onPressed: controller.busy
                    ? null
                    : () => controller.pair(device),
                child: Text(controller.text.pair),
              ),
        onTap: () => controller.selectDevice(device),
      ),
    );
  }
}

class _PeerStatusBadge extends StatelessWidget {
  const _PeerStatusBadge({required this.device, required this.label});

  final Device device;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final online = isPeerOnline(device);
    final icon = !device.trusted
        ? Icons.link_off
        : online
        ? Icons.fiber_manual_record
        : Icons.fiber_manual_record;
    final color = !device.trusted
        ? scheme.outline
        : online
        ? const Color(0xFF10B981) // Clean emerald green for online status
        : scheme.outline;
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Container(
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(
            color: scheme.surface,
            shape: BoxShape.circle,
            border: Border.all(color: scheme.surface, width: 0.5),
          ),
          child: Icon(icon, size: 11, color: color),
        ),
      ),
    );
  }
}

class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({
    super.key,
    required this.name,
    required this.platform,
    required this.avatarSeed,
    required this.avatarColor,
    this.trusted = true,
    this.radius = 20,
  });

  final String name;
  final String platform;
  final String avatarSeed;
  final String avatarColor;
  final bool trusted;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = _colorFromHex(
      avatarColor.isEmpty ? avatarColorFor(avatarSeed) : avatarColor,
    );
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: trusted
          ? Text(
              avatarInitial(name, platform),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(Icons.lock_open, color: Colors.white, size: radius),
    );
  }
}

Color _colorFromHex(String value) {
  final clean = value.replaceFirst('#', '');
  final parsed = int.tryParse(
    clean.length == 6 ? 'FF$clean' : clean,
    radix: 16,
  );
  return Color(parsed ?? 0xFF2563EB);
}
