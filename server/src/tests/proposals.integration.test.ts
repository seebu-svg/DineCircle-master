/**
 * Two-way experience proposal contract suite.
 *
 * Covers both directions of a collaboration, which the audit found to be
 * broken in different ways:
 *
 *   Direction A — a host proposes a collaboration to a venue. The create path
 *   used to answer 500 (the INSERT referenced columns that did not exist), the
 *   venue had no endpoint to see or answer it at all, and a host could accept
 *   their own proposal.
 *
 *   Direction B — a venue drafts an experience and proposes it to a host. This
 *   did not exist: `proposed_by='restaurant'` rows could only be written by
 *   seed data, so the field was decorative.
 *
 * The rules asserted here are the ones that make the workflow safe:
 *   * only the intended recipient can answer, and a decided proposal cannot
 *     move again (conditional UPDATE, so a lost race is a 409 not a second
 *     notification)
 *   * one active collaboration per host/venue pair, enforced by
 *     `uq_collab_active` under real concurrency
 *   * both sides are notified to an account they can actually sign in to
 *     (active `restaurant_staff`, not just `restaurants.owner_id`)
 *   * nothing a venue has not approved can be seen or booked by a diner, and
 *     cancelling removes an experience instead of erasing it
 *
 * Execute from server/:  npx tsx --test src/tests/proposals.integration.test.ts
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { bootstrap, one, many, exec, type ApiHandle } from './util.js';

const handle: ApiHandle = await bootstrap();
const base = handle.base;
after(() => handle.close());

type Json = Record<string, any>;

const DEMO_PASSWORD = 'dinecircle123';
const OPS_EMAIL = 'karachi.desk+demo@example.test';
const PASSWORD = 'correct horse battery staple';
const COVER = 'assets/images/dish_steak.png';

async function api(
  token: string | null,
  method: string,
  path: string,
  body?: unknown,
): Promise<{ status: number; json: Json }> {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = (await res.json().catch(() => ({}))) as Json;
  return { status: res.status, json };
}

async function login(email: string, password: string): Promise<{ token: string; userId: string }> {
  const { status, json } = await api(null, 'POST', '/auth/login', { email, password });
  assert.equal(status, 200, `login failed for ${email}: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string };
}

let seq = 0;

/** A plain diner: no host capabilities, no venue membership. */
async function signUpAccount(prefix = 'member'): Promise<{
  token: string; userId: string; email: string;
}> {
  seq += 1;
  const email = `proposals_${prefix}_${seq}@example.com`;
  const { status, json } = await api(null, 'POST', '/auth/signup', {
    name: `Proposal ${prefix}`,
    email,
    password: PASSWORD,
  });
  assert.equal(status, 201, `signup failed: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string, email };
}

/** A host with the professional account type, which is what publishing needs. */
async function makeHost(prefix: string): Promise<{
  token: string; userId: string; email: string;
}> {
  const account = await signUpAccount(prefix);
  const promote = await api(account.token, 'POST', '/users/me/host');
  assert.equal(promote.status, 200, JSON.stringify(promote.json));
  return account;
}

/** The seeded platform admin has no password by design, so mint a session. */
async function mintAdminToken(): Promise<string> {
  const secret = `dc_proposals_admin_${randomUUID().replace(/-/g, '')}`;
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = 'super_admin' LIMIT 1`,
    [createHash('sha256').update(secret).digest('hex')],
  );
  return secret;
}

type Venue = { id: string; token: string; ownerId: string; name: string };

/**
 * A verified venue ready for host proposals. Verification goes through the
 * real admin queue because a host may only publish at a verified partner.
 */
async function registerVenue(name: string): Promise<Venue> {
  seq += 1;
  const owner = await signUpAccount('venue');
  const created = await api(owner.token, 'POST', '/partner/restaurants', {
    name,
    city: 'Lyon',
    seats: 2,
    address: '1 Rue de Test',
    timezone: 'Europe/Paris',
  });
  assert.equal(created.status, 201, `registration failed: ${JSON.stringify(created.json)}`);
  const id = created.json.data.restaurant.id as string;

  const admin = await mintAdminToken();
  const queue = await api(admin, 'GET', '/partner/verification/requests?status=pending');
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  const request = (queue.json.data.requests as Json[])
    .find((r) => r.restaurantId === id);
  assert.ok(request, 'the pending request must appear in the admin queue');
  const review = await api(
    admin,
    'POST',
    `/partner/verification/requests/${request!.id}/review`,
    { decision: 'approved', reviewerNote: 'verified by the proposal suite' },
  );
  assert.equal(review.status, 200, JSON.stringify(review.json));

  return { id, token: owner.token, ownerId: owner.userId, name };
}

