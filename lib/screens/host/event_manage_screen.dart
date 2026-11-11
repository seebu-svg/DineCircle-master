import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_widget.dart';
import '../../api/api_exception.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../models/booking.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/host_studio_controller.dart';
import '../../providers/hosts_provider.dart';

/// Event management screen for a hosted dinner (spec section 11).
/// Edit event, manage seats, view guests, approve/reject requests,
/// message guests, send announcements, cancel event, mark attendance.
class EventManageScreen extends ConsumerStatefulWidget {
  final Dinner dinner;

  const EventManageScreen({super.key, required this.dinner});

  @override
  ConsumerState<EventManageScreen> createState() => _EventManageScreenState();
}

class _EventManageScreenState extends ConsumerState<EventManageScreen> {
  late Dinner _dinner;
  List<GuestEntry> _guests = const [];
  bool _guestsLoading = true;
  final Map<String, bool> _attendance = {};
  int _guestTab = 0; // 0 = Confirmed, 1 = Requests, 2 = Attended

  @override
  void initState() {
    super.initState();
    _dinner = widget.dinner;
    _loadGuests();
  }

  /// Seeds the guest list from `GET /bookings?eventId=` (the host's real
  /// attendees). Approve/decline post to the booking endpoints and attendance
  /// uses the check-in endpoint, so every action here hits the server.
  Future<void> _loadGuests() async {
    try {
      final bookings = await ref.read(
        eventGuestsProvider(widget.dinner.id).future,
      );
      if (!mounted) return;
      setState(() {
        _guests = bookings.map(_guestFromBooking).toList();
        _guestsLoading = false;
        for (final guest in _confirmedGuests) {
          _attendance[guest.user.id] = guest.checkIn == CheckInStatus.checkedIn;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guests = const [];
        _guestsLoading = false;
      });
    }
  }

  GuestEntry _guestFromBooking(Booking b) => GuestEntry(
    id: b.id,
    user: b.user,
    seats: b.seats,
    status: switch (b.status) {
      BookingStatus.pending => GuestRequestStatus.pending,
      BookingStatus.cancelled ||
      BookingStatus.refunded => GuestRequestStatus.cancelled,
      _ => GuestRequestStatus.approved,
    },
    requestedAt: b.createdAt,
    message: b.guestName,
    checkIn: b.checkInStatus,
    checkInTime: b.checkInTime,
  );

  List<GuestEntry> get _confirmedGuests =>
      _guests.where((g) => g.status == GuestRequestStatus.approved).toList();

  List<GuestEntry> get _pendingRequests =>
      _guests.where((g) => g.status == GuestRequestStatus.pending).toList();

  int get _guestCount => _confirmedGuests.map((g) => g.user.id).toSet().length;

  Color get _statusColor {
    switch (_dinner.hostStatus) {
      case HostEventStatus.draft:
        return AppColors.textSecondary;
      case HostEventStatus.requested:
        return AppColors.warning;
      case HostEventStatus.declined:
        return AppColors.danger;
      case HostEventStatus.published:
        return AppColors.success;
      case HostEventStatus.pausedBookings:
        return AppColors.warning;
      case HostEventStatus.completed:
        return AppColors.info;
      case HostEventStatus.cancelled:
        return AppColors.danger;
    }
  }

  /// The server accepts content edits on draft, requested, declined and
  /// confirmed experiences, and refuses them once the dinner is over or
  /// called off. Tying this to `isDraft` alone used to grey out editing for a
  /// venue-declined experience, which is precisely when the host needs it.
  bool get _isEditable =>
      _dinner.hostStatus != HostEventStatus.cancelled &&
      _dinner.hostStatus != HostEventStatus.completed;

  Future<void> _updateGuest(GuestEntry guest, GuestRequestStatus status) async {
    final approve = status == GuestRequestStatus.approved;
    try {
      final controller = ref.read(guestRequestsControllerProvider);
      if (approve) {
        await controller.approve(guest.id);
      } else {
        await controller.decline(guest.id);
      }
      if (!mounted) return;
      await _loadGuests();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? '${guest.user.name} approved: ${guest.seats} seat(s) confirmed'
                : 'Request from ${guest.user.name} declined',
          ),
          backgroundColor: approve ? AppColors.success : AppColors.surfaceHigh,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Could not update the request',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ────────────────────────────────────────────────────────────
  // Actions
  // ────────────────────────────────────────────────────────────

  void _showEditSheet() {
    final titleController = TextEditingController(text: _dinner.title);
    final priceController = TextEditingController(
      text: _dinner.pricePerSeat.toStringAsFixed(0),
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom:
                MediaQuery.of(sheetContext).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit Event', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: titleController,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(
                  labelText: 'Event Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                style: AppTextStyles.bodyMedium,
                decoration: const InputDecoration(
                  labelText: 'Price Per Seat (Rs)',
                  prefixText: 'Rs ',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.schedule_rounded,
                      color: AppColors.textSecondary,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${_dinner.formattedDate} • ${_dinner.formattedTime} (date changes require re-approval)',
                        style: AppTextStyles.caption,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final newTitle = titleController.text.trim();
                    final newPrice =
                        double.tryParse(priceController.text) ??
                        _dinner.pricePerSeat;
                    Navigator.pop(sheetContext);
                    try {
                      final updated = await ref
                          .read(eventsRepositoryProvider)
                          .patchEvent(_dinner.id, {
                            'title': newTitle.isEmpty
                                ? _dinner.title
                                : newTitle,
                            'pricePerSeat': newPrice,
                          });
                      if (!mounted) return;
                      setState(() => _dinner = updated);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Event updated'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is ApiException
                                ? e.message
                                : 'Could not update the event',
                          ),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: Text(
                    'Save Changes',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSeatsSheet() {
    int seats = _dinner.totalSeats;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Manage Seats', style: AppTextStyles.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => setSheetState(() {
                          if (seats > _dinner.bookedSeats) seats--;
                        }),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.remove_rounded),
                        ),
                      ),
                      Container(
                        width: 90,
                        alignment: Alignment.center,
                        child: Text(
                          '$seats',
                          style: AppTextStyles.headlineLarge,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setSheetState(() => seats++),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusSm,
                            ),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Icon(Icons.add_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: Text(
                      'Total capacity: ${_dinner.bookedSeats} already reserved',
                      style: AppTextStyles.caption,
                    ),
                  ),
                  if (seats < _dinner.bookedSeats)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Text(
                        'Cannot go below seats already reserved',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.danger,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: seats < _dinner.bookedSeats
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              try {
                                final updated = await ref
                                    .read(eventsRepositoryProvider)
                                    .patchEvent(_dinner.id, {
                                      'seatsTotal': seats,
                                    });
                                if (!mounted) return;
                                setState(() => _dinner = updated);
                                ScaffoldMessenger.of(
                                  this.context,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Capacity updated to $seats seats',
                                    ),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(
                                  this.context,
                                ).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      e is ApiException
                                          ? e.message
                                          : 'Could not update capacity',
                                    ),
                                    backgroundColor: AppColors.danger,
                                  ),
                                );
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: Text(
                        'Update Capacity',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAnnounceSheet() {
    const audiences = ['All Guests', 'Confirmed Only', 'Pending Requests'];
    String audience = audiences.first;
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            int recipientCount;
            switch (audience) {
              case 'Confirmed Only':
                recipientCount = _confirmedGuests.length;
                break;
              case 'Pending Requests':
                recipientCount = _pendingRequests.length;
                break;
              default:
                recipientCount =
                    _confirmedGuests.length + _pendingRequests.length;
            }
            return Padding(
              padding: EdgeInsets.only(
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                top: AppSpacing.lg,
                bottom:
                    MediaQuery.of(sheetContext).viewInsets.bottom +
                    AppSpacing.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Send Announcement', style: AppTextStyles.titleLarge),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: audiences
                        .map(
                          (a) => ChoiceChip(
                            label: Text(a),
                            selected: audience == a,
                            onSelected: (_) =>
                                setSheetState(() => audience = a),
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.25,
                            ),
                            checkmarkColor: AppColors.primary,
                            labelStyle: AppTextStyles.labelSmall,
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: titleController,
                    style: AppTextStyles.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Title (optional)',
                      hintText: 'Menu update, schedule change...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: messageController,
                    maxLines: 3,
                    style: AppTextStyles.bodyMedium,
                    decoration: const InputDecoration(
                      labelText: 'Message',
                      hintText: 'Write your announcement...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      // There is no announcement endpoint yet: the old handler
                      // only showed a success snackbar while nothing was sent.
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: Text(
                        'Send to $recipientCount Guest(s)',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Announcements are not available in this release yet.',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAttendanceSheet() {
    final attendance = Map<String, bool>.from(_attendance);
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mark Attendance',
                          style: AppTextStyles.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setSheetState(() {
                          for (final guest in _confirmedGuests) {
                            attendance[guest.user.id] = true;
                          }
                        }),
                        child: const Text('Mark all present'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(sheetContext).size.height * 0.45,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _confirmedGuests
                            .map(
                              (guest) => Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.sm,
                                ),
                                child: Row(
                                  children: [
                                    AvatarWidget(
                                      imagePath: guest.user.avatarPath,
                                      initials: guest.user.initials,
                                      size: AppSpacing.avatarSm,
                                    ),
                                    const SizedBox(width: AppSpacing.md),
                                    Expanded(
                                      child: Text(
                                        guest.user.name,
                                        style: AppTextStyles.titleSmall,
                                      ),
                                    ),
                                    _AttendanceToggle(
                                      present:
                                          attendance[guest.user.id] ?? false,
                                      onChanged: (value) => setSheetState(
                                        () => attendance[guest.user.id] = value,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        final repo = ref.read(bookingsRepositoryProvider);
                        // Persist every newly-present guest via the check-in
                        // endpoint (host is already permitted), then reload so
                        // the list reflects the server's authoritative state.
                        final toCheck = _confirmedGuests
                            .where(
                              (g) =>
                                  attendance[g.user.id] == true &&
                                  g.checkIn != CheckInStatus.checkedIn,
                            )
                            .toList();
                        try {
                          for (final g in toCheck) {
                            await repo.checkIn(g.id);
                          }
                          await _loadGuests();
                          if (!mounted) return;
                          final present = attendance.values
                              .where((v) => v)
                              .length;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Attendance saved: $present of ${_confirmedGuests.length} present',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e is ApiException
                                    ? e.message
                                    : 'Could not save attendance',
                              ),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: Text(
                        'Save Attendance',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmCancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.surfaceElevated,
          title: Text('Cancel Event?', style: AppTextStyles.titleLarge),
          content: Text(
            '$_guestCount confirmed guest(s) will be notified and their seats '
            'released. The experience leaves Explore and bookings close; the '
            'record stays so guests can still see what happened.',
            style: AppTextStyles.bodySmall,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Event'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
              ),
              child: Text(
                'Cancel Event',
                style: AppTextStyles.labelMedium.copyWith(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(eventsRepositoryProvider).cancelEvent(_dinner.id);
      if (!mounted) return;
      setState(() {
        // Soft cancel: the row survives, so the local model keeps its history
        // instead of pretending the experience never existed.
        _dinner = _dinner.copyWith(
          hostStatus: HostEventStatus.cancelled,
          cancelledAt: DateTime.now(),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Event cancelled. Confirmed guests were notified.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException ? e.message : 'Could not cancel the event',
          ),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ────────────────────────────────────────────────────────────
  // Build
  // ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCancelled = _dinner.hostStatus == HostEventStatus.cancelled;
    final venueBanner = _buildVenueBanner();
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Event')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: AppSpacing.lg),
            if (venueBanner != null) ...[
              venueBanner,
              const SizedBox(height: AppSpacing.lg),
            ],
            _buildStats(),
            const SizedBox(height: AppSpacing.lg),
            _buildActionGrid(isCancelled: isCancelled),
            const SizedBox(height: AppSpacing.xl),
            _buildGuestSection(isCancelled: isCancelled),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  /// Explains where an experience stands with the venue, and quotes the
  /// venue's reason when it declined.
  ///
  /// Returns null for every state that needs no explanation. Without this a
  /// host looking at a `requested` experience had no way to learn that diners
  /// could not book it yet, and a declined one showed only a red pill.
  Widget? _buildVenueBanner() {
    final status = _dinner.hostStatus;
    if (status != HostEventStatus.requested &&
        status != HostEventStatus.declined) {
      return null;
    }
    final declined = status == HostEventStatus.declined;
    final color = declined ? AppColors.danger : AppColors.warning;
    final title = declined
        ? _dinner.isReapproval
              ? 'Waiting on the venue again after your changes'
              : 'The venue declined this experience'
        : _dinner.isReapproval
              ? 'Your changes go back to the venue for approval'
              : 'Waiting for the venue to approve';
    final body = declined
        ? (_dinner.declineReason?.isNotEmpty == true
              ? _dinner.declineReason!
              : 'The venue did not leave a reason. Edit the experience and '
                    'publish it again to send it back to their queue.')
        : 'Diners cannot find or book this yet. '
              '${_dinner.restaurant.name} approves it from their partner app.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                declined
                    ? Icons.do_not_disturb_on_rounded
                    : Icons.hourglass_top_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // The venue's note is their own wording, so it is quoted rather than
          // summarised, and clamped so a long message cannot blow up the card.
          Text(
            body,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textPrimary,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Image.asset(
                _dinner.imagePath ?? 'assets/images/hero_tasting.png',
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
              ),
              Positioned(
                left: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    _dinner.hostStatus.label,
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_dinner.title, style: AppTextStyles.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${_dinner.formattedDate} • ${_dinner.formattedTime} – ${_dinner.formattedEndTime}',
                  style: AppTextStyles.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  '${_dinner.restaurant.name} • ${_dinner.restaurant.address}',
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    return Row(
      children: [
        Expanded(
          child: _MiniStat(
            label: 'Seats',
            value: '${_dinner.bookedSeats}/${_dinner.totalSeats}',
            color: AppColors.primary,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _MiniStat(
            label: 'Guests',
            value: '$_guestCount',
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _MiniStat(
            label: 'Requests',
            value: '${_pendingRequests.length}',
            color: _pendingRequests.isEmpty
                ? AppColors.textSecondary
                : AppColors.warning,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _MiniStat(
            label: 'Price / seat',
            value: 'Rs ${_dinner.pricePerSeat.toStringAsFixed(0)}',
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _buildActionGrid({required bool isCancelled}) {
    // Edits and capacity changes go through `PATCH /events/:id`, which the
    // server allows until an experience is completed or cancelled. At a venue
    // that reserves approval, editing a decided experience reopens it.
    final isEditable = _isEditable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 3.4,
          children: [
            _ActionCard(
              icon: Icons.edit_rounded,
              label: 'Edit Event',
              onTap: isEditable ? _showEditSheet : null,
            ),
            _ActionCard(
              icon: Icons.event_seat_rounded,
              label: 'Manage Seats',
              onTap: isEditable ? _showSeatsSheet : null,
            ),
            _ActionCard(
              icon: Icons.campaign_rounded,
              label: 'Announce',
              onTap: isCancelled ? null : _showAnnounceSheet,
            ),
            _ActionCard(
              icon: Icons.how_to_reg_rounded,
              label: 'Attendance',
              onTap: _showAttendanceSheet,
            ),
            _ActionCard(
              icon: Icons.cancel_rounded,
              label: isCancelled ? 'Event Cancelled' : 'Cancel Event',
              danger: true,
              onTap: isCancelled ? null : _confirmCancel,
            ),
          ],
        ),
        if (!isCancelled && !isEditable) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'This experience has already taken place, so its listing is '
            'locked. Cancellation, attendance and guest approval stay '
            'available for your records.',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGuestSection({required bool isCancelled}) {
    const tabs = ['Confirmed', 'Requests', 'Attended'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Guest Management', style: AppTextStyles.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (var i = 0; i < tabs.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _guestTab = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _guestTab == i
                          ? AppColors.primary
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: _guestTab == i
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      tabs[i],
                      style: AppTextStyles.labelMedium.copyWith(
                        color: _guestTab == i
                            ? Colors.white
                            : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ..._buildGuestList(),
      ],
    );
  }

  List<Widget> _buildGuestList() {
    if (_guestsLoading) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    switch (_guestTab) {
      case 1:
        return _buildRequestRows();
      case 2:
        return _buildAttendedRows();
      default:
        return _buildConfirmedRows();
    }
  }

  List<Widget> _buildConfirmedRows() {
    if (_confirmedGuests.isEmpty) {
      return const [
        _GuestEmpty(
          icon: Icons.person_off_rounded,
          message: 'No confirmed guests yet',
        ),
      ];
    }
    return _confirmedGuests
        .map(
          (guest) => _GuestRow(
            avatarPath: guest.user.avatarPath,
            initials: guest.user.initials,
            name: guest.user.name,
            subtitle:
                '${guest.seats} seat(s) • approved ${guest.requestedLabel}',
            trailing: const SizedBox.shrink(),
          ),
        )
        .toList();
  }

  List<Widget> _buildRequestRows() {
    if (_pendingRequests.isEmpty) {
      return const [
        _GuestEmpty(
          icon: Icons.mark_email_read_rounded,
          message: 'No pending requests',
        ),
      ];
    }
    return _pendingRequests
        .map(
          (guest) => Container(
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
                    AvatarWidget(
                      imagePath: guest.user.avatarPath,
                      initials: guest.user.initials,
                      size: AppSpacing.avatarSm,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            guest.user.name,
                            style: AppTextStyles.titleSmall,
                          ),
                          Text(
                            '${guest.seats} seat(s) • ${guest.requestedLabel}',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (guest.message != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      '"${guest.message}"',
                      style: AppTextStyles.bodySmall.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _updateGuest(guest, GuestRequestStatus.rejected),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            _updateGuest(guest, GuestRequestStatus.approved),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                        child: Text(
                          'Approve',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
        .toList();
  }

  List<Widget> _buildAttendedRows() {
    if (_confirmedGuests.isEmpty) {
      return const [
        _GuestEmpty(
          icon: Icons.how_to_reg_rounded,
          message: 'No guests to check in',
        ),
      ];
    }
    return _confirmedGuests.map((guest) {
      final present = _attendance[guest.user.id] ?? false;
      final checkInLabel = guest.checkIn == CheckInStatus.checkedIn
          ? 'Checked in ${guest.checkInTime != null ? _formatTime(guest.checkInTime!) : ''}'
          : guest.checkIn == CheckInStatus.expired
          ? 'Expired'
          : present
          ? 'Marked present'
          : 'Not checked in';
      final checkInColor = guest.checkIn == CheckInStatus.checkedIn || present
          ? AppColors.success
          : guest.checkIn == CheckInStatus.expired
          ? AppColors.danger
          : AppColors.textSecondary;
      return _GuestRow(
        avatarPath: guest.user.avatarPath,
        initials: guest.user.initials,
        name: guest.user.name,
        subtitle: checkInLabel,
        subtitleColor: checkInColor,
        trailing: _AttendanceToggle(
          present: present,
          onChanged: (value) => setState(() {
            _attendance[guest.user.id] = value;
          }),
        ),
      );
    }).toList();
  }

  String _formatTime(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

// ══════════════════════════════════════════════════════════════
// Widgets
// ══════════════════════════════════════════════════════════════

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(value, style: AppTextStyles.titleMedium.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.danger : AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: onTap == null
              ? AppColors.surface.withValues(alpha: 0.5)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: onTap == null ? AppColors.textTertiary : color,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.labelMedium.copyWith(
                  color: onTap == null
                      ? AppColors.textTertiary
                      : AppColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuestRow extends StatelessWidget {
  final String? avatarPath;
  final String initials;
  final String name;
  final String subtitle;
  final Color? subtitleColor;
  final Widget? trailing;

  const _GuestRow({
    required this.avatarPath,
    required this.initials,
    required this.name,
    required this.subtitle,
    this.subtitleColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          AvatarWidget(
            imagePath: avatarPath,
            initials: initials,
            size: AppSpacing.avatarSm,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: AppTextStyles.titleSmall),
                Text(
                  subtitle,
                  style: AppTextStyles.caption.copyWith(
                    color: subtitleColor ?? AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _AttendanceToggle extends StatelessWidget {
  final bool present;
  final ValueChanged<bool> onChanged;

  const _AttendanceToggle({required this.present, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleSegment('Present', true),
          _toggleSegment('Absent', false),
        ],
      ),
    );
  }

  Widget _toggleSegment(String label, bool value) {
    final selected = present == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? (value ? AppColors.success : AppColors.danger)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm - 1),
        ),
        child: Text(
          label,
          style: AppTextStyles.labelSmall.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _GuestEmpty extends StatelessWidget {
  final IconData icon;
  final String message;

  const _GuestEmpty({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textTertiary, size: 32),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}
