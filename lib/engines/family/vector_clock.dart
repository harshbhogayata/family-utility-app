import 'package:flutter/foundation.dart';

/// How two vector clocks relate.
enum ClockOrder { before, after, equal, concurrent }

/// Feature 068 — a vector clock: one counter per device that edited a record.
///
/// Immutable. A local edit increments this device's counter; merging two
/// clocks takes the larger counter for every device.
@immutable
class VectorClock {
  const VectorClock([this.counters = const <String, int>{}]);

  final Map<String, int> counters;

  int operator [](String device) => counters[device] ?? 0;

  VectorClock increment(String device) {
    final Map<String, int> next = Map<String, int>.of(counters);
    next[device] = this[device] + 1;
    return VectorClock(Map<String, int>.unmodifiable(next));
  }

  VectorClock merge(VectorClock other) {
    final Map<String, int> next = Map<String, int>.of(counters);
    other.counters.forEach((String device, int n) {
      if (n > (next[device] ?? 0)) {
        next[device] = n;
      }
    });
    return VectorClock(Map<String, int>.unmodifiable(next));
  }

  /// Where this clock sits relative to [other].
  ClockOrder compare(VectorClock other) {
    bool less = false;
    bool more = false;
    final Set<String> devices = <String>{...counters.keys, ...other.counters.keys};
    for (final String d in devices) {
      final int a = this[d];
      final int b = other[d];
      if (a < b) {
        less = true;
      } else if (a > b) {
        more = true;
      }
    }
    if (less && more) {
      return ClockOrder.concurrent;
    }
    if (less) {
      return ClockOrder.before;
    }
    if (more) {
      return ClockOrder.after;
    }
    return ClockOrder.equal;
  }

  Map<String, Object?> toJson() => Map<String, Object?>.of(counters);

  static VectorClock fromJson(Object? json) {
    if (json is! Map) {
      return const VectorClock();
    }
    final Map<String, int> out = <String, int>{};
    json.forEach((Object? k, Object? v) {
      if (k is String && v is num) {
        out[k] = v.toInt();
      }
    });
    return VectorClock(Map<String, int>.unmodifiable(out));
  }

  @override
  bool operator ==(Object other) => other is VectorClock && compare(other) == ClockOrder.equal;

  @override
  int get hashCode {
    final List<String> keys = counters.keys.where((String k) => counters[k] != 0).toList()..sort();
    return Object.hashAll(keys.map((String k) => '$k:${counters[k]}'));
  }

  @override
  String toString() => 'VectorClock($counters)';
}
