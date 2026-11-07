import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/buttons.dart';
import '../../api/api_exception.dart';
import '../../models/dinner.dart';
import '../../models/host_models.dart';
import '../../models/restaurant.dart';
import '../../providers/events_provider.dart';
import '../../providers/host_studio_controller.dart';
import '../../providers/hosts_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../widgets/data_view.dart';
import '../create/create_dinner_screen.dart';
import 'analytics_screen.dart';
import 'event_manage_screen.dart';

/// Host Studio, premium creator dashboard.
///
/// Hosts and influencers are the same users who create dinners, so both
/// spec sections (11 Host Dashboard + 12 Influencer Features) live here:
/// Overview, Events, Earnings and Collabs tabs.
class HostDashboardScreen extends ConsumerStatefulWidget {
  /// 0 = Overview, 1 = Events, 2 = Earnings, 3 = Collabs
  final int initialTab;

  const HostDashboardScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<HostDashboardScreen> createState() =>
      _HostDashboardScreenState();
}

class _HostDashboardScreenState extends ConsumerState<HostDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _eventFilter = 'All';

  /// Cosmetic payout-method labels, money is a simulated ledger, so no real
  /// account details are shown or used.
  static const _bankMethod = 'Bank transfer';

  static const _filters = [
    'All',
    'Published',
    'Bookings Paused',
    'Completed',
    'Cancelled',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openEvent(Dinner dinner) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EventManageScreen(dinner: dinner)),
    );
    if (mounted) setState(() {}); // refresh badges when returning
  }

  void _openCreateDinner() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateDinnerScreen(
          onComplete: () {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Experience published successfully!'),
                backgroundColor: AppColors.success,
              ),
            );
          },
        ),
      ),
    );
  }

  void _openAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AnalyticsScreen()),
    );
  }

  /// The signed-in host's own events, drafts included (`GET /events/mine`).
  /// Host Studio reads this instead of the public feed so unpublished drafts
  /// surface here even though they never appear in Explore.
  List<Dinner> get _hostedEvents {
    return ref.watch(myEventsProvider).valueOrNull ?? const [];
  }

  /// Saved-but-unpublished dinners for the Drafts section.
  List<Dinner> get _drafts {
    final drafts =
        _hostedEvents
            .where((d) => d.hostStatus == HostEventStatus.draft)
            .toList()
          ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return drafts;
  }

  /// Edits a draft inline (title/description/date/seats/price) via
  /// `PATCH /events/:id`. Server-side validation still applies per field.
  Future<void> _editDraft(Dinner draft) async {
    final patch = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bg,
      builder: (_) => _DraftEditSheet(draft: draft),
    );
    if (patch == null || patch.isEmpty || !mounted) return;
    try {
      await ref.read(eventsControllerProvider).patchEvent(draft.id, patch);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Draft updated')));
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

  /// Publishes a draft (`PATCH /events/:id {status:'published'}`). The server
  /// re-validates the merged row; a 422 surfaces its message inline.
  Future<void> _publishDraft(Dinner draft) async {
    try {
      await ref.read(eventsControllerProvider).patchEvent(draft.id, {
        'status': 'published',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Draft published'),
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

  /// Deletes a draft, reuses the host-cancel endpoint (`DELETE /events/:id`).
  Future<void> _deleteDraft(Dinner draft) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete draft?'),
        content: Text('"${draft.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(eventsControllerProvider).cancelEvent(draft.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Draft deleted')));
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

  List<Dinner> get _filteredEvents {
    final events = _hostedEvents;
    if (_eventFilter == 'All') return events;
    return events.where((d) => d.hostStatus.label == _eventFilter).toList();
  }

  List<Dinner> get _upcomingEvents =>
      _hostedEvents
          .where(
            (d) =>
                d.dateTime.isAfter(DateTime.now()) &&
                (d.hostStatus == HostEventStatus.published ||
                    d.hostStatus == HostEventStatus.pausedBookings),
          )
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 120,
              floating: false,
              pinned: true,
              backgroundColor: AppColors.bg,
              surfaceTintColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: const EdgeInsets.only(left: AppSpacing.md, bottom: 60),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Flexible: the pinned app bar squeezes the title on small
                    // screens and at large text scales; ellipsis beats overflow.
                    Flexible(
                      child: Text(
                        'Host Studio',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.headlineSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Text(
                        'PRO',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 9,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.bg,
                        AppColors.surface,
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              actions: [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Icon(
                      Icons.insights_rounded,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  tooltip: 'Analytics & Insights',
                  onPressed: _openAnalytics,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              bottom: _PremiumTabBar(
                controller: _tabController,
                tabs: const [
                  _TabItem(icon: Icons.dashboard_rounded, label: 'Overview'),
                  _TabItem(icon: Icons.event_rounded, label: 'Events'),
                  _TabItem(icon: Icons.account_balance_wallet_rounded, label: 'Earnings'),
                  _TabItem(icon: Icons.handshake_rounded, label: 'Collabs'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildOverview(context),
            _buildEvents(context),
            _buildEarnings(context),
            _buildCollabs(context),
          ],
        ),
      ),
      floatingActionButton: _CreateExperienceFab(onTap: _openCreateDinner),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Overview tab
  // ────────────────────────────────────────────────────────────

  Widget _buildOverview(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final summary = ref.watch(myHostSummaryProvider).valueOrNull;
    final pending = (summary?.inTransit ?? 0) + (summary?.scheduled ?? 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PremiumProfileCard(user: user),
          const SizedBox(height: AppSpacing.md),
          _PremiumEarningsSummary(
            available: summary?.available ?? 0,
            pending: pending,
            netEarnings: summary?.netTotal ?? 0,
            onTap: () => _tabController.animateTo(2),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Performance', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _PerformanceGrid(summary: summary, userRating: user.rating),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Upcoming Events',
                  style: AppTextStyles.titleMedium,
                ),
              ),
              TextButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('View all'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (_upcomingEvents.isEmpty)
            _PremiumEmptyState(
              icon: Icons.event_busy_rounded,
              message: 'No upcoming events yet',
              actionLabel: 'Create Experience',
              onAction: _openCreateDinner,
            )
          else
            ..._upcomingEvents.take(3).map(
              (dinner) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PremiumEventCard(
                  dinner: dinner,
                  showActions: true,
                  onTap: () => _openEvent(dinner),
                  onGuests: () => _openEvent(dinner),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Events tab
  // ────────────────────────────────────────────────────────────

  Widget _buildEvents(BuildContext context) {
    final events = _filteredEvents;
    final drafts = _drafts;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (drafts.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: Text('Drafts', style: AppTextStyles.titleMedium),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    '${drafts.length}',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...drafts.map(
              (draft) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PremiumDraftCard(
                  draft: draft,
                  onEdit: () => _editDraft(draft),
                  onPublish: () => _publishDraft(draft),
                  onDelete: () => _deleteDraft(draft),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Your Experiences', style: AppTextStyles.titleMedium),
            const SizedBox(height: AppSpacing.md),
          ],
          _PremiumFilterChips(
            filters: _filters,
            selected: _eventFilter,
            onSelected: (filter) => setState(() => _eventFilter = filter),
          ),
          const SizedBox(height: AppSpacing.md),
          if (events.isEmpty)
            _PremiumEmptyState(
              icon: Icons.event_note_rounded,
              message: 'No events in this state',
            )
          else
            ...events.map(
              (dinner) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PremiumEventCard(
                  dinner: dinner,
                  onTap: () => _openEvent(dinner),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Earnings tab
  // ────────────────────────────────────────────────────────────

  Widget _buildEarnings(BuildContext context) {
    final summary = ref.watch(myHostSummaryProvider).valueOrNull;
    final payoutsAsync = ref.watch(myHostPayoutsProvider);
    final payouts = payoutsAsync.valueOrNull ?? const <HostPayout>[];
    final pending = (summary?.inTransit ?? 0) + (summary?.scheduled ?? 0);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PremiumBalanceCard(
            available: summary?.available ?? 0,
            pending: pending,
            netEarnings: summary?.netTotal ?? 0,
            onWithdraw: () => _showWithdrawSheet(context),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Earnings Breakdown', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _PremiumBreakdownCard(
            lifetimeGross: summary?.lifetimeGross ?? 0,
            commissionTotal: summary?.commissionTotal ?? 0,
            netTotal: summary?.netTotal ?? 0,
            events: _hostedEvents,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Payout History', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          _PremiumPayoutHistory(
            payoutsAsync: payoutsAsync,
            payouts: payouts,
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Collabs tab
  // ────────────────────────────────────────────────────────────

  Widget _buildCollabs(BuildContext context) {
    final collabsAsync = ref.watch(myHostCollaborationsProvider);
    final partners = ref.watch(myHostPartnersProvider).valueOrNull ?? const [];
    final promotableAsync = ref.watch(myHostPromotableEventsProvider);
    final promotableData = promotableAsync.valueOrNull;
    final promotableEvents = promotableData?.events ?? const [];
    final followerCount = promotableData?.followerCount ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.paddingScreen),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Find Restaurant Partners ──────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showDiscoverySheet(context),
              icon: const Icon(Icons.search_rounded, size: 18),
              label: const Text('Find Restaurant Partners'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Active Partnerships ───────────────────────────────────
          Text('Active Partnerships', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          collabsAsync.when(
            loading: () => const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Failed to load: $e',
                style: AppTextStyles.caption),
            data: (collabs) {
              final active = collabs.where((c) => c.status == 'accepted').toList();
              if (active.isEmpty && partners.isEmpty) {
                return _PremiumEmptyState(
                  icon: Icons.handshake_rounded,
                  message: 'No active partnerships yet',
                  actionLabel: 'Find Partners',
                  onAction: () => _showDiscoverySheet(context),
                );
              }
              return Column(
                children: [
                  ...partners.map(
                    (partner) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PremiumPartnerCard(
                        restaurant: partner.venue,
                        eventsTogether: partner.eventsTogether,
                        onCreateEvent: _openCreateDinner,
                      ),
                    ),
                  ),
                  ...active.map(
                    (collab) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PremiumCollabCard(
                        collab: collab,
                        onView: () => _showCollabDetail(context, collab),
                        onComplete: () => _completeCollab(collab.id),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Incoming Proposals ────────────────────────────────────
          collabsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (collabs) {
              final incoming = collabs
                  .where((c) => c.isIncoming && c.isPending)
                  .toList();
              if (incoming.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Incoming Proposals',
                          style: AppTextStyles.titleMedium,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusFull,
                          ),
                        ),
                        child: Text(
                          '${incoming.length}',
                          style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...incoming.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PremiumCollabCard(
                        collab: c,
                        onView: () => _showCollabDetail(context, c),
                        onComplete: null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            },
          ),

          // ── Outgoing Proposals ────────────────────────────────────
          collabsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (collabs) {
              final outgoing = collabs
                  .where((c) => c.isOutgoing)
                  .toList();
              if (outgoing.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Outgoing Proposals', style: AppTextStyles.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  ...outgoing.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _PremiumCollabCard(
                        collab: c,
                        onView: () => _showCollabDetail(context, c),
                        onCancel: c.isPending
                            ? () => _cancelCollab(c.id)
                            : null,
                        onComplete: null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
              );
            },
          ),

          // ── Promote to Followers ──────────────────────────────────
          Text('Promote to Followers', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Share an upcoming experience with your $followerCount followers to boost bookings.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          if (promotableEvents.isEmpty)
            _PremiumEmptyState(
              icon: Icons.campaign_rounded,
              message: 'No published events to promote',
            )
          else
            ...promotableEvents.map(
              (evt) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _PremiumPromotableEventCard(
                  event: evt,
                  onPromote: () => _showPromoteSheet(context, evt, followerCount),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  Future<void> _cancelCollab(String collabId) async {
    try {
      await ref.read(collaborationsControllerProvider).cancelProposal(collabId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Proposal cancelled')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _completeCollab(String collabId) async {
    try {
      await ref.read(collaborationsControllerProvider).completeProposal(collabId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Collaboration marked as completed!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ────────────────────────────────────────────────────────────
  // Sheets
  // ────────────────────────────────────────────────────────────

  void _showWithdrawSheet(BuildContext context) {
    final available =
        ref.read(myHostSummaryProvider).valueOrNull?.available ?? 0.0;
    String method = _bankMethod;
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
                  Text('Withdraw Earnings', style: AppTextStyles.titleLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Available: ${_money(available)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.success,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SectionLabel('PAYOUT METHOD'),
                  const SizedBox(height: AppSpacing.md),
                  _MethodOption(
                    label: _bankMethod,
                    subtitle: '1-3 business days',
                    icon: Icons.account_balance_rounded,
                    selected: method == _bankMethod,
                    onTap: () => setSheetState(() => method = _bankMethod),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _MethodOption(
                    label: 'PayPal',
                    subtitle: 'Instant',
                    icon: Icons.paypal_rounded,
                    selected: method == 'PayPal',
                    onTap: () => setSheetState(() => method = 'PayPal'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: available <= 0
                          ? null
                          : () async {
                              Navigator.pop(sheetContext);
                              try {
                                await ref
                                    .read(walletControllerProvider)
                                    .withdraw(
                                      amount: available,
                                      method: method,
                                    );
                                if (mounted) {
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Withdrawal of ${_money(available)} to $method requested',
                                      ),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(this.context)
                                      .showSnackBar(
                                        SnackBar(
                                          content: Text(_describeError(e)),
                                          backgroundColor: AppColors.danger,
                                        ),
                                      );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                      ),
                      child: Text(
                        'Confirm Withdrawal (${_money(available)})',
                        style: AppTextStyles.labelLarge,
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

  void _showCollabDetail(BuildContext context, CollaborationInvite collab) {
    final isIncoming = collab.isIncoming;
    final isPending = collab.isPending;
    final isActive = collab.status == 'accepted';
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status chip
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(collab.status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    ),
                    child: Text(
                      collab.statusLabel,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: _statusColor(collab.status),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (isIncoming)
                    const Icon(Icons.inbox_rounded, color: AppColors.info, size: 18)
                  else
                    const Icon(Icons.send_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    isIncoming ? 'Incoming' : 'Outgoing',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Restaurant info
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    child: Image.asset(
                      collab.restaurant.imagePath ??
                          'assets/images/venue_interior.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          collab.restaurant.name,
                          style: AppTextStyles.titleSmall,
                        ),
                        if (collab.restaurantRating > 0)
                          Row(
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: AppColors.gold, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                collab.restaurantRating.toStringAsFixed(1),
                                style: AppTextStyles.caption,
                              ),
                              if (collab.restaurantCuisines.isNotEmpty) ...[                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  collab.restaurantCuisines.join(', '),
                                  style: AppTextStyles.caption,
                                ),
                              ],
                            ],
                          ),
                        Text(collab.receivedLabel, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(collab.title, style: AppTextStyles.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(collab.message, style: AppTextStyles.bodySmall),
              const SizedBox(height: AppSpacing.xl),
              // Action buttons based on status and direction
              if (isIncoming && isPending) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          try {
                            await ref
                                .read(invitesControllerProvider)
                                .decline(collab.id);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(content: Text('Proposal declined')),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(_describeError(e)),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          }
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          try {
                            await ref
                                .read(invitesControllerProvider)
                                .accept(collab.id);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Partnership with ${collab.restaurant.name} accepted!',
                                  ),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(_describeError(e)),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
              ] else if (isIncoming && isActive) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Active partnership',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: AppColors.success,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _openCreateDinner();
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Create Experience'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                  ),
                ),
              ] else if (!isIncoming && isPending) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _cancelCollab(collab.id);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('Cancel Proposal'),
                  ),
                ),
              ] else if (isActive) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(sheetContext);
                      await _completeCollab(collab.id);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    ),
                    child: const Text('Mark as Completed'),
                  ),
                ),
              ] else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: _statusColor(collab.status), size: 20),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'This collaboration is ${collab.statusLabel.toLowerCase()}',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: _statusColor(collab.status),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(
                height: MediaQuery.of(sheetContext).viewInsets.bottom +
                    AppSpacing.md,
              ),
            ],
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'accepted':
        return AppColors.success;
      case 'declined':
        return AppColors.danger;
      case 'cancelled':
        return AppColors.textSecondary;
      case 'completed':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  void _showDiscoverySheet(BuildContext context) {
    final hostId = ref.read(currentUserIdProvider);
    if (hostId == null) return;
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
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (_, scrollController) {
            final partnersAsync = ref.watch(hostDiscoverPartnersProvider(hostId));
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Find Restaurant Partners',
                          style: AppTextStyles.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Verified partner restaurants available for collaboration',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: partnersAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Failed to load partners',
                                style: AppTextStyles.bodySmall),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                              onPressed: () => ref.invalidate(
                                hostDiscoverPartnersProvider(hostId),
                              ),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                      data: (partners) {
                        if (partners.isEmpty) {
                          return const Center(
                            child: EmptyStateView(
                              icon: Icons.storefront_rounded,
                              message: 'No verified partners available yet',
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: partners.length,
                          itemBuilder: (_, i) {
                            final p = partners[i];
                            return _DiscoverPartnerTile(
                              partner: p,
                              onPropose: () {
                                Navigator.pop(sheetContext);
                                _showProposalSheet(context, p);
                              },
                            );
                          },
                        );
                      },
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

  void _showProposalSheet(
    BuildContext context,
    DiscoverablePartner partner,
  ) {
    final titleCtrl = TextEditingController();
    final messageCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
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
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + AppSpacing.lg,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send Proposal', style: AppTextStyles.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'to ${partner.name}',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Proposal Title',
                    hintText: 'e.g. Summer Rooftop Series',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().length < 3) ? 'Min 3 characters' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: messageCtrl,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    hintText: 'Tell them about your collaboration idea...',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: 'Cancel',
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        text: 'Send Proposal',
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          Navigator.pop(sheetContext);
                          try {
                            await ref
                                .read(collaborationsControllerProvider)
                                .sendProposal(
                                  restaurantId: partner.id,
                                  title: titleCtrl.text.trim(),
                                  message: messageCtrl.text.trim(),
                                );
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Proposal sent to ${partner.name}!',
                                  ),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } on ApiException catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: AppColors.danger,
                                ),
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showPromoteSheet(
    BuildContext context,
    PromotableEvent event,
    int followerCount,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Promote Experience', style: AppTextStyles.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(event.title, style: AppTextStyles.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      '${event.restaurantName} • ${event.seatsLeft} seats left • Rs ${event.pricePerSeat.toStringAsFixed(0)}/seat',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.people_rounded,
                      color: AppColors.primary, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '$followerCount followers will see this',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await ref
                          .read(collaborationsControllerProvider)
                          .promoteEvent(event.id);
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Promoted "${event.title}" to $followerCount followers!',
                            ),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      }
                    } on ApiException catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(
                            content: Text(e.message),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.campaign_rounded, size: 18),
                  label: const Text('Record Promotion'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _money(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';

  /// Turns a thrown error into a short, user-facing message for a snackbar.
  String _describeError(Object e) =>
      e is ApiException ? e.message : 'Something went wrong. Please try again.';
}

// ══════════════════════════════════════════════════════════════
// Premium Tab Bar
// ══════════════════════════════════════════════════════════════

class _TabItem {
  final IconData icon;
  final String label;

  const _TabItem({required this.icon, required this.label});
}

class _PremiumTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<_TabItem> tabs;

  const _PremiumTabBar({required this.controller, required this.tabs});

  @override
  Size get preferredSize => const Size.fromHeight(56);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Row(
          children: List.generate(tabs.length, (index) {
            final isSelected = controller.index == index;
            return GestureDetector(
              onTap: () => controller.animateTo(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tabs[index].icon,
                      size: 16,
                      color: isSelected ? Colors.white : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tabs[index].label,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: isSelected ? Colors.white : AppColors.textSecondary,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Profile Card
// ══════════════════════════════════════════════════════════════

class _PremiumProfileCard extends StatelessWidget {
  final dynamic user;

  const _PremiumProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              AvatarWidget(
                imagePath: user.avatarPath,
                initials: user.initials,
                size: AppSpacing.avatarLg,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: AppColors.goldGradient,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.star_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ),
                ),
              ),
            ],
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
                        user.name,
                        style: AppTextStyles.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user.isVerified) ...[
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.primary,
                        size: 14,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Host & Food Influencer',
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.people_rounded,
                      value: '${user.followers}',
                      label: 'followers',
                    ),
                    const SizedBox(width: AppSpacing.md),
                    _MiniStat(
                      icon: Icons.star_rounded,
                      value: user.rating.toStringAsFixed(1),
                      label: 'rating',
                      valueColor: AppColors.warning,
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, size: 20),
            color: AppColors.textSecondary,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile settings coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;

  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: valueColor ?? AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          value,
          style: AppTextStyles.labelSmall.copyWith(
            color: valueColor ?? AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 2),
        Text(label, style: AppTextStyles.labelSmall.copyWith(fontSize: 10)),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Earnings Summary
// ══════════════════════════════════════════════════════════════

class _PremiumEarningsSummary extends StatelessWidget {
  final double available;
  final double pending;
  final double netEarnings;
  final VoidCallback onTap;

  const _PremiumEarningsSummary({
    required this.available,
    required this.pending,
    required this.netEarnings,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
          gradient: LinearGradient(
            colors: [
              AppColors.surface,
              AppColors.surfaceElevated,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Available Balance',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _formatMoney(available),
              style: AppTextStyles.displaySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _CompactBalanceChip(
                    label: 'Pending',
                    value: _formatMoney(pending),
                    icon: Icons.schedule_rounded,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _CompactBalanceChip(
                    label: 'Net Earnings',
                    value: _formatMoney(netEarnings),
                    icon: Icons.trending_up_rounded,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatMoney(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

class _CompactBalanceChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _CompactBalanceChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.titleSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Performance Grid
// ══════════════════════════════════════════════════════════════

class _PerformanceGrid extends StatelessWidget {
  final dynamic summary;
  final double userRating;

  const _PerformanceGrid({required this.summary, required this.userRating});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 400;
        final crossAxisCount = isWide ? 3 : 2;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.4,
          children: [
            _PremiumStatCard(
              label: 'Hosted',
              value: '${summary?.hostedCount ?? 0}',
              icon: Icons.confirmation_number_rounded,
              color: AppColors.primary,
            ),
            _PremiumStatCard(
              label: 'Seats Sold',
              value: '${summary?.seatsSold ?? 0}',
              icon: Icons.event_seat_rounded,
              color: AppColors.info,
            ),
            _PremiumStatCard(
              label: 'Upcoming',
              value: '${summary?.upcomingCount ?? 0}',
              icon: Icons.chair_rounded,
              color: AppColors.success,
            ),
            _PremiumStatCard(
              label: 'Fill Rate',
              value: '${(summary?.averageFillRate ?? 0).toStringAsFixed(0)}%',
              icon: Icons.people_rounded,
              color: AppColors.gold,
            ),
            _PremiumStatCard(
              label: 'Revenue',
              value: _formatMoney(summary?.lifetimeGross ?? 0),
              icon: Icons.payments_rounded,
              color: AppColors.success,
            ),
            _PremiumStatCard(
              label: 'Avg Rating',
              value: userRating.toStringAsFixed(1),
              icon: Icons.star_rounded,
              color: AppColors.warning,
            ),
          ],
        );
      },
    );
  }

  String _formatMoney(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

class _PremiumStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _PremiumStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, color: color, size: 14),
          ),
          const Spacer(),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Event Card
// ══════════════════════════════════════════════════════════════

class _PremiumEventCard extends ConsumerWidget {
  final Dinner dinner;
  final VoidCallback onTap;
  final bool showActions;
  final VoidCallback? onGuests;

  const _PremiumEventCard({
    required this.dinner,
    required this.onTap,
    this.showActions = false,
    this.onGuests,
  });

  Color get _statusColor {
    switch (dinner.hostStatus) {
      case HostEventStatus.draft:
        return AppColors.textSecondary;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(myHostPendingRequestsProvider)[dinner.id] ?? 0;
    final progress = dinner.totalSeats == 0
        ? 0.0
        : (dinner.bookedSeats / dinner.totalSeats).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  dinner.title,
                                  style: AppTextStyles.titleSmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (pending > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: AppSpacing.sm),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.danger.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                                  ),
                                  child: Text(
                                    '$pending',
                                    style: AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.danger,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${dinner.formattedDate} • ${dinner.formattedTime}',
                            style: AppTextStyles.caption,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dinner.restaurant.name,
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                      child: Text(
                        dinner.hostStatus.label,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: _statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                          backgroundColor: AppColors.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            dinner.isFull ? AppColors.warning : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      '${dinner.bookedSeats}/${dinner.totalSeats}',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'Rs ${(dinner.bookedSeats * dinner.pricePerSeat).toStringAsFixed(0)}',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (showActions) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onTap,
                          icon: const Icon(Icons.tune_rounded, size: 14),
                          label: const Text('Manage', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onGuests,
                          icon: const Icon(Icons.groups_rounded, size: 14),
                          label: Text('Guests', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Draft Card
// ══════════════════════════════════════════════════════════════

class _PremiumDraftCard extends StatelessWidget {
  final Dinner draft;
  final VoidCallback onEdit;
  final VoidCallback onPublish;
  final VoidCallback onDelete;

  const _PremiumDraftCard({
    required this.draft,
    required this.onEdit,
    required this.onPublish,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                child: Image.asset(
                  draft.imagePath ?? 'assets/images/hero_tasting.png',
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
                      draft.title,
                      style: AppTextStyles.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.formattedDate} • ${draft.restaurant.name}',
                      style: AppTextStyles.caption,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  'Draft',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 14),
                  label: const Text('Edit', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPublish,
                  icon: const Icon(Icons.publish_rounded, size: 14),
                  label: const Text('Publish', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Delete draft',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.danger,
                ),
                style: IconButton.styleFrom(
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Balance Card (Earnings Tab)
// ══════════════════════════════════════════════════════════════

class _PremiumBalanceCard extends StatelessWidget {
  final double available;
  final double pending;
  final double netEarnings;
  final VoidCallback onWithdraw;

  const _PremiumBalanceCard({
    required this.available,
    required this.pending,
    required this.netEarnings,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Available Balance',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _formatMoney(available),
            style: AppTextStyles.displayLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _BalanceInfo(
                  label: 'Pending',
                  value: _formatMoney(pending),
                  color: AppColors.warning,
                  icon: Icons.schedule_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _BalanceInfo(
                  label: 'Net Earnings',
                  value: _formatMoney(netEarnings),
                  color: AppColors.success,
                  icon: Icons.trending_up_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onWithdraw,
              icon: const Icon(Icons.account_balance_rounded, size: 18),
              label: const Text('Withdraw'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMoney(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

class _BalanceInfo extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _BalanceInfo({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: color,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Breakdown Card
// ══════════════════════════════════════════════════════════════

class _PremiumBreakdownCard extends StatelessWidget {
  final double lifetimeGross;
  final double commissionTotal;
  final double netTotal;
  final List<Dinner> events;

  const _PremiumBreakdownCard({
    required this.lifetimeGross,
    required this.commissionTotal,
    required this.netTotal,
    required this.events,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _BreakdownRow(
            label: 'Event Revenue',
            value: _formatMoney(lifetimeGross),
            valueColor: AppColors.textPrimary,
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.border),
          _BreakdownRow(
            label: 'Platform Commission',
            value: '-${_formatMoney(commissionTotal)}',
            valueColor: AppColors.danger,
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.border),
          _BreakdownRow(
            label: 'Net Earnings',
            value: _formatMoney(netTotal),
            valueColor: AppColors.success,
          ),
          const Divider(height: AppSpacing.lg, color: AppColors.border),
          ...events
              .where((d) => d.hostStatus != HostEventStatus.cancelled)
              .map(
                (dinner) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          dinner.title,
                          style: AppTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatMoney(dinner.bookedSeats * dinner.pricePerSeat),
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  String _formatMoney(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _BreakdownRow({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
        Text(
          value,
          style: AppTextStyles.titleSmall.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Payout History
// ══════════════════════════════════════════════════════════════

class _PremiumPayoutHistory extends StatelessWidget {
  final AsyncValue<List<HostPayout>> payoutsAsync;
  final List<HostPayout> payouts;

  const _PremiumPayoutHistory({
    required this.payoutsAsync,
    required this.payouts,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          if (payoutsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (payouts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.textTertiary,
                    size: 32,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'No payouts yet',
                    style: AppTextStyles.bodySmall,
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < payouts.length; i++) ...[
              if (i > 0) const Divider(height: AppSpacing.lg, color: AppColors.border),
              _PremiumPayoutTile(payout: payouts[i]),
            ],
        ],
      ),
    );
  }
}

class _PremiumPayoutTile extends StatelessWidget {
  final HostPayout payout;

  const _PremiumPayoutTile({required this.payout});

  Color get _statusColor {
    switch (payout.status) {
      case 'paid':
        return AppColors.success;
      case 'processing':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  String get _dateLabel =>
      '${payout.date.month}/${payout.date.day}/${payout.date.year}';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: const Icon(
            Icons.account_balance_rounded,
            color: AppColors.success,
            size: 18,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(payout.period, style: AppTextStyles.titleSmall),
              const SizedBox(height: 2),
              Text(
                '$_dateLabel • ${payout.method}',
                style: AppTextStyles.caption,
              ),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              payout.formattedAmount,
              style: AppTextStyles.titleSmall.copyWith(
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: _statusColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
              child: Text(
                payout.status,
                style: AppTextStyles.labelSmall.copyWith(
                  color: _statusColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Filter Chips
// ══════════════════════════════════════════════════════════════

class _PremiumFilterChips extends StatelessWidget {
  final List<String> filters;
  final String selected;
  final ValueChanged<String> onSelected;

  const _PremiumFilterChips({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final isSelected = selected == filter;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: GestureDetector(
              onTap: () => onSelected(filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  filter,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isSelected ? Colors.white : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Empty State
// ══════════════════════════════════════════════════════════════

class _PremiumEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _PremiumEmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

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
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.textTertiary, size: 28),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(actionLabel!),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Create Experience FAB
// ══════════════════════════════════════════════════════════════

class _CreateExperienceFab extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateExperienceFab({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_rounded),
      label: Text(
        'Create Experience',
        style: AppTextStyles.labelLarge.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      elevation: 4,
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Partner Card
// ══════════════════════════════════════════════════════════════

class _PremiumPartnerCard extends StatelessWidget {
  final Restaurant restaurant;
  final int eventsTogether;
  final VoidCallback onCreateEvent;

  const _PremiumPartnerCard({
    required this.restaurant,
    required this.eventsTogether,
    required this.onCreateEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
              restaurant.imagePath ?? 'assets/images/venue_interior.png',
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
                  restaurant.name,
                  style: AppTextStyles.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$eventsTogether event${eventsTogether == 1 ? '' : 's'} together • ${restaurant.cuisine}',
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: OutlinedButton(
              onPressed: onCreateEvent,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Create', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}

// (_PremiumInviteCard and _PremiumPromoteCard replaced by _PremiumCollabCard
// and _PremiumPromotableEventCard at end of file)

// ══════════════════════════════════════════════════════════════
// Shared helper widgets
// ══════════════════════════════════════════════════════════════

class _MethodOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodOption({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.titleSmall),
                  Text(subtitle, style: AppTextStyles.caption),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.labelSmall.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Bottom-sheet editor for a saved draft. Pops only the fields that changed,
/// in the create-schema's camelCase shape, for `PATCH /events/:id`.
class _DraftEditSheet extends StatefulWidget {
  final Dinner draft;

  const _DraftEditSheet({required this.draft});

  @override
  State<_DraftEditSheet> createState() => _DraftEditSheetState();
}

class _DraftEditSheetState extends State<_DraftEditSheet> {
  late final TextEditingController _titleCtrl = TextEditingController(
    text: widget.draft.title,
  );
  late final TextEditingController _descCtrl = TextEditingController(
    text: widget.draft.description,
  );
  late final TextEditingController _seatsCtrl = TextEditingController(
    text: '${widget.draft.totalSeats}',
  );
  late final TextEditingController _priceCtrl = TextEditingController(
    text: widget.draft.pricePerSeat.toStringAsFixed(0),
  );
  late DateTime _date = widget.draft.dateTime;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _seatsCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Map<String, dynamic> _buildPatch() {
    final draft = widget.draft;
    final patch = <String, dynamic>{};
    final title = _titleCtrl.text.trim();
    if (title.isNotEmpty && title != draft.title) patch['title'] = title;
    final description = _descCtrl.text.trim();
    if (description != draft.description) {
      patch['description'] = description;
    }
    if (_date != draft.dateTime) {
      patch['startAt'] = DateTime(
        _date.year,
        _date.month,
        _date.day,
        draft.dateTime.hour,
        draft.dateTime.minute,
      ).toUtc().toIso8601String();
    }
    final seats = int.tryParse(_seatsCtrl.text.trim());
    if (seats != null && seats != draft.totalSeats) {
      patch['seatsTotal'] = seats;
    }
    final price = double.tryParse(_priceCtrl.text.trim());
    if (price != null && price != draft.pricePerSeat) {
      patch['pricePerSeat'] = price;
    }
    return patch;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.paddingScreen,
        right: AppSpacing.paddingScreen,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Edit draft', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _titleCtrl,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Date'),
              child: Text(
                '${_date.month}/${_date.day}/${_date.year}',
                style: AppTextStyles.bodyMedium,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _seatsCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Seats'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Price per seat',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  text: 'Cancel',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: PrimaryButton(
                  text: 'Save changes',
                  onPressed: () => Navigator.pop(context, _buildPatch()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Collab Card (full lifecycle)
// ══════════════════════════════════════════════════════════════

class _PremiumCollabCard extends StatelessWidget {
  final CollaborationInvite collab;
  final VoidCallback onView;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  const _PremiumCollabCard({
    required this.collab,
    required this.onView,
    this.onCancel,
    this.onComplete,
  });

  Color get _statusColor {
    switch (collab.status) {
      case 'accepted':
        return AppColors.success;
      case 'declined':
        return AppColors.danger;
      case 'cancelled':
        return AppColors.textSecondary;
      case 'completed':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: _statusColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  collab.statusLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: _statusColor,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              Icon(
                collab.isIncoming
                    ? Icons.inbox_rounded
                    : Icons.send_rounded,
                color: AppColors.textSecondary,
                size: 14,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Image.asset(
                  collab.restaurant.imagePath ??
                      'assets/images/venue_interior.png',
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collab.title,
                      style: AppTextStyles.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${collab.restaurant.name} • ${collab.receivedLabel}',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            collab.message,
            style: AppTextStyles.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onView,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              ),
              child: const Text('View details', style: TextStyle(fontSize: 12)),
            ),
          ),
          if (onCancel != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                ),
                child: const Text('Cancel Proposal', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
          if (onComplete != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onComplete,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                ),
                child: const Text('Mark Complete', style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Premium Promotable Event Card
// ══════════════════════════════════════════════════════════════

class _PremiumPromotableEventCard extends StatelessWidget {
  final PromotableEvent event;
  final VoidCallback onPromote;

  const _PremiumPromotableEventCard({
    required this.event,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AppTextStyles.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.restaurantName} • ${event.seatsLeft} seats left • Rs ${event.pricePerSeat.toStringAsFixed(0)}',
                  style: AppTextStyles.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton.icon(
            onPressed: onPromote,
            icon: const Icon(Icons.share_rounded, size: 14),
            label: const Text('Promote', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Discover Partner Tile
// ══════════════════════════════════════════════════════════════

class _DiscoverPartnerTile extends StatelessWidget {
  final DiscoverablePartner partner;
  final VoidCallback onPropose;

  const _DiscoverPartnerTile({
    required this.partner,
    required this.onPropose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(partner.name, style: AppTextStyles.titleSmall),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (partner.rating > 0) ...[
                      const Icon(Icons.star_rounded,
                          color: AppColors.gold, size: 12),
                      const SizedBox(width: 2),
                      Text(
                        partner.rating.toStringAsFixed(1),
                        style: AppTextStyles.caption,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Text(
                      partner.neighborhood,
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
                if (partner.cuisines.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    partner.cuisines.join(' \u2022 '),
                    style: AppTextStyles.caption.copyWith(fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ElevatedButton(
            onPressed: onPropose,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Propose', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
