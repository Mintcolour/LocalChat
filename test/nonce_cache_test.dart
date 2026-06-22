import 'package:flutter_test/flutter_test.dart';
import 'package:localchat/services/nonce_cache.dart';

void main() {
  group('NonceCache', () {
    test('first registration returns true, replay returns false', () {
      final cache = NonceCache(ttl: const Duration(minutes: 10));
      expect(cache.register('a'), isTrue);
      expect(cache.register('a'), isFalse);
    });

    test('expired nonce is accepted again after TTL', () {
      final cache = NonceCache(ttl: const Duration(minutes: 10));
      final start = DateTime.utc(2026, 6, 22, 10);
      expect(cache.register('a', now: start), isTrue);
      expect(
        cache.register('a', now: start.add(const Duration(minutes: 11))),
        isTrue,
      );
    });

    test('distinct keys are tracked independently', () {
      final cache = NonceCache();
      expect(cache.register('a'), isTrue);
      expect(cache.register('b'), isTrue);
      expect(cache.register('a'), isFalse);
      expect(cache.register('b'), isFalse);
    });

    test('capacity cap evicts the oldest entry to bound memory', () {
      final cache = NonceCache(
        ttl: const Duration(minutes: 10),
        maxCapacity: 2,
      );
      final now = DateTime.utc(2026, 6, 22, 10);
      expect(cache.register('a', now: now), isTrue);
      expect(cache.register('b', now: now), isTrue);
      // 容量已满，登记 c 会淘汰最早过期者 a。
      expect(cache.register('c', now: now), isTrue);
      expect(cache.size, 2);
      // a 被淘汰后可再次登记（视为新 nonce）。
      expect(cache.register('a', now: now), isTrue);
    });

    test('expired entries are reaped before capacity eviction', () {
      final cache = NonceCache(
        ttl: const Duration(minutes: 1),
        maxCapacity: 2,
      );
      final t0 = DateTime.utc(2026, 6, 22, 10);
      expect(cache.register('a', now: t0), isTrue);
      // b 在更晚时刻登记，a 此时已过期。
      final t1 = t0.add(const Duration(minutes: 5));
      expect(cache.register('b', now: t1), isTrue);
      expect(cache.register('c', now: t1), isTrue);
      // a 已过期被清理，b/c 仍在。
      expect(cache.contains('b', now: t1), isTrue);
      expect(cache.contains('c', now: t1), isTrue);
    });
  });
}
