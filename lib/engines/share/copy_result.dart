import 'dart:async';
import 'dart:typed_data';

/// Feature 066 — Copy result.
///
/// Puts a text or image result on the clipboard without saving a file.
/// Sensitive content (OTPs, card or ID numbers, passwords, or anything the
/// tool marks as sensitive) is cleared again after [CopyResult.clearAfter],
/// unless something else was copied in the meantime.

/// What a tool hands over to be copied.
sealed class CopyContent {
  const CopyContent({this.sensitive = false});

  /// Forces the clear-after timer on, whatever the content looks like.
  final bool sensitive;
}

class CopyText extends CopyContent {
  const CopyText(this.text, {super.sensitive});

  final String text;
}

class CopyImage extends CopyContent {
  const CopyImage(this.pngBytes, {super.sensitive, this.label = 'Picture'});

  /// PNG bytes; images go on the clipboard as images, never as a path.
  final Uint8List pngBytes;
  final String label;
}

/// The phone's clipboard. Text uses Flutter's clipboard; images need the
/// platform, which may not support them ([setImage] returns false).
abstract class ClipboardBackend {
  Future<void> setText(String text);

  /// Returns false when this phone cannot hold an image on the clipboard.
  Future<bool> setImage(Uint8List png);

  Future<String?> getText();

  Future<void> clear();
}

/// In-memory clipboard for tests and previews.
class MemoryClipboardBackend implements ClipboardBackend {
  MemoryClipboardBackend({this.supportsImages = true});

  final bool supportsImages;
  String? text;
  Uint8List? image;
  int clears = 0;

  @override
  Future<void> setText(String value) async {
    text = value;
    image = null;
  }

  @override
  Future<bool> setImage(Uint8List png) async {
    if (!supportsImages) {
      return false;
    }
    image = png;
    text = null;
    return true;
  }

  @override
  Future<String?> getText() async => text;

  @override
  Future<void> clear() async {
    text = '';
    image = null;
    clears++;
  }
}

enum CopyStatus { copied, unsupported, empty }

class CopyOutcome {
  const CopyOutcome(this.status, {this.clearsAt, this.kind = 'text'});

  final CopyStatus status;

  /// When the clipboard will be wiped, or null if it stays.
  final DateTime? clearsAt;

  /// 'text' or 'image'.
  final String kind;

  bool get ok => status == CopyStatus.copied;
  bool get willClear => clearsAt != null;

  String get message {
    switch (status) {
      case CopyStatus.empty:
        return 'Nothing to copy';
      case CopyStatus.unsupported:
        return 'This phone can\'t hold pictures on the clipboard. Use Share instead.';
      case CopyStatus.copied:
        final String what = kind == 'image' ? 'Picture copied' : 'Copied';
        return willClear ? '$what. Clipboard clears in ${CopyResult.clearAfter.inSeconds} s' : what;
    }
  }
}

/// Spots content that should not linger on the clipboard.
abstract final class SensitiveText {
  static final RegExp _otp = RegExp(r'^\s*\d{4,8}\s*$');
  static final RegExp _otpPhrase = RegExp(r'\b(otp|one[- ]time|verification code|passcode|pin)\b', caseSensitive: false);
  static final RegExp _password = RegExp(r'\b(password|passwd|pwd|cvv|secret)\b', caseSensitive: false);
  static final RegExp _pan = RegExp(r'\b[A-Z]{5}\d{4}[A-Z]\b');
  static final RegExp _aadhaar = RegExp(r'\b[2-9]\d{3}[ -]?\d{4}[ -]?\d{4}\b');
  static final RegExp _digitRun = RegExp(r'(?:\d[ -]?){12,19}');

  /// True for OTPs, passwords, PAN, Aadhaar and card numbers.
  static bool looksSensitive(String text) {
    final String t = text.trim();
    if (t.isEmpty) {
      return false;
    }
    if (_otp.hasMatch(t)) {
      return true;
    }
    if (_otpPhrase.hasMatch(t) && RegExp(r'\d{4,8}').hasMatch(t)) {
      return true;
    }
    if (_password.hasMatch(t) || _pan.hasMatch(t) || _aadhaar.hasMatch(t)) {
      return true;
    }
    for (final RegExpMatch m in _digitRun.allMatches(t)) {
      final String digits = m.group(0)!.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 13 && digits.length <= 19 && luhn(digits)) {
        return true;
      }
    }
    return false;
  }

  /// Card-number checksum.
  static bool luhn(String digits) {
    int sum = 0;
    bool alt = false;
    for (int i = digits.length - 1; i >= 0; i--) {
      int d = digits.codeUnitAt(i) - 48;
      if (d < 0 || d > 9) {
        return false;
      }
      if (alt) {
        d *= 2;
        if (d > 9) {
          d -= 9;
        }
      }
      sum += d;
      alt = !alt;
    }
    return sum % 10 == 0;
  }
}

