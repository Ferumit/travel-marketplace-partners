import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// Generates solid, uniform-size PNG marker icons for map placemarks.
///
/// All markers are 96 px × 96 px, fully opaque, and share the same
/// circular shape with a white ring + color fill + white icon.
///   • Driver  – blue  #007AFF  (car icon)
///   • Guide   – green #34C759  (flag icon)
///   • Client  – orange #FF9500 (person icon)
class UserMarkerPainter {
  UserMarkerPainter._();

  static const double _size = 96.0;
  static const double _outerR = 44.0;
  static const double _innerR = 36.0;
  static const double _iconSize = 38.0;

  static const Color colorDriver = Color(0xFF007AFF); // blue
  static const Color colorGuide  = Color(0xFF34C759); // green
  static const Color colorClient = Color(0xFFFF9500); // orange

  /// Returns a solid PNG for the Driver role (blue, car icon).
  static Future<Uint8List?> driver() =>
      _build(colorDriver, LucideIcons.car);

  /// Returns a solid PNG for the Guide role (green, flag icon).
  static Future<Uint8List?> guide() =>
      _build(colorGuide, LucideIcons.flag);

  /// Returns a solid PNG for the Client role (orange, person icon).
  static Future<Uint8List?> client() =>
      _build(colorClient, LucideIcons.user);

  static Future<Uint8List?> _build(Color color, IconData icon) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const center   = Offset(_size / 2, _size / 2);

    // White outer ring (solid background so map tile doesn't bleed through)
    canvas.drawCircle(center, _outerR,
        Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Colored inner fill
    canvas.drawCircle(center, _innerR,
        Paint()..color = color..style = PaintingStyle.fill);

    // White icon centred inside
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: _iconSize,
          color: Colors.white,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

    final img  = await recorder.endRecording()
        .toImage(_size.toInt(), _size.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}
