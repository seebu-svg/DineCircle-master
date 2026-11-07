import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../api/dto/reservation_dto.dart';
import '../../models/restaurant.dart';
import '../../models/table_reservation.dart';
import '../../providers/reservations_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';
import '../../widgets/data_view.dart';

/// Modal bottom sheet for booking a table at a restaurant.
///
/// Shows a date strip (today + 13 days), a party-size stepper (1–12), and
/// the available time slots from the server. On submit, creates a reservation
/// via [ReservationsController.create] and pops with the new [TableReservation].
class ReserveTableSheet extends ConsumerStatefulWidget {
  const ReserveTableSheet({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  ConsumerState<ReserveTableSheet> createState() => _ReserveTableSheetState();
}

class _ReserveTableSheetState extends ConsumerState<ReserveTableSheet> {
  late DateTime _selectedDate;
  int _partySize = 2;
  String _notes = '';
  AvailabilitySlotDto? _selectedSlot;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  List<DateTime> get _dateRange {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    return List.generate(14, (i) => base.add(Duration(days: i)));
  }

  AvailabilityDto? get _availability {
    final query = AvailabilityQuery(
      restaurantId: widget.restaurant.id,
      date: _selectedDate,
      partySize: _partySize,
    );
    return ref.watch(availabilityProvider(query)).valueOrNull;
  }

  Object? get _availabilityError {
    final query = AvailabilityQuery(
      restaurantId: widget.restaurant.id,
      date: _selectedDate,
      partySize: _partySize,
    );
    return ref.watch(availabilityProvider(query)).error;
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dateRange;
    final availability = _availability;

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
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Reserve a table',
                    style: AppTextStyles.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  widget.restaurant.name,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Date strip
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: dates.length,
                separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final date = dates[index];
                  final isSelected = _isSameDay(date, _selectedDate);
                  final isPast = date.isBefore(DateTime.now());
                  return _DateChip(
                    date: date,
                    isSelected: isSelected,
                    isDisabled: isPast,
                    onTap: isPast
                        ? null
                        : () => setState(() {
                              _selectedDate = date;
                              _selectedSlot = null;
                            }),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Party size stepper
            Row(
              children: [
                Text('Party size', style: AppTextStyles.labelSmall),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline_rounded),
                  onPressed: _partySize > 1
                      ? () => setState(() {
                            _partySize--;
                            _selectedSlot = null;
                          })
                      : null,
                ),
                Text(
                  '$_partySize',
                  style: AppTextStyles.titleSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _partySize < 12
                      ? () => setState(() {
                            _partySize++;
                            _selectedSlot = null;
                          })
                      : null,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Slots
            if (_availabilityError != null && availability == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: ErrorStateView(
                  error: _availabilityError!,
                  onRetry: () => ref.invalidate(
                    availabilityProvider(AvailabilityQuery(
                      restaurantId: widget.restaurant.id,
                      date: _selectedDate,
                      partySize: _partySize,
                    )),
                  ),
                ),
              )
            else if (availability == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (availability.slots.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    'No tables available on this date.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final slot in availability.slots)
                        if (slot.available)
                          _SlotChip(
                            slot: slot,
                            isSelected: _selectedSlot == slot,
                            onTap: () =>
                                setState(() => _selectedSlot = slot),
                          ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.md),

            // Notes
            TextField(
              decoration: const InputDecoration(
                hintText: 'Special requests (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
              maxLength: 200,
              onChanged: (v) => _notes = v,
            ),
            const SizedBox(height: AppSpacing.md),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  _error!,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),

            // Submit
            PrimaryButton(
              text: 'Request table',
              isLoading: _busy,
              onPressed: _selectedSlot == null || _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _submit() async {
    final slot = _selectedSlot;
    if (slot == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reservation = await ref
          .read(reservationsControllerProvider)
          .create(
            restaurantId: widget.restaurant.id,
            startAt: slot.startAt,
            partySize: _partySize,
            notes: _notes,
          );
      if (!mounted) return;
      Navigator.pop(context, reservation);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Table requested. Reference ${reservation.reference}'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not book the table. Please try again.';
      });
    }
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.date,
    required this.isSelected,
    this.isDisabled = false,
    this.onTap,
  });

  final DateTime date;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayName = dayNames[date.weekday - 1];
    final bg = isSelected
        ? AppColors.primary
        : isDisabled
            ? AppColors.border
            : AppColors.surface;
    final fg = isSelected
        ? Colors.white
        : isDisabled
            ? AppColors.textTertiary
            : AppColors.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              dayName,
              style: AppTextStyles.labelSmall.copyWith(color: fg),
            ),
            const SizedBox(height: 2),
            Text(
              '${date.day}',
              style: AppTextStyles.titleSmall.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotChip extends StatelessWidget {
  const _SlotChip({
    required this.slot,
    required this.isSelected,
    required this.onTap,
  });

  final AvailabilitySlotDto slot;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hour = slot.startAt.hour == 0
        ? 12
        : (slot.startAt.hour > 12 ? slot.startAt.hour - 12 : slot.startAt.hour);
    final minute = slot.startAt.minute.toString().padLeft(2, '0');
    final period = slot.startAt.hour < 12 ? 'AM' : 'PM';
    final label = '$hour:$minute $period';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
