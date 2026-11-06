import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// A real, scannable QR code rendered from an authoritative payload string
/// (the booking reference). Backed by the pure-Dart `qr_flutter` encoder, so it
/// renders identically in widget tests and on the web. When [data] is empty we
/// fall back to a neutral placeholder rather than letting the encoder throw.
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    this.size = 160,
    this.foreground = Colors.black,
    this.background = Colors.white,
  });

  final String data;
  final double size;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    if (data.trim().isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.qr_code_2_rounded,
          size: size * 0.6,
          color: foreground.withValues(alpha: 0.3),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(8),
      child: QrImageView(
        data: data,
        size: size - 16,
        version: QrVersions.auto,
        backgroundColor: background,
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: foreground),
        dataModuleStyle: QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: foreground,
        ),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
