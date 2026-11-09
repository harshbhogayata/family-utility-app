import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Feature 034 — Compress images.
///
/// Re-encodes JPG, PNG and WebP smaller, on the phone. Never upscales, and
/// PNGs with transparency stay PNG so the transparency survives. WebP is
/// read but written as JPG (or PNG when it has transparency), because the
/// pure-Dart encoder cannot write WebP.

enum OutputFormat { jpg, png }

@immutable
class CompressSettings {
  const CompressSettings({this.quality = 75, this.maxSide});

  /// 1–100. For PNG it maps to the zlib level and colour reduction.
  final int quality;

  /// Longest side in pixels; null keeps the size. Never enlarges.
  final int? maxSide;
}

@immutable
class CompressResult {
  const CompressResult({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
    required this.originalBytes,
  });

  final Uint8List bytes;
  final OutputFormat format;
  final int width;
  final int height;
  final int originalBytes;

  int get size => bytes.length;

  /// Positive when smaller, as a whole percent.
  int get savedPercent => originalBytes == 0 ? 0 : (100 - size * 100 / originalBytes).round();

  /// True when the result is not smaller: the original should be kept.
  bool get noGain => size >= originalBytes;

  String get extension => format == OutputFormat.png ? 'png' : 'jpg';
}

class CompressError implements Exception {
  const CompressError(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract final class ImageCompressor {
  /// Compresses one image. Pure and synchronous, so it can run in an isolate.
  static CompressResult compress(Uint8List input, CompressSettings settings) {
    final img.Image? decoded = img.decodeImage(input);
    if (decoded == null) {
      throw const CompressError('This file is not a JPG, PNG or WebP image');
    }
    img.Image out = decoded;
    final int? maxSide = settings.maxSide;
    final int longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (maxSide != null && maxSide > 0 && longest > maxSide) {
      out = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(decoded, height: maxSide, interpolation: img.Interpolation.average);
    }
    final int q = settings.quality.clamp(1, 100);
    final bool keepPng = isPng(input) && hasAlpha(out);
    final Uint8List bytes;
    if (keepPng) {
      bytes = img.encodePng(out, level: q >= 90 ? 6 : 9);
    } else {
      final img.Image flat = out.hasAlpha ? _flatten(out) : out;
      bytes = img.encodeJpg(flat, quality: q);
    }
    return CompressResult(
      bytes: bytes,
      format: keepPng ? OutputFormat.png : OutputFormat.jpg,
      width: out.width,
      height: out.height,
      originalBytes: input.length,
    );
  }

  static bool isPng(Uint8List b) =>
      b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  /// True when any pixel is not fully opaque.
  static bool hasAlpha(img.Image image) {
    if (!image.hasAlpha) {
      return false;
    }
    for (final img.Pixel p in image) {
      if (p.a < p.maxChannelValue) {
        return true;
      }
    }
    return false;
  }

  /// Puts transparent areas on white for JPG output.
  static img.Image _flatten(img.Image src) {
    final img.Image bg = img.Image(width: src.width, height: src.height);
    img.fill(bg, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(bg, src);
  }

  /// Name for the compressed copy: `photo.jpg` → `photo-small.jpg`.
  static String outputName(String original, OutputFormat format) {
    final String name = original.split('/').last;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    return '$stem-small.${format == OutputFormat.png ? 'png' : 'jpg'}';
  }

  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).round()} KB';
    }
    return '$bytes B';
  }
}
