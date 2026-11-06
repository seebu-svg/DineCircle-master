import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// DineCircle Design System - Typography
/// Premium typography hierarchy with careful spacing and weights
class AppTextStyles {
  AppTextStyles._();

  // Display styles
  static TextStyle get displayLarge => GoogleFonts.inter(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  static TextStyle get displayMedium => GoogleFonts.inter(
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: AppColors.textPrimary,
    height: 1.25,
  );

  static TextStyle get displaySmall => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  // Headline styles
  static TextStyle get headlineLarge => GoogleFonts.inter(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle get headlineMedium => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.35,
  );

  static TextStyle get headlineSmall => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // Title styles
  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get titleSmall => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  // Body styles
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // Label styles
  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
    color: AppColors.textPrimary,
    height: 1.4,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Caption
  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.2,
    color: AppColors.textSecondary,
    height: 1.4,
  );

  // Button text
  static TextStyle get button => GoogleFonts.inter(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
    height: 1.0,
  );

  // Overline
  static TextStyle get overline => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.5,
    color: AppColors.textSecondary,
    height: 1.0,
  );
}
