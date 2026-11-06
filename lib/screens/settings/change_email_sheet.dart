import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/user_profile.dart';
import '../../providers/session_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';

/// Opens the verified email-change sheet (`POST /auth/change-email` →
/// `POST /auth/change-email/confirm`).
Future<void> showChangeEmailSheet(BuildContext context, UserProfile user) {
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
      child: ChangeEmailSheet(currentEmail: user.email),
    ),
  );
}

/// Two-step email changer: password-confirmed request first, then the 6-digit
/// code the server minted for the pending address. The email is only applied
/// after the code validates, so an attacker with the password still needs
/// access to the destination address (or, in this prototype without a mail
/// provider, the dev code the API returns directly).
class ChangeEmailSheet extends ConsumerStatefulWidget {
  final String currentEmail;

  const ChangeEmailSheet({super.key, required this.currentEmail});

  @override
  ConsumerState<ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends ConsumerState<ChangeEmailSheet> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _confirming = false;
  bool _saving = false;
  String? _error;
  String? _devCode;
  String _pendingEmail = '';

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _codePattern = RegExp(r'^[0-9]{6}$');

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _fail(String message) {
    setState(() {
      _saving = false;
      _error = message;
    });
  }

  /// Step 1: confirm the password and mint the challenge code.
  Future<void> _request() async {
    if (_saving) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !_emailPattern.hasMatch(email)) {
      _fail('Enter a valid email address.');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      _fail('Confirm your password.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final challenge = await ref
          .read(sessionControllerProvider.notifier)
          .requestEmailChange(email: email, password: _passwordCtrl.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _confirming = true;
        _pendingEmail = challenge.pendingEmail.isEmpty
            ? email
            : challenge.pendingEmail;
        _devCode = challenge.devCode;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _fail(error.message);
    } catch (_) {
      if (!mounted) return;
      _fail('Could not reach the server. Please try again.');
    }
  }

  /// Step 2: validate the code and apply the new address.
  Future<void> _confirm() async {
    if (_saving) return;
    final code = _codeCtrl.text.trim();
    if (!_codePattern.hasMatch(code)) {
      _fail('Enter the 6-digit code.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .confirmEmailChange(code: code);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Email updated to $_pendingEmail. Other devices signed out.',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      _fail(error.message);
    } catch (_) {
      if (!mounted) return;
      _fail('Could not reach the server. Please try again.');
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
          Text(
            _confirming ? 'Confirm the code' : 'Change Email',
            style: AppTextStyles.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _confirming
                ? 'We sent a 6-digit code to $_pendingEmail. '
                      'It expires in 15 minutes.'
                : 'Signed in as ${widget.currentEmail}. '
                      'The new address needs to be confirmed before it applies.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_confirming) ...[
            if (_devCode != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'Dev build: your code is $_devCode (no mail provider wired).',
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextField(
              key: const Key('emailCodeField'),
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: const InputDecoration(
                labelText: '6-digit code',
                counterText: '',
              ),
            ),
          ] else ...[
            TextField(
              key: const Key('newEmailField'),
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'New email'),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('confirmPasswordEmailField'),
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Current password'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: AppColors.danger),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            text: _confirming ? 'Confirm change' : 'Send code',
            isLoading: _saving,
            onPressed: _saving ? null : (_confirming ? _confirm : _request),
          ),
          if (_confirming) ...[
            const SizedBox(height: AppSpacing.xs),
            Center(
              child: TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                        _confirming = false;
                        _error = null;
                        _devCode = null;
                        _codeCtrl.clear();
                      }),
                child: const Text('Start over'),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}
