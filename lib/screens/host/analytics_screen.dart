import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../models/host_models.dart';
import '../../providers/hosts_provider.dart';
import '../../widgets/data_view.dart';

/// Analytics & Insights for hosts, fully server-driven.
///
/// Every metric comes from `GET /hosts/:id/analytics?period=`. No hardcoded
/// values, no client-side factor multiplication. The period selector drives a
/// real re-fetch from the backend.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  static const _periods = ['7d', '30d', '90d', 'all'];
  static const _periodLabels = {'7d': '7D', '30d': '30D', '90d': '90D', 'all': 'All'};

  @override
  void initState() {
    super.initState();
    // Sync the provider's period with the initial selection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsPeriodProvider.notifier).state = '30d';
    });
  }

  void _setPeriod(String period) {
    ref.read(analyticsPeriodProvider.notifier).state = period;
  }

  String _compact(num value) {
    final v = value is int ? value : value.toInt();
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) {
      final k = v / 1000;
      return k >= 10 ? '${k.toStringAsFixed(0)}K' : '${k.toStringAsFixed(1)}K';
    }
    return '$v';
  }

  String _money(double value) =>
      'Rs ${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}';

  @override
  Widget build(BuildContext context) {
    final period = ref.watch(analyticsPeriodProvider);
    final analyticsAsync = ref.watch(myHostAnalyticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text('Analytics & Insights', maxLines: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodSelector(period),
            const SizedBox(height: AppSpacing.lg),
            analyticsAsync.when(
              loading: () => const _AnalyticsSkeleton(),
              error: (error, _) => ErrorStateView(
                error: error,
                onRetry: () => ref.invalidate(myHostAnalyticsProvider),
              ),
              data: (analytics) {
                if (analytics == null) {
                  return const EmptyStateView(
                    icon: Icons.insights_rounded,
                    message: 'Sign in to view your analytics',
                  );
                }
                return _buildAnalyticsContent(analytics, period);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(String current) {
    return Row(
      children: _periods
          .map(
            (period) => Expanded(
              child: GestureDetector(
                onTap: () => _setPeriod(period),
                child: Container(
                  margin: EdgeInsets.only(
                    right: period == _periods.last ? 0 : AppSpacing.sm,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: current == period
                        ? AppColors.primary
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: current == period
                          ? AppColors.primary
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    _periodLabels[period]!,
                    style: AppTextStyles.labelMedium.copyWith(
                      color: current == period
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildAnalyticsContent(HostAnalytics a, String period) {
    final periodLabel = period == 'all' ? 'all time' : 'last ${period.replaceAll('d', ' days')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Key metrics row ─────────────────────────────────────────────
        Text('Overview', style: AppTextStyles.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        _buildKeyMetrics(a),
        const SizedBox(height: AppSpacing.xl),

        // ── Earnings section ────────────────────────────────────────────
        Text('Earnings', style: AppTextStyles.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        _buildEarningsSection(a),
        const SizedBox(height: AppSpacing.xl),

        // ── Performance dashboard (2x2) ─────────────────────────────────
        Text('Performance', style: AppTextStyles.headlineMedium),
        const SizedBox(height: AppSpacing.md),
        _buildPerformanceDashboard(a),
        const SizedBox(height: AppSpacing.xl),

        // ── Revenue Trend chart ─────────────────────────────────────────
        Text('Revenue Trend', style: AppTextStyles.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(periodLabel, style: AppTextStyles.caption),
        const SizedBox(height: AppSpacing.md),
        _buildTrendChart(a.trend),
        const SizedBox(height: AppSpacing.xl),

        // ── Top Performing Experiences ──────────────────────────────────
        if (a.topPerformingEvents.isNotEmpty) ...[
          Text('Top Performing Experiences', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.md),
          _buildTopEvents(a.topPerformingEvents),
          const SizedBox(height: AppSpacing.xl),
        ],

        // ── Event-Level Breakdown ───────────────────────────────────────
        if (a.performance.isNotEmpty) ...[
          Text('Event Breakdown', style: AppTextStyles.headlineMedium),
          const SizedBox(height: AppSpacing.md),
          _buildEventBreakdown(a.performance),
          const SizedBox(height: AppSpacing.xxl),
        ],

        // ── Zero state when no data at all ──────────────────────────────
        if (a.totalEventsHosted == 0 && a.trend.isEmpty && a.performance.isEmpty)
          const EmptyStateView(
            icon: Icons.insights_rounded,
            message: 'No event analytics yet.\nHost your first experience to see data here.',
          ),
      ],
    );
  }

  Widget _buildKeyMetrics(HostAnalytics a) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Events Hosted',
                value: '${a.totalEventsHosted}',
                icon: Icons.restaurant_menu_rounded,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                label: 'Bookings',
                value: '${a.totalBookings}',
                icon: Icons.confirmation_number_rounded,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                label: 'Seats Reserved',
                value: '${a.totalSeatsReserved}',
                icon: Icons.event_seat_rounded,
                color: AppColors.primaryLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _MetricCard(
                label: 'Recorded Revenue',
                value: _money(a.grossRevenue),
                icon: Icons.payments_rounded,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                label: 'Total Views',
                value: _compact(a.totalViews),
                icon: Icons.visibility_rounded,
                color: AppColors.info,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _MetricCard(
                label: 'Avg Rating',
                value: a.reviewCount > 0
                    ? a.averageRating.toStringAsFixed(1)
                    : '-',
                icon: Icons.star_rounded,
                color: AppColors.gold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEarningsSection(HostAnalytics a) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _EarningsRow(
            label: 'Net Earnings',
            value: _money(a.hostNetEarnings),
            icon: Icons.account_balance_wallet_rounded,
            color: AppColors.success,
          ),
          const Divider(height: AppSpacing.lg),
          _EarningsRow(
            label: 'Avg Seat Price',
            value: _money(a.averageSeatPrice),
            icon: Icons.chair_alt_rounded,
            color: AppColors.info,
          ),
          const Divider(height: AppSpacing.lg),
          _EarningsRow(
            label: 'Platform Commission',
            value: _money(a.commission),
            icon: Icons.receipt_long_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceDashboard(HostAnalytics a) {
    final fillRate = (a.averageSeatFillRate * 100).clamp(0, 100);
    final conversion = a.conversionRate.clamp(0, 100);
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _PerformanceCard(
                label: 'Fill Rate',
                value: '${fillRate.toStringAsFixed(1)}%',
                icon: Icons.how_to_reg_rounded,
                color: AppColors.primary,
                subtitle: 'Avg seats filled',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PerformanceCard(
                label: 'Avg Rating',
                value: a.reviewCount > 0
                    ? '${a.averageRating.toStringAsFixed(1)} ★'
                    : '-',
                icon: Icons.star_rounded,
                color: AppColors.gold,
                subtitle: a.reviewCount > 0
                    ? 'From ${a.reviewCount} guest review(s)'
                    : 'No guest reviews yet',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: _PerformanceCard(
                label: 'Upcoming / Done',
                value: '${a.upcomingCount} / ${a.completedCount}',
                icon: Icons.calendar_month_rounded,
                color: AppColors.info,
                subtitle: 'Events status',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _PerformanceCard(
                label: 'Conversion',
                value: '${conversion.toStringAsFixed(1)}%',
                icon: Icons.trending_up_rounded,
                color: AppColors.success,
                subtitle: 'Views → Bookings',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrendChart(List<HostTrendPoint> points) {
    if (points.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: const EmptyStateView(
          icon: Icons.show_chart_rounded,
          message: 'No revenue history yet',
        ),
      );
    }

    final maxRevenue = points.fold<double>(
      0,
      (m, p) => p.revenue > m ? p.revenue : m,
    );
    final effectiveMax = maxRevenue <= 0 ? 1.0 : maxRevenue;

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
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((p) {
                final ratio = (p.revenue / effectiveMax).clamp(0.05, 1.0);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _money(p.revenue),
                          style: AppTextStyles.caption.copyWith(fontSize: 9),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          height: 120 * ratio - 14,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final p in points)
                Text(p.label, style: AppTextStyles.caption),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopEvents(List<HostEventStat> events) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0) const Divider(height: AppSpacing.lg),
            _buildTopEventRow(events[i], i + 1),
          ],
        ],
      ),
    );
  }

  Widget _buildTopEventRow(HostEventStat stat, int rank) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: rank <= 3
                ? AppColors.gold.withValues(alpha: 0.2)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: rank <= 3
                  ? AppColors.gold.withValues(alpha: 0.5)
                  : AppColors.border,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '#$rank',
            style: AppTextStyles.labelSmall.copyWith(
              color: rank <= 3 ? AppColors.gold : AppColors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                stat.title,
                style: AppTextStyles.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${_compact(stat.views)} views • ${stat.bookings} bookings • ${stat.conversion.toStringAsFixed(1)}% conv',
                style: AppTextStyles.caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            '${stat.seatsBooked} seats',
            style: AppTextStyles.titleSmall.copyWith(color: AppColors.success),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEventBreakdown(List<HostEventStat> stats) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const Divider(height: AppSpacing.lg),
            _ExpandableEventRow(
              stat: stats[i],
              compactFmt: _compact,
            ),
          ],
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Widgets
// ══════════════════════════════════════════════════════════════

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetricCard({
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
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value,
            style: AppTextStyles.titleSmall.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
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

class _PerformanceCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String subtitle;

  const _PerformanceCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: AppTextStyles.titleMedium.copyWith(color: color),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.labelSmall),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: AppTextStyles.caption.copyWith(fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _EarningsRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _EarningsRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: AppTextStyles.titleSmall)),
        Text(
          value,
          style: AppTextStyles.titleSmall.copyWith(color: color),
        ),
      ],
    );
  }
}

class _ExpandableEventRow extends StatefulWidget {
  final HostEventStat stat;
  final String Function(num) compactFmt;

  const _ExpandableEventRow({
    required this.stat,
    required this.compactFmt,
  });

  @override
  State<_ExpandableEventRow> createState() => _ExpandableEventRowState();
}

class _ExpandableEventRowState extends State<_ExpandableEventRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.stat;
    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        style: AppTextStyles.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.compactFmt(s.views)} views • ${s.bookings} bookings',
                        style: AppTextStyles.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Text(
                  '${s.seatsBooked} seats',
                  style: AppTextStyles.titleSmall.copyWith(
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.bg,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _DetailChip(label: 'Pending', value: '${s.pending}'),
                _DetailChip(label: 'Checked In', value: '${s.checkedIn}'),
                _DetailChip(
                  label: 'Conversion',
                  value: '${s.conversion.toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;

  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTextStyles.labelMedium),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }
}

/// Loading skeleton shown while analytics are being fetched.
class _AnalyticsSkeleton extends StatelessWidget {
  const _AnalyticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < 6; i++) ...[
          Container(
            height: 80,
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
          ),
        ],
      ],
    );
  }
}
