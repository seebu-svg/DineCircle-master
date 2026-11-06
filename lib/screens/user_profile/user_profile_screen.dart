import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/safety.dart';
import '../../models/user_profile.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/avatar_widget.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../providers/events_provider.dart';
import '../../screens/safety/report_sheet.dart';
import '../../screens/safety/safety_actions.dart';

/// Public host profile screen — experience-first design (spec section 13).
///
/// Answers three questions:
/// 1. Who is hosting?
/// 2. Why should I trust them?
/// 3. What dining experiences can I join?
class UserProfileScreen extends ConsumerStatefulWidget {
  final UserProfile user;
  final void Function(Dinner dinner)? onDinnerTap;

  const UserProfileScreen({super.key, required this.user, this.onDinnerTap});

  @override
  ConsumerState<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends ConsumerState<UserProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider(widget.user.id));
    final profile = profileAsync.valueOrNull;
    final user = profile?.user ?? widget.user;
    // Use the dedicated host-events feed (all events, upcoming + past) so we
    // can split them into two groups on-screen.
    final allHosted = ref.watch(hostEventsProvider(widget.user.id)).valueOrNull ??
        profile?.hostedUpcoming ??
        const <Dinner>[];
    final now = DateTime.now();
    final upcoming = allHosted
        .where((d) => d.dateTime.isAfter(now) && d.hostStatus != HostEventStatus.cancelled)
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final past = allHosted
        .where((d) => d.dateTime.isBefore(now))
        .toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    final isSelf = ref.watch(currentUserIdProvider) == widget.user.id;
    final isLoading = profileAsync.isLoading && profile == null;
    final hasError = profileAsync.hasError && profile == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.name),
        actions: [
          if (!isSelf)
            PopupMenuButton<String>(
              key: const Key('profileSafetyMenu'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) async {
                if (!mounted) return;
                if (value == 'report') {
                  await ReportSheet.show(
                    context,
                    ReportTargetType.user,
                    widget.user.id,
                  );
                } else if (value == 'block') {
                  await confirmAndBlock(
                    context: context,
                    ref: ref,
                    userId: widget.user.id,
                    userName: widget.user.name,
                    popOnSuccess: true,
                  );
                } else if (value == 'share') {
                  await Clipboard.setData(
                    ClipboardData(text: 'Check out ${user.name} on DineCircle'),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile link copied')),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  key: Key('profileReportAction'),
                  value: 'report',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.flag_outlined),
                    title: Text('Report profile'),
                  ),
                ),
                PopupMenuItem<String>(
                  key: const Key('profileShareAction'),
                  value: 'share',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.share_rounded),
                    title: const Text('Share profile'),
                  ),
                ),
                const PopupMenuItem<String>(
                  key: Key('profileBlockAction'),
                  value: 'block',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.block_rounded, color: AppColors.danger),
                    title: Text(
                      'Block user',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: _buildBody(
        context,
        isLoading: isLoading,
        hasError: hasError,
        user: user,
        upcomingEvents: upcoming,
        pastEvents: past,
        isSelf: isSelf,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isLoading,
    required bool hasError,
    required UserProfile user,
    required List<Dinner> upcomingEvents,
    required List<Dinner> pastEvents,
    required bool isSelf,
  }) {
    if (hasError) {
      return _ErrorState(
        onRetry: () => ref.invalidate(userProfileProvider(widget.user.id)),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          _buildHeader(user),
          const SizedBox(height: AppSpacing.md),

          // ── Action buttons ──────────────────────────────────────────────
          if (!isSelf) ...[
            _buildActionRow(user),
            const SizedBox(height: AppSpacing.lg),
          ],

          // ── Stats ───────────────────────────────────────────────────────
          _buildStats(user),
          const SizedBox(height: AppSpacing.lg),

          // ── Upcoming Experiences (prioritized) ──────────────────────────
          // A Personal account is private: their hosted experiences are not
          // advertised, matching the server's `hostedUpcoming` gate.
          if (user.isProfessional) ...[
            _buildExperiences(upcomingEvents),

            // ── Past Experiences ──────────────────────────────────────────
            if (pastEvents.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _buildPastExperiences(pastEvents),
            ],
          ] else
            _buildPrivateNotice(),

          // ── Ratings & Reviews ───────────────────────────────────────────
          const SizedBox(height: AppSpacing.lg),
          _buildRatings(user),

          // ── Interests ───────────────────────────────────────────────────
          if (user.interests.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _buildInterests(user),
          ],

          // ── Social links ────────────────────────────────────────────────
          if (user.socialLinks.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _buildSocialLinks(user),
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(UserProfile user) {
    return Column(
      children: [
        AvatarWidget(
          imagePath: user.avatarPath,
          initials: user.initials,
          size: AppSpacing.avatarXl,
          gradientIndex: user.id.hashCode % 6,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Name + verified badge
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                user.name,
                style: AppTextStyles.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (user.isVerified) ...[
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.verified_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ],
          ],
        ),
        // Bio
        if (user.bio != null && user.bio!.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            user.bio!,
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        // Account mode + host badges
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          alignment: WrapAlignment.center,
          children: [
            _Badge(
              key: const Key('publicProfileAccountType'),
              icon: user.isProfessional
                  ? Icons.public_rounded
                  : Icons.lock_rounded,
              label: user.isProfessional ? 'Professional' : 'Private',
              gradient: user.isProfessional,
            ),
            if (user.isInfluencer)
              _Badge(
                icon: Icons.star_rounded,
                label: 'Food Influencer',
                gradient: true,
              ),
            if (user.isRestaurantPartner)
              _Badge(
                icon: Icons.restaurant_rounded,
                label: 'Restaurant Partner',
                gradient: false,
              ),
          ],
        ),
      ],
    );
  }

  /// Shown instead of the experiences feed for a Personal (private) account.
  Widget _buildPrivateNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.lock_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'This is a private profile. Dining experiences hosted here are '
              'not listed publicly.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionRow(UserProfile user) {
    return Row(
      children: [
        // Share (compact icon button for narrow devices)
        Expanded(
          child: SecondaryButton(
            text: 'Share',
            icon: Icons.share_rounded,
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: 'Check out ${user.name} on DineCircle'),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile link copied')),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Widget _buildStats(UserProfile user) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.md,
        horizontal: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ProfileStat(
              value: '${user.dinnersHosted}',
              label: 'Hosted',
            ),
          ),
          _divider(),
          Expanded(
            child: _ProfileStat(
              value: '${user.dinnersAttended}',
              label: 'Attended',
            ),
          ),
          _divider(),
          Expanded(
            child: _ProfileStat(value: '${user.followers}', label: 'Followers'),
          ),
          _divider(),
          Expanded(
            child: _ProfileStat(value: '${user.following}', label: 'Following'),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 32, color: AppColors.border);

  // ── Upcoming Experiences ──────────────────────────────────────────────────

  Widget _buildExperiences(List<Dinner> hostedEvents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Upcoming Experiences', style: AppTextStyles.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (hostedEvents.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  color: AppColors.textTertiary,
                  size: 32,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'No upcoming experiences yet',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          )
        else
          ...hostedEvents.map(
            (dinner) => _ExperienceTile(
              dinner: dinner,
              onTap: () => widget.onDinnerTap?.call(dinner),
            ),
          ),
      ],
    );
  }

  Widget _buildPastExperiences(List<Dinner> pastEvents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Past Experiences',
          style: AppTextStyles.titleMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Opacity(
          opacity: 0.6,
          child: Column(
            children: pastEvents
                .map(
                  (dinner) => _PastExperienceTile(
                    dinner: dinner,
                    onTap: () => widget.onDinnerTap?.call(dinner),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  // ── Ratings & Trust ──────────────────────────────────────────────────────

  Widget _buildRatings(UserProfile user) {
    final hasReviews = user.reviewCount > 0;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Star icon with rating value
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Center(
              child: Text(
                user.rating > 0 ? user.rating.toStringAsFixed(1) : '—',
                style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasReviews
                      ? '${user.rating.toStringAsFixed(1)} from ${user.reviewCount} review${user.reviewCount == 1 ? '' : 's'}'
                      : 'No reviews yet',
                  style: AppTextStyles.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasReviews) ...[
                  const SizedBox(height: 2),
                  _StarBar(rating: user.rating),
                ] else
                  Text(
                    'Reviews appear after hosted experiences',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                if (user.isVerified) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.success,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Verified host',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Interests ─────────────────────────────────────────────────────────────

  Widget _buildInterests(UserProfile user) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Interests', style: AppTextStyles.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: user.interests
              .map((i) => TagChip(label: i, onTap: () {}))
              .toList(),
        ),
      ],
    );
  }

  // ── Social links ──────────────────────────────────────────────────────────

  Widget _buildSocialLinks(UserProfile user) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.center,
      children: user.socialLinks
          .map(
            (link) => Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(link.platform.icon, color: AppColors.primary, size: 14),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    link.handle,
                    style: AppTextStyles.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// =============================================================================
// Private helper widgets
// =============================================================================

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  const _ProfileStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.titleMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool gradient;
  const _Badge({
    super.key,
    required this.icon,
    required this.label,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        gradient: gradient ? AppColors.goldGradient : null,
        color: gradient ? null : AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: gradient ? null : Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: gradient ? Colors.white : AppColors.primary,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: gradient ? Colors.white : AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StarBar extends StatelessWidget {
  final double rating;
  const _StarBar({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = i < rating.round();
        return Icon(
          filled ? Icons.star_rounded : Icons.star_border_rounded,
          color: AppColors.gold,
          size: 14,
        );
      }),
    );
  }
}

/// Hosted experience tile — shows image, title, venue, date, price, and CTA.
class _ExperienceTile extends StatelessWidget {
  final Dinner dinner;
  final VoidCallback? onTap;
  const _ExperienceTile({required this.dinner, this.onTap});

  @override
  Widget build(BuildContext context) {
    final seats = dinner.availableSeats;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            // Cover image
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Image.asset(
                dinner.imagePath ?? 'assets/images/hero_tasting.png',
                width: 56,
                height: 56,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Title + venue + date
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
                    dinner.formattedLocation,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          dinner.formattedDate,
                          style: AppTextStyles.caption,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '·',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        seats > 0 ? '$seats seats left' : 'Full',
                        style: AppTextStyles.caption.copyWith(
                          color: seats > 0
                              ? AppColors.success
                              : AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Price + CTA
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  dinner.pricePerSeat > 0
                      ? 'Rs ${dinner.pricePerSeat.toStringAsFixed(0)}'
                      : 'Free',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _JoinButton(
                  enabled: seats > 0,
                  onTap: seats > 0 ? onTap : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback? onTap;
  const _JoinButton({required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: enabled ? AppColors.primary : AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          enabled ? 'View' : 'Full',
          style: AppTextStyles.labelSmall.copyWith(
            color: enabled ? Colors.white : AppColors.textTertiary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Muted past-experience tile — no join affordance, just title/date/venue.
class _PastExperienceTile extends StatelessWidget {
  final Dinner dinner;
  final VoidCallback? onTap;
  const _PastExperienceTile({required this.dinner, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Image.asset(
                dinner.imagePath ?? 'assets/images/hero_tasting.png',
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
                    dinner.title,
                    style: AppTextStyles.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dinner.formattedLocation,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dinner.formattedDate,
                    style: AppTextStyles.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
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
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'Completed',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: AppColors.textTertiary,
              size: 48,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load profile',
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Check your connection and try again.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              text: 'Retry',
              icon: Icons.refresh_rounded,
              isFullWidth: false,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
