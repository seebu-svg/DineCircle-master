import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../data/mock_data.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';

/// P1-5 Food Preferences — cuisines/interests, dietary preferences and
/// allergies, all persisted through `PATCH /users/me` (`tastes`, `dietary`,
/// `allergies`). The server caps tastes at 8 and the label lists at 12, so
/// the screen enforces the same ceilings instead of surfacing a 422.
class FoodPreferencesScreen extends ConsumerStatefulWidget {
  const FoodPreferencesScreen({super.key});

  @override
  ConsumerState<FoodPreferencesScreen> createState() =>
      _FoodPreferencesScreenState();
}

class _FoodPreferencesScreenState extends ConsumerState<FoodPreferencesScreen> {
  /// Common allergen labels offered as one-tap chips; anything else can be
  /// typed. Mirrors the usual "major allergens" vocabulary venues expect.
  static const List<String> _allergySuggestions = [
    'Peanuts',
    'Tree Nuts',
    'Shellfish',
    'Fish',
    'Eggs',
    'Milk',
    'Wheat',
    'Soy',
    'Sesame',
  ];

  static const int _maxTastes = 8;
  static const int _maxLabels = 12;

  final _allergyCtrl = TextEditingController();
  late final Set<String> _tastes;
  late final Set<String> _dietary;
  late final Set<String> _allergies;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _tastes = {if (user != null) ...user.interests};
    _dietary = {if (user != null) ...user.dietary};
    _allergies = {if (user != null) ...user.allergies};
  }

  @override
  void dispose() {
    _allergyCtrl.dispose();
    super.dispose();
  }

  void _toggle(Set<String> bucket, String value, int cap) {
    setState(() {
      if (bucket.contains(value)) {
        bucket.remove(value);
      } else if (bucket.length < cap) {
        bucket.add(value);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You can pick up to $cap here.')),
        );
      }
    });
  }

  void _addAllergy() {
    final raw = _allergyCtrl.text.trim();
    if (raw.isEmpty) return;
    _allergyCtrl.clear();
    _toggle(_allergies, raw, _maxLabels);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(sessionControllerProvider.notifier).updateSettings({
        'tastes': _tastes.toList(),
        'dietary': _dietary.toList(),
        'allergies': _allergies.toList(),
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Food preferences saved.'),
          backgroundColor: AppColors.success,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Food Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          Text('Cuisines & interests', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Shapes your feed. Up to $_maxTastes '
            '(${_tastes.length} selected).',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipWall(
            options: MockData.interestTags,
            selected: _tastes,
            onTap: (value) => _toggle(_tastes, value, _maxTastes),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text('Dietary preferences', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Hosts see these before approving your seat.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipWall(
            options: MockData.dietaryOptions,
            selected: _dietary,
            onTap: (value) => _toggle(_dietary, value, _maxLabels),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text('Allergies', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Shared with the host and venue when you book.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _ChipWall(
            options: _allergySuggestions,
            selected: _allergies,
            onTap: (value) => _toggle(_allergies, value, _maxLabels),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('allergyFreeField'),
                  controller: _allergyCtrl,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    hintText: 'Add your own (e.g. Cilantro)',
                    counterText: '',
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addAllergy(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add allergy',
                onPressed: _allergies.length < _maxLabels ? _addAllergy : null,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          child: PrimaryButton(
            text: 'Save preferences',
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}

/// A selectable chip wall: [options] render as tags bound to [selected];
/// selections outside [options] (free-text allergies) stay visible at the
/// end so nothing picked is invisible. [onTap] toggles membership.
class _ChipWall extends StatelessWidget {
  const _ChipWall({
    required this.options,
    required this.selected,
    required this.onTap,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final extras = selected.where((s) => !options.contains(s)).toList();
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        ...options.map(
          (option) => TagChip(
            label: option,
            isSelected: selected.contains(option),
            onTap: () => onTap(option),
          ),
        ),
        ...extras.map(
          (extra) => TagChip(
            label: extra,
            isSelected: true,
            onTap: () => onTap(extra),
          ),
        ),
      ],
    );
  }
}
