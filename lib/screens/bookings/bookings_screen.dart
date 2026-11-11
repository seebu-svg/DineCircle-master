import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../api/api_exception.dart';
import '../../api/app_config.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/booking.dart';
import '../../providers/users_provider.dart';
import '../../widgets/booking_check_in_sheet.dart';
import '../../widgets/booking_receipt_sheet.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/data_view.dart';
import '../../widgets/buttons.dart';
import '../detail/dinner_detail_screen.dart';
import '../map/map_screen.dart';
import '../tables/my_tables_screen.dart';

/// Bookings screen - central hub for managing all reservations (spec section 8).
///
/// Upcoming tab: QR/check-in code, event details, booking status, directions,
/// contact host, cancel booking.
/// Past tab: completed dinners, receipts, reviews, rebooking options.
/// Payments tab: wallet, methods, transaction history.
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _statusFilter = 'All';
  int _currentTab = 0;

  static const _statusFilters = [
    'All',
    'Pending',
    'Confirmed',
    'Cancelled',
    'Completed',
    'No-show',
    'Refunded',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() => _currentTab = _tabController.index);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Booking> _filterByStatus(List<Booking> bookings) {
    if (_statusFilter == 'All') return bookings;
    return bookings.where((b) => b.statusLabel == _statusFilter).toList();
  }

  void _onRebook(Booking booking) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DinnerDetailScreen(dinner: booking.dinner),
      ),
    );
  }

  Future<void> _cancelBooking(Booking booking) async {
    try {
      await ref.read(bookingsControllerProvider).cancel(booking.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Booking cancelled. Refund processing.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingsAsync = ref.watch(myBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Past'),
            Tab(text: 'Tables'),
          ],
        ),
      ),
      body: DataView<List<Booking>>(
        value: bookingsAsync,
        onRetry: () => ref.invalidate(myBookingsProvider),
        builder: (context, allBookings) {
          final filtered = _filterByStatus(allBookings);
          // Same status-plus-clock rule as My Tables: an event that has already
          // started is Past even when the booking row is still `confirmed`.
          final now = DateTime.now();
          final upcoming = filtered
              .where((b) => b.isUpcomingAt(now))
              .toList()
            ..sort((a, b) => a.dinner.dateTime.compareTo(b.dinner.dateTime));
          final past = filtered
              .where((b) => !b.isUpcomingAt(now))
              .toList()
            ..sort((a, b) => b.dinner.dateTime.compareTo(a.dinner.dateTime));

          return Column(
            children: [
              // Status filter chips, only for Upcoming and Past tabs.
              // The Tables tab uses MyTablesScreen (its own layout).
              if (_currentTab < 2)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.paddingScreen,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _statusFilters.length,
                      itemBuilder: (context, index) {
                        final filter = _statusFilters[index];
                        final isSelected = _statusFilter == filter;
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: FilterChip(
                            label: Text(
                              filter,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.textSecondary,
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: isSelected,
                            onSelected: (_) =>
                                setState(() => _statusFilter = filter),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.surfaceElevated,
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _UpcomingBookings(
                      bookings: upcoming,
                      onRebook: _onRebook,
                      onCancel: _cancelBooking,
                    ),
                    _PastBookings(bookings: past, onRebook: _onRebook),
                    const MyTablesScreen(embedded: true),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming
// ---------------------------------------------------------------------------

class _UpcomingBookings extends StatelessWidget {
  final List<Booking> bookings;
  final void Function(Booking) onRebook;
  final void Function(Booking) onCancel;

  const _UpcomingBookings({
    required this.bookings,
    required this.onRebook,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return const EmptyState(
        icon: Icons.event_busy_rounded,
        title: 'No upcoming bookings',
        message: 'When you book a dinner, it will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _UpcomingBookingCard(
          booking: booking,
          onRebook: onRebook,
          onCancel: onCancel,
        );
      },
    );
  }
}

class _UpcomingBookingCard extends StatelessWidget {
  final Booking booking;
  final void Function(Booking) onRebook;
  final void Function(Booking) onCancel;

  const _UpcomingBookingCard({
    required this.booking,
    required this.onRebook,
    required this.onCancel,
  });

  Color get _statusColor {
    switch (booking.status) {
      case BookingStatus.confirmed:
        return AppColors.success;
      case BookingStatus.pending:
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get _statusIcon {
    switch (booking.status) {
      case BookingStatus.confirmed:
        return Icons.check_circle_rounded;
      case BookingStatus.pending:
        return Icons.schedule_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  String get _statusLabel => booking.statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: image + title + status
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Image.asset(
                  booking.dinner.imagePath ?? 'assets/images/hero_tasting.png',
                  width: 64,
                  height: 64,
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
                      style: AppTextStyles.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      booking.dinner.restaurant.name,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_statusIcon, color: _statusColor, size: 12),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              _statusLabel,
                              style: AppTextStyles.labelSmall.copyWith(
                                color: _statusColor,
                                fontSize: 10,
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
            ],
          ),
          const Divider(height: 24),
          // Event details grid
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DetailChip(
                icon: Icons.calendar_today_rounded,
                label: booking.dinner.formattedDate,
              ),
              _DetailChip(
                icon: Icons.access_time_rounded,
                label: booking.dinner.formattedTime,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DetailChip(
                icon: Icons.person_rounded,
                label: '${booking.seats} seat${booking.seats > 1 ? 's' : ''}',
              ),
              _DetailChip(
                icon: Icons.payments_rounded,
                label: booking.formattedTotal,
              ),
            ],
          ),
          if (booking.promoCode != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_offer_rounded,
                    color: AppColors.success,
                    size: 12,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${booking.promoCode}: ${booking.formattedDiscount}',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.success,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // Primary CTA + overflow menu
          _buildPrimaryAction(context),
        ],
      ),
    );
  }

  /// Status-driven primary CTA with remaining actions in an overflow menu.
  Widget _buildPrimaryAction(BuildContext context) {
    // Confirmed bookings get the QR ticket as the main action.
    final isConfirmed = booking.status == BookingStatus.confirmed;
    final primaryLabel = isConfirmed ? 'Show QR Ticket' : 'Cancel Booking';
    final primaryIcon = isConfirmed
        ? Icons.qr_code_rounded
        : Icons.cancel_outlined;
    final VoidCallback primaryAction = isConfirmed
        ? () => _showQrPass(context)
        : () => _showCancelDialog(context);

    return Row(
      children: [
        Expanded(
          child: SecondaryButton(
            text: primaryLabel,
            icon: primaryIcon,
            onPressed: primaryAction,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        PopupMenuButton<String>(
          icon: const Icon(
            Icons.more_horiz_rounded,
            color: AppColors.textSecondary,
          ),
          color: AppColors.surfaceElevated,
          onSelected: (value) {
            switch (value) {
              case 'directions':
                _showDirections(context);
              case 'cancel':
                _showCancelDialog(context);
            }
          },
          itemBuilder: (ctx) => [
            PopupMenuItem(
              value: 'directions',
              child: ListTile(
                leading: Icon(Icons.directions_rounded, size: 20),
                title: Text('Directions', style: AppTextStyles.bodySmall),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (isConfirmed)
              PopupMenuItem(
                value: 'cancel',
                child: ListTile(
                  leading: Icon(
                    Icons.cancel_outlined,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  title: Text('Cancel Booking', style: AppTextStyles.bodySmall),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _showQrPass(BuildContext context) {
    showBookingCheckInSheet(context, booking);
  }

  void _showDirections(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DirectionsSheet(booking: booking),
    );
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        title: const Text('Cancel Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to cancel your booking for:',
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              booking.dinner.title,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${booking.dinner.formattedDate} · ${booking.seats} seat${booking.seats > 1 ? 's' : ''}',
              style: AppTextStyles.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.warning,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      booking.dinner.cancellationPolicy,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Booking'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onCancel(booking);
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DetailChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyles.labelSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Directions
// ---------------------------------------------------------------------------

/// Dark map style JSON, matches DineCircle's dark theme with orange accents.
const String _kDarkMapStyle =
    '[\n'
    '  {"elementType":"geometry","stylers":[{"color":"#0a090c"}]},\n'
    '  {"elementType":"labels.text.stroke","stylers":[{"color":"#1b181f"}]},\n'
    '  {"elementType":"labels.text.fill","stylers":[{"color":"#9a95a3"}]},\n'
    '  {"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c0bbb0"}]},\n'
    '  {"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#7a7070"}]},\n'
    '  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#0e1210"}]},\n'
    '  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1b181f"}]},\n'
    '  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#131116"}]},\n'
    '  {"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#6b6670"}]},\n'
    '  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#232028"}]},\n'
    '  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#1b181f"}]},\n'
    '  {"featureType":"road.highway","elementType":"labels.text.fill","stylers":[{"color":"#ff8a3d"}]},\n'
    '  {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#131116"}]},\n'
    '  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#070610"}]},\n'
    '  {"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#2a2530"}]}\n'
    ']';

class _DirectionsSheet extends StatefulWidget {
  final Booking booking;

  const _DirectionsSheet({required this.booking});

  @override
  State<_DirectionsSheet> createState() => _DirectionsSheetState();
}

class _DirectionsSheetState extends State<_DirectionsSheet> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    final restaurant = widget.booking.dinner.restaurant;

    // Launches the Google Maps app (or web) for the given travel mode. Falls
    // back to a snackbar when the venue has no coordinates on file.
    void openRoute(String travelMode) {
      if (!restaurant.hasCoordinates) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No location on file for this venue'),
            backgroundColor: AppColors.info,
          ),
        );
        return;
      }
      Navigator.pop(context);
      MapScreen.openDirections(
        lat: restaurant.latitude!,
        lng: restaurant.longitude!,
        destinationName: restaurant.name,
        travelMode: travelMode,
      );
    }

    // Null-safe address helpers, restaurant.city is String?.
    final city = restaurant.city;
    final fullAddress = city != null && city.isNotEmpty
        ? '${restaurant.address}, $city'
        : restaurant.address;
    final displayAddress = city != null && city.isNotEmpty
        ? '${restaurant.address}\n$city'
        : restaurant.address;

    final hasValidAddress = fullAddress.trim().isNotEmpty;
    final hasApiKey = AppConfig.googleMapsApiKey.isNotEmpty;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Directions + Close
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.directions_rounded,
                    color: AppColors.info,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Directions',
                    style: AppTextStyles.titleMedium,
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
            // Interactive Google Map with dark style, or placeholder when no
            // coordinates / API key are available.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceElevated,
                ),
                child: restaurant.hasCoordinates && hasApiKey
                    ? GoogleMap(
                        onMapCreated: _onMapCreated,
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            restaurant.latitude!,
                            restaurant.longitude!,
                          ),
                          zoom: 15,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('booking_venue'),
                            position: LatLng(
                              restaurant.latitude!,
                              restaurant.longitude!,
                            ),
                            infoWindow: InfoWindow(title: restaurant.name),
                          ),
                        },
                        zoomGesturesEnabled: true,
                        scrollGesturesEnabled: true,
                        rotateGesturesEnabled: true,
                        tiltGesturesEnabled: true,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                        myLocationEnabled: false,
                        style: _kDarkMapStyle,
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.map_rounded,
                            size: 48,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            restaurant.hasCoordinates
                                ? 'Map unavailable'
                                : 'No coordinates on file',
                            style: AppTextStyles.bodySmall,
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Venue name + address
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: AppTextStyles.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.textSecondary,
                        size: 16,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          displayAddress,
                          style: AppTextStyles.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Transport options: Wrap allows 3+2 layout on narrow screens.
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _TransportButton(
                  icon: Icons.directions_car_rounded,
                  label: 'Drive',
                  onTap: () => openRoute('driving'),
                ),
                _TransportButton(
                  icon: Icons.directions_transit_rounded,
                  label: 'Transit',
                  onTap: () => openRoute('transit'),
                ),
                _TransportButton(
                  icon: Icons.directions_walk_rounded,
                  label: 'Walk',
                  onTap: () => openRoute('walking'),
                ),
                _TransportButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy Address',
                  disabled: !hasValidAddress,
                  onTap: hasValidAddress
                      ? () {
                          Clipboard.setData(ClipboardData(text: fullAddress));
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Address copied to clipboard'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      : () {},
                ),
                _TransportButton(
                  icon: Icons.map_outlined,
                  label: 'Open Full Map',
                  onTap: () {
                    if (!restaurant.hasCoordinates) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No location on file for this venue'),
                          backgroundColor: AppColors.info,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context);
                    MapScreen.openDirections(
                      lat: restaurant.latitude!,
                      lng: restaurant.longitude!,
                      destinationName: restaurant.name,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TransportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool disabled;

  const _TransportButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = disabled ? () {} : onTap;
    return SizedBox(
      width:
          (MediaQuery.of(context).size.width -
              AppSpacing.lg * 2 -
              AppSpacing.sm * 2) /
          3,
      child: InkWell(
        onTap: effectiveOnTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: disabled ? AppColors.surfaceHigh : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: disabled ? AppColors.textDisabled : AppColors.border,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: disabled ? AppColors.textDisabled : AppColors.primary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: disabled ? AppColors.textDisabled : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Past
// ---------------------------------------------------------------------------

class _PastBookings extends StatelessWidget {
  final List<Booking> bookings;
  final void Function(Booking) onRebook;

  const _PastBookings({required this.bookings, required this.onRebook});

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return const EmptyState(
        icon: Icons.history_rounded,
        title: 'No past bookings',
        message: 'Your completed dinners will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return _PastBookingCard(booking: booking, onRebook: onRebook);
      },
    );
  }
}

class _PastBookingCard extends StatelessWidget {
  final Booking booking;
  final void Function(Booking) onRebook;

  const _PastBookingCard({required this.booking, required this.onRebook});

  Color get _statusColor {
    switch (booking.status) {
      case BookingStatus.completed:
        return AppColors.info;
      case BookingStatus.cancelled:
        return AppColors.danger;
      case BookingStatus.noShow:
        return AppColors.textSecondary;
      case BookingStatus.refunded:
        return AppColors.gold;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData get _statusIcon {
    switch (booking.status) {
      case BookingStatus.completed:
        return Icons.event_available_rounded;
      case BookingStatus.cancelled:
        return Icons.cancel_rounded;
      case BookingStatus.noShow:
        return Icons.person_off_rounded;
      case BookingStatus.refunded:
        return Icons.money_off_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Image.asset(
                  booking.dinner.imagePath ?? 'assets/images/hero_tasting.png',
                  width: 64,
                  height: 64,
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
                      style: AppTextStyles.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      booking.dinner.restaurant.name,
                      style: AppTextStyles.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(_statusIcon, color: _statusColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          booking.statusLabel,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: _statusColor,
                          ),
                        ),
                      ],
                    ),
                    // Honest Stripe outcome for a released hold.
                    if (booking.isPaymentFailed)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Payment failed. The hold was released and no charge was made.',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          // Event details
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DetailChip(
                icon: Icons.calendar_today_rounded,
                label: booking.dinner.formattedDate,
              ),
              _DetailChip(
                icon: Icons.access_time_rounded,
                label: booking.dinner.formattedTime,
              ),
              _DetailChip(
                icon: Icons.person_rounded,
                label: '${booking.seats} seat${booking.seats > 1 ? 's' : ''}',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _DetailChip(
                icon: Icons.payments_rounded,
                label: booking.formattedTotal,
              ),
              if (booking.promoCode != null)
                _DetailChip(
                  icon: Icons.local_offer_rounded,
                  label: booking.promoCode!,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Contextual actions
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    switch (booking.status) {
      case BookingStatus.completed:
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                text: 'Book Again',
                icon: Icons.refresh_rounded,
                onPressed: () => onRebook(booking),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: 'Review',
                    icon: Icons.star_rounded,
                    onPressed: () => _showReviewForm(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SecondaryButton(
                    text: 'Receipt',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () => _showReceipt(context),
                  ),
                ),
              ],
            ),
          ],
        );
      case BookingStatus.refunded:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    text: 'View Receipt',
                    icon: Icons.receipt_long_rounded,
                    onPressed: () => _showReceipt(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SecondaryButton(
                    text: 'Rebook',
                    icon: Icons.refresh_rounded,
                    onPressed: () => onRebook(booking),
                  ),
                ),
              ],
            ),
          ],
        );
      case BookingStatus.cancelled:
        return Row(
          children: [
            Expanded(
              child: SecondaryButton(
                text: 'View Details',
                icon: Icons.info_outline_rounded,
                onPressed: () => _showBookingDetails(context),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SecondaryButton(
                text: 'Rebook',
                icon: Icons.refresh_rounded,
                onPressed: () => onRebook(booking),
              ),
            ),
          ],
        );
      case BookingStatus.noShow:
        return SizedBox(
          width: double.infinity,
          child: SecondaryButton(
            text: 'Book Again',
            icon: Icons.refresh_rounded,
            onPressed: () => onRebook(booking),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  void _showReviewForm(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ReviewFormSheet(booking: booking),
    );
  }

  void _showReceipt(BuildContext context) {
    showBookingReceiptSheet(context, booking);
  }

  void _showBookingDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BookingDetailsSheet(booking: booking),
    );
  }
}

// ---------------------------------------------------------------------------
// Review Form
// ---------------------------------------------------------------------------

class _ReviewFormSheet extends StatefulWidget {
  final Booking booking;

  const _ReviewFormSheet({required this.booking});

  @override
  State<_ReviewFormSheet> createState() => _ReviewFormSheetState();
}

class _ReviewFormSheetState extends State<_ReviewFormSheet> {
  int _rating = 0;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
                    color: AppColors.gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Leave a Review',
                        style: AppTextStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.booking.dinner.title,
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
            const SizedBox(height: AppSpacing.lg),
            // Star rating
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(5, (i) {
                  final starIndex = i + 1;
                  return GestureDetector(
                    onTap: () => setState(() => _rating = starIndex),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starIndex <= _rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: AppColors.gold,
                        size: 36,
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (_rating > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Text(
                  _ratingLabel(_rating),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.gold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // Comment
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _controller,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Share your experience...',
                  hintStyle: AppTextStyles.bodySmall,
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // Quick tags
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children:
                  [
                    'Great food',
                    'Amazing host',
                    'Wonderful atmosphere',
                    'Would go again',
                    'Great value',
                  ].map((tag) {
                    return ActionChip(
                      label: Text(tag, style: AppTextStyles.caption),
                      onPressed: () {
                        final current = _controller.text;
                        _controller.text = current.isEmpty
                            ? '$tag. '
                            : '$current $tag. ';
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                text: 'Submit Review',
                icon: Icons.send_rounded,
                onPressed: _rating == 0
                    ? null
                    : () {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Review submitted! Thank you.'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return '';
    }
  }
}

// ---------------------------------------------------------------------------
// Booking Details (for cancelled/no-show)
// ---------------------------------------------------------------------------

class _BookingDetailsSheet extends StatelessWidget {
  final Booking booking;

  const _BookingDetailsSheet({required this.booking});

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
                Expanded(
                  child: Text(
                    'Booking Details',
                    style: AppTextStyles.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Header
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  child: Image.asset(
                    booking.dinner.imagePath ??
                        'assets/images/hero_tasting.png',
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
                        booking.dinner.title,
                        style: AppTextStyles.titleSmall,
                      ),
                      Text(
                        booking.dinner.restaurant.name,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            _statusIconFor(booking.status),
                            color: _statusColorFor(booking.status),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            booking.statusLabel,
                            style: AppTextStyles.labelSmall.copyWith(
                              color: _statusColorFor(booking.status),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Details
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Column(
                children: [
                  _DetailRow(label: 'Booking ID', value: booking.id),
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Date',
                    value: booking.dinner.formattedDate,
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Time',
                    value: booking.dinner.formattedTime,
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Venue',
                    value: booking.dinner.restaurant.name,
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Address',
                    value:
                        booking.dinner.restaurant.city != null &&
                            booking.dinner.restaurant.city!.isNotEmpty
                        ? '${booking.dinner.restaurant.address}, ${booking.dinner.restaurant.city}'
                        : booking.dinner.restaurant.address,
                  ),
                  const Divider(height: 20),
                  _DetailRow(label: 'Seats', value: '${booking.seats}'),
                  const Divider(height: 20),
                  _DetailRow(label: 'Total', value: booking.formattedTotal),
                  if (booking.guestName != null &&
                      booking.guestName!.isNotEmpty) ...[
                    const Divider(height: 20),
                    _DetailRow(label: 'Guest', value: booking.guestName!),
                  ],
                  if (booking.promoCode != null) ...[
                    const Divider(height: 20),
                    _DetailRow(
                      label: 'Promo',
                      value:
                          '${booking.promoCode} (-${booking.formattedDiscount})',
                      valueColor: AppColors.success,
                    ),
                  ],
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Payment Method',
                    value: booking.paymentMethodLabel,
                  ),
                  if (booking.paymentState !=
                      BookingPaymentState.notCharged) ...[
                    const Divider(height: 20),
                    _DetailRow(
                      label: 'Payment Status',
                      value: booking.paymentStateLabel,
                      valueColor: paymentStateColor(booking.paymentState),
                    ),
                  ],
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Booked On',
                    value:
                        '${booking.createdAt.month}/${booking.createdAt.day}/${booking.createdAt.year}',
                  ),
                  const Divider(height: 20),
                  _DetailRow(
                    label: 'Check-in',
                    value: booking.checkInStatusLabel,
                    valueColor: booking.checkInStatus == CheckInStatus.checkedIn
                        ? AppColors.success
                        : booking.checkInStatus == CheckInStatus.expired
                        ? AppColors.danger
                        : AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColorFor(BookingStatus status) {
    switch (status) {
      case BookingStatus.cancelled:
        return AppColors.danger;
      case BookingStatus.noShow:
        return AppColors.textSecondary;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _statusIconFor(BookingStatus status) {
    switch (status) {
      case BookingStatus.cancelled:
        return Icons.cancel_rounded;
      case BookingStatus.noShow:
        return Icons.person_off_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall),
        Flexible(
          child: Text(
            value,
            style: AppTextStyles.titleSmall.copyWith(
              color: valueColor ?? AppColors.textPrimary,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
