import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../screens/profile/edit_profile_screen.dart';

/// Opens the shared profile editor as a full-screen page.
///
/// The editor used to be a bottom sheet; it is now a `fullscreenDialog` page
/// (see [EditProfileScreen]) because the form grew a photo block, per-field
/// validation and a sticky save bar, none of which behave well under a sheet
/// while the keyboard is up. The entry point keeps its name and signature so
/// every caller (Profile, Settings) is unchanged.
Future<void> showEditProfileSheet(BuildContext context, UserProfile user) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => EditProfileScreen(user: user),
    ),
  );
}

/// Legacy wrapper kept so existing `EditProfileSheet(user: …)` usages still
/// resolve to the same editor. New code should call [showEditProfileSheet].
class EditProfileSheet extends StatelessWidget {
  const EditProfileSheet({super.key, required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) => EditProfileScreen(user: user);
}
