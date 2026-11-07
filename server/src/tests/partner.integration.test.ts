/**
 * Partner App API contract suite.
 *
 * Runs the real Express API against an isolated, freshly seeded PostgreSQL
 * database and exercises the shared-backend contract the separate Partner App
 * codes against:
 *   * authorization: diners/hosts are refused, and a partner only ever sees the
 *     venues it belongs to (registration → staff invite → role ladder)
 *   * registration & verification: self-service signup, the admin queue, and
 *     the verified-only gates it unlocks (deals)
 *   * menu, table inventory and the reservation lifecycle, including the
 *     customer-facing availability that must agree with partner inventory
 *   * concurrency: two simultaneous requests for the last covers resolve to one
 *     booking and one 409, never two oversold rows
 *   * host event approvals: a venue that opts in intercepts host publishing,
 *     and the customer app cannot see or book a pending event
 *   * money: earnings/commission arithmetic and the payout history
 *   * response contract: `{ data, meta }` envelopes, pagination and statuses
 *
 * Execute from server/:  npm test
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { bootstrap, one, many, exec, type ApiHandle } from './util.js';

const handle: ApiHandle = await bootstrap();
const base = handle.base;
after(() => handle.close());

type Json = Record<string, any>;

const ROOFTOP = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
const DEMO_PASSWORD = 'dinecircle123';
const OPS_EMAIL = 'karachi.desk+demo@example.test';
const PASSWORD = 'correct horse battery staple';

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
async function signUpAccount(prefix = 'member'): Promise<{
  token: string; userId: string; email: string;
}> {
  seq += 1;
  const email = `partner_${prefix}_${seq}@example.com`;
  const { status, json } = await api(null, 'POST', '/auth/signup', {
    name: `Partner ${prefix}`,
    email,
    password: PASSWORD,
  });
  assert.equal(status, 201, `signup failed: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string, email };
}

/** The seeded platform admin has no password by design, so mint a session. */
async function mintAdminToken(): Promise<string> {
  const secret = `dc_partner_admin_${randomUUID().replace(/-/g, '')}`;
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = 'super_admin' LIMIT 1`,
    [createHash('sha256').update(secret).digest('hex')],
  );
  return secret;
}

async function makeHost(prefix: string): Promise<{ token: string; userId: string; email: string }> {
  const account = await signUpAccount(prefix);
  const promote = await api(account.token, 'POST', '/users/me/host');
  assert.equal(promote.status, 200, JSON.stringify(promote.json));
  return account;
}

/** A venue registered through the API, ready for the tests that need one. */
type Venue = { id: string; token: string; ownerId: string; branchId: string };

async function registerVenue(overrides: Json = {}): Promise<Venue> {
  const owner = await signUpAccount('venue');
  const created = await api(owner.token, 'POST', '/partner/restaurants', {
    name: `Partner Table ${seq}`,
    city: 'Lyon',
    seats: 2,
    address: '1 Rue de Test',
    timezone: 'Europe/Paris',
    ...overrides,
  });
  assert.equal(created.status, 201, `registration failed: ${JSON.stringify(created.json)}`);
  const id = created.json.data.restaurant.id as string;
  const branch = await one<{ id: string }>(
    `SELECT id FROM restaurant_branches WHERE restaurant_id = $1::UUID AND is_primary`,
    [id],
  );
  assert.ok(branch, 'registration must create a primary branch');
  return { id, token: owner.token, ownerId: owner.userId, branchId: branch.id };
}

/** Verifies a venue through the real admin queue (not a DB shortcut). */
async function verifyVenue(venueId: string, adminToken: string): Promise<void> {
  const queue = await api(adminToken, 'GET', '/partner/verification/requests?status=pending');
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  const request = (queue.json.data.requests as Json[])
    .find((r) => r.restaurantId === venueId);
  assert.ok(request, 'the pending request must appear in the admin queue');
  const review = await api(
    adminToken,
    'POST',
    `/partner/verification/requests/${request!.id}/review`,
    { decision: 'approved', reviewerNote: 'verified by the contract suite' },
  );
  assert.equal(review.status, 200, JSON.stringify(review.json));
}

// ── 1. Authorization ─────────────────────────────────────────────────────────

test('partner API refuses anonymous callers and plain diners', async () => {
  const diner = await signUpAccount('diner');

  const anonymous = await api(null, 'GET', '/partner/restaurants');
  assert.equal(anonymous.status, 401);

  const asDiner = await api(diner.token, 'GET', '/partner/restaurants');
  assert.equal(asDiner.status, 403);
  assert.match(asDiner.json.error, /partner/i);

  // Every partner surface is closed to a diner, including the ones that would
  // otherwise be reachable by guessing a venue id.
  for (const path of [
    `/partner/restaurants/${ROOFTOP}`,
    `/partner/restaurants/${ROOFTOP}/dashboard`,
    `/partner/restaurants/${ROOFTOP}/menu`,
    `/partner/restaurants/${ROOFTOP}/tables`,
    `/partner/restaurants/${ROOFTOP}/deals`,
    `/partner/restaurants/${ROOFTOP}/earnings`,
    `/partner/restaurants/${ROOFTOP}/reservations`,
    '/partner/analytics',
    '/partner/bookings',
  ]) {
    const res = await api(diner.token, 'GET', path);
    assert.equal(res.status, 403, `${path} should be closed, got ${res.status}`);
  }
});

test('a partner only reaches the venues it belongs to', async () => {
  const ops = await login(OPS_EMAIL, DEMO_PASSWORD);

  const list = await api(ops.token, 'GET', '/partner/restaurants');
  assert.equal(list.status, 200, JSON.stringify(list.json));
  const venues = list.json.data.restaurants as Json[];
  assert.ok(venues.length >= 10, 'the seeded partner desk owns 10 venues');
  assert.ok(venues.every((v) => v.myRole === 'owner'));

  // A venue owned by someone else is 403, not 404-with-data.
  const foreign = await api(ops.token, 'GET', `/partner/restaurants/${ROOFTOP}`);
  assert.equal(foreign.status, 403);

  // An id that does not exist is 404, the two cases stay distinguishable.
  const missing = await api(ops.token, 'GET', `/partner/restaurants/${randomUUID()}`);
  assert.equal(missing.status, 404);

  const foreignWrite = await api(ops.token, 'PATCH', `/partner/restaurants/${ROOFTOP}`, {
    tagline: 'hijacked',
  });
  assert.equal(foreignWrite.status, 403);
  const untouched = await one<{ tagline: string }>(
    'SELECT tagline FROM restaurants WHERE id = $1::UUID',
    [ROOFTOP],
  );
  assert.notEqual(untouched?.tagline, 'hijacked');
});

// ── 2. Registration & verification ───────────────────────────────────────────

test('registration creates an unverified venue, a branch and a queue entry', async () => {
  const venue = await registerVenue({ name: 'Fresh Partner Cafe', seats: 2 });

  const profile = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}`);
  assert.equal(profile.status, 200, JSON.stringify(profile.json));
  const restaurant = profile.json.data.restaurant;
  assert.equal(restaurant.partnershipStatus, 'pending_review');
  assert.equal(restaurant.verified, false);
  assert.equal(restaurant.myRole, 'owner');

  // The primary branch is exposed through its own collection (the Partner App
  // files tables and reservations against it).
  const branches = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/branches`);
  assert.equal(branches.status, 200, JSON.stringify(branches.json));
  const primary = (branches.json.data.branches as Json[]).find((b) => b.isPrimary);
  assert.equal(primary?.id, venue.branchId);
  assert.equal(primary?.timeZone, 'Europe/Paris');

  const request = await one<{ status: string }>(
    'SELECT status FROM partner_verification_requests WHERE restaurant_id = $1::UUID',
    [venue.id],
  );
  assert.equal(request?.status, 'pending');

  // Deals are a customer-facing promise: blocked until the venue is verified.
  const blocked = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/deals`, {
    title: 'Too early',
    value: 10,
    endsAt: new Date(Date.now() + 7 * 864e5).toISOString(),
  });
  assert.equal(blocked.status, 403);
  assert.match(blocked.json.error, /verified/i);
});

