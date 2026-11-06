import 'package:flutter/material.dart';

/// DineCircle Design System - Color Palette
/// Dark theme with warm amber/ember accents for a premium dining experience
class AppColors {
  AppColors._();

  // Background colors
  static const Color bg = Color(0xFF0A090C);
  static const Color surface = Color(0xFF131116);
  static const Color surfaceElevated = Color(0xFF1B181F);
  static const Color surfaceHigh = Color(0xFF232028);

  // Border colors
  static const Color border = Color(0xFF272430);
  static const Color borderLight = Color(0xFF3A3642);

  // Primary accent - warm amber/ember
  static const Color primary = Color(0xFFFF8A3D);
  static const Color primaryLight = Color(0xFFFFB347);
  static const Color primaryDark = Color(0xFFE67A2E);

  // Gold accent
  static const Color gold = Color(0xFFE9B872);
  static const Color goldLight = Color(0xFFF5D4A0);

  // Text colors
  static const Color textPrimary = Color(0xFFF5F3F0);
  static const Color textSecondary = Color(0xFF9A95A3);
  static const Color textTertiary = Color(0xFF6B6670);
  static const Color textDisabled = Color(0xFF4A4550);

  // Status colors
  static const Color success = Color(0xFF4ADE80);
  static const Color warning = Color(0xFFFBBF24);
  static const Color danger = Color(0xFFFF5C5C);
  static const Color info = Color(0xFF60A5FA);

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, primaryLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [gold, goldLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [surface, surfaceElevated],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Overlay for images
  static const LinearGradient imageOverlay = LinearGradient(
    colors: [Colors.transparent, Colors.black87],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Avatar gradients
  static const List<LinearGradient> avatarGradients = [
    LinearGradient(
      colors: [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFA770EF), Color(0xFFCF8BF3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFF093FB), Color(0xFFF5576C)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFF4481EB), Color(0xFF04BEFE)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    LinearGradient(
      colors: [Color(0xFFFA709A), Color(0xFFFEE140)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];
}