/** Adds a manager to a venue through the real invite flow, not a DB shortcut. */
async function addManager(venue: Venue): Promise<{ token: string; userId: string }> {
  const recruit = await signUpAccount('manager');
  const invite = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/staff`, {
    email: recruit.email,
    role: 'manager',
  });
  assert.equal(invite.status, 201, JSON.stringify(invite.json));
  const accept = await api(recruit.token, 'POST',
    `/partner/restaurants/${venue.id}/staff/accept`);
  assert.equal(accept.status, 200, JSON.stringify(accept.json));
  return { token: recruit.token, userId: recruit.userId };
}

/** Opts a venue into approving host experiences, the way the Partner App can. */
async function requireApproval(venue: Venue): Promise<void> {
  const res = await api(venue.token, 'PATCH', `/partner/restaurants/${venue.id}`, {
    requiresHostApproval: true,
  });
  assert.equal(res.status, 200, JSON.stringify(res.json));
}

function inDays(days: number, hour = 19): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
}

/** A published, bookable host experience at `venue`. */
async function publishEvent(
  host: { token: string; userId: string },
  venueId: string,
  title: string,
  days = 12,
  requiresApproval = false,
): Promise<Json> {
  const created = await api(host.token, 'POST', '/events', {
    title,
    tagline: 'proposal suite fixture',
    description: 'an experience used to prove the proposal workflow end to end',
    coverImage: COVER,
    restaurantId: venueId,
    startAt: inDays(days),
    seatsTotal: 8,
    pricePerSeat: 60,
    audience: 'public',
    requiresApproval,
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  return created.json.event as Json;
}

/** A host proposal (Direction A) that is expected to succeed. */
async function proposeToVenue(
  host: { token: string; userId: string },
  venueId: string,
  title: string,
  experienceId?: string,
): Promise<Json> {
  const res = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venueId,
    title,
    message: 'We would love to run this series with your team.',
    ...(experienceId ? { experienceId } : {}),
  });
  assert.equal(res.status, 201, JSON.stringify(res.json));
  return res.json.collaboration as Json;
}

const collabRows = (hostId: string, venueId: string) =>
  many<{ status: string; proposed_by: string }>(
    `SELECT status, proposed_by FROM collaboration_invites
      WHERE host_id = $1::UUID AND restaurant_id = $2::UUID`,
    [hostId, venueId],
  );

// ── 1. Direction A: create, dedupe, discover ────────────────────────────────

test('a host proposal is stored, listed on both sides, and cannot be repeated', async () => {
  const venue = await registerVenue('Proposal Desk Grill');
  const host = await makeHost('proposer');

  const proposal = await proposeToVenue(host, venue.id, 'Sunset Supper Series');
  assert.equal(proposal.status, 'invited');
  assert.equal(proposal.proposedBy, 'host');
  assert.equal(proposal.restaurant.id, venue.id);
  assert.equal(proposal.respondedAt, null, 'an unanswered proposal has no decision time');

  // The host's own outbox lists it.
  const outbox = await api(host.token, 'GET', `/hosts/${host.userId}/collabs`);
  assert.equal(outbox.status, 200, JSON.stringify(outbox.json));
  const mine = (outbox.json.collaborations as Json[])
    .find((c) => c.id === proposal.id);
  assert.ok(mine, 'the host outbox must contain the proposal just sent');
  assert.equal(mine!.proposedBy, 'host');
  assert.equal(mine!.respondedAt, null);

  // Repeating the send is refused rather than piling up duplicates.
  const repeat = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venue.id,
    title: 'Sunset Supper Series again',
    message: 'second attempt',
  });
  assert.equal(repeat.status, 409, JSON.stringify(repeat.json));
  assert.match(repeat.json.error, /already exists/i);

  // Two taps racing each other still leave exactly one active row: the
  // friendly pre-check is backed by the `uq_collab_active` partial index.
  const raced = await Promise.all([
    api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
      restaurantId: venue.id,
      title: 'Raced A',
      message: 'race',
    }),
    api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
      restaurantId: venue.id,
      title: 'Raced B',
      message: 'race',
    }),
  ]);
  const codes = raced.map((r) => r.status).sort();
  assert.deepEqual(codes, [409, 409], 'both racers lose to the existing active row');
  const rows = await collabRows(host.userId, venue.id);
  assert.equal(rows.length, 1, 'no duplicate collaboration rows may exist');
  assert.equal(rows[0]!.status, 'invited');
});

test('a proposal cannot be aimed at an unknown venue or at its own sender', async () => {
  const venue = await registerVenue('Boundary Cellar');
  const host = await makeHost('boundary');

  const unknown = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: randomUUID(),
    title: 'Nowhere Supper',
    message: 'no such venue',
  });
  assert.equal(unknown.status, 404, JSON.stringify(unknown.json));

  // A host is not a venue, so pointing the proposal at a user id must fail.
  const selfVenue = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: host.userId,
    title: 'My Own Table',
    message: 'invalid target',
  });
  assert.equal(selfVenue.status, 404, JSON.stringify(selfVenue.json));

  const short = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venue.id,
    title: 'x',
    message: 'too short',
  });
  assert.equal(short.status, 400, JSON.stringify(short.json));
});

test('a host cannot propose on top of someone else\'s experience', async () => {
  const venue = await registerVenue('Borrowed Table Bistro');
  const host = await makeHost('linker');
  const other = await makeHost('otherOwner');

  const foreignEvent = await publishEvent(other, venue.id, 'Someone Elses Supper');

  const attach = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venue.id,
    title: 'Borrowed Series',
    message: 'trying to attach a foreign experience',
    experienceId: foreignEvent.id,
  });
  assert.equal(attach.status, 422, JSON.stringify(attach.json));
  assert.equal((await collabRows(host.userId, venue.id)).length, 0);

  // An unknown experience id is refused the same way, not silently ignored.
  const ghost = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venue.id,
    title: 'Ghost Series',
    message: 'no such experience',
    experienceId: randomUUID(),
  });
  assert.equal(ghost.status, 422, JSON.stringify(ghost.json));
});

// ── 2. Who may see and answer ───────────────────────────────────────────────

test('the venue side of a proposal is visible only to that venue', async () => {
  const venue = await registerVenue('Inbox Only Kitchen');
  const host = await makeHost('viewer');
  const proposal = await proposeToVenue(host, venue.id, 'Inbox Visibility Series');

  // A diner cannot reach the partner surface at all.
  const diner = await signUpAccount('nosy');
  const asDiner = await api(diner.token, 'GET',
    `/partner/restaurants/${venue.id}/collab-proposals`);
  assert.equal(asDiner.status, 403, JSON.stringify(asDiner.json));

  const anonymous = await api(null, 'GET', `/partner/restaurants/${venue.id}/collab-proposals`);
  assert.equal(anonymous.status, 401, JSON.stringify(anonymous.json));

  // The host who sent it is not a venue either.
  const asHost = await api(host.token, 'GET',
    `/partner/restaurants/${venue.id}/collab-proposals`);
  assert.equal(asHost.status, 403, JSON.stringify(asHost.json));

  // Another venue must not learn the proposal exists.
  const other = await registerVenue('Uninvolved Table');
  const foreign = await api(other.token, 'GET',
    `/partner/restaurants/${other.id}/collab-proposals`);
  assert.equal(foreign.status, 200, JSON.stringify(foreign.json));
  assert.equal((foreign.json.data.proposals as Json[]).length, 0);
  const foreignAnswer = await api(other.token, 'POST',
    `/partner/restaurants/${other.id}/collab-proposals/${proposal.id}/accept`);
  assert.equal(foreignAnswer.status, 404, JSON.stringify(foreignAnswer.json));

  // The right venue sees it, with the host's identity attached.
  const inbox = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/collab-proposals?status=invited`);
  assert.equal(inbox.status, 200, JSON.stringify(inbox.json));
  const seen = (inbox.json.data.proposals as Json[]).find((p) => p.id === proposal.id);
  assert.ok(seen, 'the venue inbox must list the incoming proposal');
  assert.equal(seen!.direction, 'incoming');
  assert.equal(seen!.host.id, host.userId);
  assert.equal(seen!.restaurant.id, venue.id);

  // Direction filters keep the two queues apart.
  const outgoing = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/collab-proposals?direction=outgoing`);
  assert.equal(outgoing.status, 200, JSON.stringify(outgoing.json));
  assert.equal((outgoing.json.data.proposals as Json[]).length, 0);

  const badFilter = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/collab-proposals?direction=sideways`);
  assert.equal(badFilter.status, 400, JSON.stringify(badFilter.json));
});

