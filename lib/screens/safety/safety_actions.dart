import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../providers/api_client_provider.dart';
import '../../providers/safety_provider.dart';

/// Shared "Block user" confirmation flow (P2-1).
///
/// Used from profiles and chat. The server decides everything real — mutual
/// follows are removed in one transaction and discovery/messaging restrictions
/// apply immediately — so the client only confirms, calls
/// `POST /users/:id/block`, refreshes the affected providers and [popOnSuccess]
/// leaves whatever surface showed the blocked person. Returns the outcome so
/// callers can react; never claims success on failure.
Future<bool> confirmAndBlock({
  required BuildContext context,
  required WidgetRef ref,
  required String userId,
  required String userName,
  bool popOnSuccess = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Block $userName?'),
      content: Text(
        'You and $userName will stop seeing each other\u2019s profiles, '
        'events and content, and any follows between you are removed. This '
        'does not cancel existing bookings \u2014 contact support if you need '
        'help with one.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('blockConfirmButton'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Block'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await ref.read(safetyRepositoryProvider).block(userId);
    ref
      ..invalidate(blockedUsersProvider)
      ..invalidate(myReportsProvider);
    if (!context.mounted) return true;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$userName is blocked.')));
    if (popOnSuccess) Navigator.of(context).pop();
    return true;
  } on ApiException catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
    return false;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not block. Try again.')),
      );
    }
    return false;
  }
}
