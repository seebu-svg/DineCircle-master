import 'package:flutter/material.dart';

import '../../models/deal.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Shared presentation helpers for the Deals surfaces (feed + detail).
///
/// Keeps rupee formatting, expiry math and badge pills consistent between
/// the Discover Deals screen and the Deal Details screen. All amounts come
/// straight from the server in PKR; nothing here converts or invents values.
class DealUi {
  DealUi._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `Rs 500` / `Rs 1,250` — PKR with thousands separators, no decimals
  /// unless the server value genuinely carries cents.
  static String money(num value) {
    final fractionDigits = value == value.roundToDouble() ? 0 : 2;
    final fixed = value.toStringAsFixed(fractionDigits);
    final parts = fixed.split('.');
    final grouped = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]},',
    );
    return 'Rs $grouped${parts.length > 1 ? '.${parts[1]}' : ''}';
  }

  /// `20%` — trims trailing zeros so `20.00` from the numeric column reads
  /// as a clean discount percentage.
  static String percent(num value) =>
      value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

  /// `05 Nov 2026`.
  static String date(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')} ${_months[dt.month - 1]} ${dt.year}';

  /// Days remaining until [deal] ends (may be 0 or negative for stale data).
  static int daysLeft(Deal deal) =>
      deal.endsAt.difference(DateTime.now()).inDays;

  /// Whether the deal expires within a week — drives the urgency badge and
  /// the Limited-Time Offers section.
  static bool isExpiringSoon(Deal deal) => daysLeft(deal) <= 7;

  /// Short urgency label shown on cards; null when there is no rush.
  static String? urgencyLabel(Deal deal) {
    final days = daysLeft(deal);
    if (days <= 0) return 'Expires today';
    if (days <= 7) return '$days day${days == 1 ? '' : 's'} left';
    return null;
  }

  /// Strength ranking used to pick the Featured carousel: percent deals lead,
  /// then the largest rupee discounts.
  static double rank(Deal deal) => switch (deal.kind) {
    'percent' => deal.value * 100,
    'fixed' => deal.value,
    'package' => 0,
    _ => 0,
  };
}

/// Gradient discount badge (`20% off`, `Rs 500 off`, `Package deal`).
class DealBadge extends StatelessWidget {
  const DealBadge({super.key, required this.deal, this.onDark = false});

  final Deal deal;

  /// True when the badge sits on top of cover art, where a frosted look reads
  /// better than the brand gradient.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        gradient: onDark ? null : AppColors.primaryGradient,
        color: onDark ? Colors.black.withValues(alpha: 0.55) : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: onDark
            ? Border.all(color: Colors.white.withValues(alpha: 0.25))
            : null,
      ),
      child: Text(
        deal.kindLabel,
        style: AppTextStyles.labelSmall.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Small status pill (urgency, code, city) used across deal cards.
class DealPill extends StatelessWidget {
  const DealPill({
    super.key,
    required this.label,
    this.icon,
    this.color = AppColors.textSecondary,
  });

  final String label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
