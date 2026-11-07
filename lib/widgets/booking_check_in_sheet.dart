import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../models/booking.dart';
import '../providers/users_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'qr_code_view.dart';

/// The lightweight check-in pass: a decorative QR plus the authoritative
/// booking reference, and a real "Check me in" action.
///
/// Replaces the old full-screen Digital Pass for the first launch, the QR is
/// enough to show at the door, and check-in hits `POST /bookings/:id/checkin`.
Future<void> showBookingCheckInSheet(BuildContext context, Booking booking) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CheckInSheet(booking: booking),
  );
}

class _CheckInSheet extends ConsumerStatefulWidget {
  const _CheckInSheet({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_CheckInSheet> createState() => _CheckInSheetState();
}

class _CheckInSheetState extends ConsumerState<_CheckInSheet> {
  bool _busy = false;
  bool _checkedIn = false;

  Future<void> _checkIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(bookingsControllerProvider).checkIn(widget.booking.id);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _checkedIn = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked in. Enjoy the event!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      final message = error is ApiException
          ? error.message
          : 'Could not check you in. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final dinner = booking.dinner;
    final reference = booking.qrCode ?? 'DC-${booking.id.hashCode.abs()}';
    final alreadyUsed =
        _checkedIn || booking.checkInStatus == CheckInStatus.checkedIn;

    // The pass is taller than the sheet slot once the text scale is raised, so
    // the card scrolls instead of clipping the check-in action.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                dinner.title,
                style: AppTextStyles.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                dinner.restaurant.name,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              QrCodeView(data: reference, size: 180),
              const SizedBox(height: AppSpacing.md),
              Text(
                reference,
                style: AppTextStyles.titleMedium.copyWith(
                  fontFamily: 'monospace',
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Show this code at check-in',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: alreadyUsed
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusMd,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: AppColors.success,
                              size: 18,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              'Checked in',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      )
                    : FilledButton.icon(
                        onPressed: _busy ? null : _checkIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: Text(_busy ? 'Checking in…' : 'Check me in'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
