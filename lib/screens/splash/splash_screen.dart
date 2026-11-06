import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/buttons.dart';

/// Splash screen
class SplashScreen extends StatelessWidget {
  final VoidCallback onGetStarted;

  const SplashScreen({super.key, required this.onGetStarted});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.bg, AppColors.surface],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.paddingScreen),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 60),
                  // Logo
                  const BrandMark(size: 120),
                  const SizedBox(height: AppSpacing.lg),
                  // Title
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'DineCircle',
                      style: AppTextStyles.displayLarge.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Where food influencers turn their\naudience into a dining community.',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 60),
                  // Get started button
                  PrimaryButton(text: 'Get Started', onPressed: onGetStarted),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: onGetStarted,
                    child: Text(
                      'Already have an account? Sign in',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
