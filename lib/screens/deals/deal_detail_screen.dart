import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/deal.dart';
import '../../models/restaurant.dart';
import '../../providers/deals_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/deal_cover_image.dart';
import '../restaurant_detail/restaurant_profile_route.dart';
import 'deal_ui.dart';

/// Pushes the premium Deal Details page for [deal].
///
/// [onRestaurantTap] is forwarded so the venue action keeps using the shell's
/// shared Restaurant Profile navigation when one is available.
void openDealDetail(
  BuildContext context,
  Deal deal, {
  void Function(Restaurant restaurant)? onRestaurantTap,
}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DealDetailScreen(
        deal: deal,
        onRestaurantTap: onRestaurantTap,
      ),
    ),
  );
}

/// Deal Details, a premium, single-deal view.
///
/// Shows the offer, its cover art, the restaurant behind it, validity,
/// conditions and redemption instructions, all straight from the
/// `GET /api/deals` payload. Package deals carry a real rupee price in
/// `value`; percentage/fixed deals carry a discount, the original bill
/// depends on what the guest orders, so no prices are ever invented here.
/// Redemption happens at the restaurant: no checkout, no payment.
class DealDetailScreen extends ConsumerWidget {
  const DealDetailScreen({
    super.key,
    required this.deal,
    this.onRestaurantTap,
  });

  final Deal deal;
  final void Function(Restaurant restaurant)? onRestaurantTap;

  void _openVenue(BuildContext context) {
    final cb = onRestaurantTap;
    if (cb != null) {
      cb(
        Restaurant(
          id: deal.restaurantId,
          name: deal.restaurantName,
          description: '',
          cuisine: '',
          address: deal.city ?? '',
          city: deal.city,
          imagePath: deal.coverImage,
        ),
      );
      return;
    }
    openRestaurantProfile(context, id: deal.restaurantId);
  }

