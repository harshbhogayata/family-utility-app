import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../engines/image/before_after.dart';

/// Feature 039 — compares an original picture with its compressed copy,
/// either with a draggable divider or side by side. Pinch to zoom; both
/// halves zoom together.
class BeforeAfterView extends StatefulWidget {
  const BeforeAfterView({
    super.key,
    required this.before,
    required this.after,
    this.initialMode = CompareMode.slider,
  });

  final Uint8List before;
  final Uint8List after;
  final CompareMode initialMode;

  @override
  State<BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<BeforeAfterView> {
  late CompareMode _mode = widget.initialMode;
  double _split = 0.5;
  final TransformationController _zoom = TransformationController();

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  Widget _picture(Uint8List bytes, String label) => Semantics(
        label: label,
        image: true,
        child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true, excludeFromSemantics: true),
      );

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(color: Colors.white)),
      );

  Widget _zoomable(Widget child) => InteractiveViewer(
        transformationController: _zoom,
        minScale: CompareLimits.minZoom,
        maxScale: CompareLimits.maxZoom,
        child: child,
      );

  Widget _slider() {
    return LayoutBuilder(builder: (BuildContext context, BoxConstraints box) {
      final double w = box.maxWidth;
      return Stack(children: <Widget>[
        Positioned.fill(
          child: _zoomable(Stack(fit: StackFit.expand, children: <Widget>[
            _picture(widget.after, 'After'),
            ClipRect(
              clipper: _LeftPart(_split),
              child: _picture(widget.before, 'Before'),
            ),
          ])),
        ),
        Positioned(
          left: w * _split - 22,
          top: 0,
          bottom: 0,
          width: 44,
          child: GestureDetector(
            key: const Key('compare-handle'),
            behavior: HitTestBehavior.translucent,
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                setState(() => _split = CompareLimits.splitAt(w * _split + d.delta.dx, w)),
            child: Center(
              child: Container(width: 3, color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        Positioned(left: 8, top: 8, child: _tag('Before')),
        Positioned(right: 8, top: 8, child: _tag('After')),
      ]);
    });
  }

  Widget _sideBySide() {
    return Row(children: <Widget>[
      Expanded(
        child: Stack(children: <Widget>[
          Positioned.fill(child: _zoomable(_picture(widget.before, 'Before'))),
          Positioned(left: 8, top: 8, child: _tag('Before')),
        ]),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Stack(children: <Widget>[
          Positioned.fill(child: _zoomable(_picture(widget.after, 'After'))),
          Positioned(left: 8, top: 8, child: _tag('After')),
        ]),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final SizeSaving s = SizeSaving(widget.before.length, widget.after.length);
    final TextTheme text = Theme.of(context).textTheme;
    return Column(children: <Widget>[
      Padding(
        padding: const EdgeInsets.all(8),
        child: SegmentedButton<CompareMode>(
          key: const Key('compare-mode'),
          segments: const <ButtonSegment<CompareMode>>[
            ButtonSegment<CompareMode>(value: CompareMode.slider, label: Text('Slider'), icon: Icon(Icons.compare)),
            ButtonSegment<CompareMode>(
                value: CompareMode.sideBySide, label: Text('Side by side'), icon: Icon(Icons.view_column)),
          ],
          selected: <CompareMode>{_mode},
          onSelectionChanged: (Set<CompareMode> m) => setState(() => _mode = m.first),
        ),
      ),
      Expanded(child: ClipRect(child: _mode == CompareMode.slider ? _slider() : _sideBySide())),
      if (_mode == CompareMode.slider)
        Slider(
          key: const Key('compare-split'),
          value: _split,
          min: 0.02,
          max: 0.98,
          semanticFormatterCallback: (double v) => 'Showing ${(v * 100).round()}% of the original',
          onChanged: (double v) => setState(() => _split = CompareLimits.clampSplit(v)),
        ),
      Semantics(
        liveRegion: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Column(children: <Widget>[
            Text(s.label, key: const Key('compare-saving'), style: text.titleMedium, textAlign: TextAlign.center),
            Text(s.sizes, key: const Key('compare-sizes'), textAlign: TextAlign.center),
          ]),
        ),
      ),
      TextButton(
        key: const Key('compare-reset-zoom'),
        style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
        onPressed: () => _zoom.value = Matrix4.identity(),
        child: const Text('Reset zoom'),
      ),
    ]);
  }
}

class _LeftPart extends CustomClipper<Rect> {
  const _LeftPart(this.split);
  final double split;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * split, size.height);

  @override
  bool shouldReclip(_LeftPart old) => old.split != split;
}

/// Full-screen page around [BeforeAfterView].
class BeforeAfterScreen extends StatelessWidget {
  const BeforeAfterScreen({super.key, required this.title, required this.before, required this.after});

  final String title;
  final Uint8List before;
  final Uint8List after;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Compare: $title')),
      body: SafeArea(child: BeforeAfterView(before: before, after: after)),
    );
  }
}