test('only the intended recipient can answer, in either direction', async () => {
  const venue = await registerVenue('Wrong Hands Trattoria');
  const host = await makeHost('recipient');
  const stranger = await makeHost('stranger');
  const incoming = await proposeToVenue(host, venue.id, 'Answered By Me Series');

  // The host may not accept their own outgoing proposal: that would grant a
  // collaboration the venue never approved.
  const selfAccept = await api(host.token, 'POST',
    `/hosts/${host.userId}/invites/${incoming.id}/accept`);
  assert.equal(selfAccept.status, 409, JSON.stringify(selfAccept.json));
  assert.match(selfAccept.json.error, /venue sent/i);

  // A different host holding the same kind of endpoint gets a 404, so the
  // attempt does not confirm the proposal exists.
  const strangerAccept = await api(stranger.token, 'POST',
    `/hosts/${stranger.userId}/invites/${incoming.id}/accept`);
  assert.equal(strangerAccept.status, 404, JSON.stringify(strangerAccept.json));

  const venueAccept = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${incoming.id}/accept`);
  assert.equal(venueAccept.status, 200, JSON.stringify(venueAccept.json));
  assert.equal(venueAccept.json.data.proposal.status, 'accepted');

  // A decided proposal cannot be reversed, not even by the party that decided.
  const reversal = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${incoming.id}/decline`,
    { reason: 'changed our mind' });
  assert.equal(reversal.status, 409, JSON.stringify(reversal.json));

  // And the sender may no longer withdraw it. The host-side cancel keeps its
  // documented 400 ("unchanged in behaviour" per the plan); what matters is
  // that the decided row cannot be moved again.
  const lateCancel = await api(host.token, 'POST',
    `/hosts/${host.userId}/collabs/${incoming.id}/cancel`);
  assert.equal(lateCancel.status, 400, JSON.stringify(lateCancel.json));

  const stored = await one<{ status: string; responded_at: Date | null; responded_by: string | null }>(
    'SELECT status, responded_at, responded_by FROM collaboration_invites WHERE id = $1::UUID',
    [incoming.id],
  );
  assert.equal(stored?.status, 'accepted');
  assert.ok(stored?.responded_at, 'the decision time must be persisted');
  assert.equal(stored?.responded_by, venue.ownerId, 'and who decided is recorded');
});

