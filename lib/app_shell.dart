import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'theme/app_colors.dart';
import 'theme/app_spacing.dart';
import 'theme/app_text_styles.dart';
import 'widgets/account_type_sheet.dart';
import 'widgets/connectivity_banner.dart';
import 'models/dinner.dart';
import 'models/restaurant.dart';
import 'models/user_profile.dart';
import 'models/discovery_category.dart';
import 'providers/events_provider.dart';
import 'providers/session_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/explore/explore_screen.dart';
import 'screens/create/create_dinner_screen.dart';
import 'screens/bookings/bookings_screen.dart';
import 'screens/deals/deals_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/qr_menu/qr_scan_screen.dart';
import 'screens/detail/dinner_detail_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'screens/booking_confirmed/booking_confirmed_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/saved/saved_screen.dart';
import 'screens/restaurant_detail/restaurant_profile_route.dart';
import 'screens/search/universal_search_screen.dart';
import 'screens/user_profile/user_profile_screen.dart';
import 'screens/location/location_screen.dart';
import 'providers/saved_locations_provider.dart';

/// Main app shell with the five primary tabs per spec:
/// Home · Explore · Scan QR (prominent centre action) · Deals · Profile.
///
/// Tab indices: 0 Home, 1 Explore, 2 Deals, 3 Profile. Scan QR is not a
/// persistent tab — it opens the camera full-screen (and keeps the hardware
/// camera alive only while the scanner route is on screen).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _currentIndex = 0;

  // Category chosen from a home tile, carried into the Explore tab.
  // (Previously used `initialCategory`; the new ExploreScreen uses tabs instead.)

  void _onCategoryTap(DiscoveryCategory category) {
    setState(() => _currentIndex = 1);
  }

  void _onDinnerTap(Dinner dinner) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DinnerDetailScreen(
          dinner: dinner,
          onJoin: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CheckoutScreen(
                  dinner: dinner,
                  onComplete: (booking) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BookingConfirmedScreen(
                          dinner: dinner,
                          booking: booking,
                          onViewBooking: () {
                            Navigator.popUntil(
                              context,
                              (route) => route.isFirst,
                            );
                            // Bookings left the bottom bar — open it as a page.
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const BookingsScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          onUserTap: _onUserTap,
          onRestaurantTap: _onRestaurantTap,
        ),
      ),
    );
  }

  void _onCreateTap() => _handleCreate();

  /// Centre navigation action — opens the branded QR scanner full-screen.
  void _onScanTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
  }

  /// Publishing requires a Professional account. A Personal account gets the
  /// shared "Go Professional" sheet (onboarding included) before the wizard,
  /// so the upgrade path is identical here and in Settings.
  Future<void> _handleCreate() async {
    if (!ref.read(canHostProvider)) {
      final switched = await showAccountTypeSheet(context);
      if (!switched) return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateDinnerScreen(
          onComplete: () {
            ref.invalidate(eventsFeedProvider);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Dinner published successfully!'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }

  void _pushPage(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _onRestaurantTap(Restaurant restaurant) {
    openRestaurantProfile(context, seed: restaurant);
  }

  void _onLocationTap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LocationScreen(
          onLocationConfirmed: (city, area) {
            ref.read(lastSelectedCityProvider.notifier).setCity(city);
            ref.read(lastSelectedAreaProvider.notifier).setArea(area);
            Navigator.pop(context);
            final label = area.isNotEmpty ? '$area, $city' : city;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Location set to $label'),
                duration: const Duration(seconds: 1),
              ),
            );
          },
        ),
      ),
    );
  }

  void _onUserTap(UserProfile user) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UserProfileScreen(user: user)),
    );
  }

  void _onNotificationsTap() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  /// Opens the universal search screen from Home's search bar. The city is
  /// editable inline via the location chip inside the screen.
  void _onOpenSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UniversalSearchScreen(onLocationTap: _onLocationTap),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ConnectivityBanner(),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                HomeScreen(
                  onDinnerTap: _onDinnerTap,
                  onNotificationsTap: _onNotificationsTap,
                  onRestaurantTap: _onRestaurantTap,
                  onCreateTap: _onCreateTap,
                  onExploreTap: () => setState(() => _currentIndex = 1),
                  onBookingsTap: () => _pushPage(const BookingsScreen()),
                  onSavedTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SavedScreen()),
                    );
                  },
                  onLocationTap: _onLocationTap,
                  onCategoryTap: _onCategoryTap,
                  onSearchTap: _onOpenSearch,
                  onOccasionTap: (_) => setState(() => _currentIndex = 1),
                  onBecomeHostTap: _handleCreate,
                ),
                ExploreScreen(
                  onDinnerTap: _onDinnerTap,
                  onRestaurantTap: _onRestaurantTap,
                  onUserTap: _onUserTap,
                  onLocationTap: _onLocationTap,
                ),
                DealsScreen(
                  onRestaurantTap: _onRestaurantTap,
                  onLocationTap: _onLocationTap,
                ),
                const ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXxl),
          ),
          border: Border(
            top: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.6)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 26,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Expanded(
                  child: _NavItem(
                    icon: Icons.home_rounded,
                    label: 'Home',
                    isSelected: _currentIndex == 0,
                    onTap: () => setState(() => _currentIndex = 0),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.explore_rounded,
                    label: 'Explore',
                    isSelected: _currentIndex == 1,
                    onTap: () => setState(() => _currentIndex = 1),
                  ),
                ),
                // Scan QR — prominent branded centre action.
                _ScanCenterAction(onTap: _onScanTap),
                Expanded(
                  child: _NavItem(
                    icon: Icons.local_offer_rounded,
                    label: 'Deals',
                    isSelected: _currentIndex == 2,
                    onTap: () => setState(() => _currentIndex = 2),
                  ),
                ),
                Expanded(
                  child: _NavItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    isSelected: _currentIndex == 3,
                    onTap: () => setState(() => _currentIndex = 3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: isSelected,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtle active-state motion: the pill lifts and gains a soft
            // tint when its tab becomes the current one.
            AnimatedScale(
              scale: isSelected ? 1.06 : 1,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Center(child: Icon(icon, color: color, size: 22)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.labelSmall.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// The centre of the bar: an elevated gradient disc carrying the brand's
/// QR-scanner glyph, sized to read as the primary action at a glance.
class _ScanCenterAction extends StatelessWidget {
  final VoidCallback onTap;

  const _ScanCenterAction({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Scan QR menu',
      // Keep the inner label Text from merging into this node's label.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.surfaceElevated,
                    width: 3,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.38),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              Text(
                'Scan QR',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