test('the admin queue verifies the venue and unlocks selling', async () => {
  const venue = await registerVenue({ name: 'Queue Partner Bistro' });
  const admin = await mintAdminToken();

  // Regression: `GET /:restaurantId` used to shadow this literal path, so the
  // queue answered 404 "Restaurant" for the id `verification`.
  const queue = await api(admin, 'GET', '/partner/verification/requests');
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  assert.ok((queue.json.data.requests as Json[]).some((r) => r.restaurantId === venue.id));

  await verifyVenue(venue.id, admin);

  const profile = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}`);
  assert.equal(profile.json.data.restaurant.verified, true);
  assert.equal(profile.json.data.restaurant.partnershipStatus, 'verified');

  // The desk is told, and the request cannot be reviewed twice.
  const note = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM notifications
      WHERE restaurant_id = $1::UUID AND category = 'verification'`,
    [venue.id],
  );
  assert.equal(note?.count, 1);

  const again = await api(admin, 'POST', `/partner/verification/requests/${
    (await one<{ id: string }>(
      'SELECT id FROM partner_verification_requests WHERE restaurant_id = $1::UUID',
      [venue.id],
    ))!.id
  }/review`, { decision: 'approved' });
  assert.equal(again.status, 409);
});

// ── 3. Staff membership & role ladder ────────────────────────────────────────

