import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/saved_location.dart';
import '../../providers/saved_locations_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Screen for managing saved locations (Home, Work, favourites).
///
/// Reached from the Profile / Me tab. The user can:
/// - Set or clear their **Home** and **Work** addresses.
/// - Add a new **favourite** area by typing a city + neighbourhood.
/// - Swipe-to-delete or tap the trash icon on any custom location.
/// - Tap a row to jump to that city/area across the app.
class SavedLocationsScreen extends ConsumerStatefulWidget {
  /// Called when the user taps a saved location to make it active.
  final void Function(String city, String area)? onLocationSelected;

  const SavedLocationsScreen({super.key, this.onLocationSelected});

  @override
  ConsumerState<SavedLocationsScreen> createState() =>
      _SavedLocationsScreenState();
}

class _SavedLocationsScreenState extends ConsumerState<SavedLocationsScreen> {
  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedLocationsProvider);
    final home = _ofKind(saved, SavedLocationKind.home);
    final work = _ofKind(saved, SavedLocationKind.work);
    final favourites = saved
        .where((l) => l.kind == SavedLocationKind.favourite)
        .toList();
    final customs = saved
        .where((l) => l.kind == SavedLocationKind.custom)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: Text('Saved Locations', style: AppTextStyles.headlineMedium),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        children: [
          // ── Home ──────────────────────────────────────────────────────────
          _PinnedLocationTile(
            icon: Icons.home_rounded,
            kind: SavedLocationKind.home,
            label: 'Home',
            location: home,
            onSet: () => _showAddSheet(SavedLocationKind.home),
            onClear: home != null ? () => _clear(home.id) : null,
            onTap: home != null
                ? () => widget.onLocationSelected?.call(home.city, home.area)
                : null,
          ),

          // ── Work ──────────────────────────────────────────────────────────
          _PinnedLocationTile(
            icon: Icons.work_rounded,
            kind: SavedLocationKind.work,
            label: 'Work',
            location: work,
            onSet: () => _showAddSheet(SavedLocationKind.work),
            onClear: work != null ? () => _clear(work.id) : null,
            onTap: work != null
                ? () => widget.onLocationSelected?.call(work.city, work.area)
                : null,
          ),

          const Divider(height: 32, color: AppColors.border),

          // ── Favourites ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.paddingScreen,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text('Favourites', style: AppTextStyles.titleMedium),
                ),
                GestureDetector(
                  onTap: () => _showAddSheet(SavedLocationKind.favourite),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (favourites.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              child: Text(
                'No favourite locations yet. Tap + to add one.',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            )
          else
            for (final loc in favourites)
              _SavedLocationRow(
                location: loc,
                onTap: () =>
                    widget.onLocationSelected?.call(loc.city, loc.area),
                onDelete: () => _clear(loc.id),
              ),

          if (customs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.paddingScreen,
              ),
              child: Text('Other saved', style: AppTextStyles.titleMedium),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final loc in customs)
              _SavedLocationRow(
                location: loc,
                onTap: () =>
                    widget.onLocationSelected?.call(loc.city, loc.area),
                onDelete: () => _clear(loc.id),
              ),
          ],

          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }

  SavedLocation? _ofKind(List<SavedLocation> list, SavedLocationKind kind) {
    for (final loc in list) {
      if (loc.kind == kind) return loc;
    }
    return null;
  }

  Future<void> _clear(String id) async {
    await ref.read(savedLocationsProvider.notifier).remove(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location removed'),
          backgroundColor: AppColors.textSecondary,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _showAddSheet(SavedLocationKind kind) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _AddLocationSheet(kind: kind),
    );
  }
}

// ── Pinned tile (Home / Work) ────────────────────────────────────────────────

class _PinnedLocationTile extends StatelessWidget {
  final IconData icon;
  final SavedLocationKind kind;
  final String label;
  final SavedLocation? location;
  final VoidCallback onSet;
  final VoidCallback? onClear;
  final VoidCallback? onTap;

  const _PinnedLocationTile({
    required this.icon,
    required this.kind,
    required this.label,
    required this.location,
    required this.onSet,
    this.onClear,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSet = location != null;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.paddingScreen,
        vertical: AppSpacing.xs,
      ),
      child: GestureDetector(
        onTap: isSet ? onTap : onSet,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(
              color: isSet
                  ? AppColors.primary.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: isSet
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : AppColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  icon,
                  color: isSet ? AppColors.primary : AppColors.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      isSet ? location!.subtitle : 'Set your $label address',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isSet
                            ? AppColors.textSecondary
                            : AppColors.textTertiary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSet)
                GestureDetector(
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: Icon(
                      Icons.close_rounded,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                  ),
                )
              else
                const Icon(
                  Icons.add_circle_outline_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Row for a favourite / custom saved location ──────────────────────────────

class _SavedLocationRow extends StatelessWidget {
  final SavedLocation location;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _SavedLocationRow({required this.location, this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(location.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete?.call(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: const Icon(Icons.delete_rounded, color: AppColors.danger),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.paddingScreen,
          vertical: AppSpacing.xs,
        ),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.bookmark_rounded,
                  color: AppColors.gold,
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location.name,
                        style: AppTextStyles.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        location.subtitle,
                        style: AppTextStyles.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Padding(
                      padding: EdgeInsets.all(AppSpacing.sm),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.textTertiary,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet for adding a saved location ─────────────────────────────────

class _AddLocationSheet extends ConsumerStatefulWidget {
  final SavedLocationKind kind;

  const _AddLocationSheet({required this.kind});

  @override
  ConsumerState<_AddLocationSheet> createState() => _AddLocationSheetState();
}

class _AddLocationSheetState extends ConsumerState<_AddLocationSheet> {
  final _nameCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  bool _saving = false;

  String get _kindLabel => switch (widget.kind) {
    SavedLocationKind.home => 'Home',
    SavedLocationKind.work => 'Work',
    SavedLocationKind.favourite => 'Favourite',
    SavedLocationKind.custom => 'Location',
  };

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final city = _cityCtrl.text.trim();
    final area = _areaCtrl.text.trim();
    if (city.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please enter a city.')));
      return;
    }
    setState(() => _saving = true);

    final location = SavedLocation(
      // Local-only IDs use a timestamp; the server assigns a real UUID on sync.
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      kind: widget.kind,
      name: name.isEmpty ? _kindLabel : name,
      city: city,
      area: area,
      address: area.isEmpty ? city : '$area, $city',
    );

    await ref.read(savedLocationsProvider.notifier).add(location);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$_kindLabel location saved.'),
        backgroundColor: AppColors.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.paddingScreen,
        AppSpacing.lg,
        AppSpacing.paddingScreen,
        AppSpacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Add $_kindLabel', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name (optional)',
              hintText: _kindLabel,
              prefixIcon: const Icon(Icons.label_outline_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'City *',
              hintText: 'e.g. Karachi',
              prefixIcon: Icon(Icons.location_city_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _areaCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Area / Neighbourhood',
              hintText: 'e.g. DHA Phase 2',
              prefixIcon: Icon(Icons.map_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('Save $_kindLabel', style: AppTextStyles.button),
            ),
          ),
        ],
      ),
    );
  }
}
