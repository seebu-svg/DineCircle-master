import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/review.dart';
import '../../models/user_profile.dart';
import '../../providers/reservations_provider.dart';
import '../../providers/restaurants_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/social_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_picker_sheet.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/buttons.dart';
import '../../widgets/delete_account_flow.dart';
import '../../widgets/edit_profile_sheet.dart';
import '../bookings/bookings_screen.dart';
import '../help/help_screen.dart';
import '../host/host_dashboard_screen.dart';
import '../location/saved_locations_screen.dart';
import '../notifications/notifications_screen.dart';
import '../preferences/food_preferences_screen.dart';
import '../saved/saved_screen.dart';
import '../settings/privacy_settings_screen.dart';
import '../settings/settings_screen.dart';
import '../tables/my_tables_screen.dart';
import '../qr_menu/qr_scan_screen.dart';
import 'profile_overview_widgets.dart';

/// Profile screen — a premium dining identity and account hub.
///
/// Organised into five vertical zones:
///   1. Identity card (photo, name, @handle, city, member-since, bio, links)
///   2. Diner stats (experiences attended, tables booked, saved places)
///   3. Activity grid (reservations, joined dinners, hosting, saved venues)
///   4. Dining preferences (cuisines, dietary, allergies — editable)
///   5. Grouped navigation menu (My Dining · Hosting · Account & Support)
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text("You'll need to sign back in to continue."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  /// Pull-to-refresh: re-reads the profile and every counter shown on screen.
  /// A failed refresh keeps the current profile and says so.
  Future<void> _refresh(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    ref
      ..invalidate(savedEventsProvider)
      ..invalidate(myBookingsProvider)
      ..invalidate(myReservationsProvider)
      ..invalidate(followedVenuesProvider);
    try {
      await ref.read(sessionControllerProvider.notifier).refresh();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not refresh your profile.')),
      );
    }
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  /// One menu row, inset so it sits comfortably inside a [ProfileMenuGroup].
  Widget _menuRow(
    IconData icon,
    String title,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: _MenuItem(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // Real counts from backend providers — no fabricated data.
    final savedCount = ref.watch(savedEventsProvider).valueOrNull?.length ?? 0;
    final bookingsCount =
        ref.watch(myBookingsProvider).valueOrNull?.length ?? 0;
    final reservationsCount =
        ref.watch(myReservationsProvider).valueOrNull?.length ?? 0;
    final savedVenuesCount =
        ref.watch(followedVenuesProvider).valueOrNull?.length ?? 0;
    final canHost = ref.watch(canHostProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => _push(context, const SettingsScreen()),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(context, ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Identity card ─────────────────────────────────
                        ProfileIdentityCard(
                          user: user,
                          onAvatarTap: () => showAvatarPickerSheet(context),
                          onEdit: () => showEditProfileSheet(context, user),
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // ── Diner stats ──────────────────────────────────
                        ProfileStatsStrip(
                          experiences: user.dinnersAttended,
                          tablesBooked: bookingsCount,
                          saved: savedCount,
                          onExperiences: () =>
                              _push(context, const BookingsScreen()),
                          onTables: () =>
                              _push(context, const MyTablesScreen()),
                          onSaved: () => _push(context, const SavedScreen()),
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── Activity shortcuts ──────────────────────────
                        const _SectionHeader(title: 'Your Activity'),
                        const SizedBox(height: AppSpacing.sm),
                        QuickActionsGrid(
                          actions: [
                            QuickAction(
                              icon: Icons.event_seat_rounded,
                              label: 'Reservations',
                              count: reservationsCount,
                              onTap: () =>
                                  _push(context, const MyTablesScreen()),
                            ),
                            QuickAction(
                              icon: Icons.local_dining_rounded,
                              label: 'Joined',
                              count: bookingsCount,
                              onTap: () => _push(context, const BookingsScreen()),
                            ),
                            if (canHost)
                              QuickAction(
                                icon: Icons.storefront_rounded,
                                label: 'Hosted',
                                tint: AppColors.gold,
                                onTap: () => _push(
                                  context,
                                  const HostDashboardScreen(initialTab: 1),
                                ),
                              ),
                            QuickAction(
                              icon: Icons.bookmark_rounded,
                              label: 'Saved',
                              count: savedVenuesCount,
                              tint: AppColors.success,
                              onTap: () =>
                                  _push(context, const SavedScreen(initialTab: 1)),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xl),

                        // ── Dining preferences ──────────────────────────
                        _SectionHeader(
                          title: 'Dining Preferences',
                          onEdit: () =>
                              _push(context, const FoodPreferencesScreen()),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _buildDiningPreferences(context, user),
                        const SizedBox(height: AppSpacing.xl),

                        // ── My Dining ────────────────────────────────
                        ProfileMenuGroup(
                          title: 'My Dining',
                          rows: [
                            _menuRow(
                              Icons.confirmation_number_rounded,
                              'My Tables & Bookings',
                              () => _push(context, const BookingsScreen()),
                            ),
                            _menuRow(
                              Icons.favorite_rounded,
                              'Saved Places & Experiences',
                              () => _push(context, const SavedScreen()),
                            ),
                            _menuRow(
                              Icons.qr_code_scanner_rounded,
                              'Scan Menu QR',
                              () => _push(context, const QrScanScreen()),
                            ),
                            _menuRow(
                              Icons.location_on_rounded,
                              'Saved Locations',
                              () =>
                                  _push(context, const SavedLocationsScreen()),
                            ),
                            _menuRow(
                              Icons.star_rounded,
                              'My Reviews',
                              () => _showMyReviewsSheet(context, user),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // ── Hosting ──────────────────────────────────
                        if (canHost) ...[
                          ProfileMenuGroup(
                            title: 'Hosting',
                            rows: [
                              _menuRow(
                                Icons.storefront_rounded,
                                'Host Studio',
                                () => _push(
                                  context,
                                  const HostDashboardScreen(),
                                ),
                                subtitle:
                                    'Manage events, analytics & collaborations',
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                        ],

                        // ── Account & Support ───────────────────────
                        ProfileMenuGroup(
                          title: 'Account & Support',
                          rows: [
                            _menuRow(
                              Icons.settings_rounded,
                              'Account Settings',
                              () => _push(context, const SettingsScreen()),
                            ),
                            _menuRow(
                              Icons.notifications_rounded,
                              'Notifications',
                              () => _push(context, const NotificationsScreen()),
                            ),
                            _menuRow(
                              Icons.privacy_tip_rounded,
                              'Privacy & Safety',
                              () => _push(
                                context,
                                const PrivacySettingsScreen(),
                              ),
                            ),
                            _menuRow(
                              Icons.help_rounded,
                              'Help & Support',
                              () => _push(context, const HelpScreen()),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),

                        // ── Log out ──────────────────────────────────
                        Center(
                          child: TextButton(
                            onPressed: () => _confirmLogout(context, ref),
                            child: Text(
                              'Log Out',
                              style: AppTextStyles.labelMedium.copyWith(
                                color: AppColors.danger,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: TextButton(
                            key: const Key('profileDeleteAccount'),
                            onPressed: () =>
                                confirmAndDeleteAccount(context, ref),
                            child: Text(
                              'Delete Account',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Dining preferences summary — shows tags for cuisines, dietary and
  /// allergies from the user model, or a prompt to set them up.
  Widget _buildDiningPreferences(BuildContext context, UserProfile user) {
    final hasInterests = user.interests.isNotEmpty;
    final hasDietary = user.dietary.isNotEmpty;
    final hasAllergies = user.allergies.isNotEmpty;
    final hasLocation = user.location != null && user.location!.isNotEmpty;
    final hasAny = hasInterests || hasDietary || hasAllergies || hasLocation;

    if (!hasAny) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Icon(
              Icons.restaurant_menu_rounded,
              color: AppColors.textTertiary,
              size: 28,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Tell us what you love to dine on.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              text: 'Set up preferences',
              icon: Icons.add_rounded,
              onPressed: () => _push(context, const FoodPreferencesScreen()),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (hasLocation)
          _DiningTag(
            user.location!,
            Icons.location_on_rounded,
            AppColors.primary,
          ),
        ...user.interests.map(
          (t) =>
              _DiningTag(t, Icons.restaurant_menu_rounded, AppColors.primary),
        ),
        ...user.dietary.map(
          (d) => _DiningTag(d, Icons.eco_rounded, AppColors.success),
        ),
        ...user.allergies.map(
          (a) => _DiningTag(a, Icons.warning_amber_rounded, AppColors.danger),
        ),
      ],
    );
  }

  /// Opens the reviews sheet showing reviews the user has received.
  void _showMyReviewsSheet(BuildContext context, UserProfile user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: _MyReviewsSheet(user: user),
      ),
    );
  }
}

// ─── Reviews sheet ──────────────────────────────────────────────────────────

/// The signed-in user's received reviews, read live from [userProfileProvider].
class _MyReviewsSheet extends ConsumerWidget {
  final UserProfile user;

  const _MyReviewsSheet({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider(user.id));
    final reviews = profileAsync.valueOrNull?.reviews ?? const <Review>[];

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Reviews You Received',
            style: AppTextStyles.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${user.reviewCount} reviews · '
            '${user.rating.toStringAsFixed(1)} average',
            style: AppTextStyles.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          if (profileAsync.isLoading && reviews.isEmpty)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text(
                'No reviews yet.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: reviews.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: AppSpacing.lg),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AvatarWidget(
                            imagePath: review.reviewer.avatarPath,
                            initials: review.reviewer.initials,
                            size: AppSpacing.avatarSm,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  review.reviewer.name,
                                  style: AppTextStyles.titleSmall,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  review.formattedDate,
                                  style: AppTextStyles.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(5, (i) {
                              return Icon(
                                i < review.rating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: AppColors.gold,
                                size: 16,
                              );
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        review.comment,
                        style: AppTextStyles.bodySmall,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Shared helper widgets ──────────────────────────────────────────────────

/// Bold section heading with optional edit action.
class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onEdit;

  const _SectionHeader({required this.title, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            title,
            style: AppTextStyles.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (onEdit != null)
          GestureDetector(
            onTap: onEdit,
            child: Text(
              'Edit',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}

/// A single tag inside the dining-preference cloud.
class _DiningTag extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _DiningTag(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// A navigation row inside a menu section.
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  const _MenuItem({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textSecondary),
      title: Text(title, style: AppTextStyles.titleSmall),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textTertiary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textTertiary,
      ),
    );
  }
}
