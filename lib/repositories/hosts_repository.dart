import '../api/api_client.dart';
import '../api/mappers/mappers.dart';
import '../api/json.dart';
import '../models/host_models.dart';

/// Host-studio analytics, wallet and invitations backed by the server
/// (`/hosts/:id/*`).
///
/// The server authorizes these per host: only the host themselves (or a
/// partner/super admin) can read another host's numbers, so a 403 here means a
/// viewer asked for someone else's dashboard. Money is a server-side simulated
/// ledger, a withdrawal is a recorded row that reduces [Wallet.available].
abstract class HostsRepository {
  Future<HostSummary> summary(String hostId);
  Future<List<HostPayout>> payouts(String hostId);
  Future<List<HostTrendPoint>> trend(String hostId);
  Future<List<HostEventStat>> performance(String hostId);
  Future<List<HostPartner>> partners(String hostId);
  Future<List<CollaborationInvite>> invites(String hostId);
  Future<CollaborationInvite> respondToInvite(
    String hostId,
    String inviteId,
    bool accept, {
    String? reason,
  });
  Future<Wallet> wallet(String hostId);
  Future<Wallet> requestWithdrawal({
    required String hostId,
    required double amount,
    required String method,
  });

  // ── Phase 2: Analytics ───────────────────────────────────────────────────
  Future<HostAnalytics> analytics(String hostId, {String period = 'all'});

  // ── Phase 3: Collaborations ──────────────────────────────────────────────
  Future<List<CollaborationInvite>> collaborations(String hostId);
  Future<CollaborationInvite> sendProposal({
    required String hostId,
    required String restaurantId,
    required String title,
    required String message,
    String? experienceId,
  });
  Future<CollaborationInvite> cancelProposal({
    required String hostId,
    required String collabId,
  });
  Future<CollaborationInvite> completeProposal({
    required String hostId,
    required String collabId,
    String? experienceId,
  });

  // ── Phase 3: Discovery & Promote ─────────────────────────────────────────
  Future<List<DiscoverablePartner>> discoverPartners(String hostId);
  Future<({List<PromotableEvent> events, int followerCount})> promotableEvents(
    String hostId,
  );
  Future<void> promoteEvent(String hostId, String eventId);
}

class ApiHostsRepository implements HostsRepository {
  ApiHostsRepository(this._client);

  final ApiClient _client;

  @override
  Future<HostSummary> summary(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/summary');
    final json = asMap(body);
    return HostSummary(
      earned: asDouble(json['earned']),
      inTransit: asDouble(json['inTransit']),
      scheduled: asDouble(json['scheduled']),
      netTotal: asDouble(json['netTotal']),
      lifetimeGross: asDouble(json['lifetimeGross']),
      commissionTotal: asDouble(json['commissionTotal']),
      seatsSold: asInt(json['seatsSold']),
      seatsReserved: asInt(json['seatsReserved']),
      averageSeatPrice: asDouble(json['averageSeatPrice']),
      hostedCount: asInt(json['hostedCount']),
      upcomingCount: asInt(json['upcomingCount']),
      averageFillRate: asDouble(json['averageFillRate']),
      averageRating: asDouble(json['averageRating']),
      reviewCount: asInt(json['reviewCount']),
      nextPayoutDate: asDateOrNull(json['nextPayoutDate']),
      platformCommissionRate: asDouble(json['platformCommissionRate'], 0.10),
      available: asDouble(json['available']),
    );
  }

  @override
  Future<List<HostPayout>> payouts(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/payouts');
    return asMapList(asMap(body)['payouts']).map((p) {
      final gross = asDouble(p['gross']);
      final commission = asDouble(p['commission']);
      return HostPayout(
        id: asString(p['id']),
        amount: asDouble(p['net'], gross - commission),
        method: 'Bank transfer',
        status: asString(p['status'], 'pending'),
        date: asDateOrNull(p['date']) ?? DateTime.now(),
        period: asString(p['eventTitle']),
      );
    }).toList();
  }

  @override
  Future<List<HostTrendPoint>> trend(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/trend');
    return asMapList(asMap(body)['trend'])
        .map(
          (t) => HostTrendPoint(
            label: asString(t['label']),
            seats: asInt(t['seats']),
            revenue: asDouble(t['revenue']),
          ),
        )
        .toList();
  }

  @override
  Future<List<HostEventStat>> performance(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/performance');
    return asMapList(asMap(body)['performance'])
        .map(
          (r) => HostEventStat(
            eventId: asString(r['eventId']),
            title: asString(r['title']),
            coverImage: asStringOrNull(r['coverImage']),
            views: asInt(r['views']),
            seatsBooked: asInt(r['seatsBooked']),
            bookings: asInt(r['bookings']),
            pending: asInt(r['pending']),
            checkedIn: asInt(r['checkedIn']),
          ),
        )
        .toList();
  }