test('staff membership grants venue access but never manager powers', async () => {
  const venue = await registerVenue({ name: 'Staff Ladder Grill' });
  const recruit = await signUpAccount('recruit');

  // Before the invite the account has no partner reach at all.
  const before = await api(recruit.token, 'GET', `/partner/restaurants/${venue.id}`);
  assert.equal(before.status, 403);

  const invite = await api(recruit.token === '' ? '' : venue.token, 'POST',
    `/partner/restaurants/${venue.id}/staff`,
    { email: recruit.email, role: 'staff' });
  assert.equal(invite.status, 201, JSON.stringify(invite.json));

  // An unaccepted invite is inert: it must not confer access yet.
  const pending = await api(recruit.token, 'GET', `/partner/restaurants/${venue.id}`);
  assert.equal(pending.status, 403);

  const accept = await api(recruit.token, 'POST',
    `/partner/restaurants/${venue.id}/staff/accept`);
  assert.equal(accept.status, 200, JSON.stringify(accept.json));

  // Day-of operations: read the venue, see tables and reservations.
  const dashboard = await api(recruit.token, 'GET', `/partner/restaurants/${venue.id}/dashboard`);
  assert.equal(dashboard.status, 200, JSON.stringify(dashboard.json));
  assert.equal(dashboard.json.data.restaurant.id, venue.id);

  // …but not change the profile, the menu or the table inventory.
  const profileWrite = await api(recruit.token, 'PATCH',
    `/partner/restaurants/${venue.id}`, { tagline: 'staff edited this' });
  assert.equal(profileWrite.status, 403);
  const table = await api(recruit.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: 'S-01', seats: 4,
  });
  assert.equal(table.status, 403);

  // Membership does not leak across venues either.
  const other = await registerVenue({ name: 'Unrelated Kitchen' });
  const crossVenue = await api(recruit.token, 'GET', `/partner/restaurants/${other.id}`);
  assert.equal(crossVenue.status, 403);
});

// ── 4. Menu management ───────────────────────────────────────────────────────

test('menu sections, items and the 86-list keep prices server-side', async () => {
  const venue = await registerVenue({ name: 'Menu Contract Cafe' });

  const section = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/menu/sections`, {
    name: 'Small plates',
  });
  assert.equal(section.status, 201, JSON.stringify(section.json));
  const sectionId = section.json.data.section.id as string;

  const item = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/menu/items`, {
    sectionId,
    name: 'Cured trout',
    price: 18.5,
    dietaryTags: ['gluten-free'],
  });
  assert.equal(item.status, 201, JSON.stringify(item.json));
  assert.equal(item.json.data.item.price, 18.5);

  const bad = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/menu/items`, {
    sectionId,
    name: 'Negative price',
    price: -4,
  });
  assert.equal(bad.status, 400, 'a negative price must be rejected');

  const menu = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/menu`);
  assert.equal(menu.status, 200);
  const sections = menu.json.data.sections as Json[];
  assert.equal(sections.length, 1);
  assert.equal((sections[0]!.items as Json[]).length, 1);

  // An item id from another venue must not be writable through this route.
  const otherVenue = await registerVenue({ name: 'Menu Isolation Diner' });
  const cross = await api(otherVenue.token, 'POST',
    `/partner/restaurants/${otherVenue.id}/menu/availability`,
    { itemIds: [item.json.data.item.id as string], isAvailable: false });
  assert.equal(cross.status, 200);
  const stillAvailable = await one<{ is_available: boolean }>(
    'SELECT is_available FROM restaurant_menu_items WHERE id = $1::UUID',
    [item.json.data.item.id],
  );
  assert.equal(stillAvailable?.is_available, true, 'the other venue touched nothing');
});

