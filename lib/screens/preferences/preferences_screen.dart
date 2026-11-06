import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../api/api_exception.dart';
import '../../data/mock_data.dart';

/// Taste preferences screen.
///
/// The chosen cuisines are persisted to the server through `PATCH /users/me`
/// (`tastes[]`) rather than kept local-only, so personalization follows the
/// account across devices. The first-launch flag still advances even if the
/// write fails, so a transient error never traps the user on this screen.
class PreferencesScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;

  const PreferencesScreen({super.key, required this.onComplete});

  @override
  ConsumerState<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends ConsumerState<PreferencesScreen> {
  final Set<String> _selectedInterests = {};
  // The city captured during first-run; defaults to the app's home market so a
  // fresh account always lands in the seeded Karachi world.
  String _selectedCity = 'Karachi';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Re-hydrate prior selections so returning users see their saved tastes.
    final user = ref.read(currentUserProvider);
    final existing = user?.interests;
    if (existing != null) _selectedInterests.addAll(existing);
    _selectedCity = user?.location ?? 'Karachi';
  }

  void _toggleInterest(String interest) {
    setState(() {
      if (_selectedInterests.contains(interest)) {
        _selectedInterests.remove(interest);
      } else {
        _selectedInterests.add(interest);
      }
    });
  }

  void _selectCity(String city) => setState(() => _selectedCity = city);

  /// Best-effort server persist, then hand control back to [AppFlow].
  Future<void> _continue() async {
    if (_saving) return;
    final user = ref.read(currentUserProvider);
    if (user == null) {
      widget.onComplete();
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionControllerProvider.notifier)
          .updateProfile(
            name: user.name,
            city: _selectedCity,
            bio: user.bio ?? '',
            // The server caps tastes at 8; trim rather than risk a 422.
            tastes: _selectedInterests.take(8).toList(),
          );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      // Network hiccup: proceed so first-launch isn't blocked.
    }
    if (mounted) widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.paddingScreen,
                  AppSpacing.paddingScreen,
                  AppSpacing.paddingScreen,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'What are you interested in?',
                        style: AppTextStyles.displaySmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Select your favorite cuisines and dining styles to personalize your experience.',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Interests
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                  vertical: AppSpacing.lg,
                ),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: MockData.interestTags.map((interest) {
                    final isSelected = _selectedInterests.contains(interest);
                    return TagChip(
                      label: interest,
                      isSelected: isSelected,
                      onTap: () => _toggleInterest(interest),
                    );
                  }).toList(),
                ),
              ),
              // Location
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.paddingScreen,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Where do you dine?',
                      style: AppTextStyles.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Pick your city so we can show dinners near you.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: MockData.cities.map((city) {
                        return TagChip(
                          label: city,
                          isSelected: city == _selectedCity,
                          onTap: () => _selectCity(city),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              // Bottom button
              Padding(
                padding: const EdgeInsets.all(AppSpacing.paddingScreen),
                child: Column(
                  children: [
                    Text(
                      '${_selectedInterests.length} selected · $_selectedCity',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    PrimaryButton(
                      text: 'Continue',
                      isLoading: _saving,
                      onPressed: !_saving && _selectedInterests.isNotEmpty
                          ? _continue
                          : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
