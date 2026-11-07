import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/safety.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/safety_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Shared "Report" bottom sheet used by profiles, events, reviews and chat.
///
/// The flow is the P2 spec's: pick a reason, optionally add details, submit,
/// and show the server-issued `RP-…` reference as confirmation. Duplicate
/// open reports (409) and rate-limit (429) responses surface the server's
/// own message, so the UI never pretends a report went through.
class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
  });

  final ReportTargetType targetType;
  final String targetId;

  /// Presents the sheet; returns `true` if a report was filed successfully.
  static Future<bool> show(
    BuildContext context,
    ReportTargetType targetType,
    String targetId,
  ) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: ReportSheet(targetType: targetType, targetId: targetId),
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  ReportReason? _reason;
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _reference;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reason;
    if (reason == null || _submitting) return;
    setState(() {
      _submitting = true;
      _reference = null;
    });
    try {
      final report = await ref
          .read(safetyRepositoryProvider)
          .submitReport(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: reason,
            description: _descriptionController.text.trim(),
          );
      // Refresh "My Reports" wherever it is mounted.
      ref.invalidate(myReportsProvider);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _reference = report.reference;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send the report. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Success state: keep the sheet open briefly showing the reference so the
    // user can read it before dismissing.
    if (_reference != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.verified_outlined,
              size: 40,
              color: AppColors.success,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Report submitted', style: AppTextStyles.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Keep your reference for follow-up: $_reference',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('reportDoneButton'),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Done'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              ),
            ),
          ),
          Text(
            'Report ${widget.targetType.label.toLowerCase()}',
            style: AppTextStyles.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Your identity stays private. The reported account is never told who filed this.',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: AppSpacing.md),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<ReportReason>(
                    groupValue: _reason,
                    onChanged: (value) => setState(() => _reason = value),
                    child: Column(
                      children: [
                        for (final reason in ReportReason.values)
                          RadioListTile<ReportReason>(
                            key: Key('reportReason_${reason.wire}'),
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              reason.label,
                              style: AppTextStyles.titleSmall,
                            ),
                            value: reason,
                            activeColor: AppColors.primary,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('reportDescriptionField'),
                    controller: _descriptionController,
                    maxLines: 3,
                    maxLength: 1000,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Add details (optional)',
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('reportSubmitButton'),
                      onPressed: _reason == null || _submitting
                          ? null
                          : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Text('Submit report'),
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
}