  @override
  Future<List<HostPartner>> partners(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/partners');
    return asMapList(asMap(body)['partners'])
        .map(
          (p) => HostPartner(
            venue: Mappers.slimRestaurant(
              id: asString(p['id']),
              name: asString(p['name']),
              coverImage: asStringOrNull(p['coverImage']),
              neighborhood: asStringOrNull(p['neighborhood']),
            ),
            eventsTogether: asInt(p['eventsTogether']),
          ),
        )
        .toList();
  }

  @override
  Future<List<CollaborationInvite>> invites(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/invites');
    return asMapList(asMap(body)['invites']).map(_inviteFromDto).toList();
  }

  @override
  Future<CollaborationInvite> respondToInvite(
    String hostId,
    String inviteId,
    bool accept, {
    String? reason,
  }) async {
    final verb = accept ? 'accept' : 'decline';
    // A decline without a reason leaves the host guessing what to fix; the
    // server caps it at 500 characters and stores it verbatim.
    final note = reason?.trim();
    final body = await _client.postJson(
      '/hosts/$hostId/invites/$inviteId/$verb',
      body: {'reason': ?(note == null || note.isEmpty ? null : note)},
    );
    return _inviteFromDto(asMap(asMap(body)['invite']));
  }

  CollaborationInvite _inviteFromDto(Map<String, dynamic> row) {
    final restaurant = asMap(row['restaurant']);
    // `experience` is null on every host-authored proposal, so an empty map
    // means "nothing linked" rather than a payload that failed to parse.
    final experienceRow = asMap(row['experience']);
    final status = asString(row['status'], 'invited');
    return CollaborationInvite(
      id: asString(row['id']),
      restaurant: Mappers.slimRestaurant(
        id: asString(restaurant['id']),
        name: asString(restaurant['name']),
        coverImage: asStringOrNull(restaurant['coverImage']),
        neighborhood: asStringOrNull(restaurant['neighborhood']),
      ),
      title: asString(row['title']),
      message: asString(row['message']),
      receivedAt: asDateOrNull(row['receivedAt']) ?? DateTime.now(),
      isAccepted: status == 'accepted',
      status: status,
      proposedBy: asString(row['proposedBy'], 'restaurant'),
      experienceId: asStringOrNull(row['experienceId']),
      respondedAt: asDateOrNull(row['respondedAt']),
      declineReason: asString(row['declineReason']),
      experience: experienceRow.isEmpty
          ? null
          : LinkedExperience(
              id: asString(experienceRow['id']),
              title: asString(experienceRow['title']),
              coverImage: asStringOrNull(experienceRow['coverImage']),
              startAt: asDateOrNull(experienceRow['startAt']),
              status: asString(experienceRow['status'], 'draft'),
            ),
      restaurantRating: asDouble(restaurant['rating']),
      restaurantCuisines: asStringList(restaurant['cuisines']),
    );
  }

  @override
  Future<Wallet> wallet(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/wallet');
    return _walletFromDto(asMap(body));
  }

  @override
  Future<Wallet> requestWithdrawal({
    required String hostId,
    required double amount,
    required String method,
  }) async {
    await _client.postJson(
      '/hosts/$hostId/withdrawals',
      body: {'amount': amount, 'method': method},
    );
    // Re-read so the returned balances match the ledger's authoritative state.
    return wallet(hostId);
  }

  Wallet _walletFromDto(Map<String, dynamic> json) => Wallet(
    available: asDouble(json['available']),
    lifetimeNet: asDouble(json['lifetimeNet']),
    pendingWithdrawals: asDouble(json['pendingWithdrawals']),
    withdrawals: asMapList(json['withdrawals'])
        .map(
          (w) => Withdrawal(
            id: asString(w['id']),
            amount: asDouble(w['amount']),
            method: asString(w['method']),
            status: asString(w['status'], 'requested'),
            date: asDateOrNull(w['date']) ?? DateTime.now(),
          ),
        )
        .toList(),
  );

  // ── Phase 2: Analytics ───────────────────────────────────────────────────

