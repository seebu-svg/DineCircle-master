/// Shared harness for the responsive/overflow audit.
///
/// The audit treats a `RenderFlex overflowed` message as a test failure, so it
/// is captured from `FlutterError.onError` instead of being swallowed. Every
/// helper here is deliberately free of app state so any screen, sheet, dialog
/// or standalone widget can reuse the same matrix.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dine_circle/theme/app_theme.dart';

/// Logical widths the app is audited at: small phone → phablet → tablet.
const List<double> kAuditWidths = <double>[320, 360, 390, 430, 600];

/// Text scales: default, accessibility, maximum accessibility.
const List<double> kAuditTextScales = <double>[1.0, 1.3, 2.0];

/// Collects `RenderFlex overflowed` messages raised during a test.
class OverflowCapture {
  final List<String> errors = <String>[];
  void Function() _restore = () {};

  void _add(String error) => errors.add(error);
  void restore() => _restore();
}

/// Starts capturing overflow errors. Call [OverflowCapture.restore] before
/// asserting (use `addTearDown` for safety when an expectation throws first).
OverflowCapture startOverflowCapture() {
  final capture = OverflowCapture();
  final original = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
      capture._add(details.exceptionAsString());
    }
    original?.call(details);
  };
  capture._restore = () => FlutterError.onError = original;
  addTearDown(capture.restore);
  return capture;
}

/// Sets a logical viewport. Devices are emulated at 3x so text rasterises with
/// realistic font metrics.
void applyViewport(
  WidgetTester tester,
  double logicalWidth, {
  double? logicalHeight,
}) {
  const dpr = 3.0;
  final height = logicalHeight ?? logicalWidth * 2.0;
  tester.view.physicalSize = Size(logicalWidth * dpr, height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

/// Landscape viewport for a phone whose short side is [shortSide].
void applyLandscapeViewport(WidgetTester tester, double shortSide) {
  applyViewport(tester, shortSide * 2, logicalHeight: shortSide);
}

/// Applies an accessibility text scale.
void applyTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Simulates the software keyboard by raising the bottom view inset, which is
/// what `Scaffold.resizeToAvoidBottomInset` and every sheet's `viewInsets`
/// padding react to.
void applyKeyboardInset(WidgetTester tester, double logicalBottom) {
  tester.view.viewInsets = FakeViewPadding(
    bottom: logicalBottom * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetViewInsets);
}

/// Fails the test when any overflow was captured.
void expectNoOverflow(OverflowCapture capture, String reason) {
  expect(capture.errors, isEmpty, reason: reason);
}

/// Wraps [home] in the app theme, exactly like the running app.
Widget themedApp({required Widget home, required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.darkTheme, home: home),
  );
}