test('a venue cannot answer its own outgoing proposal, but the host can', async () => {
  const venue = await registerVenue('Self Answer Bistro');
  const host = await makeHost('target');

  const outgoing = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Cook With Us',
      message: 'we drafted a menu for your name',
    });
  assert.equal(outgoing.status, 201, JSON.stringify(outgoing.json));
  const proposalId = outgoing.json.data.proposal.id as string;

  // Accepting one's own proposal would be the venue approving itself.
  const selfAnswer = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${proposalId}/accept`);
  assert.equal(selfAnswer.status, 409, JSON.stringify(selfAnswer.json));
  assert.match(selfAnswer.json.error, /host has to answer/i);

  // The venue cannot withdraw on the host's behalf either — that verb is for
  // rows the venue sent, and answering one is not its call.
  const wrongAnswer = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${proposalId}/decline`, {
      reason: 'no',
    });
  assert.equal(wrongAnswer.status, 409, JSON.stringify(wrongAnswer.json));

  // The intended recipient answers, and the venue is told with its own note.
  const decline = await api(host.token, 'POST',
    `/hosts/${host.userId}/invites/${proposalId}/decline`, {
      reason: 'That date collides with my residency',
    });
  assert.equal(decline.status, 200, JSON.stringify(decline.json));
  assert.equal(decline.json.status, 'declined');
  assert.match(decline.json.invite.declineReason, /residency/);

  const told = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE actor_id = $1::UUID AND kind = 'collab' AND body ILIKE $2`,
    [venue.ownerId, `%That date collides%`],
  );
  assert.equal(told?.count, 1, 'the venue hears the host wording in its own feed');

  // A decided proposal cannot be withdrawn by the sender that made it.
  const tooLate = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${proposalId}/cancel`);
  assert.equal(tooLate.status, 409, JSON.stringify(tooLate.json));

  const stored = await one<{ status: string }>(
    'SELECT status FROM collaboration_invites WHERE id = $1::UUID', [proposalId]);
  assert.equal(stored?.status, 'declined', 'the decision stands');

  // Withdrawing an *unanswered* proposal remains the sender's right, and a
  // withdrawn proposal can then be answered by nobody.
  const second = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Cook With Us, Second Take',
      message: 'the first one is closed, this one is open',
    });
  assert.equal(second.status, 201, JSON.stringify(second.json));
  const secondId = second.json.data.proposal.id as string;

  const withdrawn = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${secondId}/cancel`);
  assert.equal(withdrawn.status, 200, JSON.stringify(withdrawn.json));
  assert.equal(withdrawn.json.data.proposal.status, 'cancelled');

  const afterCancel = await api(host.token, 'POST',
    `/hosts/${host.userId}/invites/${secondId}/accept`);
  assert.equal(afterCancel.status, 409, JSON.stringify(afterCancel.json));
});

test('a host withdrawing their own proposal frees the pair for a new one', async () => {
  const venue = await registerVenue('Withdraw And Retry Cafe');
  const host = await makeHost('retrier');
  const first = await proposeToVenue(host, venue.id, 'First Attempt Series');

  const cancel = await api(host.token, 'POST',
    `/hosts/${host.userId}/collabs/${first.id}/cancel`);
  assert.equal(cancel.status, 200, JSON.stringify(cancel.json));
  assert.equal(cancel.json.status, 'cancelled');

  const stored = await one<{ status: string; updated_at: Date | null }>(
    'SELECT status, updated_at FROM collaboration_invites WHERE id = $1::UUID',
    [first.id],
  );
  assert.equal(stored?.status, 'cancelled');
  assert.ok(stored?.updated_at, 'a withdrawal must leave a modification timestamp');

  // The unique index only covers invited/accepted rows, so the retry is legal.
  const retry = await proposeToVenue(host, venue.id, 'Second Attempt Series');
  assert.notEqual(retry.id, first.id);
  assert.equal((await collabRows(host.userId, venue.id)).length, 2);
});

// ── 4. Notification audience ────────────────────────────────────────────────

test('a proposal reaches every active staff account of the venue, not just its owner', async () => {
  const venue = await registerVenue('Shared Inbox Room');
  const manager = await addManager(venue);
  const host = await makeHost('announcer');

  const proposal = await proposeToVenue(host, venue.id, 'Notified Series');

  // The venue-scoped row is what the Partner App inbox reads, so it must exist
  // once regardless of how many people work at the venue. The notice names the
  // proposal in its body, not its title, so that is the column to match.
  const notices = await many<{ read: boolean; body: string }>(
    `SELECT read, body FROM notifications
      WHERE restaurant_id = $1::UUID AND body ILIKE $2`,
    [venue.id, `%Notified Series%`],
  );
  assert.equal(notices.length, 1, 'exactly one venue notification per proposal');
  assert.equal(notices[0]!.read, false);

  // Every active staff account gets a personal activity row. Before this the
  // only recipient was `restaurants.owner_id`, which on seeded venues is an
  // account nobody can sign in to, so proposals arrived in a dead inbox.
  for (const userId of [venue.ownerId, manager.userId]) {
    const seen = await one<{ count: number }>(
      `SELECT count(*)::int AS count FROM activity
        WHERE actor_id = $1::UUID AND kind = 'collab'
          AND title = 'New collaboration proposal from host' AND body ILIKE $2`,
      [userId, `%Notified Series%`],
    );
    assert.equal(seen?.count, 1, `${userId} must be told about the proposal`);
  }

  // A decision is announced back to the host, and only to that host.
  const accept = await api(manager.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${proposal.id}/accept`);
  assert.equal(accept.status, 200, JSON.stringify(accept.json));

  const hostNotice = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE actor_id = $1::UUID AND kind = 'collab' AND body ILIKE $2`,
    [host.userId, `%accepted%`],
  );
  assert.equal(hostNotice?.count, 1, 'the host is told once that the venue accepted');

  const stranger = await makeHost('uninvolved');
  const bystander = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE actor_id = $1::UUID AND kind IN ('collab', 'approval')`,
    [stranger.userId],
  );
  assert.equal(bystander?.count, 0, 'nobody else receives the news');
});

test('a decline carries the venue note to the host verbatim', async () => {
  const venue = await registerVenue('Candid Decline Bar');
  const host = await makeHost('declined');
  const proposal = await proposeToVenue(host, venue.id, 'Refused Series');

  const decline = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${proposal.id}/decline`, {
      reason: 'Our private dining room is booked that month',
    });
  assert.equal(decline.status, 200, JSON.stringify(decline.json));
  assert.equal(decline.json.data.proposal.status, 'declined');
  assert.match(decline.json.data.proposal.declineReason, /private dining room/);

  const stored = await one<{ decline_reason: string; responded_by: string | null }>(
    'SELECT decline_reason, responded_by FROM collaboration_invites WHERE id = $1::UUID',
    [proposal.id],
  );
  assert.match(stored!.decline_reason, /private dining room/, 'the note is persisted');
  assert.equal(stored?.responded_by, venue.ownerId);

  const hostNotice = await one<{ body: string }>(
    `SELECT body FROM activity
      WHERE actor_id = $1::UUID AND kind = 'collab' ORDER BY created_at DESC LIMIT 1`,
    [host.userId],
  );
  assert.match(hostNotice!.body, /Our private dining room is booked that month/,
    'the host sees the venue wording, not a generic message');

  // The note is capped at 500 characters by `respondSchema`, so an over-long
  // one is rejected before it can reach the CHECK constraint on the column.
  const retry = await api(host.token, 'POST', `/hosts/${host.userId}/collabs/propose`, {
    restaurantId: venue.id,
    title: 'Refused Series Two',
    message: 'a declined proposal does not lock the pair forever',
  });
  assert.equal(retry.status, 201, JSON.stringify(retry.json));
  const secondId = retry.json.collaboration.id as string;

  const tooLong = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals/${secondId}/decline`, {
      reason: 'x'.repeat(501),
    });
  assert.equal(tooLong.status, 400, JSON.stringify(tooLong.json));

  // The rejected decline left the proposal untouched, so it can still be answered.
  const stillPending = await one<{ status: string }>(
    'SELECT status FROM collaboration_invites WHERE id = $1::UUID', [secondId]);
  assert.equal(stillPending?.status, 'invited');
});

// ── 5. Direction B: a venue proposes to a host ──────────────────────────────

