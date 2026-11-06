import 'package:dine_circle/models/public_menu.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/repositories/public_menu_repository.dart';
import 'package:dine_circle/screens/qr_menu/qr_menu_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/overflow_harness.dart';

/// Menu fixture mirroring what `GET /api/public/menu/:restaurantId` returns for
/// a seeded Karachi venue: asset-path photos, integer PKR prices, a mix of
/// tagged and untagged dishes, and one dish with no photo at all.
PublicMenu _menu({List<PublicMenuSection>? sections}) {
  return PublicMenu(
    restaurant: const PublicMenuRestaurant(
      id: 'r1',
      name: 'Kolachi Restaurant',
      city: 'Karachi',
      neighborhood: 'Do Darya',
      coverImage: 'assets/images/venue_rooftop.png',
      openingHours: {
        'mon': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'tue': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'wed': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'thu': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'fri': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'sat': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
        'sun': {
          'windows': [
            {'open': '00:00', 'close': '24:00'},
          ],
        },
      },
    ),
    sections: sections ??
        const [
          PublicMenuSection(
            id: 's1',
            name: 'From the Grill',
            items: [
              PublicMenuItem(
                id: 'i1',
                name: 'Grilled Prawns',
                description: 'Jumbo prawns, lemon butter and green chutney.',
                price: 2450,
                dietaryTags: ['seafood'],
                photoUrl: 'assets/images/dish_steak.png',
              ),
              PublicMenuItem(
                id: 'i2',
                name: 'Chicken Malai Boti',
                description: 'Cream-marinated boneless chicken, charcoal grilled.',
                price: 1290,
              ),
            ],
          ),
          PublicMenuSection(
            id: 's2',
            name: 'Rice & Breads',
            items: [
              PublicMenuItem(
                id: 'i3',
                name: 'Garlic Naan',
                description: 'Tandoor naan brushed with garlic butter.',
                price: 220,
                dietaryTags: ['vegetarian'],
                photoUrl: 'assets/images/dish_pasta.png',
              ),
            ],
          ),
        ],
  );
}

class _FakePublicMenuRepository implements PublicMenuRepository {
  _FakePublicMenuRepository({this.menu});

  final PublicMenu? menu;
  int scanCalls = 0;

  @override
  Future<PublicMenu> fetch(String restaurantId) async => menu ?? _menu();

  @override
  Future<void> recordScan(String restaurantId) async {
    scanCalls += 1;
  }
}

void main() {
  Widget app(PublicMenuRepository repo) {
    return ProviderScope(
      overrides: [publicMenuRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: const QrMenuScreen(restaurantId: 'r1'),
      ),
    );
  }

  group('QrMenuScreen', () {
    testWidgets('renders venue, location and section headings', (tester) async {
      applyViewport(tester, 360, logicalHeight: 900);
      final capture = startOverflowCapture();

      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Kolachi Restaurant'), findsWidgets);
      expect(find.text('Do Darya · Karachi'), findsOneWidget);
      expect(find.text('From the Grill'), findsWidgets);
      expect(find.text('Rice & Breads'), findsWidgets);
      expectNoOverflow(capture, 'menu shelf');
    });

    testWidgets('renders dish names and grouped PKR prices', (tester) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Grilled Prawns'), findsOneWidget);
      expect(find.text('Rs 2,450'), findsOneWidget);
      expect(find.text('Rs 220'), findsOneWidget);
    });

    testWidgets('shows the compact open status for a 24h venue', (
      tester,
    ) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Open now'), findsOneWidget);
    });

    testWidgets('omits the status pill when the venue published no hours', (
      tester,
    ) async {
      applyViewport(tester, 360, logicalHeight: 900);
      final repo = _FakePublicMenuRepository(
        menu: PublicMenu(
          restaurant: const PublicMenuRestaurant(
            id: 'r1',
            name: 'No Hours Cafe',
            city: 'Karachi',
          ),
          sections: _menu().sections,
        ),
      );

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      expect(find.text('Open now'), findsNothing);
      expect(find.text('Closed'), findsNothing);
    });

    testWidgets('search narrows the list and hides empty sections', (
      tester,
    ) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'prawns');
      await tester.pumpAndSettle();

      expect(find.text('Grilled Prawns'), findsOneWidget);
      expect(find.text('Chicken Malai Boti'), findsNothing);
      // The only rice/bread dish does not match, so its section disappears.
      expect(find.text('Garlic Naan'), findsNothing);
    });

    testWidgets('dietary filter narrows items and can be cleared', (
      tester,
    ) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      // Filter chips are the tappable dietary badges in the filter row, which
      // sits above the dish cards and therefore matches first.
      await tester.tap(find.text('VEG').first);
      await tester.pumpAndSettle();

      expect(find.text('Garlic Naan'), findsOneWidget);
      expect(find.text('Grilled Prawns'), findsNothing);

      await tester.tap(find.text('VEG').first);
      await tester.pumpAndSettle();

      expect(find.text('Grilled Prawns'), findsOneWidget);
    });

    testWidgets('unmatched query shows the no-results state', (tester) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('No dishes match your filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();

      expect(find.text('Grilled Prawns'), findsOneWidget);
    });

    testWidgets('tapping a dish opens the detail sheet', (tester) async {
      applyViewport(tester, 360, logicalHeight: 900);
      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Grilled Prawns'));
      await tester.pumpAndSettle();

      expect(find.text('FROM THE GRILL'), findsOneWidget);
      expect(
        find.text('Jumbo prawns, lemon butter and green chutney.'),
        findsWidgets,
      );
      expect(find.text('Rs 2,450'), findsWidgets);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();

      expect(find.text('FROM THE GRILL'), findsNothing);
      expect(find.text('Grilled Prawns'), findsOneWidget);
    });

    testWidgets('a menu whose sections are all empty shows the empty state', (
      tester,
    ) async {
      applyViewport(tester, 360, logicalHeight: 900);
      final repo = _FakePublicMenuRepository(
        menu: PublicMenu(
          restaurant: const PublicMenuRestaurant(id: 'r1', name: 'Empty Venue'),
          sections: const [
            // Every dish in this section is unavailable server-side, so the
            // route returns the section with no items.
            PublicMenuSection(id: 's1', name: 'Mains'),
          ],
        ),
      );

      await tester.pumpWidget(app(repo));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('No menu items available right now'),
        findsOneWidget,
      );
      expect(find.text('Menu'), findsOneWidget);
    });

    testWidgets('survives an accessibility text scale without overflow', (
      tester,
    ) async {
      applyViewport(tester, 320, logicalHeight: 640);
      applyTextScale(tester, 1.3);
      final capture = startOverflowCapture();

      await tester.pumpWidget(app(_FakePublicMenuRepository()));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
      await tester.pumpAndSettle();

      expectNoOverflow(capture, 'menu at 320x640 @1.3x');
    });
  });
}
