/// Feature 115 — Recents and favourites.
///
/// The home grid order for one member: pinned tools first, in the order the
/// member arranged them, then recently used tools (newest first), then every
/// other tool in its registry order. Pure and on-device.
abstract final class ToolOrder {
  static List<String> order({
    required List<String> all,
    required List<String> pinned,
    required List<String> recents,
  }) {
    final Set<String> known = all.toSet();
    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    void take(String id) {
      if (known.contains(id) && seen.add(id)) {
        out.add(id);
      }
    }

    pinned.forEach(take);
    recents.forEach(take);
    all.forEach(take);
    return out;
  }

  /// [pinned] with [id] moved to [index] (clamped). Unknown ids leave it as is.
  static List<String> move(List<String> pinned, String id, int index) {
    if (!pinned.contains(id)) {
      return List<String>.of(pinned);
    }
    final List<String> next = pinned.where((String p) => p != id).toList();
    final int at = index < 0 ? 0 : (index > next.length ? next.length : index);
    next.insert(at, id);
    return next;
  }
}
