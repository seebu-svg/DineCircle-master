/**
 * P2 Safety & Trust integration suite. Runs the real Express API against an
 * isolated freshly-seeded PostgreSQL database and verifies the three shipped
 * features plus their cross-user enforcement:
 *   * blocks: removal of mutual follows, discovery/profile/chat/booking
 *     restrictions, idempotency, unblock semantics, existing-booking integrity
 *   * reports: all four target types, evidence snapshots, duplicate and
 *     self-report guards, reporter privacy, super_admin-only moderation
 *   * feedback: categories, validation, persistence, ticket history ownership
 *   * regressions: auth, discovery, follow/unfollow, booking + group chat,
 *     Host Studio stats and the earnings wallet keep working untouched.
 *
 * Execute from server/:  npm run test:integration
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { bootstrap, one, many, exec, type ApiHandle } from './util.js';

const handle: ApiHandle = await bootstrap();
const base = handle.base;
after(() => handle.close());

type Json = Record<string, any>;

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

async function mustOne<T extends Record<string, any>>(
  sql: string,
  params: unknown[] = [],
): Promise<T> {
  const row = await one<T>(sql, params);
  assert.ok(row, `expected a row from: ${sql}`);
  return row;
}

let seq = 0;
const PASSWORD = 'correct horse battery staple';

async function signUpAccount(
  prefix = 'member',
): Promise<{ token: string; userId: string; email: string }> {
  seq += 1;
  const email = `p2_${prefix}_${seq}@example.com`;
  const { status, json } = await api(null, 'POST', '/auth/signup', {
    name: `P2 ${prefix}`,
    email,
    password: PASSWORD,
  });
  assert.equal(status, 201, `signup failed: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string, email };
}

const SEAT_ROOFTOP = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';

/** A published host event (fixture reused by several block/report cases). */
async function createHostEvent(token: string) {
  const startAt = new Date(Date.now() + 9 * 864e5).toISOString();
  const created = await api(token, 'POST', '/events', {
    title: 'Trust Table',
    tagline: 'p2 safety fixture',
    description: 'fixture event created by the safety integration suite',
    coverImage: 'assets/images/dish_pasta.png',
    restaurantId: SEAT_ROOFTOP,
    startAt,
    seatsTotal: 10,
    pricePerSeat: 40,
    audience: 'public',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  return created.json.event as Json;
}

async function makeHost(prefix: string) {
  const account = await signUpAccount(prefix);
  // The rooftop venue needs partner verification before a fresh host can
  // publish there (same fixture rule as the account/money suites).
  await exec(
    `UPDATE restaurants SET is_partner = true, partnership_status = 'verified'
      WHERE id = $1::UUID`,
    [SEAT_ROOFTOP],
  );
  const promote = await api(account.token, 'POST', '/users/me/host');
  assert.equal(promote.status, 200, JSON.stringify(promote.json));
  return account;
}

// ── 1. Block guards ──────────────────────────────────────────────────────────

test('block refuses self-block, unknown and deleted accounts', async () => {
  const alice = await signUpAccount('bgA');

  const self = await api(alice.token, 'POST', `/users/${alice.userId}/block`);
  assert.equal(self.status, 403);
  assert.match(self.json.error, /yourself/i);

  const ghost = await api(alice.token, 'POST', `/users/${randomUUID()}/block`);
  assert.equal(ghost.status, 404);

  // An anonymised (deleted) shell must not be blockable through the API.
  const victim = await signUpAccount('bgGone');
  const gone = await api(victim.token, 'DELETE', '/users/me', {
    password: PASSWORD,
  });
  assert.equal(gone.status, 200, JSON.stringify(gone.json));
  const shell = await mustOne<{ id: string }>(
    'SELECT id FROM users WHERE is_deleted = true LIMIT 1',
  );
  const stale = await api(alice.token, 'POST', `/users/${shell.id}/block`);
  assert.equal(stale.status, 404);

  // Blocking requires a session.
  assert.equal((await api(null, 'POST', `/users/${alice.userId}/block`)).status, 401);
});

// ── 2. Block severs the follow graph ─────────────────────────────────────────

test('block removes mutual follows, blocks new follows, unblock never restores', async () => {
  const a = await signUpAccount('blkA');
  const b = await signUpAccount('blkB');

  // Mutually following first (POST /follow answers 201 on creation).
  assert.equal((await api(a.token, 'POST', `/users/${b.userId}/follow`)).status, 201);
  assert.equal((await api(b.token, 'POST', `/users/${a.userId}/follow`)).status, 201);
  assert.equal(
    (await one(`SELECT 1 AS ok FROM follows WHERE follower_id = $1::UUID AND followee_id = $2::UUID`, [
      a.userId,
      b.userId,
    ]))?.ok,
    1,
  );

  const blocked = await api(a.token, 'POST', `/users/${b.userId}/block`);
  assert.equal(blocked.status, 200, JSON.stringify(blocked.json));
  assert.equal(blocked.json.blocked, true);
  assert.equal(blocked.json.removedFollows, 2, 'both directions severed');

  const rows = await many(
    `SELECT 1 FROM follows WHERE (follower_id = $1::UUID AND followee_id = $2::UUID)
       OR (follower_id = $2::UUID AND followee_id = $1::UUID)`,
    [a.userId, b.userId],
  );
  assert.equal(rows.length, 0, 'no follow rows survive a block');

  // Counters moved with the rows.
  const counts = await mustOne<{ af: number; bf: number }>(
    `SELECT (SELECT following_count FROM users WHERE id = $1::UUID) AS af,
            (SELECT followers_count FROM users WHERE id = $2::UUID) AS bf`,
    [a.userId, b.userId],
  );
  assert.equal(Number(counts.af), 0);
  assert.equal(Number(counts.bf), 0);

  // Neither side can re-follow while blocked; the reverse block direction is
  // enforced symmetrically server-side.
  const aFollows = await api(a.token, 'POST', `/users/${b.userId}/follow`);
  assert.equal(aFollows.status, 403);
  const bFollows = await api(b.token, 'POST', `/users/${a.userId}/follow`);
  assert.equal(bFollows.status, 403);

  // Duplicate block is idempotent, never a second row.
  const again = await api(a.token, 'POST', `/users/${b.userId}/block`);
  assert.equal(again.status, 200);
  assert.equal(again.json.removedFollows, 0);
  const blockRows = await many('SELECT 1 FROM user_blocks WHERE blocker_id = $1::UUID', [
    a.userId,
  ]);
  assert.equal(blockRows.length, 1);

  // The blocker's own list; nobody else can read it.
  const list = await api(a.token, 'GET', '/users/me/blocked');
  assert.equal(list.status, 200);
  assert.equal(list.json.count, 1);
  assert.equal(list.json.blocked[0].id, b.userId);
  assert.equal((await api(b.token, 'GET', '/users/me/blocked')).json.count, 0);

  // Unblock lifts the restriction but restores NOTHING.
  const unblocked = await api(a.token, 'DELETE', `/users/${b.userId}/block`);
  assert.equal(unblocked.status, 200);
  assert.equal(unblocked.json.blocked, false);
  assert.equal((await api(a.token, 'GET', '/users/me/blocked')).json.count, 0);

  const restored = await mustOne<{ n: string }>(
    'SELECT count(*)::text AS n FROM follows WHERE follower_id = $1::UUID AND followee_id = $2::UUID',
    [a.userId, b.userId],
  );
  assert.equal(restored.n, '0', 'unblock never re-follows behind your back');

  // And fresh follows work again now that the block is gone.
  assert.equal((await api(a.token, 'POST', `/users/${b.userId}/follow`)).status, 201);
});

// ── 3. Discovery + profile privacy under a block ─────────────────────────────

test('blocked pairs vanish from each other and get 403 on direct profile reads', async () => {
  const a = await signUpAccount('dvA');
  const b = await signUpAccount('dvB');
  // Give both a shared searchable name (ILIKE matches name/handle/bio).
  const marker = `Zeta Qmark ${randomUUID().slice(0, 8)}`;
  await exec('UPDATE users SET name = $2 WHERE id = $1::UUID', [a.userId, `${marker} Alpha`]);
  await exec('UPDATE users SET name = $2 WHERE id = $1::UUID', [b.userId, `${marker} Beta`]);
  const query = encodeURIComponent(marker);

  const visibleBefore = await api(a.token, 'GET', `/users?q=${query}&limit=50`);
  assert.equal(visibleBefore.status, 200);
  assert.ok(
    (visibleBefore.json.users as Json[]).some((u) => u.id === b.userId),
    'discovery shows the account before the block',
  );

  assert.equal((await api(a.token, 'POST', `/users/${b.userId}/block`)).status, 200);

  const after = await api(a.token, 'GET', `/users?q=${query}&limit=50`);
  assert.ok(
    !(after.json.users as Json[]).some((u) => u.id === b.userId),
    'the blocker never sees the blocked account',
  );
  // Symmetric: the blocked person loses the blocker too.
  const mirror = await api(b.token, 'GET', `/users?q=${query}&limit=50`);
  assert.ok(
    !(mirror.json.users as Json[]).some((u) => u.id === a.userId),
    'the blocked account never sees the blocker',
  );

  // Direct profile reads are refused both ways, no private-data leak.
  const aSeesB = await api(a.token, 'GET', `/users/${b.userId}`);
  assert.equal(aSeesB.status, 403);
  const bSeesA = await api(b.token, 'GET', `/users/${a.userId}`);
  assert.equal(bSeesA.status, 403);

  // Rosters are covered by the same guard.
  assert.equal((await api(a.token, 'GET', `/users/${b.userId}/followers`)).status, 403);
  assert.equal((await api(b.token, 'GET', `/users/${a.userId}/following`)).status, 403);

  // Unrelated third parties are NOT affected by someone else's block.
  const c = await signUpAccount('dvC');
  assert.equal((await api(c.token, 'GET', `/users/${b.userId}`)).status, 200);
});

// ── 4. Events, bookings and existing tickets ─────────────────────────────────

test('block hides the host\'s events and refuses new bookings while old tickets survive', async () => {
  const host = await makeHost('evH');
  const event = await createHostEvent(host.token);
  const guest = await signUpAccount('evG');

  // Guest can see and join normally first (also proves booking still works).
  assert.equal((await api(guest.token, 'GET', `/events/${event.id}`)).status, 200);
  const first = await api(guest.token, 'POST', `/events/${event.id}/bookings`, {
    seats: 1,
  });
  assert.equal(first.status, 201, JSON.stringify(first.json));
  const bookingId = first.json.booking.id as string;

  const feed = await api(guest.token, 'GET', `/events?hostId=${host.userId}&limit=50`);
  assert.equal((feed.json.events as Json[]).length, 1);

  assert.equal((await api(guest.token, 'POST', `/users/${host.userId}/block`)).status, 200);

  // Hidden from the personalized feed/search.
  const hidden = await api(guest.token, 'GET', `/events?hostId=${host.userId}&limit=50`);
  assert.equal((hidden.json.events as Json[]).length, 0, 'feed drops blocked-host events');
  // The host continues to see their own events in discovery (blocking hides
  // content from the BLOCKER's perspective, not the host's).
  const hostView = await api(host.token, 'GET', `/events?q=${encodeURIComponent('Trust Table')}&limit=50`);
  assert.ok(
    (hostView.json.events as Json[]).some((e) => e.id === event.id),
    'the host still sees their own event even after being blocked by a guest',
  );

  // New joins are refused…
  const late = await api(guest.token, 'POST', `/events/${event.id}/bookings`, {
    seats: 2,
  });
  assert.equal(late.status, 403);
  assert.match(late.json.error, /cannot join/i);

  // …but the EXISTING paid ticket stays intact and usable.
  const ticket = await mustOne<Json>(
    'SELECT status, seats FROM bookings WHERE id = $1::UUID',
    [bookingId],
  );
  assert.notEqual(ticket.status, 'cancelled');
  assert.equal(Number(ticket.seats), 1);
  const detail = await api(guest.token, `GET`, `/events/${event.id}`);
  assert.equal(detail.status, 200, 'ticket holders keep access despite the block');
  assert.equal(
    (await api(guest.token, 'GET', '/bookings')).json.bookings.some(
      (b: Json) => b.id === bookingId,
    ),
    true,
    'booking history still lists the ticket',
  );

  // An unrelated diner can still join the same event.
  const other = await signUpAccount('evO');
  assert.equal(
    (await api(other.token, 'POST', `/events/${event.id}/bookings`, { seats: 1 })).status,
    201,
  );
});

// ── 5. Group chat under a block ──────────────────────────────────────────────

test('blocked pairs cannot post new messages in the host\'s event chat; history stays', async () => {
  const host = await makeHost('chH');
  const event = await createHostEvent(host.token);
  const guest = await signUpAccount('chG');
  const third = await signUpAccount('chT');

  for (const g of [guest, third]) {
    assert.equal(
      (await api(g.token, 'POST', `/events/${event.id}/bookings`, { seats: 1 })).status,
      201,
    );
  }

  // Guest posts normally, then the host blocks them.
  const posted = await api(guest.token, 'POST', `/events/${event.id}/messages`, {
    text: 'Looking forward to this one!',
  });
  assert.equal(posted.status, 201, JSON.stringify(posted.json));
  const messageId = posted.json.message.id as string;

  assert.equal((await api(host.token, 'POST', `/users/${guest.userId}/block`)).status, 200);

  // New messages from the blocked guest are refused server-side…
  const refused = await api(guest.token, 'POST', `/events/${event.id}/messages`, {
    text: 'are you there?',
  });
  assert.equal(refused.status, 403);
  assert.match(refused.json.error, /cannot message/i);

  // …and the same rule bites back: the blocker (now blocked-pair) cannot post
  // into the host's thread either, while the host themselves still can.
  assert.equal(
    (await api(guest.token, 'POST', `/events/${event.id}/messages`, { text: 'hi' })).status,
    403,
  );
  assert.equal(
    (await api(host.token, 'POST', `/events/${event.id}/messages`, { text: 'housekeeping' }))
      .status,
    201,
    'the host always keeps their own thread',
  );

  // A third party sharing the table is unaffected.
  assert.equal(
    (await api(third.token, 'POST', `/events/${event.id}/messages`, { text: 'who brings wine' }))
      .status,
    201,
  );

  // History remains readable for the blocked guest, no evidence is destroyed.
  const history = await api(guest.token, 'GET', `/events/${event.id}/messages`);
  assert.equal(history.status, 200);
  assert.ok(
    (history.json.messages as Json[]).some((m) => m.id === messageId),
    'existing messages survive the block',
  );
});

// ── 6. Reports ───────────────────────────────────────────────────────────────

test('reports file against users, events, reviews and messages with references', async () => {
  const host = await makeHost('rpH');
  const event = await createHostEvent(host.token);
  const guest = await signUpAccount('rpG');
  const reader = await signUpAccount('rpR');

  // A completed booking lets the guest review the event (real fixture path).
  const booked = await api(guest.token, 'POST', `/events/${event.id}/bookings`, { seats: 1 });
  assert.equal(booked.status, 201);
  await exec(
    "UPDATE bookings SET status = 'completed' WHERE id = $1::UUID",
    [booked.json.booking.id as string],
  );
  const reviewed = await api(guest.token, 'POST', `/events/${event.id}/reviews`, {
    rating: 1,
    text: 'Awful experience, total scam of a dinner.',
  });
  assert.equal(reviewed.status, 201, JSON.stringify(reviewed.json));
  const reviewRow = await mustOne<{ id: string }>(
    'SELECT id FROM reviews WHERE event_id = $1::UUID AND author_id = $2::UUID',
    [event.id, guest.userId],
  );

  const msg = await api(guest.token, 'POST', `/events/${event.id}/messages`, {
    text: 'spam spam spam',
  });
  assert.equal(msg.status, 201);

  const cases: Array<[string, string, string]> = [
    ['user', guest.userId, 'harassment'],
    ['event', event.id as string, 'misleading_event_info'],
    ['review', reviewRow.id, 'spam'],
    ['message', msg.json.message.id as string, 'inappropriate_content'],
  ];
  for (const [targetType, targetId, reason] of cases) {
    const filed = await api(reader.token, 'POST', '/reports', {
      targetType,
      targetId,
      reason,
      description: `p2 suite checking the ${targetType} target`,
    });
    assert.equal(filed.status, 201, JSON.stringify(filed.json));
    const report = filed.json.report as Json;
    assert.match(report.reference, /^RP-[A-HJ-NP-Z0-9]{6}$/);
    assert.equal(report.targetType, targetType);
    assert.equal(report.status, 'pending');
    // The user-facing payload never carries the reporter or the evidence.
    assert.equal(report.reporterId, undefined);
    assert.equal(report.evidence, undefined);
  }

  // Evidence snapshots persisted for moderation even if targets vanish.
  const stored = await many<{ evidence: string; target_type: string }>(
    'SELECT target_type, evidence FROM reports WHERE reporter_id = $1::UUID',
    [reader.userId],
  );
  assert.equal(stored.length, 4);
  assert.ok(stored.every((r) => r.evidence.length > 0), 'evidence captured per target');
});

test('reports reject invalid targets, reasons, self-reports and duplicates', async () => {
  const host = await makeHost('rvH');
  const event = await createHostEvent(host.token);
  const stranger = await signUpAccount('rvS');

  // Garbage enums → 400 validation.
  const badReason = await api(stranger.token, 'POST', '/reports', {
    targetType: 'user',
    targetId: host.userId,
    reason: 'vibes',
  });
  assert.equal(badReason.status, 400);
  const badType = await api(stranger.token, 'POST', '/reports', {
    targetType: 'restaurant',
    targetId: host.userId,
    reason: 'spam',
  });
  assert.equal(badType.status, 400);

  // Unknown target ids → 404, per-type copy.
  const missing = await api(stranger.token, 'POST', '/reports', {
    targetType: 'event',
    targetId: randomUUID(),
    reason: 'spam',
  });
  assert.equal(missing.status, 404);
  assert.match(missing.json.error, /event/i);

  // A deleted (anonymised) profile cannot be reported.
  const victim = await signUpAccount('rvGone');
  assert.equal(
    (await api(victim.token, 'DELETE', '/users/me', { password: PASSWORD })).status,
    200,
  );
  const deleted = await api(stranger.token, 'POST', '/reports', {
    targetType: 'user',
    targetId: victim.userId,
    reason: 'spam',
  });
  assert.equal(deleted.status, 404, 'deleted shells are not reportable targets');

  // Self-report guard.
  const mine = await api(host.token, 'POST', '/reports', {
    targetType: 'event',
    targetId: event.id,
    reason: 'spam',
  });
  assert.equal(mine.status, 400);
  assert.match(mine.json.error, /own content/i);

  // Duplicate guard: one OPEN report per reporter+target, then 409.
  const first = await api(stranger.token, 'POST', '/reports', {
    targetType: 'user',
    targetId: host.userId,
    reason: 'harassment',
  });
  assert.equal(first.status, 201);
  const dup = await api(stranger.token, 'POST', '/reports', {
    targetType: 'user',
    targetId: host.userId,
    reason: 'harassment',
  });
  assert.equal(dup.status, 409);
  assert.match(dup.json.error, /already have an open report/i);
  const openRows = await many(
    "SELECT 1 FROM reports WHERE reporter_id = $1::UUID AND target_id = $2::UUID",
    [stranger.userId, host.userId],
  );
  assert.equal(openRows.length, 1, 'the queue never gets queue pollution');

  // Reports need a session.
  assert.equal((await api(null, 'POST', '/reports', {})).status, 401);
});

test('report history is private; moderation is super_admin-only and unlocks resolved targets', async () => {
  const host = await makeHost('hsH');
  const reporter = await signUpAccount('hsR');
  const nosy = await signUpAccount('hsN');
  const event = await createHostEvent(host.token);

  const filed = await api(reporter.token, 'POST', '/reports', {
    targetType: 'event',
    targetId: event.id,
    reason: 'unsafe_experience',
    description: 'no smoke exits visible in the photos',
  });
  assert.equal(filed.status, 201);
  const reportId = filed.json.report.id as string;
  const reference = filed.json.report.reference as string;

  // Own history shows it…
  const mine = await api(reporter.token, 'GET', '/users/me/reports');
  assert.equal(mine.status, 200);
  assert.equal(mine.json.count, 1);
  assert.equal(mine.json.reports[0].reference, reference);
  assert.equal(mine.json.reports[0].status, 'pending');

  // …nobody else's history reveals anything, and the reported host has no
  // endpoint that exposes the report or its reporter at all.
  const other = await api(nosy.token, 'GET', '/users/me/reports');
  assert.equal(other.json.count, 0);
  assert.equal((await api(nosy.token, 'GET', '/reports')).status, 403, 'queue needs super_admin');
  assert.equal((await api(reporter.token, 'GET', '/reports')).status, 403);
  assert.equal((await api(host.token, 'GET', '/reports')).status, 403);
  const patchAsUser = await api(nosy.token, 'PATCH', `/reports/${reportId}`, {
    status: 'dismissed',
  });
  assert.equal(patchAsUser.status, 403, 'regular users cannot moderate');

  // Mint a super_admin session straight in the DB (the seeded admin has no
  // password by design, so logins cannot produce its token).
  const adminSecret = `dc_admin_${randomUUID().replace(/-/g, '')}`;
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = 'super_admin' LIMIT 1`,
    [createHash('sha256').update(adminSecret).digest('hex')],
  );

  const queue = await api(adminSecret, 'GET', '/reports?status=pending');
  assert.equal(queue.status, 200);
  const queued = (queue.json.reports as Json[]).find((r) => r.id === reportId);
  assert.ok(queued, 'the queue shows the open report to the admin');
  assert.equal(queued.reporterId, reporter.userId, 'admin sees the reporter…');
  assert.ok(queued.evidence.includes('Trust Table'), '…plus the evidence snapshot');

  const advanced = await api(adminSecret, 'PATCH', `/reports/${reportId}`, {
    status: 'reviewing',
  });
  assert.equal(advanced.status, 200);
  assert.equal(advanced.json.report.status, 'reviewing');
  const resolved = await api(adminSecret, 'PATCH', `/reports/${reportId}`, {
    status: 'resolved',
  });
  assert.equal(resolved.status, 200);
  assert.equal(resolved.json.report.status, 'resolved');

  // The reporter sees the live status transition in their own history.
  const after = await api(reporter.token, 'GET', '/users/me/reports');
  assert.equal(after.json.reports[0].status, 'resolved');

  // Once closed, the same target may be flagged again (new reference).
  const second = await api(reporter.token, 'POST', '/reports', {
    targetType: 'event',
    targetId: event.id,
    reason: 'unsafe_experience',
  });
  assert.equal(second.status, 201, JSON.stringify(second.json));
  assert.notEqual(second.json.report.reference, reference);

  // Bad admin input is still validated.
  assert.equal(
    (await api(adminSecret, 'PATCH', `/reports/${reportId}`, { status: 'wontfix' })).status,
    400,
  );
});

// ── 7. Feedback & support ────────────────────────────────────────────────────

test('feedback files every category and persists it with an FB ticket', async () => {
  const me = await signUpAccount('fbA');
  const categories = [
    'bug',
    'feature',
    'booking',
    'payment',
    'restaurant_experience',
    'general',
  ];

  for (const category of categories) {
    const filed = await api(me.token, 'POST', '/feedback', {
      category,
      subject: `${category} check from the p2 suite`,
      description: 'A long enough description so validation lets this through.',
      relatedRef: category === 'booking' ? 'DC-TEST01' : '',
    });
    assert.equal(filed.status, 201, JSON.stringify(filed.json));
    assert.match(filed.json.feedback.ticket, /^FB-[A-HJ-NP-Z0-9]{6}$/);
    assert.equal(filed.json.feedback.status, 'open');
    assert.equal(filed.json.feedback.category, category);
  }

  const rows = await many<{ category: string }>(
    'SELECT category FROM feedback WHERE user_id = $1::UUID',
    [me.userId],
  );
  assert.equal(rows.length, categories.length, 'each ticket is a real DB row');
  const history = await api(me.token, 'GET', '/users/me/feedback');
  assert.equal(history.json.count, categories.length);
});

test('feedback validates its fields and refuses strangers', async () => {
  const a = await signUpAccount('fbB');
  const b = await signUpAccount('fbC');

  const shortSubject = await api(a.token, 'POST', '/feedback', {
    category: 'bug',
    subject: 'ab',
    description: 'long enough description here',
  });
  assert.equal(shortSubject.status, 400);

  const shortBody = await api(a.token, 'POST', '/feedback', {
    category: 'bug',
    subject: 'valid subject',
    description: 'tiny',
  });
  assert.equal(shortBody.status, 400);

  const badCategory = await api(a.token, 'POST', '/feedback', {
    category: 'vibes',
    subject: 'valid subject',
    description: 'long enough description here',
  });
  assert.equal(badCategory.status, 400);

  assert.equal((await api(null, 'POST', '/feedback', {})).status, 401, 'auth required');

  // A ticket is filed…
  const filed = await api(a.token, 'POST', '/feedback', {
    category: 'general',
    subject: 'Visible to me only',
    description: 'this ticket must never leak to another account',
  });
  assert.equal(filed.status, 201);

  // …and another account can neither see it nor move its status.
  const history = await api(b.token, 'GET', '/users/me/feedback');
  assert.equal(history.json.count, 0);
  assert.equal((await api(b.token, 'GET', '/feedback')).status, 403);
  assert.equal(
    (await api(b.token, 'PATCH', `/feedback/${filed.json.feedback.id}`, { status: 'resolved' }))
      .status,
    403,
    'users cannot move their own ticket, let alone someone else\u2019s',
  );

  // super_admin CAN triage it (status workflow is support-side only).
  const adminSecret = `dc_admin_${randomUUID().replace(/-/g, '')}`;
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = 'super_admin' LIMIT 1`,
    [createHash('sha256').update(adminSecret).digest('hex')],
  );
  const moved = await api(adminSecret, 'PATCH', `/feedback/${filed.json.feedback.id}`, {
    status: 'in_progress',
  });
  assert.equal(moved.status, 200);
  assert.equal(moved.json.feedback.status, 'in_progress');
  const refreshed = await api(a.token, 'GET', '/users/me/feedback');
  assert.equal(refreshed.json.feedback[0].status, 'in_progress');
});

// ── 8. Regressions: the rest of the app keeps working ────────────────────────

test('regression: auth, discovery, follow flow, and wallet survive the P2 changes', async () => {
  // Auth round-trip.
  const account = await signUpAccount('rgA');
  const login = await api(null, 'POST', '/auth/login', {
    email: account.email,
    password: PASSWORD,
  });
  assert.equal(login.status, 200);
  assert.equal((await api(login.json.token as string, 'GET', '/auth/me')).status, 200);

  // Discovery still returns the seeded world.
  const feed = await api(account.token, 'GET', '/events?limit=10');
  assert.equal(feed.status, 200);
  assert.ok((feed.json.events as Json[]).length > 0, 'seeded events still list');

  // Follow/unfollow round-trip for a NON-blocked pair still counts correctly.
  const friend = await signUpAccount('rgB');
  const followed = await api(account.token, 'POST', `/users/${friend.userId}/follow`);
  assert.equal(followed.status, 201);
  assert.equal(Number(followed.json.followers), 1);
  const unfollowed = await api(account.token, 'DELETE', `/users/${friend.userId}/follow`);
  assert.equal(unfollowed.status, 200);
  assert.equal(Number(unfollowed.json.followers), 0);

  // Host Studio + earnings wallet for a fresh host with a booked event.
  const host = await makeHost('rgH');
  const event = await createHostEvent(host.token);
  const guest = await signUpAccount('rgG');
  assert.equal(
    (await api(guest.token, 'POST', `/events/${event.id}/bookings`, { seats: 2 })).status,
    201,
  );
  const studio = await api(host.token, 'GET', `/hosts/${host.userId}/summary`);
  assert.equal(studio.status, 200, JSON.stringify(studio.json));
  const wallet = await api(host.token, 'GET', `/hosts/${host.userId}/wallet`);
  assert.equal(wallet.status, 200, JSON.stringify(wallet.json));
});
