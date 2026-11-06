import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/safety.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/safety_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Help & Feedback → Send feedback.
///
/// Client limits mirror the server's zod schema exactly (subject 3–120,
/// description 10–2000, optional reference ≤40) so a submit only ever fails
/// for real reasons — and the success state shows the `FB-…` ticket the
/// support team asks for.
class FeedbackFormScreen extends ConsumerStatefulWidget {
  const FeedbackFormScreen({super.key, this.initialCategory});

  /// Optional pre-selected category (e.g. `payment` from "Payment Issues").
  final FeedbackCategory? initialCategory;

  @override
  ConsumerState<FeedbackFormScreen> createState() => _FeedbackFormScreenState();
}

class _FeedbackFormScreenState extends ConsumerState<FeedbackFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _refController = TextEditingController();
  late FeedbackCategory? _category = widget.initialCategory;
  bool _submitting = false;
  String? _ticket;

  @override
  void dispose() {
    _subjectController.dispose();
    _descriptionController.dispose();
    _refController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final category = _category;
    if (category == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick a category first.')));
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;
    setState(() => _submitting = true);
    try {
      final item = await ref
          .read(safetyRepositoryProvider)
          .submitFeedback(
            category: category,
            subject: _subjectController.text.trim(),
            description: _descriptionController.text.trim(),
            relatedRef: _refController.text.trim(),
          );
      ref.invalidate(myFeedbackProvider);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _ticket = item.ticket;
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
        const SnackBar(content: Text('Could not send feedback. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Success state replaces the form entirely — nothing left to tap twice.
    if (_ticket != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Send Feedback')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 44,
                  color: AppColors.success,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Thank you!', style: AppTextStyles.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your ticket number is $_ticket. Track its status from '
                  'Help & Feedback — we keep every ticket under this reference.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('feedbackDoneButton'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Send Feedback')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          children: [
            Text('Category', style: AppTextStyles.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final category in FeedbackCategory.values)
                  ChoiceChip(
                    key: Key('feedbackCategory_${category.wire}'),
                    label: Text(category.label),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const Key('feedbackSubjectField'),
              controller: _subjectController,
              maxLength: 120,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Subject',
                hintText: 'Short summary of the issue',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 3) {
                  return 'Give us at least a few words (3+).';
                }
                if (text.length > 120) {
                  return 'Keep the subject under 120 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('feedbackDescriptionField'),
              controller: _descriptionController,
              maxLines: 6,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What happened, and what did you expect?',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.length < 10) {
                  return 'Please add a little more detail (10+ characters).';
                }
                if (text.length > 2000) {
                  return 'Too long — keep it under 2000 characters.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const Key('feedbackRefField'),
              controller: _refController,
              maxLength: 40,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Booking / event reference (optional)',
                hintText: 'e.g. DC-7K3MQF',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              height: AppSpacing.buttonHeightMd,
              child: FilledButton(
                key: const Key('feedbackSubmitButton'),
                onPressed: _category == null || _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text('Send feedback'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
