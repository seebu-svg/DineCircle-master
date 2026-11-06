import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_exception.dart';
import '../providers/session_provider.dart';
import '../providers/users_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'avatar_widget.dart';

/// Where a new profile photo comes from.
enum AvatarSource { camera, gallery }

/// Picks a photo and returns its (already resized/compressed) bytes, or null
/// when the user cancels. A provider so widget tests can swap the platform
/// picker for canned bytes.
typedef AvatarImagePicker = Future<Uint8List?> Function(AvatarSource source);

/// Server ceiling for `PUT /users/me/avatar` (mirrors `MAX_AVATAR_BYTES`).
const int kMaxAvatarBytes = 512 * 1024;

final avatarImagePickerProvider = Provider<AvatarImagePicker>((ref) {
  final picker = ImagePicker();
  return (source) async {
    // 512px is twice the largest avatar the app renders; quality 85 keeps a
    // typical JPEG around 50–120 KB — well under the server's 512 KB cap.
    final file = await picker.pickImage(
      source: source == AvatarSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (file == null) return null;
    return file.readAsBytes();
  };
});

/// Opens the profile-photo sheet: take a photo, choose one from the library,
/// or remove the current photo. Uploads go through [SessionController], so
/// every surface reading the session picks the new photo up immediately.
Future<void> showAvatarPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surfaceElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSpacing.radiusXl),
      ),
    ),
    builder: (_) => const SafeArea(child: AvatarPickerSheet()),
  );
}

class AvatarPickerSheet extends ConsumerStatefulWidget {
  const AvatarPickerSheet({super.key});

  @override
  ConsumerState<AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends ConsumerState<AvatarPickerSheet> {
  bool _busy = false;
  String? _error;

  /// Sent/total ratio of the in-flight avatar upload (0..1); null while the
  /// length is unknown or while removing, which render an indeterminate bar.
  double? _progress;

  Future<void> _pick(AvatarSource source) async {
    if (_busy) return;
    final Uint8List? bytes;
    try {
      bytes = await ref.read(avatarImagePickerProvider)(source);
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _error = _permissionMessage(e, source));
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not open that photo. Try another one.');
      return;
    }
    if (bytes == null || !mounted) return; // cancelled
    if (bytes.isEmpty) {
      setState(() => _error = 'Could not open that photo. Try another one.');
      return;
    }
    if (bytes.length > kMaxAvatarBytes) {
      setState(
        () => _error = 'That photo is too large — keep it under 512 KB.',
      );
      return;
    }
    await _run(
      () => ref
          .read(sessionControllerProvider.notifier)
          .uploadAvatar(
            bytes!,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress.clamp(0.0, 1.0));
            },
          ),
      success: 'Profile photo updated',
    );
  }

  Future<void> _remove() => _run(
    () => ref.read(sessionControllerProvider.notifier).removeAvatar(),
    success: 'Profile photo removed',
  );

  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not update your photo. Please try again.';
      });
    }
  }

  String _permissionMessage(PlatformException e, AvatarSource source) {
    final code = e.code.toLowerCase();
    if (code.contains('access_denied') || code.contains('permission')) {
      return source == AvatarSource.camera
          ? 'Camera access is off. Allow it in your device settings.'
          : 'Photo access is off. Allow it in your device settings.';
    }
    if (code.contains('no_available_camera')) {
      return 'No camera is available on this device.';
    }
    return 'Could not open that photo. Try another one.';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final hasPhoto = (user?.avatarPath ?? '').isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Profile Photo',
            style: AppTextStyles.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          // Live preview of what the header will show after the upload.
          Center(
            child: AvatarWidget(
              imagePath: user?.avatarPath,
              initials: user?.initials,
              size: AppSpacing.avatarXxl,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_busy)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                    child: LinearProgressIndicator(
                      key: const Key('avatarBusy'),
                      value: _progress,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceHigh,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _progress == null
                        ? 'Updating photo…'
                        : 'Uploading photo… ${(_progress! * 100).round()}%',
                    key: const Key('avatarProgressLabel'),
                    style: AppTextStyles.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          else ...[
            ListTile(
              key: const Key('avatarTakePhoto'),
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Take Photo'),
              onTap: () => _pick(AvatarSource.camera),
            ),
            ListTile(
              key: const Key('avatarChooseGallery'),
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => _pick(AvatarSource.gallery),
            ),
            if (hasPhoto)
              ListTile(
                key: const Key('avatarRemove'),
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: AppColors.danger,
                ),
                title: Text(
                  'Remove Photo',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: _remove,
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _error!,
              style: AppTextStyles.caption.copyWith(color: AppColors.danger),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
