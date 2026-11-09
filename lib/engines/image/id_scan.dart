import 'dart:typed_data';

import 'id_card_page.dart';

/// Feature 049 — ID scan: the guided two-shot flow over feature 044's page
/// builder. Pure Dart; the camera and the disk stay in the tool.

enum IdScanStep {
  front('Step 1 of 2: front of the card', 'Place the front of the card inside the frame'),
  back('Step 2 of 2: back of the card', 'Turn the card over and place the back inside the frame'),
  review('Ready to print', 'Check both sides, then save');

  const IdScanStep(this.title, this.hint);
  final String title;
  final String hint;
}

class IdScanFlow {
  IdScanFlow({this.engine = const IdCardEngine()});

  final IdCardEngine engine;
  Uint8List? _front;
  Uint8List? _back;
  IdScanStep _step = IdScanStep.front;

  /// After a retake, go straight back to review.
  bool _retaking = false;

  IdScanStep get step => _step;
  bool get hasFront => _front != null;
  bool get hasBack => _back != null;
  Uint8List? get front => _front;
  Uint8List? get back => _back;

  /// Takes the photo for the current step and moves on.
  void capture(Uint8List photo) {
    switch (_step) {
      case IdScanStep.front:
        _front = photo;
        _step = _retaking || _back != null ? IdScanStep.review : IdScanStep.back;
      case IdScanStep.back:
        _back = photo;
        _step = IdScanStep.review;
      case IdScanStep.review:
        throw StateError('Both sides are in; retake one first');
    }
    _retaking = false;
  }

  /// Goes back to photograph one side again; the other side is kept.
  void retake(IdScanStep side) {
    if (side == IdScanStep.review) {
      throw ArgumentError.value(side, 'side', 'Retake the front or the back');
    }
    _retaking = true;
    _step = side;
  }

  /// One printable page with both sides, front above back.
  IdCardPage build(IdPaper paper) {
    final Uint8List? f = _front;
    final Uint8List? b = _back;
    if (f == null || b == null || _step != IdScanStep.review) {
      throw StateError('Photograph both sides first');
    }
    return engine.build(f, b, paper);
  }
}
