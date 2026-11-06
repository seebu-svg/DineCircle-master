import 'package:flutter/material.dart';

import '../screens/settings/professional_onboarding_screen.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'buttons.dart';

/// Instagram-style "you need a Professional account for this" sheet.
///
/// Shared by the centre create action and Settings so there is exactly ONE
/// upgrade path: this sheet explains the switch, and the onboarding screen
/// performs it. Pops `true` when the account ends up Professional, so the
/// caller can continue into the action that was requested.
Future<bool> showAccountTypeSheet(BuildContext context) async {
  final switched = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const AccountTypeSheet(),
  );
  return switched ?? false;
}

class AccountTypeSheet extends StatelessWidget {
  const AccountTypeSheet({super.key});

  Future<void> _continue(BuildContext context) async {
    final switched = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const ProfessionalOnboardingScreen(),
      ),
    );
    if (!context.mounted) return;
    // Onboarding already republished the session; hand the answer back so the
    // caller can carry on with whatever it was trying to do.
    if (switched == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: const Icon(
                  Icons.storefront_rounded,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'Go Professional',
                  style: AppTextStyles.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Hosting is part of a Professional account: you get a public host '
            'profile and Host Studio to publish dining experiences and manage '
            'guests. It is free, and it is the same account you already use.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            key: const Key('accountTypeSheetContinue'),
            text: 'Continue',
            onPressed: () => _continue(context),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