test('a venue drafts an experience for a host and publishing waits for acceptance', async () => {
  const venue = await registerVenue('Venue Led Kitchen');
  const host = await makeHost('proposedTo');

  const draft = await api(venue.token, 'POST', '/partner/events', {
    restaurantId: venue.id,
    hostId: host.userId,
    title: 'Chef Table With A Guest Host',
    tagline: 'drafted by the venue',
    description: 'a venue-written experience that needs the host to accept',
    startAt: inDays(20),
    endAt: inDays(20, 22),
    seatsTotal: 10,
    pricePerSeat: 90,
    coverImage: COVER,
  });
  assert.equal(draft.status, 201, JSON.stringify(draft.json));
  const eventId = draft.json.data.event.id as string;
  assert.equal(draft.json.data.event.status, 'draft',
    'a venue can never publish on a host\'s behalf');
  assert.equal(draft.json.data.event.hostId, host.userId);

  const proposal = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Cook With Us',
      message: 'we wrote a tasting for your name, would you host it?',
      experienceId: eventId,
    });
  assert.equal(proposal.status, 201, JSON.stringify(proposal.json));
  const proposalId = proposal.json.data.proposal.id as string;
  assert.equal(proposal.json.data.proposal.proposedBy, 'restaurant');
  assert.equal(proposal.json.data.proposal.direction, 'outgoing');
  assert.equal(proposal.json.data.proposal.experience.id, eventId,
    'the host must see the experience itself, not just a title');

  // The host sees the attached experience in their inbox without a second call.
  const inbox = await api(host.token, 'GET', `/hosts/${host.userId}/invites`);
  assert.equal(inbox.status, 200, JSON.stringify(inbox.json));
  const seen = (inbox.json.invites as Json[]).find((i) => i.id === proposalId);
  assert.ok(seen, 'a venue proposal appears in the host inbox');
  assert.equal(seen!.experience.id, eventId);
  assert.equal(seen!.restaurant.id, venue.id);

  // Publishing before acceptance is refused, so the experience cannot reach
  // diners under a collaboration nobody agreed to.
  const early = await api(host.token, 'PATCH', `/events/${eventId}`, {
    status: 'published',
  });
  assert.equal(early.status, 409, JSON.stringify(early.json));
  assert.match(early.json.error, /accept the collaboration/i);
  const stillDraft = await one<{ status: string }>(
    'SELECT status FROM dinner_events WHERE id = $1::UUID', [eventId],
  );
  assert.equal(stillDraft?.status, 'draft');

  const accept = await api(host.token, 'POST',
    `/hosts/${host.userId}/invites/${proposalId}/accept`);
  assert.equal(accept.status, 200, JSON.stringify(accept.json));
  assert.equal(accept.json.status, 'accepted');

  const publish = await api(host.token, 'PATCH', `/events/${eventId}`, {
    status: 'published',
  });
  assert.equal(publish.status, 200, JSON.stringify(publish.json));
  assert.equal(publish.json.event.status, 'confirmed',
    'a venue without the approval opt-in goes live once the host publishes');

  // The proposal row keeps pointing at the experience it produced.
  const linked = await one<{ experience_id: string; status: string }>(
    'SELECT experience_id, status FROM collaboration_invites WHERE id = $1::UUID',
    [proposalId],
  );
  assert.equal(linked?.experience_id, eventId);
  assert.equal(linked?.status, 'accepted');
});

test('a venue proposal refuses non-hosts, foreign drafts and published drafts', async () => {
  const venue = await registerVenue('Strict Proposer Deli');
  const host = await makeHost('strictTarget');
  const personal = await signUpAccount('personalOnly');

  const notAHost = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: personal.userId,
      title: 'Plain User Series',
      message: 'this account never became a host',
    });
  assert.equal(notAHost.status, 404, JSON.stringify(notAHost.json));

  // A draft belonging to a different host cannot be smuggled in.
  const otherHostDraft = await api(venue.token, 'POST', '/partner/events', {
    restaurantId: venue.id,
    hostId: host.userId,
    title: 'Correct Owner Draft',
    startAt: inDays(21),
    endAt: inDays(21, 22),
    seatsTotal: 6,
    pricePerSeat: 40,
    coverImage: COVER,
  });
  assert.equal(otherHostDraft.status, 201, JSON.stringify(otherHostDraft.json));
  const draftId = otherHostDraft.json.data.event.id as string;

  const foreignVenue = await registerVenue('Other Venue Entirely');
  const hijack = await api(foreignVenue.token, 'POST',
    `/partner/restaurants/${foreignVenue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Cross Venue Hijack',
      message: 'trying to attach another venue draft',
      experienceId: draftId,
    });
  assert.equal(hijack.status, 422, JSON.stringify(hijack.json));

  // Only a draft may be attached: publishing is the host\'s decision.
  const liveEvent = await publishEvent(host, venue.id, 'Already Live Series');
  const tooLate = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Attach A Published Event',
      message: 'this is not a draft',
      experienceId: liveEvent.id,
    });
  assert.equal(tooLate.status, 422, JSON.stringify(tooLate.json));
  assert.match(tooLate.json.error, /draft/i);
});

test('a venue may list professional hosts it has not already paired with', async () => {
  const venue = await registerVenue('Host Roster Room');
  const host = await makeHost('rostered');
  // A personal account whose name matches the same search term: the roster is
  // supposed to hold professional hosts only, so this one must never appear.
  const diner = await signUpAccount('rosterPeek');

  const found = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/discover-hosts?q=Proposal`);
  assert.equal(found.status, 200, JSON.stringify(found.json));
  const roster = found.json.data.hosts as Json[];
  assert.ok(roster.some((h) => h.id === host.userId),
    'a professional host with no active collaboration is discoverable');
  assert.ok(!roster.some((h) => h.id === diner.userId),
    'a personal account is never offered as a host');
  const kinds = await many<{ account_type: string }>(
    `SELECT account_type FROM users WHERE id = ANY($1::UUID[])`,
    [roster.map((h) => h.id as string)],
  );
  assert.ok(kinds.every((k) => k.account_type === 'professional'),
    'the roster holds professional accounts only');

  // Once paired, the host leaves the list so the venue cannot send twice.
  const proposal = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Pairing Series',
      message: 'let us work together',
    });
  assert.equal(proposal.status, 201, JSON.stringify(proposal.json));

  const after = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/discover-hosts`);
  assert.equal(after.status, 200, JSON.stringify(after.json));
  assert.ok(!(after.json.data.hosts as Json[]).some((h) => h.id === host.userId),
    'an active collaboration removes the host from discovery');

  // A duplicate send is refused by the same rule the index enforces.
  const twice = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/collab-proposals`, {
      hostId: host.userId,
      title: 'Pairing Series Again',
      message: 'second attempt',
    });
  assert.equal(twice.status, 409, JSON.stringify(twice.json));

  // A diner has no business reading the roster.
  const closed = await api(diner.token, 'GET',
    `/partner/restaurants/${venue.id}/discover-hosts`);
  assert.equal(closed.status, 403, JSON.stringify(closed.json));
});

