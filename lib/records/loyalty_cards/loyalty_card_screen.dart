import 'dart:async';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';

import '../../engines/records/loyalty_cards.dart';

/// The barcode a till scanner reads, for [f].
Barcode barcodeFor(CardFormat f) => switch (f) {
      CardFormat.code128 => Barcode.code128(),
      CardFormat.ean13 => Barcode.ean13(),
      CardFormat.ean8 => Barcode.ean8(),
      CardFormat.upcA => Barcode.upcA(),
      CardFormat.code39 => Barcode.code39(),
      CardFormat.itf => Barcode.itf(),
      CardFormat.codabar => Barcode.codabar(),
      CardFormat.qr => Barcode.qrCode(),
      CardFormat.pdf417 => Barcode.pdf417(),
      CardFormat.dataMatrix => Barcode.dataMatrix(),
      CardFormat.aztec => Barcode.aztec(),
    };

/// Feature 100 — the card at the till: black on white, full brightness
/// while open, the old level put back on leaving. Drawn on the phone, so it
/// works with no signal.
class LoyaltyCardScreen extends StatefulWidget {
  const LoyaltyCardScreen({super.key, required this.card, required this.brightness});

  final LoyaltyCard card;
  final ScreenBrightness brightness;

  @override
  State<LoyaltyCardScreen> createState() => _LoyaltyCardScreenState();
}

class _LoyaltyCardScreenState extends State<LoyaltyCardScreen> {
  double? _before;
  bool _read = false;

  @override
  void initState() {
    super.initState();
    unawaited(_brighten());
  }

  Future<void> _brighten() async {
    try {
      _before = await widget.brightness.current();
      if (!mounted) {
        return;
      }
      _read = true;
      await widget.brightness.set(1.0);
    } catch (_) {
      // No native side: the card still shows.
    }
  }

  Future<void> _restore() async {
    try {
      await widget.brightness.set(_before);
    } catch (_) {
      // Nothing to put back.
    }
  }

  @override
  void dispose() {
    if (_read) {
      unawaited(_restore());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LoyaltyCard c = widget.card;
    const TextStyle ink = TextStyle(color: Colors.black);
    return Theme(
      data: ThemeData.light(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          title: Text(c.store),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Semantics(
                    label: '${c.store} card barcode, number ${c.number}',
                    image: true,
                    child: ExcludeSemantics(
                      child: BarcodeWidget(
                        key: const Key('lc-barcode'),
                        barcode: barcodeFor(c.format),
                        data: c.number,
                        width: c.isLinear ? double.infinity : 260,
                        height: c.isLinear ? 140 : 260,
                        color: Colors.black,
                        backgroundColor: Colors.white,
                        drawText: false,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        errorBuilder: (BuildContext context, String error) => Text(
                          'This number cannot be drawn as ${LoyaltyCards.formatLabel(c.format)}. Show the number instead.',
                          key: const Key('lc-barcode-error'),
                          style: ink,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    c.number,
                    key: const Key('lc-number'),
                    style: const TextStyle(color: Colors.black, fontSize: 24, letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  if (c.note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(c.note, style: ink, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    '${LoyaltyCards.formatLabel(c.format)} · screen at full brightness · works offline',
                    style: const TextStyle(color: Colors.black54, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