// ── 5. Tables, reservations & concurrency ────────────────────────────────────

test('table inventory and reservations agree with customer availability', async () => {
  const venue = await registerVenue({ name: 'Covers Contract Trattoria' });

  // Two seats, one table, so capacity is unambiguous.
  const table = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: 'T-01', seats: 2, zone: 'Main', branchId: venue.branchId,
  });
  assert.equal(table.status, 201, JSON.stringify(table.json));

  const duplicate = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: 'T-01', seats: 2,
  });
  assert.equal(duplicate.status, 409, 'table labels are unique per venue');

  const date = new Date(Date.now() + 3 * 864e5).toISOString().slice(0, 10);
  const customer = await api(null, 'GET',
    `/restaurants/${venue.id}/availability?date=${date}&partySize=2`);
  assert.equal(customer.status, 401, 'the customer app reads availability signed in');

  const diner = await signUpAccount('resGuest');
  const availability = await api(diner.token, 'GET',
    `/restaurants/${venue.id}/availability?date=${date}&partySize=2`);
  assert.equal(availability.status, 200, JSON.stringify(availability.json));
  assert.equal(availability.json.data.capacity, 2, 'capacity comes from live tables');

  const startAt = new Date(Date.now() + 3 * 864e5);
  startAt.setUTCHours(19, 0, 0, 0);

  const booking = await api(diner.token, 'POST', `/restaurants/${venue.id}/reservations`, {
    partySize: 2,
    startAt: startAt.toISOString(),
    branchId: venue.branchId,
  });
  assert.equal(booking.status, 201, JSON.stringify(booking.json));
  const reservationId = booking.json.data.reservation.id as string;
  assert.equal(booking.json.data.reservation.status, 'pending');

  // The desk sees the same row…
  const deskList = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/reservations`);
  assert.equal(deskList.status, 200);
  assert.ok((deskList.json.data.reservations as Json[]).some((r) => r.id === reservationId));

  // …and its confirmation lands back in the diner's list.
  const confirm = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/reservations/${reservationId}/confirm`);
  assert.equal(confirm.status, 200, JSON.stringify(confirm.json));
  assert.equal(confirm.json.data.reservation.status, 'confirmed');

  const mine = await api(diner.token, 'GET', '/users/me/reservations');
  const reflected = (mine.json.data.reservations as Json[]).find((r) => r.id === reservationId);
  assert.equal(reflected?.status, 'confirmed');

  // Illegal transitions are refused: a confirmed booking cannot skip to done.
  const skip = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/reservations/${reservationId}/complete`);
  assert.equal(skip.status, 409);

  const seat = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/reservations/${reservationId}/seat`);
  assert.equal(seat.status, 200);
  const complete = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/reservations/${reservationId}/complete`);
  assert.equal(complete.status, 200);
  assert.equal(complete.json.data.reservation.status, 'completed');
});

test('concurrent requests for the last covers book exactly one table', async () => {
  const venue = await registerVenue({ name: 'Concurrency Contract Bar' });
  await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: 'ONLY', seats: 2,
  });

  const startAt = new Date(Date.now() + 4 * 864e5);
  startAt.setUTCHours(20, 0, 0, 0);

  // Five desks tapping "book" for the same slot at the same instant.
  const attempts = await Promise.all(
    Array.from({ length: 5 }, (_, i) =>
      api(venue.token, 'POST', `/partner/restaurants/${venue.id}/reservations`, {
        guestName: `Walk-in ${i}`,
        partySize: 2,
        startAt: startAt.toISOString(),
      }).then((r) => r)),
  );

  const created = attempts.filter((r) => r.status === 201);
  const rejected = attempts.filter((r) => r.status === 409);
  assert.equal(created.length, 1, `expected exactly one booking, got ${created.length}`);
  assert.equal(rejected.length, 4, 'the rest must be refused with 409');

  const held = await one<{ held: number }>(
    `SELECT COALESCE(SUM(party_size), 0)::int AS held FROM table_reservations
      WHERE restaurant_id = $1::UUID AND status = ANY($2::text[])`,
    [venue.id, ['pending', 'confirmed', 'seated']],
  );
  assert.equal(held?.held, 2, 'the venue is never oversold');
});

// ── 6. Host event approvals ──────────────────────────────────────────────────

test('a venue that opts in intercepts host publishing and keeps it non-bookable', async () => {
  const venue = await registerVenue({ name: 'Approval Contract Hall' });
  const admin = await mintAdminToken();
  await verifyVenue(venue.id, admin);

  const policy = await api(venue.token, 'PATCH', `/partner/restaurants/${venue.id}`, {
    requiresHostApproval: true,
  });
  assert.equal(policy.status, 200, JSON.stringify(policy.json));
  assert.equal(policy.json.data.restaurant.requiresHostApproval, true);

  const host = await makeHost('request');
  const startAt = new Date(Date.now() + 8 * 864e5).toISOString();
  const created = await api(host.token, 'POST', '/events', {
    title: 'Approval Needed Supper',
    tagline: 'contract fixture',
    description: 'a host event that the venue must approve before it is bookable',
    coverImage: 'assets/images/dish_steak.png',
    restaurantId: venue.id,
    startAt,
    seatsTotal: 8,
    pricePerSeat: 55,
    audience: 'public',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  const eventId = created.json.event.id as string;
  assert.equal(created.json.event.status, 'requested', 'opt-in venues see requests first');

  const diner = await signUpAccount('requestGuest');
  const hidden = await api(diner.token, 'GET', `/events/${eventId}`);
  assert.equal(hidden.status, 404, 'a pending event is not public yet');
  const cannotBook = await api(diner.token, 'POST', `/bookings`, { eventId, seats: 1 });
  assert.equal(cannotBook.status, 404, 'and it cannot be booked through a stale link');

  const queue = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/event-requests`);
  assert.equal(queue.status, 200, JSON.stringify(queue.json));
  const request = (queue.json.data.requests as Json[]).find((r) => r.id === eventId);
  assert.ok(request, 'the request is in the venue queue');
  assert.equal(request!.hostName, 'Partner request');

  const approve = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/event-requests/${eventId}/approve`);
  assert.equal(approve.status, 200, JSON.stringify(approve.json));
  assert.equal(approve.json.data.request.status, 'confirmed');

  const nowVisible = await api(diner.token, 'GET', `/events/${eventId}`);
  assert.equal(nowVisible.status, 200, 'approval publishes the event to diners');

  const again = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/event-requests/${eventId}/approve`);
  assert.equal(again.status, 409, 'a decision is final');

  const note = await one<{ count: number }>(
    `SELECT count(*)::int AS count FROM activity
      WHERE event_id = $1::UUID AND actor_id = $2::UUID AND kind = 'approval'`,
    [eventId, host.userId],
  );
  assert.equal(note?.count, 1, 'the host is told in their own activity feed');

  // Declining is symmetric and keeps the reason.
  const second = await api(host.token, 'POST', '/events', {
    title: 'Declined Supper',
    coverImage: 'assets/images/dish_pasta.png',
    restaurantId: venue.id,
    startAt: new Date(Date.now() + 9 * 864e5).toISOString(),
    seatsTotal: 4,
    pricePerSeat: 30,
    audience: 'public',
  });
  assert.equal(second.status, 201, JSON.stringify(second.json));
  const secondId = second.json.event.id as string;

  const decline = await api(venue.token, 'POST',
    `/partner/restaurants/${venue.id}/event-requests/${secondId}/decline`,
    { reason: 'Kitchen is closed that night' });
  assert.equal(decline.status, 200, JSON.stringify(decline.json));
  assert.equal(decline.json.data.request.status, 'declined');

  const declined = await one<{ status: string; decline_reason: string }>(
    'SELECT status, decline_reason FROM dinner_events WHERE id = $1::UUID',
    [secondId],
  );
  assert.equal(declined?.status, 'declined');
  assert.match(declined!.decline_reason, /Kitchen is closed/);
});