// ── 6. Approval policy on publish and edit ──────────────────────────────────

test('publishing a draft respects the venue approval policy', async () => {
  const gated = await registerVenue('Approval Gated Hall');
  await requireApproval(gated);
  const open = await registerVenue('Open Publishing Yard');

  const gatedHost = await makeHost('gatedPublisher');
  const draft = await api(gatedHost.token, 'POST', '/events', {
    title: 'Half Finished Supper',
    tagline: 'a draft',
    description: 'saved early and published later',
    restaurantId: gated.id,
    coverImage: COVER,
    status: 'draft',
  });
  assert.equal(draft.status, 201, JSON.stringify(draft.json));
  assert.equal(draft.json.event.status, 'draft');

  const publish = await api(gatedHost.token, 'PATCH', `/events/${draft.json.event.id}`, {
    status: 'published',
    startAt: inDays(25),
    seatsTotal: 6,
    pricePerSeat: 45,
  });
  assert.equal(publish.status, 200, JSON.stringify(publish.json));
  assert.equal(publish.json.event.status, 'requested',
    'an opt-in venue must approve before diners see it');

  const diner = await signUpAccount('gatedViewer');
  const hidden = await api(diner.token, 'GET', `/events/${draft.json.event.id}`);
  assert.equal(hidden.status, 404, 'a pending experience is not public');

  // The same flow at an ordinary venue goes straight live.
  const openHost = await makeHost('openPublisher');
  const openDraft = await api(openHost.token, 'POST', '/events', {
    title: 'Quick Publish Supper',
    tagline: 'a draft',
    description: 'saved early and published at a venue with no opt-in',
    restaurantId: open.id,
    coverImage: COVER,
    status: 'draft',
  });
  assert.equal(openDraft.status, 201, JSON.stringify(openDraft.json));
  const openPublish = await api(openHost.token, 'PATCH',
    `/events/${openDraft.json.event.id}`, {
      status: 'published',
      startAt: inDays(26),
      seatsTotal: 6,
      pricePerSeat: 45,
    });
  assert.equal(openPublish.status, 200, JSON.stringify(openPublish.json));
  assert.equal(openPublish.json.event.status, 'confirmed');

  // A raw status from a client is never trusted.
  const smuggled = await api(gatedHost.token, 'PATCH', `/events/${draft.json.event.id}`, {
    status: 'confirmed',
  });
  assert.equal(smuggled.status, 400, JSON.stringify(smuggled.json));
});

test('a host edit at an opt-in venue reopens the approval and says so', async () => {
  const venue = await registerVenue('Reapproval Room');
  await requireApproval(venue);
  const host = await makeHost('reapprover');
  const event = await publishEvent(host, venue.id, 'Reapproved Supper');

  const approve = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/event-requests/${event.id}/approve`);
  assert.equal(approve.status, 200, JSON.stringify(approve.json));
  assert.equal(approve.json.data.request.status, 'confirmed');

  const edit = await api(host.token, 'PATCH', `/events/${event.id}`, {
    description: 'the menu changed after approval',
  });
  assert.equal(edit.status, 200, JSON.stringify(edit.json));
  assert.equal(edit.json.event.status, 'requested',
    'a changed experience is not live until the venue looks again');
  assert.ok(edit.json.event.approvalStaleAt, 'the stale marker is exposed');

  const diner = await signUpAccount('reapprovalViewer');
  const hidden = await api(diner.token, 'GET', `/events/${event.id}`);
  assert.equal(hidden.status, 404, 'the edited experience is delisted while waiting');

  // The venue queue distinguishes a first request from a re-approval.
  const queue = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/event-requests`);
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  const row = (queue.json.data.requests as Json[]).find((r) => r.id === event.id);
  assert.ok(row, 'the reopened request is back in the queue');
  assert.equal(row!.isReapproval, true, 'and it is labelled as a re-approval');
});

// ── 7. Cancellation and delisting ───────────────────────────────────────────

