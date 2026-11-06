import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/menu_link.dart';
import '../../widgets/buttons.dart';
import '../restaurant_detail/restaurant_profile_route.dart';

/// Full-screen camera scanner for restaurant QR codes.
///
/// Accepts three payload shapes (see [parseMenuPayload]):
///   - `dinecircle://menu/<uuid>`
///   - `https://<host>/menu/<uuid>`
///   - bare `<uuid>`
///
/// On a successful scan the user is pushed to the shared Restaurant Profile
/// screen via [openRestaurantProfile] — the same entry point used by list
/// taps, search results and deep links. A torch toggle and close button
/// overlay the camera preview. Permission-denied state shows an explanatory
/// card with a manual code-entry fallback. Invalid payloads keep the scanner
/// alive and surface an inline error strip so the user can rescan.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );

  bool _handled = false;
  String? _scanError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null) return;

    final restaurantId = parseMenuPayload(raw);
    if (restaurantId == null) {
      // Keep the scanner alive: clear the error on the next scan and let the
      // user try again without leaving the screen.
      setState(() {
        _scanError = "That QR code isn't a DineCircle menu.";
      });
      return;
    }

    _handled = true;
    _scanError = null;
    openRestaurantProfile(context, id: restaurantId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.close_rounded, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (_, state, _) {
              final on = state.torchState == TorchState.on;
              return IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    on ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: Colors.white,
                  ),
                ),
                onPressed: () => _controller.toggleTorch(),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<MobileScannerState>(
        valueListenable: _controller,
        builder: (_, state, _) {
          // Permission denied
          if (state.error != null &&
              state.error!.errorCode ==
                  MobileScannerErrorCode.permissionDenied) {
            return _PermissionDeniedBody(
              onManualEntry: _showManualEntrySheet,
              onGoBack: () => Navigator.pop(context),
            );
          }

          return Stack(
            children: [
              // Camera preview
              MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
              ),
              // Cut-out overlay
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusLg),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_scanError != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.9),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Text(
                          _scanError!,
                          style: AppTextStyles.labelSmall.copyWith(
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusFull),
                        ),
                        child: Text(
                          'Scan a restaurant QR code',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Manual entry button at bottom
              Positioned(
                left: 0,
                right: 0,
                bottom:
                    MediaQuery.of(context).padding.bottom + AppSpacing.lg,
                child: Center(
                  child: TextButton.icon(
                    onPressed: _showManualEntrySheet,
                    icon: const Icon(
                      Icons.keyboard_rounded,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Enter code manually',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showManualEntrySheet() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ManualCodeSheet(),
    );
    if (!mounted) return;
    if (result != null) {
      final restaurantId = parseMenuPayload(result);
      if (restaurantId != null) {
        _handled = true;
        _scanError = null;
        openRestaurantProfile(context, id: restaurantId);
      } else {
        setState(() {
          _scanError = 'Invalid menu code. Please check and try again.';
        });
      }
    }
  }
}

/// Permission-denied fallback with manual entry.
class _PermissionDeniedBody extends StatelessWidget {
  const _PermissionDeniedBody({
    required this.onManualEntry,
    required this.onGoBack,
  });

  final VoidCallback onManualEntry;
  final VoidCallback onGoBack;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Camera permission required',
              style: AppTextStyles.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'DineCircle needs camera access to scan restaurant menu QR codes. '
              'Please enable it in your device settings, or enter a code manually.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              text: 'Enter code manually',
              icon: Icons.keyboard_rounded,
              onPressed: onManualEntry,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onGoBack,
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small bottom sheet for pasting a menu link or UUID manually.
class _ManualCodeSheet extends StatefulWidget {
  const _ManualCodeSheet();

  @override
  State<_ManualCodeSheet> createState() => _ManualCodeSheetState();
}

class _ManualCodeSheetState extends State<_ManualCodeSheet> {
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter menu code', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Paste a DineCircle menu link or restaurant UUID from the QR code.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _textController,
            decoration: const InputDecoration(
              hintText: 'dinecircle://menu/… or UUID',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.qr_code_rounded),
            ),
            autofocus: true,
            maxLines: 2,
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            text: 'Open menu',
            onPressed: () {
              final text = _textController.text.trim();
              if (text.isNotEmpty) {
                Navigator.pop(context, text);
              }
            },
          ),
        ],
      ),
    );
  }
}