  void _copyCode(BuildContext context) {
    final code = deal.code;
    if (code == null || code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code "$code" copied'),
        backgroundColor: AppColors.surfaceHigh,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urgency = DealUi.urgencyLabel(deal);
    final cityLabel = deal.city?.trim() ?? '';
    final siblingCount = ref
        .watch(restaurantDealsProvider(deal.restaurantId))
        .valueOrNull
        ?.length;
    final venueSubtitle = siblingCount != null && siblingCount > 1
        ? '${cityLabel.isNotEmpty ? cityLabel : deal.restaurantName} · '
              '$siblingCount active deals'
        : (cityLabel.isNotEmpty ? cityLabel : 'Tap to view the full profile');

    // Partner terms copy embeds redemption steps after a "How to redeem:"
    // marker (see the deals seed); split so each lands under its own heading.
    final termsText = deal.terms.trim();
    final markerIndex = termsText.toLowerCase().indexOf('how to redeem:');
    final conditions = markerIndex < 0
        ? termsText
        : termsText.substring(0, markerIndex).trim();
    final redemption = markerIndex < 0
        ? null
        : termsText.substring(markerIndex).trim();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
        title: const Text('Deal Details'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxxl),
        children: [
          // ── Hero cover ──
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXxl),
              child: SizedBox(
                height: 240,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DealCoverImage(source: deal.coverImage),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black87,
                          ],
                          stops: [0.45, 1.0],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                    Positioned(
                      top: AppSpacing.md,
                      left: AppSpacing.md,
                      child: DealBadge(deal: deal, onDark: true),
                    ),
                    Positioned(
                      left: AppSpacing.lg,
                      right: AppSpacing.lg,
                      bottom: AppSpacing.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            deal.restaurantName.toUpperCase(),
                            style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.primaryLight,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            deal.title,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Quick facts ──
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                DealPill(
                  label: 'Valid till ${DealUi.date(deal.endsAt)}',
                  icon: Icons.event_available_rounded,
                  color: AppColors.success,
                ),
                if (urgency != null)
                  DealPill(
                    label: urgency,
                    icon: Icons.schedule_rounded,
                    color: AppColors.danger,
                  ),
                if (deal.city != null && deal.city!.trim().isNotEmpty)
                  DealPill(
                    label: deal.city!.trim(),
                    icon: Icons.location_on_outlined,
                  ),
                if (deal.startsAt.isAfter(DateTime.now()))
                  DealPill(
                    label: 'Starts ${DealUi.date(deal.startsAt)}',
                    icon: Icons.event_rounded,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── The offer ──
          _SectionLabel(label: 'The Offer'),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  deal.kindLabel,
                  style: AppTextStyles.displaySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  switch (deal.kind) {
                    'percent' =>
                      'Save ${DealUi.percent(deal.value)}% at ${deal.restaurantName}. '
                      'The discount is computed on your final bill and applied '
                      'by the restaurant when you order.',
                    'fixed' =>
                      'Save ${DealUi.money(deal.value)} at ${deal.restaurantName}. '
                      'The reduction is applied to your final bill by the '
                      'restaurant.',
                    'package' =>
                      'A curated package from ${deal.restaurantName} at the '
                      'fixed price of ${DealUi.money(deal.value)}. Ask the '
                      'restaurant what the package includes.',
                    _ => deal.description,
                  },
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (deal.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(deal.description, style: AppTextStyles.bodyMedium),
                ],
                // Redemption capacity, only surfaced when the partner set it.
                if (deal.maxRedemptions != null && deal.maxRedemptions! > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 16,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${(deal.maxRedemptions! - deal.redemptions).clamp(0, deal.maxRedemptions!)} '
                        'of ${deal.maxRedemptions} redemptions left',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // ── Promo code ──
          if (deal.requiresCode) ...[
            const SizedBox(height: AppSpacing.md),
            _DetailCard(
              highlight: true,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'REDEMPTION CODE',
                          style: AppTextStyles.overline.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          deal.code!,
                          style: AppTextStyles.headlineSmall.copyWith(
                            color: AppColors.gold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _copyCode(context),
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: const Text(
                      'Copy',
                      style: TextStyle(color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Conditions ──
          if (conditions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _SectionLabel(label: 'Conditions'),
            _DetailCard(
              child: Text(
                conditions,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],

          // ── How to redeem ──
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(label: 'How to Redeem'),
          _DetailCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RedeemStep(
                  index: 1,
                  text: 'Visit ${deal.restaurantName}'
                      '${cityLabel.isNotEmpty ? ' in $cityLabel' : ''} '
                      'any time before ${DealUi.date(deal.endsAt)}.',
                ),
                _RedeemStep(
                  index: 2,
                  text: deal.requiresCode
                      ? 'Show the code ${deal.code} to your server when ordering.'
                      : 'Tell the staff you found this offer on DineCircle.',
                ),
                _RedeemStep(
                  index: 3,
                  text: 'The restaurant applies the deal to your bill. You '
                      'pay the venue directly. DineCircle never charges you.',
                ),
                if (redemption != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    redemption,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Restaurant ──
          const SizedBox(height: AppSpacing.lg),
          _SectionLabel(label: 'Restaurant'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: Semantics(
              button: true,
              label: 'View ${deal.restaurantName} profile',
              child: GestureDetector(
                onTap: () => _openVenue(context),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        child: SizedBox(
                          width: 52,
                          height: 52,
                          child: DealCoverImage(source: deal.coverImage),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              deal.restaurantName,
                              style: AppTextStyles.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              venueSubtitle,
                              style: AppTextStyles.bodySmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Primary action ──
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.paddingScreen,
              AppSpacing.lg,
              AppSpacing.paddingScreen,
              0,
            ),
            child: Row(
              children: [
                if (deal.requiresCode) ...[
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () => _openVenue(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('Visit Restaurant'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _copyCode(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.gold,
                        side: const BorderSide(color: AppColors.gold),
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      child: const Text('Copy Code'),
                    ),
                  ),
                ] else
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openVenue(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.storefront_rounded, size: 18),
                      label: const Text('Visit Restaurant'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: Text(
              'Redeem this offer at the restaurant. DineCircle deals are '
              'settled at the venue. There is no in-app payment.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Building blocks ────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        0,
        AppSpacing.paddingScreen,
        AppSpacing.sm,
      ),
      child: Text(
        label.toUpperCase(),
        style: AppTextStyles.overline.copyWith(color: AppColors.primary),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child, this.highlight = false});

  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.paddingScreen),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(
            color: highlight ? AppColors.gold.withValues(alpha: 0.5) : AppColors.border,
          ),
        ),
        child: child,
      ),
    );
  }
}

class _RedeemStep extends StatelessWidget {
  const _RedeemStep({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Center(
              child: Text(
                '$index',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