test('venues without the opt-in keep publishing host events immediately', async () => {
  const venue = await registerVenue({ name: 'Auto Approve Bistro' });
  await verifyVenue(venue.id, await mintAdminToken());

  const host = await makeHost('auto');
  const created = await api(host.token, 'POST', '/events', {
    title: 'Auto Confirmed Supper',
    coverImage: 'assets/images/dish_tacos.png',
    restaurantId: venue.id,
    startAt: new Date(Date.now() + 10 * 864e5).toISOString(),
    seatsTotal: 6,
    pricePerSeat: 40,
    audience: 'public',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  assert.equal(created.json.event.status, 'confirmed', 'default policy is unchanged');
});

// ── 7. Deals ─────────────────────────────────────────────────────────────────

test('deal validation, publish transitions and code uniqueness', async () => {
  const venue = await registerVenue({ name: 'Deals Contract Lounge' });
  await verifyVenue(venue.id, await mintAdminToken());
  const inAWeek = () => new Date(Date.now() + 7 * 864e5).toISOString();

  const over100 = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/deals`, {
    title: 'Impossible discount', kind: 'percent', value: 150, endsAt: inAWeek(),
  });
  assert.equal(over100.status, 400, 'a percent deal above 100 is rejected');

  const past = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/deals`, {
    title: 'Expired already', kind: 'fixed', value: 10,
    endsAt: new Date(Date.now() - 864e5).toISOString(),
  });
  assert.equal(past.status, 400);

  const draft = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/deals`, {
    title: 'Two for one', kind: 'package', value: 45, code: 'twosome', endsAt: inAWeek(),
  });
  assert.equal(draft.status, 201, JSON.stringify(draft.json));
  assert.equal(draft.json.data.deal.status, 'draft');
  assert.equal(draft.json.data.deal.code, 'TWOSOME', 'codes are normalised');
  const dealId = draft.json.data.deal.id as string;

  const duplicate = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/deals`, {
    title: 'Copycat', kind: 'fixed', value: 5, code: 'TWOSOME', endsAt: inAWeek(),
  });
  assert.equal(duplicate.status, 409, 'one code per venue');

  const publish = await api(venue.token, 'PATCH',
    `/partner/restaurants/${venue.id}/deals/${dealId}`, { status: 'active' });
  assert.equal(publish.status, 200, JSON.stringify(publish.json));
  assert.equal(publish.json.data.deal.status, 'active');

  const pause = await api(venue.token, 'PATCH',
    `/partner/restaurants/${venue.id}/deals/${dealId}`, { status: 'paused' });
  assert.equal(pause.status, 200);

  const resume = await api(venue.token, 'PATCH',
    `/partner/restaurants/${venue.id}/deals/${dealId}`, { status: 'active' });
  assert.equal(resume.status, 200);

  // An active deal is retired, never destroyed: redemptions are money history.
  const retire = await api(venue.token, 'DELETE',
    `/partner/restaurants/${venue.id}/deals/${dealId}`);
  assert.equal(retire.status, 200);
  assert.equal(retire.json.data.status, 'expired');
  const stillThere = await one<{ status: string }>(
    'SELECT status FROM restaurant_deals WHERE id = $1::UUID', [dealId],
  );
  assert.equal(stillThere?.status, 'expired');

  const list = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/deals?limit=1&page=1`);
  assert.equal(list.status, 200);
  assert.deepEqual(
    { page: list.json.meta.page, limit: list.json.meta.limit, hasMore: list.json.meta.hasMore },
    { page: 1, limit: 1, hasMore: list.json.meta.total > 1 },
  );
});

// ── 8. Earnings & payouts ────────────────────────────────────────────────────

test('earnings report the venue share of captured revenue', async () => {
  const venue = await registerVenue({ name: 'Earnings Contract Grill' });
  await verifyVenue(venue.id, await mintAdminToken());

  const host = await makeHost('earner');
  const event = await api(host.token, 'POST', '/events', {
    title: 'Earnings Supper',
    coverImage: 'assets/images/dish_sushi.png',
    restaurantId: venue.id,
    startAt: new Date(Date.now() + 11 * 864e5).toISOString(),
    seatsTotal: 20,
    pricePerSeat: 100,
    audience: 'public',
  });
  assert.equal(event.status, 201, JSON.stringify(event.json));
  const eventId = event.json.event.id as string;

  // Bookings straight into the venue's event: 3 x 100 paid, 1 x 100 refunded.
  const guest = await signUpAccount('earnGuest');
  for (const paymentStatus of ['paid', 'paid', 'paid', 'paid']) {
    await exec(
      `INSERT INTO bookings (event_id, user_id, seats, price_per_seat, total_amount,
                             reference, payment_status, status)
       VALUES ($1::UUID, $2::UUID, 1, 100, 100, $3, $4, 'confirmed')`,
      [eventId, guest.userId, `PRT-${randomUUID().slice(0, 8)}`, paymentStatus],
    );
  }
  const refunded = await one<{ id: string }>(
    'SELECT id FROM bookings WHERE event_id = $1::UUID LIMIT 1', [eventId],
  );
  await exec(
    `INSERT INTO refunds (booking_id, event_id, guest_id, amount, reason, status)
     VALUES ($1::UUID, $2::UUID, $3::UUID, 100, 'guest_cancel', 'refunded')`,
    [refunded!.id, eventId, guest.userId],
  );

  const earnings = await api(venue.token, 'GET',
    `/partner/restaurants/${venue.id}/earnings?from=${
      new Date(Date.now() - 864e5).toISOString()}&to=${
      new Date(Date.now() + 864e5).toISOString()}`);
  assert.equal(earnings.status, 200, JSON.stringify(earnings.json));
  const report = earnings.json.data.earnings;
  assert.equal(report.gross, 400);
  assert.equal(report.refunds, 100);
  assert.equal(report.commissionRate, 0.1);
  assert.equal(report.commission, 30, 'commission is charged on gross minus refunds');
  assert.equal(report.net, 270);
  assert.equal(report.bookings, 4);

  const payouts = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/payouts`);
  assert.equal(payouts.status, 200);
  assert.deepEqual(payouts.json.data.payouts, [], 'nothing has been settled yet');

  // A staff-level account is not allowed to read money.
  const recruit = await signUpAccount('earnStaff');
  await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/staff`,
    { email: recruit.email, role: 'staff' });
  await api(recruit.token, 'POST', `/partner/restaurants/${venue.id}/staff/accept`);
  const denied = await api(recruit.token, 'GET',
    `/partner/restaurants/${venue.id}/earnings`);
  assert.equal(denied.status, 403, 'earnings need manager or owner');
});

// ── 9. Dashboard ─────────────────────────────────────────────────────────────

test('the dashboard aggregates live numbers for the venue', async () => {
  const venue = await registerVenue({ name: 'Dashboard Contract Bar' });
  await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: 'D-01', seats: 4,
  });

  const startAt = new Date(Date.now() + 5 * 864e5);
  startAt.setUTCHours(19, 30, 0, 0);
  const booking = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/reservations`, {
    guestName: 'Dashboard Guest', partySize: 3, startAt: startAt.toISOString(),
  });
  assert.equal(booking.status, 201, JSON.stringify(booking.json));

  const dashboard = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/dashboard`);
  assert.equal(dashboard.status, 200, JSON.stringify(dashboard.json));
  const data = dashboard.json.data;

  assert.equal(data.restaurant.id, venue.id);
  assert.equal(data.today.capacity, 4);
  assert.equal(data.today.tables, 1);
  assert.equal(data.today.timeZone, 'Europe/Paris');

  // The dashboard is scoped to the venue's own service date, so a booking five
  // days out must not inflate today's covers.
  assert.equal(data.today.reservations.pending, 0);
  assert.equal(data.today.covers, 0);

  // Today's service row is seeded directly: the booking API refuses past start
  // times and "today" is the variable under test here (creation is covered in
  // the reservation test above). The date comes from the API, not the clock.
  await exec(
    `INSERT INTO table_reservations
       (restaurant_id, user_id, guest_name, guest_phone, party_size, start_at,
        duration_minutes, status, reference, notes, source)
     VALUES ($1::UUID, $2::UUID, 'Dashboard Three', '', 3,
             ($3::date + interval '19 hours') AT TIME ZONE $4,
             90, 'pending', 'TR-DASH1', '', 'partner')`,
    [venue.id, venue.ownerId, data.today.date, data.today.timeZone],
  );

  const again = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/dashboard`);
  assert.equal(again.status, 200, JSON.stringify(again.json));
  const service = again.json.data.today;
  assert.equal(service.reservations.pending, 1);
  assert.equal(service.covers, 3);
  assert.equal(service.occupancy, 0.75);
  assert.equal(again.json.data.notifications.unread >= 0, true);
  assert.equal(again.json.data.earnings.commissionRate, 0.1);
});