typedef ClearScheduler = Timer Function(Duration after, void Function() callback);

Timer _defaultScheduler(Duration after, void Function() callback) => Timer(after, callback);

/// Copies results and wipes sensitive ones after a minute.
class CopyResult {
  CopyResult(this._clipboard, {ClearScheduler? schedule, DateTime Function()? now})
      : _schedule = schedule ?? _defaultScheduler,
        _now = now ?? DateTime.now;

  static const Duration clearAfter = Duration(seconds: 60);

  final ClipboardBackend _clipboard;
  final ClearScheduler _schedule;
  final DateTime Function() _now;

  Timer? _timer;

  /// What this engine last put there, so a later copy elsewhere is left alone.
  String? _ownText;
  bool _ownImage = false;
  int _generation = 0;

  /// Text that was on the clipboard before the last copy, for Undo.
  String? _previous;
  bool _canUndo = false;

  bool get canUndo => _canUndo;
  bool get clearPending => _timer?.isActive ?? false;

  bool isSensitive(CopyContent content) {
    if (content.sensitive) {
      return true;
    }
    return content is CopyText && SensitiveText.looksSensitive(content.text);
  }

  Future<CopyOutcome> copy(CopyContent content) async {
    final String? before = await _safeGetText();
    final CopyOutcome outcome;
    switch (content) {
      case CopyText(:final String text):
        if (text.isEmpty) {
          return const CopyOutcome(CopyStatus.empty);
        }
        await _clipboard.setText(text);
        _ownText = text;
        _ownImage = false;
        outcome = _copied(content, 'text');
      case CopyImage(:final Uint8List pngBytes):
        if (pngBytes.isEmpty) {
          return const CopyOutcome(CopyStatus.empty, kind: 'image');
        }
        final bool ok = await _clipboard.setImage(pngBytes);
        if (!ok) {
          return const CopyOutcome(CopyStatus.unsupported, kind: 'image');
        }
        _ownText = null;
        _ownImage = true;
        outcome = _copied(content, 'image');
    }
    _previous = before;
    _canUndo = true;
    return outcome;
  }

  CopyOutcome _copied(CopyContent content, String kind) {
    _timer?.cancel();
    _timer = null;
    final int gen = ++_generation;
    if (!isSensitive(content)) {
      return CopyOutcome(CopyStatus.copied, kind: kind);
    }
    _timer = _schedule(clearAfter, () => unawaited(_expire(gen)));
    return CopyOutcome(CopyStatus.copied, kind: kind, clearsAt: _now().add(clearAfter));
  }

  Future<void> _expire(int gen) async {
    if (gen != _generation) {
      return;
    }
    _timer = null;
    if (_ownImage) {
      // Images can't be read back on every phone; clear what we put there
      // unless text has been copied over it since.
      final String? current = await _safeGetText();
      if (current == null || current.isEmpty) {
        await _clipboard.clear();
      }
    } else {
      final String? current = await _safeGetText();
      if (current == _ownText) {
        await _clipboard.clear();
      }
    }
    _ownText = null;
    _ownImage = false;
  }

  /// Wipes the clipboard now if it still holds what we copied.
  Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    await _expire(_generation);
  }

  /// Puts back the text that was there before the last copy.
  Future<bool> undo() async {
    if (!_canUndo) {
      return false;
    }
    _timer?.cancel();
    _timer = null;
    _generation++;
    final String? prev = _previous;
    if (prev == null || prev.isEmpty) {
      await _clipboard.clear();
    } else {
      await _clipboard.setText(prev);
    }
    _ownText = null;
    _ownImage = false;
    _previous = null;
    _canUndo = false;
    return true;
  }

  Future<String?> _safeGetText() async {
    try {
      return await _clipboard.getText();
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  static CopyResult? _instance;

  /// App-wide engine; bootstrap installs the system clipboard.
  static CopyResult get instance => _instance ??= CopyResult(MemoryClipboardBackend());

  static void install(CopyResult engine) {
    _instance?.dispose();
    _instance = engine;
  }
}
