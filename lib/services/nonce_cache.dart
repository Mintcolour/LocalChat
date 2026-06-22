import 'dart:collection';

/// 带 TTL 与容量上限的防重放 nonce 缓存。
///
/// 旧实现用无限增长的 `Set<String>` 记录已见 nonce，长时间运行会无界增长，且
/// 没有时间窗外的淘汰（计划 P0：nonce 改为带 TTL 和容量上限的缓存）。本类对每个
/// 条目记录过期时间，[register] 命中已存在且未过期的 key 时返回 false；容量达到
/// 上限时先按过期时间清理，仍不足则淘汰最早过期的条目。
class NonceCache {
  NonceCache({
    this.ttl = const Duration(minutes: 10),
    this.maxCapacity = 10000,
  });

  final Duration ttl;
  final int maxCapacity;

  /// key -> 该条目过期时刻（自 epoch 起的毫秒数）。
  final LinkedHashMap<String, int> _entries = LinkedHashMap<String, int>();

  /// 当前缓存条目数（主要供测试断言）。
  int get size => _entries.length;

  /// 尝试登记 [key]。
  ///
  /// 返回 true 表示此前未登记（或已过期被回收），调用方应继续处理；
  /// 返回 false 表示在 TTL 窗口内重复出现，调用方应拒绝（防重放）。
  bool register(String key, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final expiry = nowMs + ttl.inMilliseconds;
    final existing = _entries[key];
    if (existing != null) {
      if (existing > nowMs) {
        // 未过期重复命中 → 重放。
        return false;
      }
      // 已过期，更新过期时间并续期。
      _entries.remove(key);
    }
    _ensureCapacity(nowMs);
    _entries[key] = expiry;
    return true;
  }

  /// 是否包含未过期的 [key]（不登记，仅供测试/诊断查询）。
  bool contains(String key, {DateTime? now}) {
    final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final expiry = _entries[key];
    return expiry != null && expiry > nowMs;
  }

  void _ensureCapacity(int nowMs) {
    if (_entries.length < maxCapacity) {
      // 顺手清理已过期条目，避免它们占位。
      _entries.removeWhere((_, expiry) => expiry <= nowMs);
      return;
    }
    // 容量已满：先清过期。
    _entries.removeWhere((_, expiry) => expiry <= nowMs);
    if (_entries.length < maxCapacity) return;
    // 仍未腾出空间：淘汰过期时间最早（即最接近过期）的条目。
    final oldest = _entries.keys.first;
    _entries.remove(oldest);
  }
}
