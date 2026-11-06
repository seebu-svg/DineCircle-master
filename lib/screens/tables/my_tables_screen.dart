import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/table_reservation.dart';
import '../../providers/reservations_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/data_view.dart';

/// My Tables screen — the diner's table reservations.
///
/// Backed by `GET /users/me/reservations` through [myReservationsProvider].
/// Tapping a card opens a detail bottom sheet with a cancel action for
/// reservations still in `pending` or `confirmed` status.
///
/// When [embedded] is true, the Scaffold and AppBar are omitted so the
/// widget can be placed inside a TabBarView (e.g. the Bookings tab).
class MyTablesScreen extends ConsumerWidget {
  const MyTablesScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservationsAsync = ref.watch(myReservationsProvider);
    final body = _buildBody(context, ref, reservationsAsync);

    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('My Tables', maxLines: 1),
        ),
      ),
      body: body,
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<TableReservation>> reservationsAsync,
  ) {
    return DataView<List<TableReservation>>(
        value: reservationsAsync,
        onRetry: () => ref.invalidate(myReservationsProvider),
        isEmpty: (data) => data.isEmpty,
        emptyWidget: const EmptyStateView(
          icon: Icons.event_seat_rounded,
          message: 'No tables booked yet.\nReserve one from a restaurant page.',
        ),
        builder: (context, reservations) {
          // Split into upcoming (pending/confirmed/seated) and past (completed/
          // cancelled/no-show). Upcoming first.
          final upcoming = reservations
              .where((r) =>
                  r.status == ReservationStatus.pending ||
                  r.status == ReservationStatus.confirmed ||
                  r.status == ReservationStatus.seated)
              .toList()
            ..sort((a, b) => a.startAt.compareTo(b.startAt));
          final past = reservations
              .where((r) =>
                  r.status == ReservationStatus.completed ||
                  r.status == ReservationStatus.cancelled ||
                  r.status == ReservationStatus.noShow)
              .toList()
            ..sort((a, b) => b.startAt.compareTo(a.startAt));

          if (upcoming.isEmpty && past.isEmpty) {
            return const EmptyStateView(
              icon: Icons.event_seat_rounded,
              message: 'No tables booked yet.\nReserve one from a restaurant page.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.paddingScreen),
            children: [
              if (upcoming.isNotEmpty) ...[
                Text(
                  'Upcoming',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final r in upcoming)
                  _ReservationCard(
                    reservation: r,
                    onTap: () => _showDetail(context, ref, r),
                  ),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Past',
                  style: AppTextStyles.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final r in past)
                  _ReservationCard(
                    reservation: r,
                    onTap: () => _showDetail(context, ref, r),
                  ),
              ],
              const SizedBox(height: AppSpacing.xl),
            ],
          );
        },
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, TableReservation r) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ReservationDetailSheet(reservation: r),
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({required this.reservation, this.onTap});

  final TableReservation reservation;
  final VoidCallback? onTap;

  Color get _statusColor {
    switch (reservation.status) {
      case ReservationStatus.confirmed:
        return AppColors.success;
      case ReservationStatus.pending:
        return AppColors.warning;
      case ReservationStatus.seated:
        return AppColors.info;
      case ReservationStatus.completed:
        return AppColors.textSecondary;
      case ReservationStatus.cancelled:
      case ReservationStatus.noShow:
        return AppColors.danger;
      case ReservationStatus.unknown:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reservation.restaurantName ?? 'Restaurant',
                        style: AppTextStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (reservation.city != null &&
                          reservation.city!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          reservation.city!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(
                    reservation.statusLabel,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: _statusColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                _InfoChip(
                  icon: Icons.calendar_today_rounded,
                  label: reservation.formattedDate,
                ),
                _InfoChip(
                  icon: Icons.access_time_rounded,
                  label: reservation.formattedTime,
                ),
                _InfoChip(
                  icon: Icons.people_rounded,
                  label: '${reservation.partySize}',
                ),
                _InfoChip(
                  icon: Icons.tag_rounded,
                  label: reservation.reference,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 14),
        const SizedBox(width: 4),
        Text(
          label,
          style: AppTextStyles.labelSmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ReservationDetailSheet extends ConsumerWidget {
  const _ReservationDetailSheet({required this.reservation});

  final TableReservation reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = reservation;
    return SafeArea(
      child: Padding(
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
                Expanded(
                  child: Text(
                    r.restaurantName ?? 'Reservation',
                    style: AppTextStyles.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _DetailRow(label: 'Reference', value: r.reference),
            _DetailRow(label: 'Date', value: r.formattedDate),
            _DetailRow(label: 'Time', value: r.formattedTime),
            _DetailRow(label: 'Duration', value: '${r.durationMinutes} min'),
            _DetailRow(label: 'Party size', value: '${r.partySize}'),
            _DetailRow(label: 'Status', value: r.statusLabel),
            if (r.guestName.isNotEmpty)
              _DetailRow(label: 'Guest', value: r.guestName),
            if (r.notes.isNotEmpty)
              _DetailRow(label: 'Notes', value: r.notes),
            if (r.tableLabel != null && r.tableLabel!.isNotEmpty)
              _DetailRow(label: 'Table', value: r.tableLabel!),
            if (r.isCancellable) ...[
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Cancel reservation'),
                  onPressed: () => _cancel(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel reservation?'),
        content: Text(
          'Your table at ${reservation.restaurantName ?? "the restaurant"} '
          'for ${reservation.partySize} on ${reservation.formattedDate} '
          'at ${reservation.formattedTime} will be released.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel reservation'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref
          .read(reservationsControllerProvider)
          .cancel(reservation.id);
      if (!context.mounted) return;
      Navigator.pop(context); // close sheet
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reservation cancelled.')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.bodyMedium),
          ),
        ],
      ),
    );
  }
}
