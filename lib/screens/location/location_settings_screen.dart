import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_exception.dart';
import '../../providers/saved_locations_provider.dart';
import '../../providers/session_provider.dart';
import '../../providers/users_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/buttons.dart';
import '../../widgets/common_widgets.dart';

/// P1-6 Location Settings — the account's city plus a preferred dining area
/// (neighbourhood/district). Both persist through `PATCH /users/me`
/// (`city`, `home_area`) and republish the session, so the map, the nearby
/// feeds and the distance ranking pick the new locale up immediately.
class LocationSettingsScreen extends ConsumerStatefulWidget {
  const LocationSettingsScreen({super.key});

  @override
  ConsumerState<LocationSettingsScreen> createState() =>
      _LocationSettingsScreenState();
}

class _LocationSettingsScreenState
    extends ConsumerState<LocationSettingsScreen> {
  final _searchCtrl = TextEditingController();
  late final TextEditingController _homeAreaCtrl;
  late String _city;
  String _searchQuery = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _city = user?.location ?? 'Karachi';
    _homeAreaCtrl = TextEditingController(text: user?.homeArea ?? '');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _homeAreaCtrl.dispose();
    super.dispose();
  }

  /// Supported cities from `GET /locations/cities` (hard-coded fallback when
  /// offline). The account's current city is always offered, even if it is a
  /// legacy value outside the supported list, so saving never silently moves
  /// the user.
  List<String> _filteredCities(List<String> supported) {
    final cities = [
      if (_city.isNotEmpty && !supported.contains(_city)) _city,
      ...supported,
    ];
    if (_searchQuery.isEmpty) return cities;
    return cities
        .where((c) => c.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  Future<void> _save() async {
    if (_saving) return;
    final area = _homeAreaCtrl.text.trim();
    if (area.length > 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keep the dining area under 80 characters.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(sessionControllerProvider.notifier).updateSettings({
        'city': _city,
        'homeArea': area,
      });
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            area.isEmpty
                ? 'Location set to $_city.'
                : 'Location set to $area, $_city.',
          ),
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
    final cities = _filteredCities(ref.watch(supportedCityNamesProvider));
    final areas = ref.watch(areasForCityProvider(_city));
    return Scaffold(
      appBar: AppBar(title: const Text('Location')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        children: [
          Text('City', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'We show dinners near here first.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchCtrl,
            decoration: const InputDecoration(
              hintText: 'Search city...',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: AppSpacing.md),
          if (cities.isEmpty)
            Text(
              'DineCircle is not in that city yet.',
              style: AppTextStyles.bodySmall,
            )
          else
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: cities
                  .map(
                    (city) => TagChip(
                      key: Key('cityChip_$city'),
                      label: city,
                      isSelected: city == _city,
                      onTap: () => setState(() => _city = city),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: AppSpacing.xl),

          Text('Preferred dining area', style: AppTextStyles.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Optional neighbourhood or district within $_city '
            '(e.g. DHA, Clifton).',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('homeAreaField'),
            controller: _homeAreaCtrl,
            maxLength: 80,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Area or district',
              counterText: '',
            ),
          ),
          if (areas.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: areas
                  .map(
                    (area) => TagChip(
                      key: Key('areaChip_$area'),
                      label: area,
                      isSelected: _homeAreaCtrl.text.trim() == area,
                      onTap: () => setState(() => _homeAreaCtrl.text = area),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.paddingScreen),
          child: PrimaryButton(
            text: 'Save location',
            isLoading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ),
    );
  }
}
