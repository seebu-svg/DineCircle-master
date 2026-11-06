import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../models/user_profile.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../repositories/users_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/avatar_picker_sheet.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/buttons.dart';

/// Same rule as the server's `HANDLE_PATTERN`.
final RegExp _handlePattern = RegExp(
  r'^(?!.*\.\.)[a-z0-9_][a-z0-9._]{1,28}[a-z0-9_]$',
);
final RegExp _instagramPattern = RegExp(r'^[A-Za-z0-9._]{0,30}$');

/// Strips a leading `@` (users type it out of habit) and lower-cases.
String _normalizeHandle(String raw) =>
    raw.trim().replaceFirst(RegExp(r'^@+'), '').toLowerCase();

/// Accepts `name`, `@name` or a pasted profile URL.
String _normalizeInstagram(String raw) => raw
    .trim()
    .replaceFirst(
      RegExp(r'^(https?://)?(www\.)?instagram\.com/', caseSensitive: false),
      '',
    )
    .replaceFirst(RegExp(r'^@+'), '')
    .replaceFirst(RegExp(r'/+$'), '');

/// Full-screen editor for the signed-in profile card: photo, name, username,
/// city, bio and Instagram.
///
/// Only fields that actually changed are sent, so tastes, privacy toggles and
/// food preferences (owned by other screens) are never touched. Validation
/// mirrors the server's `PATCH /users/me` schema and the server stays
/// authoritative (e.g. a 409 for a username claimed a moment ago). The
/// username field additionally runs an advisory availability pre-check so the
/// diner sees the answer before saving.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key, required this.user});

  final UserProfile user;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.user.name,
  );
  late final TextEditingController _handleCtrl = TextEditingController(
    text: widget.user.handle,
  );
  late final TextEditingController _cityCtrl = TextEditingController(
    text: widget.user.location ?? '',
  );
  late final TextEditingController _bioCtrl = TextEditingController(
    text: widget.user.bio ?? '',
  );
  late final TextEditingController _instagramCtrl = TextEditingController(
    text: widget.user.instagram,
  );

  bool _saving = false;

  /// Set right before a programmatic pop so [PopScope] lets it through.
  bool _allowPop = false;

  /// Server/network failure banner (a 409 lands on the handle field instead).
  String? _error;

  String? _nameError;
  String? _handleError;
  String? _cityError;
  String? _bioError;
  String? _instagramError;

  /// Username the availability pre-check was last asked about; empty when the
  /// typed value is unchanged or locally invalid.
  String _lookupHandle = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _nameCtrl.dispose();
    _handleCtrl.dispose();
    _cityCtrl.dispose();
    _bioCtrl.dispose();
    _instagramCtrl.dispose();
    super.dispose();
  }

  /// True once any field differs from what the server last sent.
  bool get _dirty {
    final user = widget.user;
    return _nameCtrl.text.trim() != user.name ||
        _normalizeHandle(_handleCtrl.text) != user.handle.toLowerCase() ||
        _cityCtrl.text.trim() != (user.location ?? '') ||
        _bioCtrl.text.trim() != (user.bio ?? '') ||
        _normalizeInstagram(_instagramCtrl.text) != user.instagram;
  }

  void _onHandleChanged(String raw) {
    _debounce?.cancel();
    final handle = _normalizeHandle(raw);
    final changed = handle != widget.user.handle.toLowerCase();
    // Nothing to check while the field still holds the saved username or the
    // typed value cannot be a username at all — the local error owns that.
    if (!changed || handle.isEmpty || !_handlePattern.hasMatch(handle)) {
      if (_lookupHandle.isNotEmpty) setState(() => _lookupHandle = '');
      if (_handleError != null) setState(() => _handleError = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() => _lookupHandle = handle);
    });
  }

  void _clearFieldErrors() {
    _nameError = null;
    _handleError = null;
    _cityError = null;
    _bioError = null;
    _instagramError = null;
  }

  /// Validates the form and returns the changed fields only, or null (with the
  /// per-field errors set) when something is invalid.
  Map<String, dynamic>? _buildPatch() {
    _clearFieldErrors();
    final user = widget.user;

    final name = _nameCtrl.text.trim();
    if (name.length < 2 || name.length > 80) {
      _nameError = 'Name must be 2–80 characters.';
    }

    final handle = _normalizeHandle(_handleCtrl.text);
    // A legacy handle the user did not touch is never re-validated.
    final handleChanged = handle != user.handle.toLowerCase();
    if (handleChanged) {
      if (!_handlePattern.hasMatch(handle)) {
        _handleError =
            'Usernames are 3–30 letters, numbers, _ or . '
            '(no leading/trailing dot).';
      } else if (handle.startsWith('deleted_')) {
        _handleError = 'That username is reserved.';
      }
    }

    final city = _cityCtrl.text.trim();
    final cityChanged = city != (user.location ?? '');
    if (cityChanged && (city.length < 2 || city.length > 60)) {
      _cityError = 'City is required.';
    }

    final bio = _bioCtrl.text.trim();
    if (bio.length > 400) {
      _bioError = 'Bio must be 400 characters or fewer.';
    }

    final instagram = _normalizeInstagram(_instagramCtrl.text);
    if (!_instagramPattern.hasMatch(instagram)) {
      _instagramError = 'Enter a valid Instagram username.';
    }

    if (_nameError != null ||
        _handleError != null ||
        _cityError != null ||
        _bioError != null ||
        _instagramError != null) {
      return null;
    }

    return {
      if (name != user.name) 'name': name,
      if (handleChanged) 'handle': handle,
      if (cityChanged) 'city': city,
      if (bio != (user.bio ?? '')) 'bio': bio,
      if (instagram != user.instagram) 'instagram': instagram,
    };
  }

  /// Pops the editor, letting [PopScope] know the exit is intentional.
  Future<void> _pop() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    // Let the rebuilt PopScope register `canPop: true` before popping.
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _save() async {
    if (_saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final patch = _buildPatch();
    if (patch == null) {
      setState(() => _error = null);
      return;
    }

    // A username the pre-check already knows is claimed never reaches the
    // server; the message is identical to what a 409 would say.
    final handle = _normalizeHandle(_handleCtrl.text);
    if (patch.containsKey('handle') && _lookupHandle == handle) {
      final known = ref.read(handleAvailabilityProvider(handle)).valueOrNull;
      if (known != null && !known.available) {
        setState(() {
          _handleError = known.message;
          _error = null;
        });
        return;
      }
    }

    if (patch.isEmpty) {
      await _pop();
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(sessionControllerProvider.notifier).updateSettings(patch);
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Profile updated')));
      await _pop();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (error.statusCode == 409) {
          _handleError = error.message;
        } else {
          _error = error.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your profile. Please try again.';
      });
    }
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true) await _pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider) ?? widget.user;

    // The pre-check only runs for a username that is new, locally valid and
    // actually the value currently in the field.
    final typedHandle = _normalizeHandle(_handleCtrl.text);
    final lookupActive =
        _lookupHandle.isNotEmpty &&
        _lookupHandle == typedHandle &&
        _handleError == null;
    final availability = lookupActive
        ? ref.watch(handleAvailabilityProvider(_lookupHandle))
        : null;

    return PopScope(
      canPop: _allowPop || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text('Edit Profile', maxLines: 1),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.paddingScreen,
                    AppSpacing.lg,
                    AppSpacing.paddingScreen,
                    AppSpacing.lg,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PhotoHeader(
                            user: user,
                            onTap: () => showAvatarPickerSheet(context),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          if (_error != null) ...[
                            _ErrorBanner(message: _error!),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          _ProfileField(
                            fieldKey: const Key('editProfileName'),
                            controller: _nameCtrl,
                            label: 'Name',
                            helperText: 'How your name appears to other diners',
                            errorText: _nameError,
                            maxLength: 80,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ProfileField(
                            fieldKey: const Key('editProfileHandle'),
                            controller: _handleCtrl,
                            label: 'Username',
                            prefixText: '@',
                            helperText: '3–30 letters, numbers, _ or .',
                            errorText: _handleError,
                            maxLength: 31,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.next,
                            onChanged: _onHandleChanged,
                            below: lookupActive
                                ? _HandleAvailabilityRow(
                                    key: const Key('editProfileHandleStatus'),
                                    availability: availability!,
                                  )
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ProfileField(
                            fieldKey: const Key('editProfileCity'),
                            controller: _cityCtrl,
                            label: 'City',
                            errorText: _cityError,
                            maxLength: 60,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ProfileField(
                            fieldKey: const Key('editProfileBio'),
                            controller: _bioCtrl,
                            label: 'Bio',
                            helperText:
                                'A line or two about what you love to eat',
                            errorText: _bioError,
                            maxLength: 400,
                            maxLines: 4,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _ProfileField(
                            fieldKey: const Key('editProfileInstagram'),
                            controller: _instagramCtrl,
                            label: 'Instagram (optional)',
                            hintText: 'username',
                            errorText: _instagramError,
                            maxLength: 60,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _save(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Sticky footer keeps the primary action reachable above the
              // keyboard no matter how long the form gets.
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                  vertical: AppSpacing.md,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: PrimaryButton(
                      text: 'Save changes',
                      isLoading: _saving,
                      onPressed: _save,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 96 px photo, the "Change photo" action and the read-only login email.
class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.user, required this.onTap});

  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AvatarWidget(
          imagePath: user.avatarPath,
          initials: user.initials,
          size: AppSpacing.avatarXxl,
          onTap: onTap,
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.photo_camera_rounded, size: 18),
                label: const Text('Change photo'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (user.email.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A labelled, validated text field with a visible character counter. Ensures
/// itself is scrolled into view when it gains focus so the keyboard never
/// hides the field being edited.
class _ProfileField extends StatelessWidget {
  const _ProfileField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.helperText,
    this.hintText,
    this.errorText,
    this.prefixText,
    this.maxLength,
    this.maxLines = 1,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction,
    this.keyboardType,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.onSubmitted,
    this.below,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? hintText;
  final String? errorText;
  final String? prefixText;
  final int? maxLength;
  final int maxLines;
  final TextCapitalization textCapitalization;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Optional widget rendered directly under the field (availability status).
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        // Defer past this frame so the keyboard inset is already applied.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: fieldKey,
            controller: controller,
            maxLines: maxLines,
            maxLength: maxLength,
            textCapitalization: textCapitalization,
            textInputAction: textInputAction,
            keyboardType: keyboardType,
            autocorrect: autocorrect,
            enableSuggestions: enableSuggestions,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              labelText: label,
              hintText: hintText,
              helperText: helperText,
              errorText: errorText,
              prefixText: prefixText,
              alignLabelWithHint: maxLines > 1,
            ),
          ),
          ?below,
        ],
      ),
    );
  }
}

/// Advisory username check: spinner while asking, then available / taken /
/// reserved. Purely informational — Save is never blocked by it.
class _HandleAvailabilityRow extends StatelessWidget {
  const _HandleAvailabilityRow({super.key, required this.availability});

  final AsyncValue<HandleAvailability> availability;

  @override
  Widget build(BuildContext context) {
    if (availability.isLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                'Checking availability…',
                style: TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    final error = availability.error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          'Could not check availability',
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textTertiary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final value = availability.valueOrNull;
    if (value == null) return const SizedBox.shrink();

    final ok = value.available;
    final message = ok ? 'Available' : value.message;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            size: 14,
            color: ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(
                color: ok ? AppColors.success : AppColors.danger,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Red banner for a save failure that is not tied to one field.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
