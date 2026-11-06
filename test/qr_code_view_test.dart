import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:dine_circle/widgets/qr_code_view.dart';

void main() {
  testWidgets('QrCodeView renders a real QR module for a non-empty payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: QrCodeView(data: 'DC-TEST')),
        ),
      ),
    );

    expect(find.byType(QrCodeView), findsOneWidget);
    // A genuine encoder is in play: the widget tree now contains a QrImageView.
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('QrCodeView falls back to a placeholder for empty payload', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: QrCodeView(data: '   ')),
        ),
      ),
    );

    expect(find.byType(QrImageView), findsNothing);
    expect(find.byIcon(Icons.qr_code_2_rounded), findsOneWidget);
  });
}
