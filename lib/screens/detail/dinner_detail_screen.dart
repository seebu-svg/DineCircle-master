import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../models/safety.dart';
import '../../models/user_profile.dart';
import '../../models/restaurant.dart';
import '../../models/review.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/dinner_card.dart';
import '../../providers/events_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/social_provider.dart';
import '../../providers/users_provider.dart';
import '../../screens/safety/report_sheet.dart';
import '../../api/api_exception.dart';

/// Dinner detail screen — premium event details page.
///
/// Answers five questions:
/// 1. What experience am I joining?
/// 2. Who will I be dining with?
/// 3. Where and when is it happening?
/// 4. What is included in the price?
/// 5. Why should I book this experience?
class DinnerDetailScreen extends ConsumerStatefulWidget {
  final Dinner dinner;
  final VoidCallback? onJoin;
  final void Function(UserProfile user)? onUserTap;
  final void Function(Restaurant restaurant)? onRestaurantTap;

  const DinnerDetailScreen({
    super.key,
    required this.dinner,
    this.onJoin,
    this.onUserTap,
    this.onRestaurantTap,
  });

  @override
  ConsumerState<DinnerDetailScreen> createState() => _DinnerDetailScreenState();
}

class _DinnerDetailScreenState extends ConsumerState<DinnerDetailScreen> {
  /// Toggles the signed-in user's bookmark for this dinner via the social
  /// controller (server-backed); the icon re-renders from [isSavedProvider].
  Future<void> _toggleSave() async {
    final id = widget.dinner.id;
    final isSaved = ref.read(isSavedProvider(id));
    try {
      if (isSaved) {
        await ref.read(socialControllerProvider).unsave(id);
      } else {
        await ref.read(socialControllerProvider).save(id);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  /// Copies event link to clipboard and shows confirmation.
  Future<void> _shareEvent() async {
    final link = 'https://dinecircle.app/events/${widget.dinner.id}';
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Event link copied to clipboard!')),
    );
  }

  /// Opens the attended-guest review composer. Only reachable from the reviews
  /// section when [canReviewProvider] is true (the user has a completed
  /// booking); submitting calls `POST /events/:id/reviews` and refetches.
  Future<void> _showReviewComposer() async {
    final dinnerId = widget.dinner.id;
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewComposerSheet(dinnerId: dinnerId),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Thanks for your review!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Prefer the freshly fetched full detail (menu/venue/attendees); fall back
    // to the list item passed in while it loads.
    final detailAsync = ref.watch(dinnerDetailProvider(widget.dinner.id));
    final dinner = detailAsync.valueOrNull ?? widget.dinner;
    final isLoading = detailAsync.isLoading && detailAsync.valueOrNull == null;
    final hasError = detailAsync.hasError && detailAsync.valueOrNull == null;

    final reviews =
        ref.watch(reviewsForEventProvider(dinner.id)).valueOrNull ??
        const <Review>[];
    final hostEvents =
        ref.watch(hostEventsProvider(dinner.host.id)).valueOrNull ??
        const <Dinner>[];
    // Similar experiences must stay bookable: drop this event, anything in the
    // past, and cancelled listings so we never show an expired countdown.
    final now = DateTime.now();
    final otherEvents = hostEvents
        .where(
          (d) =>
              d.id != dinner.id &&
              d.dateTime.isAfter(now) &&
              d.hostStatus != HostEventStatus.cancelled,
        )
        .toList();
    final avgRating = reviews.isNotEmpty
        ? (reviews.map((r) => r.rating).reduce((a, b) => a + b) /
                  reviews.length)
              .toStringAsFixed(1)
        : '0.0';
    final isSaved = ref.watch(isSavedProvider(dinner.id));
    final canReview = ref.watch(canReviewProvider(dinner.id));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── App bar with cover image ──
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppColors.bg,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Save
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSaved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    color: isSaved ? AppColors.gold : Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: _toggleSave,
              ),
              // Share
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.share_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: _shareEvent,
              ),
              // More actions
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_vert_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => _showMoreActions(context),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Hero image with error fallback
                  _HeroImage(imagePath: dinner.imagePath),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.imageOverlay,
                    ),
                  ),
                  // Title overlay
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _HeroOverlay(
                      title: dinner.title,
                      category: dinner.category,
                      isSpecialEvent: dinner.isSpecialEvent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Content ──
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Restaurant (tappable) ──
                      _RestaurantLink(
                        restaurant: dinner.restaurant,
                        onTap: () =>
                            widget.onRestaurantTap?.call(dinner.restaurant),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // ── Event info grid ──
                      _buildInfoGrid(dinner),
                      const SizedBox(height: AppSpacing.lg),

                      // ── What to Expect ──
                      if (dinner.description.isNotEmpty ||
                          dinner.tags.isNotEmpty) ...[
                        _buildWhatToExpect(dinner),
                        const SizedBox(height: AppSpacing.lg),
                      ],

                      // ── Additional details ──
                      _buildDetailsSection(dinner),
                      const SizedBox(height: AppSpacing.lg),

                      // ── Menu ──
                      if (dinner.menu.isNotEmpty) ..._buildMenuSection(dinner),

                      // ── Host card ──
                      _buildHostCard(dinner),
                      const SizedBox(height: AppSpacing.xl),

                      // ── Attendees ──
                      if (dinner.attendees.isNotEmpty)
                        ..._buildAttendeesSection(dinner),

                      // ── Reviews ──
                      if (reviews.isNotEmpty) ...[
                        SectionHeader(
                          title: 'Event Reviews',
                          actionText: 'See all',
                          onAction: () {},
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        _buildReviewsSummary(reviews, avgRating),
                        const SizedBox(height: AppSpacing.md),
                        ...reviews.map((r) => _buildReviewCard(r)),
                        const SizedBox(height: AppSpacing.md),
                      ] else ...[
                        SectionHeader(title: 'Event Reviews'),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'No reviews yet. Be the first to review this event!',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      // Only attended guests (a completed booking) may post.
                      if (canReview)
                        OutlinedButton.icon(
                          onPressed: _showReviewComposer,
                          icon: const Icon(Icons.rate_review_outlined),
                          label: const Text('Write a review'),
                        ),
                      const SizedBox(height: AppSpacing.xl),

                      // ── Host's other events ──
                      if (otherEvents.isNotEmpty) ...[
                        SectionHeader(
                          title: "More by ${dinner.host.name.split(' ').first}",
                          actionText: 'See all',
                          onAction: () {},
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          height: 320,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.paddingScreen,
                            ),
                            itemCount: otherEvents.length,
                            itemBuilder: (context, index) {
                              final d = otherEvents[index];
                              return DinnerCard(
                                dinner: d,
                                onTap: () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => DinnerDetailScreen(
                                        dinner: d,
                                        onJoin: widget.onJoin,
                                        onUserTap: widget.onUserTap,
                                        onRestaurantTap: widget.onRestaurantTap,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      // ── Bottom bar ──
      bottomNavigationBar: _BookingBar(
        dinner: dinner,
        isLoading: isLoading,
        hasError: hasError,
        onJoin: widget.onJoin,
      ),
    );
  }

  // ── More actions bottom sheet ──
  void _showMoreActions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.dinner.host.id != ref.read(currentUserIdProvider))
              ListTile(
                key: const Key('reportEventAction'),
                leading: const Icon(
                  Icons.flag_rounded,
                  color: AppColors.danger,
                ),
                title: const Text('Report Event'),
                onTap: () {
                  Navigator.pop(ctx);
                  // Real `POST /reports` — the sheet shows the RP reference.
                  ReportSheet.show(
                    context,
                    ReportTargetType.event,
                    widget.dinner.id,
                  );
                },
              ),
            ListTile(
              leading: const Icon(
                Icons.restaurant_menu_rounded,
                color: AppColors.gold,
              ),
              title: const Text('View Restaurant'),
              onTap: () {
                Navigator.pop(ctx);
                widget.onRestaurantTap?.call(widget.dinner.restaurant);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Info grid ──
  Widget _buildInfoGrid(Dinner dinner) {
    final seatsLeft = dinner.availableSeats;
    final seatsColor = seatsLeft <= 0
        ? AppColors.danger
        : seatsLeft <= 3
        ? AppColors.warning
        : AppColors.success;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              _InfoItem(
                icon: Icons.calendar_today_rounded,
                label: 'Date',
                value: _fullDate(dinner.dateTime),
              ),
              _InfoItem(
                icon: Icons.access_time_rounded,
                label: 'Start',
                value: dinner.formattedTime,
              ),
              if (dinner.endsAt != null)
                _InfoItem(
                  icon: Icons.schedule_rounded,
                  label: 'End',
                  value: dinner.formattedEndTime,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _InfoItem(
                  icon: Icons.location_on_rounded,
                  label: 'Location',
                  value: dinner.formattedLocation,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Flexible(
                child: _InfoItem(
                  icon: Icons.people_rounded,
                  label: 'Seats',
                  value: seatsLeft <= 0
                      ? 'Full'
                      : '$seatsLeft/${dinner.totalSeats}',
                  valueColor: seatsColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fullDate(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final wd = weekdays[dt.weekday - 1];
    final mo = months[dt.month - 1];
    return '$wd, $mo ${dt.day}, ${dt.year}';
  }

  // ── What to Expect ──
  Widget _buildWhatToExpect(Dinner dinner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What to Expect', style: AppTextStyles.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        if (dinner.description.isNotEmpty)
          Text(
            dinner.description,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        if (dinner.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: dinner.tags.map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  tag,
                  style: AppTextStyles.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // ── Additional details (cuisine, dress code, age, cancellation) ──
  Widget _buildDetailsSection(Dinner dinner) {
    final items = <_DetailRow>[];
    items.add(
      _DetailRow(
        icon: Icons.restaurant_menu_rounded,
        label: 'Cuisine',
        value: dinner.restaurant.cuisine,
      ),
    );
    if (dinner.dressCode != null && dinner.dressCode!.isNotEmpty) {
      items.add(
        _DetailRow(
          icon: Icons.checkroom_rounded,
          label: 'Dress Code',
          value: dinner.dressCode!,
        ),
      );
    }
    if (dinner.ageRestriction != null && dinner.ageRestriction!.isNotEmpty) {
      items.add(
        _DetailRow(
          icon: Icons.person_outline_rounded,
          label: 'Age Restriction',
          value: dinner.ageRestriction!,
        ),
      );
    }
    items.add(
      _DetailRow(
        icon: Icons.policy_rounded,
        label: 'Cancellation',
        value: dinner.cancellationPolicy,
      ),
    );
    // RSVP rule — no rsvp_deadline column exists, so the honest rule:
    items.add(
      _DetailRow(
        icon: Icons.event_available_rounded,
        label: 'RSVP',
        value: 'Joins close when the experience starts',
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: items
            .map(
              (item) => Padding(
                padding: EdgeInsets.only(
                  bottom: item == items.last ? 0 : AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Icon(item.icon, color: AppColors.textSecondary, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        item.label,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Spacer(),
                    Flexible(
                      child: Text(
                        item.value,
                        style: AppTextStyles.labelSmall,
                        textAlign: TextAlign.right,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── Menu section ──
  List<Widget> _buildMenuSection(Dinner dinner) {
    return [
      Text('Menu', style: AppTextStyles.headlineSmall),
      const SizedBox(height: AppSpacing.md),
      ...dinner.menu.map((item) {
        final isIncluded = item.price <= 0;
        final priceText = isIncluded
            ? 'Included'
            : 'Rs ${item.price.toStringAsFixed(0)}';
        final priceColor = isIncluded ? AppColors.success : AppColors.primary;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.description,
                      style: AppTextStyles.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.tags.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: item.tags.map((tag) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusXs,
                              ),
                            ),
                            child: Text(
                              tag,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  priceText,
                  style: AppTextStyles.titleSmall.copyWith(color: priceColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  // ── Host card ──
  Widget _buildHostCard(Dinner dinner) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hosted by', style: AppTextStyles.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        GestureDetector(
          onTap: () => widget.onUserTap?.call(dinner.host),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    AvatarWidget(
                      imagePath: dinner.host.avatarPath,
                      initials: dinner.host.initials,
                      size: AppSpacing.avatarLg,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  dinner.host.name,
                                  style: AppTextStyles.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (dinner.host.isVerified) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.verified_rounded,
                                  color: AppColors.primary,
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Icon(
                                Icons.star_rounded,
                                color: AppColors.gold,
                                size: 14,
                              ),
                              const SizedBox(width: 2),
                              Flexible(
                                child: Text(
                                  dinner.host.rating.toStringAsFixed(1),
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.gold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Flexible(
                                child: Text(
                                  '(${dinner.host.reviewCount} reviews)',
                                  style: AppTextStyles.caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${dinner.host.dinnersHosted} dinners hosted',
                            style: AppTextStyles.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const Divider(height: 1),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _HostStat(
                        value: '${dinner.host.followers}',
                        label: 'Followers',
                      ),
                    ),
                    Container(width: 1, height: 30, color: AppColors.border),
                    Expanded(
                      child: _HostStat(
                        value: '${dinner.host.dinnersHosted}',
                        label: 'Hosted',
                      ),
                    ),
                    Container(width: 1, height: 30, color: AppColors.border),
                    Expanded(
                      child: _HostStat(
                        value: dinner.host.rating.toStringAsFixed(1),
                        label: 'Rating',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Attendees section ──
  List<Widget> _buildAttendeesSection(Dinner dinner) {
    return [
      SectionHeader(
        title: 'Attendees',
        actionText: '${dinner.attendees.length} going',
        onAction: () {},
      ),
      const SizedBox(height: AppSpacing.md),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: dinner.attendees.map((user) {
          return GestureDetector(
            onTap: () => widget.onUserTap?.call(user),
            child: Tooltip(
              message: user.name,
              child: AvatarWidget(
                imagePath: user.avatarPath,
                initials: user.initials,
                size: AppSpacing.avatarMd,
              ),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  // ── Reviews summary ──
  Widget _buildReviewsSummary(List<Review> reviews, String avgRating) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text(
            avgRating,
            style: AppTextStyles.displaySmall.copyWith(
              color: AppColors.gold,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < (int.tryParse(avgRating) ?? 0)
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: AppColors.gold,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${reviews.length} ${reviews.length == 1 ? 'review' : 'reviews'}',
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Single review card ──
  Widget _buildReviewCard(Review review) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarWidget(
                imagePath: review.reviewer.avatarPath,
                initials: review.reviewer.initials,
                size: 36,
              ),
              const SizedBox(width: AppSpacing.sm),
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
                children: [
                  ...List.generate(
                    5,
                    (i) => Icon(
                      i < review.rating
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: AppColors.gold,
                      size: 14,
                    ),
                  ),
                  // P2: flag someone else's review (server refuses self-reports).
                  if (review.reviewer.id != ref.read(currentUserIdProvider))
                    IconButton(
                      key: Key('reportReview_${review.id}'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(
                        Icons.flag_outlined,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => ReportSheet.show(
                        context,
                        ReportTargetType.review,
                        review.id,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            review.comment,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ──

/// Hero image with error fallback to a gradient placeholder.
class _HeroImage extends StatelessWidget {
  final String? imagePath;

  const _HeroImage({this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return _HeroPlaceholder();
    }
    // Network images
    if (imagePath!.startsWith('http')) {
      return Image.network(
        imagePath!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _HeroPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _HeroPlaceholder();
        },
      );
    }
    // Asset images
    return Image.asset(
      imagePath!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _HeroPlaceholder(),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface, AppColors.surfaceElevated],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.restaurant_rounded,
          size: 64,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

/// Hero overlay showing title and category badge.
class _HeroOverlay extends StatelessWidget {
  final String title;
  final String category;
  final bool isSpecialEvent;

  const _HeroOverlay({
    required this.title,
    required this.category,
    required this.isSpecialEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isSpecialEvent)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(
                'SPECIAL EVENT',
                style: AppTextStyles.labelSmall.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (isSpecialEvent) const SizedBox(height: AppSpacing.sm),
          Text(
            title,
            style: AppTextStyles.displayMedium.copyWith(
              color: Colors.white,
              shadows: [
                Shadow(
                  blurRadius: 8,
                  color: Colors.black.withValues(alpha: 0.6),
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              category,
              style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Restaurant link with name and navigation icon.
class _RestaurantLink extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback? onTap;

  const _RestaurantLink({required this.restaurant, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          const Icon(
            Icons.restaurant_rounded,
            color: AppColors.primary,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              restaurant.name,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          const Icon(
            Icons.open_in_new_rounded,
            color: AppColors.primary,
            size: 14,
          ),
        ],
      ),
    );
  }
}

/// Sticky bottom booking bar with price, seats, and CTA.
///
/// Shows participation status when the viewer already holds a booking,
/// and disables the action for sold-out / cancelled / past events.
class _BookingBar extends ConsumerStatefulWidget {
  final Dinner dinner;
  final bool isLoading;
  final bool hasError;
  final VoidCallback? onJoin;

  const _BookingBar({
    required this.dinner,
    required this.isLoading,
    required this.hasError,
    required this.onJoin,
  });

  @override
  ConsumerState<_BookingBar> createState() => _BookingBarState();
}

class _BookingBarState extends ConsumerState<_BookingBar> {
  bool _cancelling = false;

  Future<void> _cancelRsvp() async {
    final booking = ref.read(
      myBookingForEventProvider(widget.dinner.id),
    );
    if (booking == null || _cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Cancel RSVP'),
        content: const Text(
          'Are you sure you want to cancel your spot? You can rejoin if seats are still available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Cancel RSVP'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _cancelling = true);
    try {
      await ref.read(bookingsControllerProvider).cancel(booking.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('RSVP cancelled'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
      );
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dinner = widget.dinner;
    final seatsLeft = dinner.availableSeats;
    final isSoldOut = seatsLeft <= 0;
    final isCancelled = dinner.hostStatus == HostEventStatus.cancelled;
    final isPast = dinner.dateTime.isBefore(DateTime.now());
    final myBooking = ref.watch(
      myBookingForEventProvider(dinner.id),
    );
    final hasBooking = myBooking != null;

    // Determine the CTA label and enabled state.
    final String ctaText;
    final bool ctaEnabled;
    if (isCancelled) {
      ctaText = 'Cancelled';
      ctaEnabled = false;
    } else if (isPast) {
      ctaText = 'Ended';
      ctaEnabled = false;
    } else if (hasBooking) {
      ctaText = "You're going";
      ctaEnabled = false; // status label, not actionable via this button
    } else if (isSoldOut) {
      ctaText = 'Sold out';
      ctaEnabled = false;
    } else {
      ctaText = 'Join Dinner';
      ctaEnabled = true;
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // RSVP is free; the price is what the venue charges for the meal.
                  Text(
                    'Free RSVP',
                    style: AppTextStyles.displaySmall.copyWith(
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Estimated dining cost: Rs ${dinner.pricePerSeat.toStringAsFixed(0)} / person',
                    style: AppTextStyles.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!isSoldOut && !isCancelled && !isPast) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$seatsLeft seats left',
                      style: AppTextStyles.caption.copyWith(
                        color: seatsLeft <= 3
                            ? AppColors.warning
                            : AppColors.success,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            if (hasBooking && !isPast && !isCancelled)
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PrimaryButton(
                      text: ctaText,
                      onPressed: null, // status label
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    GestureDetector(
                      onTap: _cancelling ? null : _cancelRsvp,
                      child: Text(
                        _cancelling ? 'Cancelling…' : 'Cancel RSVP',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.danger,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  text: ctaText,
                  isLoading: widget.isLoading,
                  onPressed: ctaEnabled ? widget.onJoin : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 16),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                label,
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: AppTextStyles.labelMedium.copyWith(
            color: valueColor ?? AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });
}

class _HostStat extends StatelessWidget {
  final String value;
  final String label;

  const _HostStat({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.titleMedium),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// Bottom-sheet composer for an attended-guest review. Submits via
/// [eventsControllerProvider] (`POST /events/:id/reviews`) and pops `true` on
/// success so the caller can confirm; surfaces server rejections inline.
class _ReviewComposerSheet extends ConsumerStatefulWidget {
  final String dinnerId;

  const _ReviewComposerSheet({required this.dinnerId});

  @override
  ConsumerState<_ReviewComposerSheet> createState() =>
      _ReviewComposerSheetState();
}

class _ReviewComposerSheetState extends ConsumerState<_ReviewComposerSheet> {
  final _textCtrl = TextEditingController();
  int _rating = 5;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = 'Please write a few words about your experience.',
      );
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(eventsControllerProvider)
          .submitReview(
            widget.dinnerId,
            rating: _rating.toDouble(),
            text: text,
          );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit your review. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.xl),
          ),
        ),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate your dinner',
              style: AppTextStyles.titleLarge.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: List.generate(5, (i) {
                final star = i + 1;
                return IconButton(
                  onPressed: () => setState(() => _rating = star),
                  icon: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.gold,
                    size: 32,
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _textCtrl,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'How was the food, the host, the vibe?',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: AppTextStyles.caption.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              text: 'Submit review',
              isLoading: _submitting,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}