  @override
  Future<HostAnalytics> analytics(String hostId, {String period = 'all'}) async {
    final body = await _client.getJson('/hosts/$hostId/analytics?period=$period');
    final json = asMap(body);
    final a = asMap(json['analytics']);
    return HostAnalytics(
      totalEventsHosted: asInt(a['totalEventsHosted']),
      totalBookings: asInt(a['totalBookings']),
      totalSeatsReserved: asInt(a['totalSeatsReserved']),
      grossRevenue: asDouble(a['grossRevenue']),
      hostNetEarnings: asDouble(a['hostNetEarnings']),
      seatsSold: asInt(a['seatsSold']),
      averageSeatFillRate: asDouble(a['averageSeatFillRate']),
      averageRating: asDouble(a['averageRating']),
      reviewCount: asInt(a['reviewCount']),
      upcomingCount: asInt(a['upcomingCount']),
      completedCount: asInt(a['completedCount']),
      totalViews: asInt(a['totalViews']),
      conversionRate: asDouble(a['conversionRate']),
      topPerformingEvents: asMapList(json['topPerformingEvents'])
          .map(_eventStatFromDto)
          .toList(),
      trend: asMapList(json['trend'])
          .map(
            (t) => HostTrendPoint(
              label: asString(t['label']),
              seats: asInt(t['seats']),
              revenue: asDouble(t['revenue']),
            ),
          )
          .toList(),
      performance: asMapList(json['performance'])
          .map(_eventStatFromDto)
          .toList(),
    );
  }

  HostEventStat _eventStatFromDto(Map<String, dynamic> r) => HostEventStat(
    eventId: asString(r['eventId']),
    title: asString(r['title']),
    coverImage: asStringOrNull(r['coverImage']),
    views: asInt(r['views']),
    seatsBooked: asInt(r['seatsBooked']),
    bookings: asInt(r['bookings']),
    pending: asInt(r['pending']),
    checkedIn: asInt(r['checkedIn']),
  );

  // ── Phase 3: Collaborations ──────────────────────────────────────────────

  @override
  Future<List<CollaborationInvite>> collaborations(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/collabs');
    return asMapList(asMap(body)['collaborations'])
        .map(_inviteFromDto)
        .toList();
  }

  @override
  Future<CollaborationInvite> sendProposal({
    required String hostId,
    required String restaurantId,
    required String title,
    required String message,
    String? experienceId,
  }) async {
    final body = await _client.postJson(
      '/hosts/$hostId/collabs/propose',
      body: {
        'restaurantId': restaurantId,
        'title': title,
        'message': message,
        // A host can propose on top of an experience they already drafted, so
        // the venue approves a concrete dinner rather than a blank promise.
        'experienceId': ?experienceId,
      },
    );
    return _inviteFromDto(asMap(asMap(body)['collaboration']));
  }

  @override
  Future<CollaborationInvite> cancelProposal({
    required String hostId,
    required String collabId,
  }) async {
    final body = await _client.postJson(
      '/hosts/$hostId/collabs/$collabId/cancel',
    );
    return _inviteFromDto(asMap(asMap(body)['collaboration']));
  }

  @override
  Future<CollaborationInvite> completeProposal({
    required String hostId,
    required String collabId,
    String? experienceId,
  }) async {
    final body = await _client.postJson(
      '/hosts/$hostId/collabs/$collabId/complete',
      // The experience built together, if the host names it here; otherwise the
      // server keeps whatever was already linked.
      body: {'experienceId': ?experienceId},
    );
    return _inviteFromDto(asMap(asMap(body)['collaboration']));
  }

  // ── Phase 3: Discovery & Promote ─────────────────────────────────────────

  @override
  Future<List<DiscoverablePartner>> discoverPartners(String hostId) async {
    final body = await _client.getJson('/hosts/$hostId/discover-partners');
    return asMapList(asMap(body)['partners'])
        .map(
          (p) => DiscoverablePartner(
            id: asString(p['id']),
            name: asString(p['name']),
            coverImage: asStringOrNull(p['coverImage']),
            neighborhood: asString(p['neighborhood']),
            city: asString(p['city']),
            rating: asDouble(p['rating']),
            reviewCount: asInt(p['reviewCount']),
            cuisines: asStringList(p['cuisines']),
          ),
        )
        .toList();
  }

  @override
  Future<({List<PromotableEvent> events, int followerCount})> promotableEvents(
    String hostId,
  ) async {
    final body = await _client.getJson('/hosts/$hostId/promotable-events');
    final json = asMap(body);
    final events = asMapList(json['events'])
        .map(
          (e) => PromotableEvent(
            id: asString(e['id']),
            title: asString(e['title']),
            coverImage: asStringOrNull(e['coverImage']),
            startAt: asDateOrNull(e['startAt']) ?? DateTime.now(),
            seatsTotal: asInt(e['seatsTotal']),
            seatsBooked: asInt(e['seatsBooked']),
            seatsLeft: asInt(e['seatsLeft']),
            pricePerSeat: asDouble(e['pricePerSeat']),
            restaurantName: asString(e['restaurantName']),
          ),
        )
        .toList();
    return (events: events, followerCount: asInt(json['followerCount']));
  }

  @override
  Future<void> promoteEvent(String hostId, String eventId) async {
    await _client.postJson('/hosts/events/$eventId/promote');
  }
}
