const avatarPalette = <String>[
  '#2563EB',
  '#059669',
  '#D97706',
  '#DC2626',
  '#7C3AED',
  '#0891B2',
  '#DB2777',
  '#4F46E5',
];

String defaultDeviceNickname(String platform, String fingerprint) {
  final suffix = fingerprint
      .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
      .toUpperCase()
      .padRight(4, '0')
      .substring(0, 4);
  return '${platformDeviceLabel(platform)}-$suffix';
}

String platformDeviceLabel(String platform) {
  switch (platform.toLowerCase()) {
    case 'windows':
      return 'Windows电脑';
    case 'android':
      return 'Android手机';
    case 'ios':
      return 'iPhone';
    case 'macos':
      return 'Mac电脑';
    case 'linux':
      return 'Linux电脑';
    default:
      return 'LocalChat设备';
  }
}

String avatarSeedFor(String deviceId, String fingerprint) {
  final clean = fingerprint
      .replaceAll(RegExp(r'[^a-fA-F0-9]'), '')
      .toLowerCase();
  return clean.isNotEmpty ? clean : deviceId;
}

String avatarColorFor(String seed) {
  if (seed.isEmpty) return avatarPalette.first;
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = 0x1fffffff & (hash + unit);
    hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
    hash ^= hash >> 6;
  }
  return avatarPalette[hash.abs() % avatarPalette.length];
}

String avatarInitial(String name, String platform) {
  final trimmed = name.trim();
  if (trimmed.isNotEmpty) {
    final first = trimmed.characters.first.toUpperCase();
    if (RegExp(r'[A-Z0-9]').hasMatch(first)) return first;
  }
  final label = platformDeviceLabel(platform);
  return label.characters.first;
}

extension _CharacterAccess on String {
  Iterable<String> get characters sync* {
    final iterator = Runes(this).iterator;
    while (iterator.moveNext()) {
      yield String.fromCharCode(iterator.current);
    }
  }
}
