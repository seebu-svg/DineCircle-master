import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/safety.dart';
import '../../providers/safety_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/data_view.dart';

/// Settings → Support → My Reports: everything the user has reported with its
/// live moderation status (`GET /users/me/reports`). Each row shows the
/// server-issued `RP-…` reference so support can follow up without ever
/// exposing who reported whom to anyone else.
class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(myReportsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Reports')),
      body: DataView<List<ReportItem>>(
        value: reports,
        onRetry: () => ref.invalidate(myReportsProvider),
        isEmpty: (items) => items.isEmpty,
        emptyMessage:
            'You have not reported anything yet. You can report a profile, '
            'event, review or message from its menu.',
        builder: (context, items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myReportsProvider),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.paddingScreen),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) => _ReportCard(report: items[index]),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report});

  final ReportItem report;

  static (Color, IconData) _statusVisual(ReportStatus status) =>
      switch (status) {
        ReportStatus.pending => (
          AppColors.warning,
          Icons.hourglass_top_rounded,
        ),
        ReportStatus.reviewing => (AppColors.info, Icons.visibility_rounded),
        ReportStatus.resolved => (
          AppColors.success,
          Icons.check_circle_outline_rounded,
        ),
        ReportStatus.dismissed => (
          AppColors.textTertiary,
          Icons.do_not_disturb_on_outlined,
        ),
      };

  String _formattedDate() {
    final date = report.createdAt;
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _statusVisual(report.status);
    return Container(
      key: Key('reportCard_${report.id}'),
      padding: const EdgeInsets.all(AppSpacing.paddingCard),
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
                child: Text(
                  '${report.targetType.label} report',
                  style: AppTextStyles.titleSmall,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: AppSpacing.iconXs, color: color),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      report.status.label,
                      style: AppTextStyles.labelSmall.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(report.reason.label, style: AppTextStyles.bodyMedium),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              report.description,
              style: AppTextStyles.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              if (_formattedDate().isNotEmpty) _formattedDate(),
              'Ref ${report.reference}',
            ].join(' · '),
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
