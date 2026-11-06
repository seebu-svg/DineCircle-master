import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../providers/session_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Password-confirmed account deletion (`DELETE /users/me`), shared by the
/// Profile and Settings screens so both run the same real flow. The server
/// cancels/refunds live bookings, anonymises the account, purges the profile
/// photo and revokes every session; on success the cleared session routes the
/// app to AuthScreen.
///
/// The dialog owns its text field (and disposes it itself), returning the
/// password as the route result so no controller outlives the pop animation.
Future<void> confirmAndDeleteAccount(
  BuildContext context,
  WidgetRef ref,
) async {
  final password = await showDialog<String>(
    context: context,
    builder: (ctx) => const DeleteAccountDialog(),
  );
  if (password == null || password.isEmpty) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(sessionControllerProvider.notifier)
        .deleteAccount(password: password);
    messenger.showSnackBar(
      const SnackBar(content: Text('Your account has been deleted.')),
    );
  } on ApiException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Could not delete the account. Try again.')),
    );
  }
}

/// Password gate for account deletion. Owns (and disposes) its controller so
/// the field stays valid through the dialog's pop animation. The destructive
/// action stays disabled until a password is typed.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_passwordCtrl.text.isEmpty) return;
    Navigator.pop(context, _passwordCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently deletes your account and profile photo. '
              'Upcoming bookings are cancelled and paid seats refunded. '
              'This cannot be undone.',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('deleteAccountPassword'),
              controller: _passwordCtrl,
              obscureText: true,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Confirm your password',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _passwordCtrl,
          builder: (context, value, _) => TextButton(
            onPressed: value.text.isEmpty ? null : _submit,
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Delete forever'),
          ),
        ),
      ],
    );
  }
}
