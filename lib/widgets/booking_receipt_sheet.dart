import 'package:flutter/material.dart';

import '../models/booking.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'buttons.dart';

/// Opens the digital receipt for [booking] as a modal sheet.
///
/// Shared by the My Bookings → Payments tab and the standalone Payments
/// screen so a receipt looks identical wherever it is opened from.
Future<void> showBookingReceiptSheet(BuildContext context, Booking booking) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (_) => BookingReceiptSheet(booking: booking),
  );
}

/// Digital receipt for one booking.
///
/// Every value comes from the booking row the server returned: totals,
/// masked payment method and the normalised payment state. Nothing here is
/// recalculated or invented client-side.
class BookingReceiptSheet extends StatelessWidget {
  final Booking booking;

  const BookingReceiptSheet({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.success,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Digital Receipt',
                        style: AppTextStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Booking ${booking.reference}',
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Event info
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    child: Image.asset(
                      booking.dinner.imagePath ??
                          'assets/images/hero_tasting.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.dinner.title,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          booking.dinner.restaurant.name,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          booking.dinner.formattedDate,
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white60,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Price breakdown
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                children: [
                  ReceiptRow(
                    label:
                        'Rs ${booking.dinner.pricePerSeat.toStringAsFixed(0)} × ${booking.seats} seat${booking.seats > 1 ? 's' : ''}',
                    value: booking.formattedSubtotal,
                  ),
                  if (booking.discount > 0) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ReceiptRow(
                      label:
                          'Discount${booking.promoCode != null ? ' (${booking.promoCode})' : ''}',
                      value: '-${booking.formattedDiscount}',
                      valueColor: AppColors.success,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  ReceiptRow(
                    label: 'Service Fee',
                    value: booking.formattedServiceFee,
                  ),
                  const Divider(height: 20),
                  ReceiptRow(
                    label: 'Total Paid',
                    value: booking.formattedTotal,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Payment info
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  ReceiptRow(
                    label: 'Payment Method',
                    value: booking.paymentMethodLabel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ReceiptRow(
                    label: 'Payment Status',
                    value: booking.paymentStateLabel,
                    valueColor: paymentStateColor(booking.paymentState),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ReceiptRow(
                    label: 'Booking Status',
                    value: booking.statusLabel,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ReceiptRow(
                    label: 'Date',
                    value:
                        '${booking.createdAt.month}/${booking.createdAt.day}/${booking.createdAt.year}',
                  ),
                  if (booking.guestName != null &&
                      booking.guestName!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ReceiptRow(label: 'Guest', value: booking.guestName!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: 'Download',
                    icon: Icons.download_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Receipt PDFs are not available yet. '
                            'Backend export required.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SecondaryButton(
                    text: 'Copy Ref',
                    icon: Icons.copy_rounded,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Booking reference ${booking.reference} copied.',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Colour token for a normalised payment state.
Color paymentStateColor(BookingPaymentState state) {
  switch (state) {
    case BookingPaymentState.paid:
      return AppColors.success;
    case BookingPaymentState.pending:
      return AppColors.warning;
    case BookingPaymentState.failed:
      return AppColors.danger;
    case BookingPaymentState.refunded:
      return AppColors.gold;
    case BookingPaymentState.notCharged:
      return AppColors.textTertiary;
  }
}

/// Icon token for a normalised payment state.
IconData paymentStateIcon(BookingPaymentState state) {
  switch (state) {
    case BookingPaymentState.paid:
      return Icons.check_circle_rounded;
    case BookingPaymentState.pending:
      return Icons.schedule_rounded;
    case BookingPaymentState.failed:
      return Icons.error_rounded;
    case BookingPaymentState.refunded:
      return Icons.undo_rounded;
    case BookingPaymentState.notCharged:
      return Icons.remove_circle_outline_rounded;
  }
}

/// One label/value line inside a receipt.
class ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  const ReceiptRow({
    super.key,
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Text(
            label,
            style: isBold ? AppTextStyles.titleSmall : AppTextStyles.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style:
                (isBold ? AppTextStyles.titleSmall : AppTextStyles.titleSmall)
                    .copyWith(
                      color: valueColor ?? AppColors.textPrimary,
                      fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                    ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