// ── 10. Contract details ─────────────────────────────────────────────────────

test('partner responses keep the { data, meta } envelope and honest status codes', async () => {
  const venue = await registerVenue({ name: 'Envelope Contract Cafe' });

  const list = await api(venue.token, 'GET', `/partner/restaurants/${venue.id}/tables`);
  assert.equal(list.status, 200);
  assert.ok(Array.isArray(list.json.data.tables));
  assert.equal(typeof list.json.meta.total, 'number');

  const invalid = await api(venue.token, 'POST', `/partner/restaurants/${venue.id}/tables`, {
    label: '', seats: 0,
  });
  assert.equal(invalid.status, 400);
  assert.ok(invalid.json.error, 'errors always carry a message');

  const unknownRestaurant = await api(venue.token, 'POST',
    `/partner/restaurants/${randomUUID()}/tables`, { label: 'X', seats: 2 });
  assert.equal(unknownRestaurant.status, 404);

  // Cross-venue table ids are not addressable from another partner's session.
  const other = await registerVenue({ name: 'Envelope Isolation Cafe' });
  const foreignTable = await api(other.token, 'POST',
    `/partner/restaurants/${venue.id}/tables`, { label: 'Y', seats: 2 });
  assert.equal(foreignTable.status, 403);

  const rows = await many<{ count: number }>(
    'SELECT count(*)::int AS count FROM restaurant_tables WHERE restaurant_id = $1::UUID',
    [venue.id],
  );
  assert.equal(rows[0]?.count, 0, 'the refused write created nothing');
});

