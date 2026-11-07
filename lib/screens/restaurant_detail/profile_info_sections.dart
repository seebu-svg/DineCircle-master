import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/restaurant.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/opening_hours.dart';
import '../../widgets/media_image.dart';
import 'profile_hero.dart';

/// Icon for a venue facility label. Partners author these freely, so unknown
/// labels fall back to a neutral check rather than disappearing.
IconData facilityIcon(String amenity) {
  final lower = amenity.toLowerCase();
  if (lower.contains('wifi')) return Icons.wifi_rounded;
  if (lower.contains('parking') || lower.contains('park')) {
    return Icons.local_parking_rounded;
  }
  if (lower.contains('access')) return Icons.accessible_rounded;
  if (lower.contains('outdoor') || lower.contains('terrace')) {
    return Icons.outdoor_grill_rounded;
  }
  if (lower.contains('bar')) return Icons.local_bar_rounded;
  if (lower.contains('music') || lower.contains('live')) {
    return Icons.music_note_rounded;
  }
  if (lower.contains('family') || lower.contains('kid')) {
    return Icons.family_restroom_rounded;
  }
  if (lower.contains('delivery')) return Icons.delivery_dining_rounded;
  if (lower.contains('card')) return Icons.credit_card_rounded;
  return Icons.check_circle_outline_rounded;
}

/// Section heading with an optional trailing action.
class ProfileSectionHeading extends StatelessWidget {
  const ProfileSectionHeading({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: Text(title, style: AppTextStyles.headlineSmall)),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Venue description that collapses to four lines with a `Read more` toggle.
///
/// Only offers the toggle when the text is long enough for the clamp to
/// actually hide something, so short blurbs never grow a useless control.
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, required this.text});

  final String text;

  static const int _collapsedLines = 4;
  static const int _toggleThreshold = 180;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final needsToggle = text.length > AboutSection._toggleThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.55,
          ),
          maxLines: _expanded ? null : AboutSection._collapsedLines,
          overflow: _expanded ? null : TextOverflow.ellipsis,
        ),
        if (needsToggle)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                _expanded ? 'Show less' : 'Read more',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Opening hours reduced to today, with the rest of the week behind a toggle.
///
/// Seven always-visible rows pushed everything else off the first screen; the
/// guest almost always needs "am I able to go right now", so today leads.
class OpeningHoursCard extends StatefulWidget {
  const OpeningHoursCard({super.key, required this.hours});

  final Map<String, dynamic> hours;

  @override
  State<OpeningHoursCard> createState() => _OpeningHoursCardState();
}

