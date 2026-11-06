import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../providers/session_provider.dart';
import '../../repositories/users_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';
import 'professional_onboarding_screen.dart';

/// Account Type — the one place the mode of the account is explained and
/// switched. Instagram-familiar: two cards, the active one ticked, the other
/// offering the switch; nothing else to learn.
class AccountTypeScreen extends ConsumerWidget {
  const AccountTypeScreen({super.key});

  Future<void> _switchToPersonal(
    BuildContext context,
    WidgetRef ref,
    AccountTypeStatus status,
  ) async {
    if (!status.canSwitchToPersonal) {
      // The screen already shows the blockers; this is the defensive path for
      // a stale status that the server would reject anyway.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have ${status.blockers.length} upcoming '
            '${status.blockers.length == 1 ? 'experience' : 'experiences'}. '
            'Cancel or complete them before switching to Personal.',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch to Personal?'),
        content: const Text(
          'Your profile becomes private and Host Studio is hidden. Your '
          'reservations, joined experiences, followers and saved places stay '
          'exactly as they are, and you can switch back at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .switchAccountType('personal');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You are now on a Personal account'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _switchToProfessional(BuildContext context) async {
    final switched = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfessionalOnboardingScreen(),
      ),
    );
    if (switched == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Professional account activated'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isProfessional = ref.watch(canHostProvider);
    final statusAsync = ref.watch(accountTypeStatusProvider);
    final status = statusAsync.valueOrNull ?? const AccountTypeStatus();

    return Scaffold(
      appBar: AppBar(title: const Text('Account Type')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          Text(
            'One account, two modes',
            style: AppTextStyles.headlineSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Switch whenever you like. Your login, your ID and everything you '
            'have saved stay on the same account.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          _AccountTypeCard(
            cardKey: 'accountTypePersonalCard',
            icon: Icons.lock_rounded,
            title: 'Personal',
            visibilityLabel: 'Private',
            tint: AppColors.info,
            selected: !isProfessional,
            points: const [
              'Discover restaurants, deals and experiences',
              'Reserve tables and join dining experiences',
              'Edit your photo, name, username, bio and preferences',
              'No Host Studio — your profile is not listed publicly',
            ],
            footer: !isProfessional
                ? null
                : PrimaryButton(
                    key: const Key('accountTypeSwitchPersonal'),
                    text: 'Switch back to Personal',
                    onPressed: statusAsync.isLoading || !status.canSwitchToPersonal
                        ? null
                        : () => _switchToPersonal(context, ref, status),
                  ),
          ),
          const SizedBox(height: AppSpacing.md),

          _AccountTypeCard(
            cardKey: 'accountTypeProfessionalCard',
            icon: Icons.public_rounded,
            title: 'Professional',
            visibilityLabel: 'Public',
            tint: AppColors.gold,
            selected: isProfessional,
            points: const [
              'Everything in Personal',
              'Public host profile listed in Hosts discovery',
              'Host Studio: create and publish dining experiences',
              'Manage guests and see basic insights',
            ],
            footer: isProfessional
                ? null
                : PrimaryButton(
                    key: const Key('accountTypeSwitchProfessional'),
                    text: 'Switch to Professional',
                    onPressed: () => _switchToProfessional(context),
                  ),
          ),

          // Blockers only exist while Professional: they explain why the
          // downgrade button above is disabled and what to resolve first.
          if (isProfessional && status.blockers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _BlockersCard(blockers: status.blockers),
          ],

          if (isProfessional && status.professionalSince != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Professional since ${_monthYear(status.professionalSince!)}',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

String _monthYear(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

/// One mode: icon, public/private badge, what it unlocks and the switch CTA.
class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.cardKey,
    required this.icon,
    required this.title,
    required this.visibilityLabel,
    required this.tint,
    required this.selected,
    required this.points,
    this.footer,
  });

  final String cardKey;
  final IconData icon;
  final String title;
  final String visibilityLabel;
  final Color tint;
  final bool selected;
  final List<String> points;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: Key(cardKey),
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(
          color: selected ? tint.withValues(alpha: 0.6) : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_rounded,
                    size: 20,
                    color: tint,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  selected && visibilityLabel == 'Private'
                      ? Icons.lock_outline_rounded
                      : Icons.public_rounded,
                  size: 12,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  selected ? '$visibilityLabel · Current' : visibilityLabel,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        point,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.md),
              footer!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The upcoming experiences that must be resolved before going private.
class _BlockersCard extends StatelessWidget {
  const _BlockersCard({required this.blockers});

  final List<AccountTypeBlocker> blockers;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('accountTypeBlockers'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_busy_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${blockers.length} upcoming '
                  '${blockers.length == 1 ? 'experience' : 'experiences'}',
                  style: AppTextStyles.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Cancel or complete these before switching to Personal. Guests '
            'keep their bookings until you do.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final blocker in blockers)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  const Icon(
                    Icons.circle,
                    size: 6,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      blocker.title,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