test('cancelling removes an experience everywhere and tells the guests', async () => {
  const venue = await registerVenue('Cancelled Service Canteen');
  const host = await makeHost('canceller');
  const title = `Withdrawn Tasting ${seq}`;
  // A host-gated table seats guests as `pending`/`authorized` rather than
  // `paid`, which is the state the earnings guard deliberately leaves open so a
  // cancellation can still reach the people holding a seat.
  const event = await publishEvent(host, venue.id, title, 30, true);
  assert.equal(event.status, 'confirmed');

  const guest = await signUpAccount('affected');
  const booked = await api(guest.token, 'POST', `/events/${event.id}/bookings`, {
    seats: 2,
  });
  assert.equal(booked.status, 201, JSON.stringify(booked.json));

  const feedBefore = await api(guest.token, 'GET', `/events?q=${encodeURIComponent(title)}`);
  assert.ok((feedBefore.json.events as Json[]).some((e) => e.id === event.id),
    'it is listed while it is live');

  const cancelled = await api(host.token, 'DELETE', `/events/${event.id}`);
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.json));
  assert.equal(cancelled.json.cancelled, true, 'the row is soft-cancelled, not erased');

  const stored = await one<{
    status: string; cancelled_at: Date | null; cancelled_by: string | null;
  }>('SELECT status, cancelled_at, cancelled_by FROM dinner_events WHERE id = $1::UUID',
    [event.id]);
  assert.equal(stored?.status, 'cancelled');
  assert.ok(stored?.cancelled_at, 'the cancellation time is kept for the record');
  assert.equal(stored?.cancelled_by, host.userId, 'and who called it off');

  const feed = await api(guest.token, 'GET', `/events?q=${encodeURIComponent(title)}`);
  assert.ok(!(feed.json.events as Json[]).some((e) => e.id === event.id),
    'a cancelled experience leaves the feed');

  const searched = await api(guest.token, 'GET',
    `/search?q=${encodeURIComponent(title)}`);
  assert.equal(searched.status, 200, JSON.stringify(searched.json));
  assert.ok(!(searched.json.experiences as Json[]).some((e) => e.id === event.id),
    'and leaves search');

  // The detail page stays reachable for the people involved, because a guest
  // has to be able to open the booking they were refunded against; what the
  // soft cancel removes is discovery and bookability, not the record.
  const late = await api(guest.token, 'GET', `/events/${event.id}`);
  assert.equal(late.status, 200, JSON.stringify(late.json));
  assert.equal(late.json.event.status, 'cancelled',
    'the row announces itself as cancelled');

  const lateBooking = await api(guest.token, 'POST', `/events/${event.id}/bookings`, {
    seats: 1,
  });
  assert.equal(lateBooking.status, 404,
    'a cancelled experience is unknown to the booking path');

  const told = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE actor_id = $1::UUID AND event_id = $2::UUID AND kind = 'reminder'`,
    [guest.userId, event.id],
  );
  assert.equal(told?.count, 1, 'the guest is told in their own feed');

  // The host may still read their own cancelled record; a diner may not.
  const ownerView = await api(host.token, 'GET', `/events/${event.id}`);
  assert.equal(ownerView.status, 200, JSON.stringify(ownerView.json));
  assert.equal(ownerView.json.event.cancelledAt, stored!.cancelled_at!.toISOString(),
    'the detail exposes the cancellation trail to the host');

  // Deleting again is not a silent no-op. Soft cancel is idempotent in effect
  // but not in contract: both the host route and the venue route answer 409
  // "already cancelled", so a double-tapped desk hears the real reason.
  const twice = await api(host.token, 'DELETE', `/events/${event.id}`);
  assert.equal(twice.status, 409, JSON.stringify(twice.json));
  assert.match(String(twice.json.error), /already cancelled/);
});

test('a host cannot delete an experience that has captured money', async () => {
  const venue = await registerVenue('Money Trail Tavern');
  const host = await makeHost('payer');
  const event = await publishEvent(host, venue.id, 'Paid Supper', 31);

  const guest = await signUpAccount('payer');
  await api(guest.token, 'POST', `/events/${event.id}/bookings`, { seats: 1 });
  await exec(
    `UPDATE bookings SET payment_status = 'paid', status = 'confirmed'
      WHERE event_id = $1::UUID`,
    [event.id],
  );

  const attempt = await api(host.token, 'DELETE', `/events/${event.id}`);
  assert.equal(attempt.status, 409, JSON.stringify(attempt.json));
  assert.match(attempt.json.error, /stay on the books/i);

  const stored = await one<{ status: string }>(
    'SELECT status FROM dinner_events WHERE id = $1::UUID', [event.id],
  );
  assert.equal(stored?.status, 'confirmed', 'the row is untouched');
});

// ── 8. What the venue may change ────────────────────────────────────────────

test('the partner surface cannot drive a host experience lifecycle', async () => {
  const venue = await registerVenue('Overreaching Owner Grill');
  const host = await makeHost('protectedHost');
  const event = await publishEvent(host, venue.id, 'Host Owned Identity Dinner');

  // A raw status write is refused outright.
  const statusWrite = await api(venue.token, 'PUT', `/partner/events/${event.id}`, {
    status: 'completed',
  });
  assert.equal(statusWrite.status, 400, JSON.stringify(statusWrite.json));
  const untouched = await one<{ status: string }>(
    'SELECT status FROM dinner_events WHERE id = $1::UUID', [event.id],
  );
  assert.equal(untouched?.status, 'confirmed');

  // Identity and pricing belong to the host.
  for (const body of [
    { title: 'Renamed By The Venue' },
    { pricePerSeat: 1 },
    { tagline: 'rewritten by the venue' },
    { description: 'rewritten by the venue' },
    { coverImage: 'assets/images/dish_pasta.png' },
    { tags: ['venue chosen'] },
  ]) {
    const refused = await api(venue.token, 'PUT', `/partner/events/${event.id}`, body);
    assert.equal(refused.status, 403, `${JSON.stringify(body)} → ${JSON.stringify(refused.json)}`);
    assert.match(refused.json.error, /host-owned/i);
  }

  // Re-assigning ownership is refused too, so a venue cannot hand a host's
  // experience to somebody else.
  const reassign = await api(venue.token, 'PUT', `/partner/events/${event.id}`, {
    hostId: randomUUID(),
  });
  assert.equal(reassign.status, 400, JSON.stringify(reassign.json));

  const after = await one<{ title: string; host_id: string; price_per_seat: string }>(
    'SELECT title, host_id, price_per_seat FROM dinner_events WHERE id = $1::UUID',
    [event.id],
  );
  assert.equal(after?.title, 'Host Owned Identity Dinner');
  assert.equal(after?.host_id, host.userId);

  // Operations are allowed, and the host is told what changed.
  const timing = await api(venue.token, 'PUT', `/partner/events/${event.id}`, {
    startAt: inDays(40),
    seatsTotal: 12,
  });
  assert.equal(timing.status, 200, JSON.stringify(timing.json));
  assert.deepEqual(
    (timing.json.data.changedFields as string[]).sort(),
    ['seatsTotal', 'startAt'],
  );

  const told = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE actor_id = $1::UUID AND event_id = $2::UUID AND kind = 'approval'`,
    [host.userId, event.id],
  );
  assert.equal(told?.count, 1, 'one activity row says the venue changed the event');

  // And an empty edit is a client error, not a silent success.
  const empty = await api(venue.token, 'PUT', `/partner/events/${event.id}`, {});
  assert.equal(empty.status, 400, JSON.stringify(empty.json));
});