// ── 11. Legacy operations surface ────────────────────────────────────────────

test('the operations surface shares one envelope and notifications can be acknowledged', async () => {
  const ops = await login(OPS_EMAIL, DEMO_PASSWORD);

  // One envelope for every partner endpoint: the Partner App should not have to
  // special-case the operations routes inherited from the original surface.
  for (const path of ['/partner/events', '/partner/bookings', '/partner/menus']) {
    const res = await api(ops.token, 'GET', path);
    assert.equal(res.status, 200, `${path}: ${JSON.stringify(res.json)}`);
    assert.ok(res.json.data, `${path} must nest its payload under data`);
    assert.equal(typeof res.json.meta.total, 'number', `${path} must carry meta.total`);
  }

  const analytics = await api(ops.token, 'GET', '/partner/analytics');
  assert.equal(analytics.status, 200, JSON.stringify(analytics.json));
  assert.equal(typeof analytics.json.data.analytics.totalRevenue, 'number');
  assert.ok(Array.isArray(analytics.json.data.recentBookings));

  // A PATCH with nothing to change is a client bug, not a silent 200.
  const managed = (await api(ops.token, 'GET', '/partner/restaurants')).json
    .data.restaurants[0];
  const event = await api(ops.token, 'POST', '/partner/events', {
    restaurantId: managed.id,
    title: 'Envelope Contract Tasting',
    startAt: new Date(Date.now() + 6 * 864e5).toISOString(),
    endAt: new Date(Date.now() + 6 * 864e5 + 7200_000).toISOString(),
    seatsTotal: 2,
    pricePerSeat: 50,
  });
  assert.equal(event.status, 201, JSON.stringify(event.json));
  assert.equal(event.json.data.event.restaurantId, managed.id);

  const empty = await api(ops.token, 'PUT', `/partner/events/${event.json.data.event.id}`, {});
  assert.equal(empty.status, 400);

  // Notification read-state: the dashboard's unread badge must be clearable.
  const venue = await registerVenue({ name: 'Inbox Contract Kitchen' });
  await verifyVenue(venue.id, await mintAdminToken());

  const inbox = await api(venue.token, 'GET', '/partner/notifications');
  assert.equal(inbox.status, 200, JSON.stringify(inbox.json));
  assert.equal(inbox.json.meta.total, 1);
  assert.equal(inbox.json.meta.unread, 1);
  const note = inbox.json.data.notifications[0];
  assert.equal(note.read, false);

  // Another partner cannot acknowledge a notification it cannot see.
  const foreign = await api(ops.token, 'POST', `/partner/notifications/${note.id}/read`);
  assert.equal(foreign.status, 404);

  const read = await api(venue.token, 'POST', `/partner/notifications/${note.id}/read`);
  assert.equal(read.status, 200, JSON.stringify(read.json));
  assert.equal(read.json.data.notification.read, true);

  const cleared = await api(venue.token, 'GET', '/partner/notifications');
  assert.equal(cleared.json.meta.unread, 0);

  await exec(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'Unread probe', '', 'general', false)`,
    [venue.id],
  );
  const swept = await api(venue.token, 'POST', '/partner/notifications/read-all');
  assert.equal(swept.status, 200);
  assert.equal(swept.json.data.updated, 1);
  const drained = await api(venue.token, 'GET', '/partner/notifications');
  assert.equal(drained.json.meta.unread, 0);

  // Even the notification inbox is behind the partner gate.
  const diner = await signUpAccount('inbox');
  const asDiner = await api(diner.token, 'POST', '/partner/notifications/read-all');
  assert.equal(asDiner.status, 403);
});
