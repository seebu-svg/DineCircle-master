import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/booking.dart';
import '../../widgets/buttons.dart';
import '../../widgets/booking_check_in_sheet.dart';

/// Booking confirmed screen with digital event pass per spec section 9
class BookingConfirmedScreen extends StatelessWidget {
  final Dinner dinner;
  final Booking? booking;
  final VoidCallback? onViewBooking;

  const BookingConfirmedScreen({
    super.key,
    required this.dinner,
    this.booking,
    this.onViewBooking,
  });

  @override
  Widget build(BuildContext context) {
    // Use booking data if available, otherwise fallback defaults
    final total =
        booking?.formattedTotal ??
        'Rs ${(dinner.pricePerSeat * 1.1).toStringAsFixed(2)}';
    final paymentMethod = booking?.paymentMethodLabel ?? 'Not recorded';
    final bookingId =
        '#DC-${dinner.id.hashCode.abs().toString().substring(0, 6)}';

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('Booking Confirmed', maxLines: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () =>
              Navigator.popUntil(context, (route) => route.isFirst),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.lg),
            // Success animation placeholder
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.success.withValues(alpha: 0.2),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 50,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Booking Confirmed!',
              style: AppTextStyles.displaySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Your seat has been reserved. A confirmation has been sent to your email.',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── Digital Event Pass Preview ──
            if (booking != null)
              _PassPreviewCard(
                booking: booking!,
                onTap: () => showBookingCheckInSheet(context, booking!),
              )
            else
              // Fallback when no booking data
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        // The badge shrinks too: an ellipsis inside a
                        // non-flex row child never engages, because the row
                        // measures it with unbounded width.
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            child: Text(
                              'DINECIRCLE PASS',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // The booking id shrinks instead of pushing the pass
                        // badge out of the card on narrow devices.
                        Flexible(
                          child: Text(
                            bookingId,
                            style: AppTextStyles.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      child: Image.asset(
                        dinner.imagePath ?? 'assets/images/hero_tasting.png',
                        height: 100,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      dinner.title,
                      style: AppTextStyles.headlineSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      dinner.restaurant.name,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _PassDetail(
                            icon: Icons.calendar_today_rounded,
                            label: 'Date',
                            value: dinner.formattedDate,
                          ),
                        ),
                        Expanded(
                          child: _PassDetail(
                            icon: Icons.access_time_rounded,
                            label: 'Time',
                            value: dinner.formattedTime,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            // ── Booking Details ──
            if (booking != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Booking Details', style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _DetailRow(label: 'Booking ID', value: bookingId),
                    const Divider(height: AppSpacing.md),
                    _DetailRow(
                      label: 'Subtotal',
                      value: booking!.formattedSubtotal,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _DetailRow(
                      label: 'Service Fee',
                      value: booking!.formattedServiceFee,
                    ),
                    if (booking!.discount > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _DetailRow(
                        label: 'Discount',
                        value: booking!.formattedDiscount,
                        valueColor: AppColors.success,
                      ),
                    ],
                    const Divider(height: AppSpacing.md),
                    _DetailRow(label: 'Total Paid', value: total, isBold: true),
                    const Divider(height: AppSpacing.md),
                    _DetailRow(label: 'Payment', value: paymentMethod),
                    const SizedBox(height: AppSpacing.xs),
                    _DetailRow(
                      label: 'Status',
                      value: booking!.statusLabel,
                      valueColor: AppColors.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Actions ──
            PrimaryButton(text: 'View My Bookings', onPressed: onViewBooking),
            const SizedBox(height: AppSpacing.md),
            SecondaryButton(
              text: 'Back to Home',
              isFullWidth: true,
              onPressed: () =>
                  Navigator.popUntil(context, (route) => route.isFirst),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: () {},
              child: Text(
                'Add to Calendar',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _PassDetail extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PassDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 16),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                value,
                style: AppTextStyles.labelMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: AppTextStyles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Flexible(
          child: Text(
            value,
            style:
                (isBold ? AppTextStyles.titleSmall : AppTextStyles.labelSmall)
                    .copyWith(color: valueColor ?? AppColors.textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

/// Compact pass preview card that opens the check-in QR sheet.
class _PassPreviewCard extends StatelessWidget {
  final Booking booking;
  final VoidCallback onTap;

  const _PassPreviewCard({required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dinner = booking.dinner;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: AppColors.primary, width: 2),
        ),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                // Expanded + Align keeps the badge hugging its label while
                // still ceding width to the icon on narrow screens; the label
                // truncates instead of overflowing the card.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Text(
                        'DINECIRCLE PASS',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                          letterSpacing: 1.2,
                        ),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.qr_code_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Event info
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  child: Image.asset(
                    dinner.imagePath ?? 'assets/images/hero_tasting.png',
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dinner.title,
                        style: AppTextStyles.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dinner.restaurant.name,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${dinner.formattedDate} · ${dinner.formattedTime}',
                        style: AppTextStyles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Tap hint
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.open_in_full_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Tap to view check-in code',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
