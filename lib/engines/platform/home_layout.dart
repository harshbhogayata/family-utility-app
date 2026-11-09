import 'tool_order.dart';

/// Feature 116 — Custom home.
///
/// One member's home layout: which tools are pinned, the order they dragged
/// the rest into, and which tools they hid. Pure Dart, on-device only.
class HomeLayout {
  const HomeLayout({
    this.pinned = const <String>[],
    this.arranged = const <String>[],
    this.hidden = const <String>[],
  });

  /// Pinned tool ids, in pin order. Pinned tools always sit at the top.
  final List<String> pinned;

  /// The member's own order for the unpinned tools. Empty means "default":
  /// recently used first, then registry order (feature 115).
  final List<String> arranged;

  /// Tool ids kept off the home grid. They stay reachable from search.
  final List<String> hidden;

  static const HomeLayout empty = HomeLayout();

  bool get isDefault => pinned.isEmpty && arranged.isEmpty && hidden.isEmpty;

  bool isHidden(String id) => hidden.contains(id);

  bool isPinned(String id) => pinned.contains(id);

  /// Every known tool in home order, hidden ones included (for the editor).
  List<String> fullOrder({required List<String> all, List<String> recents = const <String>[]}) {
    return ToolOrder.order(
      all: all,
      pinned: pinned,
      recents: arranged.isEmpty ? recents : arranged,
    );
  }

  /// What the home grid shows: [fullOrder] without the hidden tools.
  List<String> visible({required List<String> all, List<String> recents = const <String>[]}) {
    final Set<String> off = hidden.toSet();
    return fullOrder(all: all, recents: recents).where((String id) => !off.contains(id)).toList();
  }

  /// The layout after the editor list [order] is rearranged by a drag from
  /// [oldIndex] to [newIndex] (ReorderableListView numbering: [newIndex] is
  /// the slot before removal). Pins keep their new relative order and stay on
  /// top; everything else keeps exactly the dragged order.
  HomeLayout reorder(List<String> order, int oldIndex, int newIndex) =>
      moveTo(order, oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex);

  /// Like [reorder], but [to] is the final index of the moved tool
  /// (ReorderableListView.onReorderItem numbering).
  HomeLayout moveTo(List<String> order, int from, int to) {
    if (from < 0 || from >= order.length) {
      return this;
    }
    final List<String> next = List<String>.of(order);
    final String id = next.removeAt(from);
    final int at = to < 0 ? 0 : (to > next.length ? next.length : to);
    next.insert(at, id);
    return arrange(next);
  }

  /// Moves [id] one step up (delta -1) or down (delta 1) in [order].
  HomeLayout step(List<String> order, String id, int delta) {
    final int from = order.indexOf(id);
    if (from < 0) {
      return this;
    }
    final int to = from + delta;
    if (to < 0 || to >= order.length) {
      return this;
    }
    return reorder(order, from, delta > 0 ? to + 1 : to);
  }

  /// Takes [order] as the member's chosen full order.
  HomeLayout arrange(List<String> order) {
    final Set<String> pins = pinned.toSet();
    return HomeLayout(
      pinned: order.where(pins.contains).toList(),
      arranged: order.where((String id) => !pins.contains(id)).toList(),
      hidden: hidden,
    );
  }

  /// Hides [id] when shown, shows it when hidden. A hidden tool is unpinned.
  HomeLayout toggleHidden(String id) {
    if (hidden.contains(id)) {
      return HomeLayout(
        pinned: pinned,
        arranged: arranged,
        hidden: hidden.where((String h) => h != id).toList(),
      );
    }
    return HomeLayout(
      pinned: pinned.where((String p) => p != id).toList(),
      arranged: arranged,
      hidden: <String>[...hidden, id],
    );
  }

  /// Pins [id] (to the end of the pins) or unpins it. Pinning shows it again.
  HomeLayout togglePinned(String id) {
    if (pinned.contains(id)) {
      return HomeLayout(
        pinned: pinned.where((String p) => p != id).toList(),
        arranged: arranged,
        hidden: hidden,
      );
    }
    return HomeLayout(
      pinned: <String>[...pinned, id],
      arranged: arranged,
      hidden: hidden.where((String h) => h != id).toList(),
    );
  }

  /// Back to the default home: no pins, no custom order, nothing hidden.
  HomeLayout reset() => empty;

  /// Plain-text summary, for Share and Save.
  String describe({
    required String memberName,
    required List<String> all,
    required String Function(String id) nameOf,
    List<String> recents = const <String>[],
  }) {
    final StringBuffer b = StringBuffer('Home for $memberName\n');
    final List<String> shown = visible(all: all, recents: recents);
    for (int i = 0; i < shown.length; i++) {
      final String id = shown[i];
      b.writeln('${i + 1}. ${nameOf(id)}${isPinned(id) ? ' (pinned)' : ''}');
    }
    final List<String> off = all.where(hidden.contains).toList();
    if (off.isNotEmpty) {
      b.writeln('Hidden: ${off.map(nameOf).join(', ')}');
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) =>
      other is HomeLayout &&
      _same(other.pinned, pinned) &&
      _same(other.arranged, arranged) &&
      _same(other.hidden, hidden);

  @override
  int get hashCode => Object.hash(Object.hashAll(pinned), Object.hashAll(arranged), Object.hashAll(hidden));

  static bool _same(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