class _OpeningHoursCardState extends State<OpeningHoursCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final days = parseOpeningHours(widget.hours);
    if (days.isEmpty) return const SizedBox.shrink();

    final todayIndex = DateTime.now().weekday - 1;
    final isOpen = isCurrentlyOpen(days);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _DayRow(
                  day: days[todayIndex],
                  isToday: true,
                  emphasise: true,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OpeningStatusPill(
                isOpen: isOpen,
                todayLabel: days[todayIndex].summary,
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: AppSpacing.xs),
            Divider(height: AppSpacing.md, color: AppColors.border),
            for (var i = 0; i < days.length; i++)
              if (i != todayIndex) _DayRow(day: days[i], isToday: false),
          ],
          const SizedBox(height: AppSpacing.xs),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _expanded ? 'Hide full week' : 'Show full week',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    this.emphasise = false,
  });

  final DayView day;
  final bool isToday;
  final bool emphasise;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              day.label,
              style: AppTextStyles.bodySmall.copyWith(
                fontWeight: emphasise || isToday
                    ? FontWeight.w600
                    : FontWeight.w400,
                color: isToday ? AppColors.primary : AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              day.summary,
              style: AppTextStyles.bodySmall.copyWith(
                color: day.closed
                    ? AppColors.textTertiary
                    : (emphasise ? AppColors.textPrimary : AppColors.textSecondary),
                fontWeight: emphasise ? FontWeight.w600 : FontWeight.w400,
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

/// Compact facility chips, icon plus label, wrapping instead of scrolling so a
/// large system font never clips them.
class FacilitiesWrap extends StatelessWidget {
  const FacilitiesWrap({super.key, required this.amenities});

  final List<String> amenities;

  static const int _maxItems = 8;

  @override
  Widget build(BuildContext context) {
    final shown = amenities
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .take(_maxItems)
        .toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final amenity in shown)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  facilityIcon(amenity),
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  amenity,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Phone / email / website / social links, each opening its native app.
class ContactCard extends StatelessWidget {
  const ContactCard({super.key, required this.restaurant, required this.onCall});

  final Restaurant restaurant;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final hasPhone =
        restaurant.phoneNumber != null && restaurant.phoneNumber!.isNotEmpty;
    final hasEmail =
        restaurant.email != null && restaurant.email!.isNotEmpty;
    final hasWebsite =
        restaurant.website != null && restaurant.website!.isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPhone)
            _ContactRow(
              icon: Icons.phone_rounded,
              label: restaurant.phoneNumber!,
              onTap: onCall,
            ),
          if (hasEmail) ...[
            if (hasPhone) const SizedBox(height: AppSpacing.sm),
            _ContactRow(
              icon: Icons.email_rounded,
              label: restaurant.email!,
              onTap: () async {
                final uri = Uri(scheme: 'mailto', path: restaurant.email);
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          ],
          if (hasWebsite) ...[
            if (hasPhone || hasEmail) const SizedBox(height: AppSpacing.sm),
            _ContactRow(
              icon: Icons.language_rounded,
              label: restaurant.website!,
              onTap: () async {
                final raw = restaurant.website!;
                final uri =
                    Uri.tryParse(raw) ?? Uri.parse('https://$raw');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              },
            ),
          ],
          if (restaurant.hasSocialMedia) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [
                if (restaurant.instagram != null)
                  _SocialLink(
                    icon: Icons.camera_alt_rounded,
                    label: 'Instagram',
                    url: 'https://instagram.com/${restaurant.instagram}',
                  ),
                if (restaurant.facebook != null)
                  _SocialLink(
                    icon: Icons.facebook_rounded,
                    label: 'Facebook',
                    url: 'https://facebook.com/${restaurant.facebook}',
                  ),
                if (restaurant.twitter != null)
                  _SocialLink(
                    icon: Icons.alternate_email_rounded,
                    label: 'Twitter',
                    url: 'https://twitter.com/${restaurant.twitter}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onTap != null)
            const Icon(
              Icons.open_in_new_rounded,
              size: 14,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}

class _SocialLink extends StatelessWidget {
  const _SocialLink({
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}

/// Responsive photo grid: up to three square tiles per row, two rows maximum,
/// with a `+N` overlay when the venue has more photos than fit.
class GalleryGrid extends StatelessWidget {
  const GalleryGrid({super.key, required this.images});

  final List<String> images;

  static const int _maxVisible = 6;

  @override
  Widget build(BuildContext context) {
    final photos = images.where((i) => i.trim().isNotEmpty).toList();
    if (photos.isEmpty) return const SizedBox.shrink();

    final maxColumns = photos.length >= 3 ? 3 : photos.length;
    final visible = photos.take(_maxVisible).toList();
    final hidden = photos.length - visible.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 320 ? 2 : maxColumns;
        final rows = (visible.length / columns).ceil();
        const gap = AppSpacing.xs;
        final tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Column(
          children: [
            for (var row = 0; row < rows; row++)
              Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : gap),
                child: Row(
                  children: [
                    for (var col = 0; col < columns; col++)
                      if (row * columns + col < visible.length) ...[
                        if (col > 0) const SizedBox(width: gap),
                        SizedBox(
                          width: tileWidth,
                          height: tileWidth,
                          child: _GalleryTile(
                            source: visible[row * columns + col],
                            index: row * columns + col,
                            images: photos,
                            overflowCount:
                                row == rows - 1 &&
                                    col == columns - 1 &&
                                    hidden > 0
                                ? hidden
                                : 0,
                          ),
                        ),
                      ] else
                        const Expanded(child: SizedBox.shrink()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.source,
    required this.index,
    required this.images,
    required this.overflowCount,
  });

  final String source;
  final int index;
  final List<String> images;
  final int overflowCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Photo ${index + 1} of ${images.length}',
      child: GestureDetector(
        onTap: () => openGalleryViewer(context, images, initialIndex: index),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: Stack(
            fit: StackFit.expand,
            children: [
              MediaImage(
                source: source,
                fallbackIcon: Icons.photo_rounded,
                cacheWidth: 360,
              ),
              if (overflowCount > 0)
                ColoredBox(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: Text(
                      '+$overflowCount',
                      style: AppTextStyles.titleMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
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

/// Opens the full-screen photo viewer at [initialIndex].
Future<void> openGalleryViewer(
  BuildContext context,
  List<String> images, {
  int initialIndex = 0,
}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GalleryViewer(images: images, initialIndex: initialIndex),
    ),
  );
}

/// Swipeable full-screen viewer with a position counter.
class GalleryViewer extends StatefulWidget {
  const GalleryViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<String> images;
  final int initialIndex;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                ),
                child: Text(
                  '${_index + 1} / ${widget.images.length}',
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, index) => SafeArea(
          child: Center(
            child: MediaImage(
              source: widget.images[index],
              fit: BoxFit.contain,
              fallbackIcon: Icons.photo_rounded,
            ),
          ),
        ),
      ),
    );
  }
}
