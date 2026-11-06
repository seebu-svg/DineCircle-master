import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/app_shell.dart';
import 'package:dine_circle/models/offer.dart';
import 'package:dine_circle/models/partner_offer.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/theme/app_colors.dart';
import 'package:dine_circle/theme/app_spacing.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:dine_circle/widgets/avatar_widget.dart';
import 'package:dine_circle/widgets/buttons.dart';
import 'package:dine_circle/widgets/common_widgets.dart';
import 'package:dine_circle/widgets/connectivity_banner.dart';
import 'package:dine_circle/widgets/deal_card.dart';
import 'package:dine_circle/widgets/dinner_card.dart';
import 'package:dine_circle/widgets/experience_card.dart';
import 'package:dine_circle/widgets/occasion_card.dart';
import 'package:dine_circle/widgets/offer_card.dart';
import 'package:dine_circle/widgets/qr_code_view.dart';
import 'package:dine_circle/widgets/restaurant_card.dart';
import 'package:dine_circle/widgets/skeleton_placeholder.dart';

import 'fake_repositories.dart';
import 'support/overflow_harness.dart';

/// Overflow audit for reusable widgets and the app shell chrome.
///
/// Screens are audited in `layout_overflow_test.dart` /
/// `layout_overflow_extended_test.dart`; this file covers the shared components
/// those screens are built from, plus the five-tab navigation bar and the
/// landscape / keyboard states.
void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  List<Override> baseOverrides() => [
    authReadyProvider.overrideWithValue(true),
    sessionControllerProvider.overrideWith(
      () => _StubSession(
        AppSession.fromProfile(fixtureHost(id: 'me', name: 'Me')),
      ),
    ),
    eventsRepositoryProvider.overrideWithValue(
      FakeEventsRepository(events: [fixtureDinner()]),
    ),
    restaurantsRepositoryProvider.overrideWithValue(
      FakeRestaurantsRepository(),
    ),
    usersRepositoryProvider.overrideWithValue(FakeUsersRepository()),
    offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
  ];

  /// Hosts a component in a page-shaped, scrollable body so it receives the
  /// same width constraints it gets inside a real screen.
  Widget page(Widget child) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.paddingScreen),
        child: child,
      ),
    );
  }

  Future<void> pumpMatrixCase(
    WidgetTester tester,
    Widget Function() build, {
    required double width,
    required double scale,
  }) async {
    applyViewport(tester, width);
    applyTextScale(tester, scale);
    await tester.pumpWidget(
      ProviderScope(
        overrides: baseOverrides(),
        child: MaterialApp(theme: AppTheme.darkTheme, home: page(build())),
      ),
    );
    await tester.pumpAndSettle();
  }

  void runWidgetMatrix(String label, Widget Function() build) {
    group('Widget — $label', () {
      for (final width in kAuditWidths) {
        for (final scale in kAuditTextScales) {
          testWidgets('${width.toInt()}px × ${scale}x', (tester) async {
            final capture = startOverflowCapture();
            await pumpMatrixCase(tester, build, width: width, scale: scale);
            capture.restore();
            expectNoOverflow(
              capture,
              '$label at ${width.toInt()}px, ${scale}x text',
            );
          });
        }
      }
    });
  }

  final dinner = fixtureDinner(
    id: 'e1',
    title: 'A Very Long Experience Title That Wraps On Narrow Screens',
  );
  final restaurant = fixtureRestaurant(id: 'r1', name: 'The Long Venue Name');
  final offer = PartnerOffer(
    id: 'o1',
    restaurant: restaurant,
    title: 'A Long Offer Title For Overflow Coverage',
    description: 'A description that is long enough to need wrapping.',
    type: OfferType.discount,
    discountPercentage: 25,
    validUntil: DateTime(2027, 1, 31),
    maxRedemptions: 100,
  );
  const appOffer = Offer(
    id: 'off1',
    name: 'Long Tasting Menu Name For Coverage',
    description: 'A description that is long enough to need wrapping.',
    restaurantId: 'r1',
    restaurantName: 'The Long Venue Name',
    city: 'Lisbon',
    pricePerGuest: 128.00,
    minGuests: 2,
  );

  // ── Shared controls ────────────────────────────────────────────────────

  runWidgetMatrix(
    'Buttons in a narrow action row',
    () => Row(
      children: [
        Expanded(
          flex: 2,
          child: PrimaryButton(
            text: 'Follow',
            icon: Icons.person_add_rounded,
            onPressed: () {},
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: SecondaryButton(
            text: 'Contact',
            icon: Icons.message_rounded,
            onPressed: () {},
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton(icon: const Icon(Icons.share_rounded), onPressed: () {}),
      ],
    ),
  );

  runWidgetMatrix(
    'Buttons with long labels',
    () => Column(
      children: [
        PrimaryButton(
          text: 'Confirm booking and continue to payment',
          icon: Icons.check_rounded,
          onPressed: () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          text: 'A secondary action with a very long label',
          icon: Icons.arrow_back_rounded,
          isFullWidth: true,
          onPressed: () {},
        ),
      ],
    ),
  );

  runWidgetMatrix(
    'Common widgets',
    () => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Upcoming experiences near you',
          actionText: 'See all',
          onAction: () {},
        ),
        const SizedBox(height: AppSpacing.sm),
        // Chips always live in a `Wrap` in the app (see the Explore filters),
        // never in a bare `Row` where they would be forced to their intrinsic
        // width.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            const RatingPill(rating: 4.8, reviewCount: 1234),
            TagChip(label: 'Seasonal menu', isSelected: true, onTap: () {}),
            TagChip(label: 'Vegetarian friendly', onTap: () {}),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        const StatTile(
          label: 'Seats booked this month',
          value: '1,284',
          icon: Icons.event_seat_rounded,
        ),
        const SizedBox(height: AppSpacing.sm),
        EmptyState(
          icon: Icons.event_busy_rounded,
          title: 'No experiences yet',
          message: 'Host a dinner and it will show up here for everyone.',
          action: PrimaryButton(text: 'Host an experience', onPressed: () {}),
        ),
      ],
    ),
  );

  runWidgetMatrix(
    'Avatar',
    () => Row(
      children: [
        AvatarWidget(initials: 'AB', size: AppSpacing.avatarXl),
        const SizedBox(width: AppSpacing.sm),
        AvatarWidget(initials: 'CD', size: AppSpacing.avatarLg),
      ],
    ),
  );

  runWidgetMatrix(
    'QR pass',
    () => QrCodeView(data: 'DINECIRCLE-E1-BOOKING-REFERENCE-0123456789'),
  );

  runWidgetMatrix('Skeleton list', () => const SkeletonList(itemCount: 3));

  // ── Cards ──────────────────────────────────────────────────────────────

  runWidgetMatrix('ExperienceCard', () => ExperienceCard(dinner: dinner));

  runWidgetMatrix('DealCard', () => DealCard(offer: appOffer));

  runWidgetMatrix(
    'DinnerCard',
    () => SizedBox(width: 280, child: DinnerCard(dinner: dinner)),
  );

  runWidgetMatrix(
    'OfferCard',
    () => SizedBox(width: 240, child: OfferCard(offer: offer)),
  );

  runWidgetMatrix(
    'RestaurantCard',
    () => SizedBox(
      width: 240,
      height: 260,
      child: RestaurantCard(restaurant: restaurant),
    ),
  );

  runWidgetMatrix(
    'OccasionCard',
    () => OccasionCard(
      item: const OccasionItem(
        title: 'Birthday dinner',
        subtitle: 'Celebrate together',
        icon: Icons.cake_rounded,
        accent: AppColors.primary,
        assetImage: 'assets/images/venue_interior.png',
      ),
    ),
  );

  // ── App shell chrome ───────────────────────────────────────────────────

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...baseOverrides(),
          connectivityProvider.overrideWith(_AlwaysOnline.new),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppShell — five-tab navigation', () {
    for (final width in kAuditWidths) {
      for (final scale in kAuditTextScales) {
        testWidgets('${width.toInt()}px × ${scale}x', (tester) async {
          applyViewport(tester, width);
          applyTextScale(tester, scale);
          final capture = startOverflowCapture();
          await pumpShell(tester);
          capture.restore();
          expectNoOverflow(
            capture,
            'AppShell at ${width.toInt()}px, ${scale}x text',
          );
          expect(find.text('Home'), findsWidgets);
          expect(find.text('Explore'), findsWidgets);
          expect(find.text('Profile'), findsWidgets);
        });
      }
    }

    for (final shortSide in const [320.0, 360.0, 430.0]) {
      testWidgets('landscape ${shortSide.toInt()}x${(shortSide * 2).toInt()}', (
        tester,
      ) async {
        applyLandscapeViewport(tester, shortSide);
        final capture = startOverflowCapture();
        await pumpShell(tester);
        capture.restore();
        expectNoOverflow(
          capture,
          'AppShell landscape at short side ${shortSide.toInt()}px',
        );
      });
    }

    for (final scale in const [1.0, 2.0]) {
      testWidgets('360px × ${scale}x with keyboard', (tester) async {
        applyViewport(tester, 360);
        applyTextScale(tester, scale);
        applyKeyboardInset(tester, 300);
        final capture = startOverflowCapture();
        await pumpShell(tester);
        capture.restore();
        expectNoOverflow(
          capture,
          'AppShell at 360px, ${scale}x text with a 300px keyboard',
        );
      });
    }
  });
}

class _AlwaysOnline extends ConnectivityNotifier {
  @override
  bool build() => true;
}

class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}
