import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';

/// Opens the change-password sheet (`POST /auth/change-password`).
Future<void> showChangePasswordSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: const ChangePasswordSheet(),
    ),
  );
}

/// Bottom-sheet password changer. The server verifies the current password
/// before accepting the new one; on success every OTHER session is revoked
/// while this device stays signed in, so the sheet simply closes.
class ChangePasswordSheet extends ConsumerStatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  ConsumerState<ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    if (current.isEmpty) {
      setState(() => _error = 'Enter your current password.');
      return;
    }
    if (next.length < 8) {
      setState(() => _error = 'New password needs at least 8 characters.');
      return;
    }
    if (next != _confirmCtrl.text) {
      setState(() => _error = 'The new passwords do not match.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .changePassword(currentPassword: current, newPassword: next);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Password changed. Other devices will need to sign in again.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not reach the server. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Change Password', style: AppTextStyles.titleLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'For security, all your other devices are signed out.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('currentPasswordField'),
            controller: _currentCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(labelText: 'Current password'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('newPasswordField'),
            controller: _newCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'New password (min 8 characters)',
              suffixIcon: Icon(Icons.visibility_off_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('confirmPasswordField'),
            controller: _confirmCtrl,
            obscureText: _obscure,
            decoration: const InputDecoration(
              labelText: 'Confirm new password',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            text: 'Update password',
            isLoading: _saving,
            onPressed: _saving ? null : _submit,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
