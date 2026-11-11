import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/host_models.dart';
import 'api_client_provider.dart';
import 'hosts_provider.dart';
import 'session_provider.dart';
import 'users_provider.dart';

/// Write actions for the host's collaboration invitations.
///
/// [accept]/[decline] hit `POST /hosts/:id/invites/:inviteId/{accept,decline}`
/// and, on success, invalidate [hostInvitesProvider] for this host so the
/// derived [myHostInvitesProvider] re-reads the server's authoritative status.
/// Any [ApiException] is surfaced by the caller.
class InvitesController {
  InvitesController(this._ref);

  final Ref _ref;

  Future<CollaborationInvite> _respond(
    String inviteId,
    bool accept, {
    String? reason,
  }) async {
    final hostId = _ref.read(currentUserIdProvider);
    if (hostId == null) {
      throw StateError('Sign in to respond to invitations.');
    }
    final invite = await _ref
        .read(hostsRepositoryProvider)
        .respondToInvite(hostId, inviteId, accept, reason: reason);
    // Invalidate the family provider itself, invalidating only the derived
    // [myHostInvitesProvider] would rebuild it against a still-cached family
    // value and never re-read the server.
    _ref.invalidate(hostInvitesProvider(hostId));
    return invite;
  }

  Future<CollaborationInvite> accept(String inviteId) =>
      _respond(inviteId, true);

  /// Declining with a [reason] is what makes the host's "why was this turned
  /// down?" answerable — the server stores it verbatim and the outbox shows it.
  Future<CollaborationInvite> decline(String inviteId, {String? reason}) =>
      _respond(inviteId, false, reason: reason);
}

final invitesControllerProvider = Provider<InvitesController>(
  (ref) => InvitesController(ref),
);

/// Withdrawals against the host's simulated wallet ledger.
///
/// [withdraw] records a `requested` row via `POST /hosts/:id/withdrawals`, then
/// refreshes both [myWalletProvider] and [myHostSummaryProvider] (the summary's
/// `available` feeds the withdraw sheet). The server rejects an over-balance
/// request with a validation [ApiException].
class WalletController {
  WalletController(this._ref);

  final Ref _ref;

  Future<Wallet> withdraw({
    required double amount,
    required String method,
  }) async {
    final hostId = _ref.read(currentUserIdProvider);
    if (hostId == null) {
      throw StateError('Sign in to withdraw earnings.');
    }
    final wallet = await _ref
        .read(hostsRepositoryProvider)
        .requestWithdrawal(hostId: hostId, amount: amount, method: method);
    // Refresh the family providers so the derived [myWalletProvider] and
    // [myHostSummaryProvider] (whose `available` feeds the withdraw sheet)
    // re-read the ledger's new balances rather than a cached value.
    _ref.invalidate(hostWalletProvider(hostId));
    _ref.invalidate(hostSummaryProvider(hostId));
    return wallet;
  }
}

final walletControllerProvider = Provider<WalletController>(
  (ref) => WalletController(ref),
);

/// Approve / decline guest seat requests on a host-gated event.
///
/// Both actions post to the booking endpoints and then reload the affected
/// event's guest list via [eventGuestsProvider], so the host sees the real
/// confirmed / released state rather than a local illusion.
class GuestRequestsController {
  GuestRequestsController(this._ref);

  final Ref _ref;

  Future<void> _run(String bookingId, bool approve) async {
    final me = _ref.read(currentUserProvider);
    if (me == null) {
      throw StateError('Sign in to manage requests.');
    }
    final repo = _ref.read(bookingsRepositoryProvider);
    final booking = approve
        ? await repo.approveRequest(bookingId, me)
        : await repo.declineRequest(bookingId, me);
    _ref.invalidate(eventGuestsProvider(booking.dinner.id));
    // Attendance and the pending badge are derived from the guest list, so the
    // single invalidation above keeps every host surface consistent.
  }

  Future<void> approve(String bookingId) => _run(bookingId, true);

  Future<void> decline(String bookingId) => _run(bookingId, false);
}

final guestRequestsControllerProvider = Provider<GuestRequestsController>(
  (ref) => GuestRequestsController(ref),
);

/// Collaboration proposal lifecycle: send, cancel, complete.
///
/// Each write invalidates [hostCollaborationsProvider] so the derived
/// [myHostCollaborationsProvider] re-reads the server's authoritative list.
class CollaborationsController {
  CollaborationsController(this._ref);

  final Ref _ref;

  String _hostId() {
    final id = _ref.read(currentUserIdProvider);
    if (id == null) throw StateError('Sign in to manage collaborations.');
    return id;
  }

  Future<CollaborationInvite> sendProposal({
    required String restaurantId,
    required String title,
    required String message,
    String? experienceId,
  }) async {
    final hostId = _hostId();
    final invite = await _ref.read(hostsRepositoryProvider).sendProposal(
      hostId: hostId,
      restaurantId: restaurantId,
      title: title,
      message: message,
      experienceId: experienceId,
    );
    _ref.invalidate(hostCollaborationsProvider(hostId));
    _ref.invalidate(hostInvitesProvider(hostId));
    return invite;
  }

  Future<CollaborationInvite> cancelProposal(String collabId) async {
    final hostId = _hostId();
    final invite = await _ref.read(hostsRepositoryProvider).cancelProposal(
      hostId: hostId,
      collabId: collabId,
    );
    _ref.invalidate(hostCollaborationsProvider(hostId));
    _ref.invalidate(hostInvitesProvider(hostId));
    return invite;
  }

  Future<CollaborationInvite> completeProposal(
    String collabId, {
    String? experienceId,
  }) async {
    final hostId = _hostId();
    final invite = await _ref.read(hostsRepositoryProvider).completeProposal(
      hostId: hostId,
      collabId: collabId,
      experienceId: experienceId,
    );
    _ref.invalidate(hostCollaborationsProvider(hostId));
    _ref.invalidate(hostInvitesProvider(hostId));
    return invite;
  }

  Future<void> promoteEvent(String eventId) async {
    final hostId = _hostId();
    await _ref.read(hostsRepositoryProvider).promoteEvent(hostId, eventId);
  }
}

final collaborationsControllerProvider = Provider<CollaborationsController>(
  (ref) => CollaborationsController(ref),
);
