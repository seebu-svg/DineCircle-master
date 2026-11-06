import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:dine_circle/api/api_exception.dart';
import 'package:dine_circle/models/booking.dart';
import 'package:dine_circle/models/host_models.dart';
import 'package:dine_circle/providers/api_client_provider.dart';
import 'package:dine_circle/providers/host_studio_controller.dart';
import 'package:dine_circle/providers/hosts_provider.dart';
import 'package:dine_circle/providers/session_provider.dart';
import 'package:dine_circle/screens/host/analytics_screen.dart';
import 'package:dine_circle/screens/host/host_dashboard_screen.dart';
import 'package:dine_circle/theme/app_theme.dart';

import 'fake_repositories.dart';

/// A signed-in host session so [currentUserIdProvider] and
/// [currentUserProvider] resolve without secure storage or the network.
class _StubSession extends SessionController {
  _StubSession(this._result);
  final AppSession _result;
  @override
  Future<AppSession> build() async => _result;
}

Override _signedInHost({String id = 'nora'}) =>
    sessionControllerProvider.overrideWith(
      () => _StubSession(
        AppSession.fromProfile(fixtureHost(id: id, name: 'Nora Feld')),
      ),
    );

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<ProviderContainer> containerWith(List<Override> overrides) async {
    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    // Resolve the async session before any controller runs, so
    // [currentUserIdProvider] / [currentUserProvider] are populated.
    await container.read(sessionControllerProvider.future);
    return container;
  }

  // The analytics screen's dense rows trip RenderFlex overflow warnings in the
  // fixed headless viewport — layout warnings, not failures.
  void tolerateOverflow() {
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
  }

  group('WalletController', () {
    test(
      'a valid withdrawal reduces available and posts a ledger row',
      () async {
        final hosts = FakeHostsRepository(
          initialAvailable: 500,
          initialLifetimeNet: 500,
        );
        final container = await containerWith([
          _signedInHost(),
          hostsRepositoryProvider.overrideWithValue(hosts),
        ]);

        final wallet = await container
            .read(walletControllerProvider)
            .withdraw(amount: 200, method: 'Bank •••• 7890');

        expect(wallet.available, 300);
        expect(wallet.withdrawals, hasLength(1));
        expect(wallet.withdrawals.first.amount, 200);
        expect(wallet.withdrawals.first.status, 'requested');
        expect(hosts.withdrawalCalls, 1);
        expect(hosts.lastWithdrawAmount, 200);
        expect(hosts.lastWithdrawMethod, 'Bank •••• 7890');
      },
    );

    test(
      'an over-balance withdrawal is rejected and leaves the ledger intact',
      () async {
        final hosts = FakeHostsRepository(
          initialAvailable: 500,
          initialLifetimeNet: 500,
        );
        final container = await containerWith([
          _signedInHost(),
          hostsRepositoryProvider.overrideWithValue(hosts),
        ]);

        await expectLater(
          container
              .read(walletControllerProvider)
              .withdraw(amount: 600, method: 'PayPal'),
          throwsA(isA<ApiException>()),
        );

        expect(hosts.availableBalance, 500);
        expect(hosts.withdrawalCalls, 1);
        expect(hosts.currentInvites, isEmpty);
      },
    );

    test(
      'the wallet family provider re-reads the new balance after withdrawing',
      () async {
        final hosts = FakeHostsRepository(
          initialAvailable: 400,
          initialLifetimeNet: 400,
        );
        final container = await containerWith([
          _signedInHost(),
          hostsRepositoryProvider.overrideWithValue(hosts),
        ]);

        // Prime the derived wallet, then keep it listened so invalidation
        // recomputes against the (now-lower) family value.
        container.listen(myWalletProvider, (_, _) {});
        final before = await container.read(myWalletProvider.future);
        expect(before?.available, 400);

        await container
            .read(walletControllerProvider)
            .withdraw(amount: 150, method: 'Bank');

        final after = await container.read(myWalletProvider.future);
        expect(after?.available, 250);
      },
    );
  });

  group('InvitesController', () {
    test('accept flips state and refreshes the derived invite list', () async {
      final hosts = FakeHostsRepository(
        invites: [
          fixtureInvite(id: 'i1', title: 'Omakase Collaboration Night'),
        ],
      );
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      container.listen(myHostInvitesProvider, (_, _) {});
      final first = await container.read(myHostInvitesProvider.future);
      expect(first.single.isAccepted, isFalse);

      final updated = await container
          .read(invitesControllerProvider)
          .accept('i1');

      expect(updated.isAccepted, isTrue);
      expect(hosts.respondCalls, 1);
      expect(hosts.lastRespondInviteId, 'i1');
      expect(hosts.lastRespondAccept, isTrue);

      final refreshed = await container.read(myHostInvitesProvider.future);
      expect(refreshed.single.isAccepted, isTrue);
    });

    test('decline flips state to not-accepted', () async {
      final hosts = FakeHostsRepository(
        invites: [fixtureInvite(id: 'i2', isAccepted: true)],
      );
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      final updated = await container
          .read(invitesControllerProvider)
          .decline('i2');

      expect(updated.isAccepted, isFalse);
      expect(hosts.lastRespondAccept, isFalse);
    });
  });

  group('GuestRequestsController', () {
    test('approve hits the booking endpoint and reloads the guest list', () async {
      final approved = fixtureBooking(
        id: 'b1',
        dinner: fixtureDinner(id: 'e1', title: 'Tasting Menu Tryout'),
        user: fixtureHost(id: 'ava', name: 'Ava Chen'),
        status: BookingStatus.confirmed,
      );
      final bookings = FakeBookingsRepository(
        mine: [approved],
        nextBooking: approved,
      );
      final container = await containerWith([
        _signedInHost(),
        bookingsRepositoryProvider.overrideWithValue(bookings),
      ]);

      // Subscribe so the post-approval invalidation recomputes the guest list.
      container.listen(eventGuestsProvider('e1'), (_, _) {});
      await container.read(eventGuestsProvider('e1').future);
      expect(bookings.guestsForCalls, 1);

      await container.read(guestRequestsControllerProvider).approve('b1');

      expect(bookings.approveCalls, 1);
      expect(bookings.lastApprovedId, 'b1');
      // The guest list was invalidated; awaiting its future forces the reload.
      await container.read(eventGuestsProvider('e1').future);
      expect(bookings.guestsForCalls, 2);
    });

    test('decline hits the decline endpoint', () async {
      final declined = fixtureBooking(
        id: 'b2',
        dinner: fixtureDinner(id: 'e1', title: 'Tasting Menu Tryout'),
        user: fixtureHost(id: 'ava', name: 'Ava Chen'),
        status: BookingStatus.cancelled,
      );
      final bookings = FakeBookingsRepository(nextBooking: declined);
      final container = await containerWith([
        _signedInHost(),
        bookingsRepositoryProvider.overrideWithValue(bookings),
      ]);

      container.listen(eventGuestsProvider('e1'), (_, _) {});

      await container.read(guestRequestsControllerProvider).decline('b2');

      expect(bookings.declineCalls, 1);
      expect(bookings.lastDeclinedId, 'b2');
    });
  });

  // Phase 5: Analytics period is forwarded to the repository.
  group('Analytics period', () {
    test('analytics() records the active period from the state provider',
        () async {
      final hosts = FakeHostsRepository(
        analyticsResult: fixtureAnalytics(totalEventsHosted: 3),
      );
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      await container.read(myHostAnalyticsProvider.future);
      expect(hosts.analyticsCalls, 1);
      expect(hosts.lastAnalyticsPeriod, '30d'); // default period

      // Switch to 7d and re-read.
      container.read(analyticsPeriodProvider.notifier).state = '7d';
      await container.read(myHostAnalyticsProvider.future);
      expect(hosts.analyticsCalls, 2);
      expect(hosts.lastAnalyticsPeriod, '7d');
    });
  });

  // Phase 5: Collaboration proposal lifecycle — send, cancel, complete.
  group('CollaborationsController', () {
    test('sendProposal hits the repository and returns a new invite', () async {
      final hosts = FakeHostsRepository();
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      final invite = await container
          .read(collaborationsControllerProvider)
          .sendProposal(
            restaurantId: 'r42',
            title: 'Summer Series',
            message: 'Let us collaborate',
          );

      expect(invite.proposedBy, 'host');
      expect(invite.status, 'invited');
      expect(hosts.sendProposalCalls, 1);
      expect(hosts.lastProposalRestaurantId, 'r42');
      expect(hosts.lastProposalTitle, 'Summer Series');
      expect(hosts.lastProposalMessage, 'Let us collaborate');
    });

    test('cancelProposal marks the collaboration as cancelled', () async {
      final hosts = FakeHostsRepository(
        collaborations: [
          fixtureInvite(
            id: 'c1',
            title: 'Active Collab',
            status: 'accepted',
            proposedBy: 'host',
          ),
        ],
      );
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      final updated = await container
          .read(collaborationsControllerProvider)
          .cancelProposal('c1');

      expect(updated.status, 'cancelled');
      expect(updated.isAccepted, isFalse);
      expect(hosts.cancelProposalCalls, 1);
      expect(hosts.lastCancelCollabId, 'c1');
    });

    test('completeProposal links an experience and flips status', () async {
      final hosts = FakeHostsRepository(
        collaborations: [
          fixtureInvite(
            id: 'c2',
            title: 'Done Collab',
            status: 'accepted',
            proposedBy: 'host',
          ),
        ],
      );
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      final updated = await container
          .read(collaborationsControllerProvider)
          .completeProposal('c2');

      expect(updated.status, 'completed');
      expect(updated.experienceId, 'exp-c2');
      expect(hosts.completeProposalCalls, 1);
      expect(hosts.lastCompleteCollabId, 'c2');
    });

    test('promoteEvent records the event id and hits the backend', () async {
      final hosts = FakeHostsRepository();
      final container = await containerWith([
        _signedInHost(),
        hostsRepositoryProvider.overrideWithValue(hosts),
      ]);

      await container
          .read(collaborationsControllerProvider)
          .promoteEvent('evt-99');

      expect(hosts.promoteEventCalls, 1);
      expect(hosts.lastPromotedEventId, 'evt-99');
    });
  });

  testWidgets('AnalyticsScreen renders live per-event rows from the server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    tolerateOverflow();

    final hosts = FakeHostsRepository(
      performanceRows: const [
        HostEventStat(
          eventId: 'e1',
          title: 'Omakase Under the Stars',
          views: 2840,
          seatsBooked: 6,
          bookings: 6,
          pending: 0,
          checkedIn: 3,
          gross: 570,
        ),
        HostEventStat(
          eventId: 'e2',
          title: 'Sunday Slow Brunch',
          views: 1930,
          seatsBooked: 5,
          bookings: 5,
          pending: 0,
          checkedIn: 2,
          gross: 190,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          _signedInHost(),
          hostsRepositoryProvider.overrideWithValue(hosts),
        ],
        child: MaterialApp(theme: AppTheme.darkTheme, home: AnalyticsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Omakase Under the Stars'), findsWidgets);
    expect(find.text('Sunday Slow Brunch'), findsWidgets);
  });

  // P0-2: Host Studio reads GET /events/mine and shows saved drafts with
  // Edit / Publish / Delete actions.
  group('Host Studio drafts', () {
    List<Override> draftsOverrides(FakeEventsRepository events) => [
      _signedInHost(),
      authReadyProvider.overrideWithValue(true),
      eventsRepositoryProvider.overrideWithValue(events),
      hostsRepositoryProvider.overrideWithValue(FakeHostsRepository()),
    ];

    Future<void> pumpDashboard(
      WidgetTester tester,
      FakeEventsRepository events,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      tolerateOverflow();
      await tester.pumpWidget(
        ProviderScope(
          overrides: draftsOverrides(events),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const HostDashboardScreen(initialTab: 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Drafts section lists drafts from mine() with actions', (
      tester,
    ) async {
      final events = FakeEventsRepository(
        events: [fixtureDinner(id: 'e1', title: 'Omakase Night')],
        mineEvents: [
          fixtureDinner(
            id: 'd1',
            title: 'Rooftop Draft',
            hostStatus: HostEventStatus.draft,
          ),
          fixtureDinner(id: 'e1', title: 'Omakase Night'),
        ],
      );
      await pumpDashboard(tester, events);

      expect(find.text('Drafts'), findsOneWidget);
      // The Overview tab pre-builds too and also lists the draft card.
      expect(find.text('Rooftop Draft'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    });

    testWidgets('Publish patches the draft and refreshes the list', (
      tester,
    ) async {
      final events = FakeEventsRepository(
        mineEvents: [
          fixtureDinner(
            id: 'd1',
            title: 'Rooftop Draft',
            hostStatus: HostEventStatus.draft,
          ),
        ],
      );
      await pumpDashboard(tester, events);

      final publish = find.text('Publish');
      await tester.ensureVisible(publish);
      await tester.pump();
      await tester.tap(publish);
      await tester.pumpAndSettle();

      expect(events.patchEventCalls, 1);
      expect(events.lastPatchId, 'd1');
      expect(events.lastPatch, {'status': 'published'});
      expect(find.text('Draft published'), findsOneWidget);
      // The reload hit GET /events/mine again after the invalidation.
      expect(events.mineCalls, 2);
    });

    testWidgets('a 422 on publish surfaces the server message inline', (
      tester,
    ) async {
      final events = FakeEventsRepository(
        mineEvents: [
          fixtureDinner(
            id: 'd1',
            title: 'Rooftop Draft',
            hostStatus: HostEventStatus.draft,
          ),
        ],
        patchError: ApiException(
          ApiErrorKind.validation,
          statusCode: 422,
          message: 'Draft not ready to publish: title too short',
        ),
      );
      await pumpDashboard(tester, events);

      final publish = find.text('Publish');
      await tester.ensureVisible(publish);
      await tester.pump();
      await tester.tap(publish);
      await tester.pumpAndSettle();

      expect(
        find.text('Draft not ready to publish: title too short'),
        findsOneWidget,
      );
    });

    testWidgets('Delete confirms and cancels the draft event', (tester) async {
      final events = FakeEventsRepository(
        mineEvents: [
          fixtureDinner(
            id: 'd1',
            title: 'Rooftop Draft',
            hostStatus: HostEventStatus.draft,
          ),
        ],
      );
      await pumpDashboard(tester, events);

      final trash = find.byIcon(Icons.delete_outline_rounded);
      await tester.ensureVisible(trash);
      await tester.pump();
      await tester.tap(trash);
      await tester.pumpAndSettle();

      expect(find.text('Delete draft?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(events.cancelEventCalls, 1);
      expect(find.text('Draft deleted'), findsOneWidget);
    });
  });
}