test('a venue cancels, completes and reopens the experiences it hosts', async () => {
  const venue = await registerVenue('Lifecycle Kitchen');
  const host = await makeHost('lifecycleHost');
  const event = await publishEvent(host, venue.id, 'Lifecycle Dinner', 32);

  const completed = await api(venue.token, 'POST', `/partner/events/${event.id}/complete`);
  assert.equal(completed.status, 200, JSON.stringify(completed.json));
  assert.equal(completed.json.data.event.status, 'completed');

  // A completed experience is editable by its host again only after a reopen.
  const editWhileDone = await api(host.token, 'PATCH', `/events/${event.id}`, {
    description: 'edited after completion',
  });
  assert.equal(editWhileDone.status, 400, JSON.stringify(editWhileDone.json));

  const reopened = await api(venue.token, 'POST', `/partner/events/${event.id}/reopen`);
  assert.equal(reopened.status, 200, JSON.stringify(reopened.json));
  assert.equal(reopened.json.data.event.status, 'confirmed');

  const cancelled = await api(venue.token, 'POST', `/partner/events/${event.id}/cancel`, {
    reason: 'Private booking took the room',
  });
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.json));

  const stored = await one<{ status: string; cancellation_reason: string }>(
    'SELECT status, cancellation_reason FROM dinner_events WHERE id = $1::UUID',
    [event.id],
  );
  assert.equal(stored?.status, 'cancelled');
  assert.match(stored!.cancellation_reason, /Private booking/);

  // A cancelled experience leaves the diner-facing surfaces.
  const diner = await signUpAccount('lifecycleViewer');
  const peek = await api(diner.token, 'GET',
    `/events?q=${encodeURIComponent('Lifecycle Dinner')}`);
  assert.equal(peek.status, 200, JSON.stringify(peek.json));
  assert.ok(!(peek.json.events as Json[]).some((e) => e.id === event.id),
    'a cancelled experience is not listed to a diner');

  const booked = await api(diner.token, 'POST', `/events/${event.id}/bookings`, {
    seats: 1,
  });
  assert.equal(booked.status, 404, 'and it cannot be booked');

  const doubleCancel = await api(venue.token, 'POST', `/partner/events/${event.id}/cancel`);
  assert.equal(doubleCancel.status, 409, JSON.stringify(doubleCancel.json));
});

// ── 9. Detail parity ────────────────────────────────────────────────────────

test('the venue sees the full record behind an approval request, menu included', async () => {
  const venue = await registerVenue('Detail Parsonage');
  await requireApproval(venue);
  const host = await makeHost('detailHost');

  const created = await api(host.token, 'POST', '/events', {
    title: 'Full Record Supper',
    tagline: 'shown to the venue in the decision sheet',
    description: 'a long description with the running order and the dietary notes',
    restaurantId: venue.id,
    coverImage: COVER,
    gallery: [COVER, 'assets/images/dish_pasta.png'],
    startAt: inDays(33),
    durationMinutes: 180,
    seatsTotal: 8,
    pricePerSeat: 120,
    audience: 'public',
    menuStyle: 'tastingMenu',
    included: ['Wine pairing', 'Welcome drink'],
    tags: ['tasting'],
    hostNote: 'Two seats are held for the venue team',
    dressCode: 'Smart casual',
    language: 'English',
    menu: [
      { name: 'Oyster & cucumber', description: 'cold starter', isSignature: false },
      { name: 'Brown butter squid', description: 'hot starter', isSignature: true },
      { name: 'Aged duck', description: 'main course', pairing: 'Pinot Noir' },
    ],
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  const eventId = created.json.event.id as string;
  assert.equal(created.json.event.status, 'requested');

  const queue = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/event-requests`);
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  const row = (queue.json.data.requests as Json[]).find((r) => r.id === eventId);
  assert.ok(row, 'the request is in the venue queue');
  assert.equal(row!.menu.length, 3,
    'the queue must not show an empty menu for an experience that has one');

  const detail = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/event-requests/${eventId}`);
  assert.equal(detail.status, 200, JSON.stringify(detail.json));
  const full = detail.json.data.request as Json;

  // Everything the host wrote, so Accept/Decline is an informed decision.
  assert.equal(full.id, eventId);
  assert.equal(full.title, 'Full Record Supper');
  assert.equal(full.description,
    'a long description with the running order and the dietary notes');
  assert.equal(full.hostName.length > 0, true);
  assert.equal(full.host.id, host.userId);
  assert.equal(full.durationMinutes, 180);
  assert.equal(full.pricePerSeat, 120);
  assert.equal(full.menuStyle, 'tastingMenu');
  assert.deepEqual(full.included, ['Wine pairing', 'Welcome drink']);
  assert.deepEqual(full.tags, ['tasting']);
  assert.equal(full.hostNote, 'Two seats are held for the venue team');
  assert.equal(full.dressCode, 'Smart casual');
  assert.equal(full.language, 'English');
  assert.equal(full.gallery.length, 2);
  assert.equal(full.requiresApproval, true);
  assert.equal(full.isReapproval, false, 'a first request is not a re-approval');
  assert.equal(full.declineReason, '');

  assert.equal(full.menu.length, 3);
  assert.deepEqual(
    full.menu.map((m: Json) => m.name),
    ['Oyster & cucumber', 'Brown butter squid', 'Aged duck'],
  );
  assert.equal(full.menu[1].isSignature, true);
  assert.equal(full.menu[2].pairing, 'Pinot Noir');

  // A request for a foreign venue is a 404, and for a non-request row too.
  const outsider = await registerVenue('Not Involved Canteen');
  const refused = await api(outsider.token, 'GET',
    `/partner/restaurants/${outsider.id}/event-requests/${eventId}`);
  assert.equal(refused.status, 404, JSON.stringify(refused.json));
});
