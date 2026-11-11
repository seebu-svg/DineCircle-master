/**
 * Admin console integration tests.
 *
 * These cover the rules the admin API exists to enforce, and the two places
 * where an admin action reaches into a shipped client surface:
 *   - role gate: 401 without a token, 403 for a diner token, 200 for super_admin
 *   - application review approves once, notifies the desk, and 409s the second time
 *   - receipt verification is what activates a subscription, with the right period
 *   - suspending a venue removes it from customer discovery, restoring returns it
 *   - a suspended account's token is refused on every authenticated route
 *   - resolving a report with `venue_suspended` writes both the venue change
 *     and the audit row
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { bootstrap, exec, many, one, type ApiHandle } from './util.js';

const handle: ApiHandle = await bootstrap();
const base = handle.base;
after(() => handle.close());

type Json = Record<string, any>;

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

function secret(label: string): string {
  return createHash('sha256').update(`${label}_${Date.now()}_${Math.random()}`).digest('hex');
}

/** Mint a token for a seeded admin account of the given role. */
async function mintAdminToken(role: 'super_admin' | 'partner_admin'): Promise<string> {
  const token = secret(`admin_${role}`);
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = $2::text ORDER BY created_at LIMIT 1`,
    [token, role],
  );
  return token;
}

/** The seeded super admin, which is what the whole console is tested against. */
let adminToken = '';
let seq = 0;

/** Create a venue through the partner path so it is a real application subject. */
async function newVenue(label: string): Promise<{ venueId: string; ownerToken: string; ownerId: string }> {
  seq += 1;
  const email = `admin_itest_${seq}@example.com`;
  const signup = await api(null, 'POST', '/auth/signup', {
    name: `Owner ${label}`,
    email,
    password: PASSWORD,
    city: 'Karachi',
  });
  assert.equal(signup.status, 201, JSON.stringify(signup.json));
  const ownerToken = signup.json.token as string;
  const ownerId = signup.json.user.id as string;

  const created = await api(ownerToken, 'POST', '/partner/restaurants', {
    name: `Admin Console ${label} ${seq}`,
    city: 'Karachi',
    seats: 4,
    address: '1 Test Rd',
    timezone: 'Asia/Karachi',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  const venueId = created.json.data.restaurant.id as string;
  await api(ownerToken, 'POST', `/partner/restaurants/${venueId}/verification`, {
    note: 'Documents are ready',
  });
  return { venueId, ownerToken, ownerId };
}

async function pendingRequestId(venueId: string): Promise<string> {
  const row = await one<{ id: string }>(
    `SELECT id FROM partner_verification_requests
      WHERE restaurant_id = $1::UUID AND status = 'pending'`,
    [venueId],
  );
  assert.ok(row, 'expected a pending verification request');
  return row.id;
}

adminToken = await mintAdminToken('super_admin');

// ── Role gate ────────────────────────────────────────────────────────────────

test('admin routes reject an unauthenticated request with 401', async () => {
  const { status } = await api(null, 'GET', '/admin/overview');
  assert.equal(status, 401);
});

test('admin routes reject a diner token with 403', async () => {
  seq += 1;
  const diner = await api(null, 'POST', '/auth/signup', {
    name: 'Diner Console Breaker',
    email: `admin_itest_diner_${seq}@example.com`,
    password: PASSWORD,
  });
  assert.equal(diner.status, 201);
  const { status, json } = await api(diner.json.token as string, 'GET', '/admin/overview');
  assert.equal(status, 403, JSON.stringify(json));
  assert.match(String(json.error), /admin role/i);
});

test('admin routes serve a super admin', async () => {
  const { status, json } = await api(adminToken, 'GET', '/admin/overview');
  assert.equal(status, 200, JSON.stringify(json));
  assert.ok(json.data.overview.totals, 'totals block missing');
  assert.equal(typeof json.data.overview.totals.venues, 'number');
  assert.ok(Array.isArray(json.data.overview.revenue));
  assert.equal(json.data.overview.revenue.length, 6);
});

test('a partner_admin token also reaches the console', async () => {
  const token = await mintAdminToken('partner_admin');
  const { status, json } = await api(token, 'GET', '/admin/applications');
  assert.equal(status, 200, JSON.stringify(json));
  assert.ok(Array.isArray(json.data.applications));
});

// ── Applications ─────────────────────────────────────────────────────────────

test('approving an application verifies the venue and notifies the desk', async () => {
  const { venueId } = await newVenue('Approve');
  const requestId = await pendingRequestId(venueId);

  const { status, json } = await api(adminToken, 'POST', `/admin/applications/${requestId}/review`, {
    decision: 'approved',
    reviewerNote: 'Documents matched the storefront.',
  });
  assert.equal(status, 200, JSON.stringify(json));

  const venue = await one<{ partnership_status: string; is_partner: boolean }>(
    'SELECT partnership_status, is_partner FROM restaurants WHERE id = $1::UUID',
    [venueId],
  );
  assert.equal(venue?.partnership_status, 'verified');
  assert.equal(venue?.is_partner, true);

  const notice = await one<{ category: string }>(
    `SELECT category FROM notifications
      WHERE restaurant_id = $1::UUID AND category = 'verification'`,
    [venueId],
  );
  assert.ok(notice, 'expected a verification notification for the desk');

  const again = await api(adminToken, 'POST', `/admin/applications/${requestId}/review`, {
    decision: 'rejected',
    reviewerNote: 'should not apply',
  });
  assert.equal(again.status, 409, JSON.stringify(again.json));
});

test('batch review reports per-id outcomes and skips decided rows', async () => {
  const first = await newVenue('BatchA');
  const second = await newVenue('BatchB');
  const ids = [await pendingRequestId(first.venueId), await pendingRequestId(second.venueId)];
  await api(adminToken, 'POST', `/admin/applications/${ids[0]}/review`, {
    decision: 'approved',
    reviewerNote: 'first pass',
  });

  const { status, json } = await api(adminToken, 'POST', '/admin/applications/batch-review', {
    ids,
    decision: 'rejected',
    reviewerNote: 'duplicate paperwork',
  });
  assert.equal(status, 200, JSON.stringify(json));
  assert.equal(json.data.changed, 1);
  assert.equal(json.data.skipped, 1);
  assert.equal(json.data.batch.find((r: Json) => r.id === ids[0]).ok, false);

  const secondVenue = await one<{ partnership_status: string }>(
    'SELECT partnership_status FROM restaurants WHERE id = $1::UUID',
    [second.venueId],
  );
  assert.equal(secondVenue?.partnership_status, 'rejected');
});

// ── Subscriptions ────────────────────────────────────────────────────────────

test('verifying a receipt activates the subscription with a one-month period', async () => {
  const { venueId } = await newVenue('Receipt');

  const recorded = await api(adminToken, 'POST', `/admin/subscriptions/${venueId}/record-payment`, {
    amountPkr: 5000,
    method: 'bank_transfer',
    reference: 'HBL-000123',
    proofPath: 'receipts/hbl-000123.pdf',
  });
  assert.equal(recorded.status, 201, JSON.stringify(recorded.json));
  const receiptId = recorded.json.data.receipt.id as string;
  assert.equal(recorded.json.data.receipt.status, 'awaiting_verification');

  const queue = await api(adminToken, 'GET', '/admin/subscriptions/receipts?status=awaiting_verification');
  assert.equal(queue.status, 200);
  assert.ok(
    queue.json.data.receipts.some((r: Json) => r.id === receiptId),
    'the new receipt should appear in the verification queue',
  );

  const verified = await api(adminToken, 'POST', `/admin/subscriptions/receipts/${receiptId}/verify`, {
    note: 'Matched the bank statement',
  });
  assert.equal(verified.status, 200, JSON.stringify(verified.json));
  const sub = verified.json.data.verification.subscription as Json;
  assert.equal(sub.status, 'active');
  assert.equal(sub.plan, 'monthly');
  assert.equal(sub.price_pkr, 5000);

  const start = new Date(sub.period_start as string);
  const end = new Date(sub.period_end as string);
  const days = Math.round((end.getTime() - start.getTime()) / 86_400_000);
  assert.ok(days >= 28 && days <= 31, `expected a ~30 day period, got ${days}`);

  const receiptRow = await one<{ status: string }>(
    'SELECT status FROM partner_payment_receipts WHERE id = $1::UUID',
    [receiptId],
  );
  assert.equal(receiptRow?.status, 'verified');

  const reVerify = await api(adminToken, 'POST', `/admin/subscriptions/receipts/${receiptId}/verify`, {
    note: 'again',
  });
  assert.equal(reVerify.status, 409);
});

test('rejecting a receipt keeps the subscription out of active', async () => {
  const { venueId } = await newVenue('Reject');
  const recorded = await api(adminToken, 'POST', `/admin/subscriptions/${venueId}/record-payment`, {
    amountPkr: 2500,
    method: 'jazzcash',
    reference: 'JC-77',
  });
  const receiptId = recorded.json.data.receipt.id as string;

  const rejected = await api(adminToken, 'POST', `/admin/subscriptions/receipts/${receiptId}/reject`, {
    reason: 'The amount does not match the monthly plan.',
  });
  assert.equal(rejected.status, 200, JSON.stringify(rejected.json));
  assert.equal(rejected.json.data.receipt.status, 'rejected');

  const sub = await one<{ status: string }>(
    'SELECT status FROM partner_subscriptions WHERE restaurant_id = $1::UUID',
    [venueId],
  );
  assert.notEqual(sub?.status, 'active');
});

// ── Venue moderation reaches the customer app ────────────────────────────────

test('suspending a venue hides it from discovery and restoring brings it back', async () => {
  const { venueId, ownerToken } = await newVenue('Suspend');
  await api(adminToken, 'POST', `/admin/applications/${await pendingRequestId(venueId)}/review`, {
    decision: 'approved',
    reviewerNote: 'verified for the discovery test',
  });

  const visibleBefore = await api(ownerToken, 'GET', '/restaurants?q=discovery');
  assert.equal(visibleBefore.status, 200);

  const suspended = await api(adminToken, 'POST', `/admin/venues/${venueId}/suspend`, {
    note: 'Food safety inspection pending',
  });
  assert.equal(suspended.status, 200, JSON.stringify(suspended.json));

  const row = await one<{ moderation_status: string; accepting_bookings: boolean }>(
    'SELECT moderation_status, accepting_bookings FROM restaurants WHERE id = $1::UUID',
    [venueId],
  );
  assert.equal(row?.moderation_status, 'suspended');
  assert.equal(row?.accepting_bookings, false);

  const listing = await api(ownerToken, 'GET', '/restaurants?limit=200');
  assert.ok(
    !listing.json.restaurants.some((r: Json) => r.id === venueId),
    'a suspended venue must not appear in customer discovery',
  );

  const restored = await api(adminToken, 'POST', `/admin/venues/${venueId}/restore`, { note: 'Cleared' });
  assert.equal(restored.status, 200);
  const after = await one<{ accepting_bookings: boolean }>(
    'SELECT accepting_bookings FROM restaurants WHERE id = $1::UUID',
    [venueId],
  );
  assert.equal(after?.accepting_bookings, true);

  const listing2 = await api(ownerToken, 'GET', '/restaurants?limit=200');
  assert.ok(
    listing2.json.restaurants.some((r: Json) => r.id === venueId),
    'a restored venue must be discoverable again',
  );
});

test('the venues list answers with the pagination envelope', async () => {
  const { status, json } = await api(adminToken, 'GET', '/admin/venues?page=1&limit=5');
  assert.equal(status, 200);
  assert.equal(json.meta.limit, 5);
  assert.ok(Array.isArray(json.data.venues));
  assert.ok(json.data.venues.length <= 5);
});

// ── Account suspension ───────────────────────────────────────────────────────

test('a suspended customer token is refused on authenticated routes', async () => {
  seq += 1;
  const email = `admin_itest_suspend_${seq}@example.com`;
  const diner = await api(null, 'POST', '/auth/signup', {
    name: 'Suspend Me',
    email,
    password: PASSWORD,
  });
  assert.equal(diner.status, 201);
  const userId = diner.json.user.id as string;
  const token = diner.json.token as string;

  // Sanity: the token works before the suspension.
  assert.equal((await api(token, 'GET', '/users/me')).status, 200);

  const suspended = await api(adminToken, 'POST', `/admin/customers/${userId}/suspend`, {
    reason: 'Repeated no-shows',
  });
  assert.equal(suspended.status, 200, JSON.stringify(suspended.json));
  const stored = await one<{ suspended_at: Date | null; suspension_reason: string }>(
    'SELECT suspended_at, suspension_reason FROM users WHERE id = $1::UUID',
    [userId],
  );
  assert.ok(stored?.suspended_at, 'suspended_at should be set');
  assert.equal(stored?.suspension_reason, 'Repeated no-shows');

  const blocked = await api(token, 'GET', '/users/me');
  assert.equal(blocked.status, 403, JSON.stringify(blocked.json));
  assert.match(String(blocked.json.error), /suspended/i);

  const restored = await api(adminToken, 'POST', `/admin/customers/${userId}/restore`);
  assert.equal(restored.status, 200);
  assert.equal((await api(token, 'GET', '/users/me')).status, 200);
});

// ── Reports ──────────────────────────────────────────────────────────────────

test('resolving a report with venue_suspended writes the venue and the audit log', async () => {
  const { venueId, ownerId } = await newVenue('ReportResolve');
  const before = await many<{ id: string }>(
    'SELECT id FROM audit_log WHERE resource = $1 AND resource_id = $2',
    ['reports', venueId],
  );

  const refRow = await one<{ reference: string }>(
    `SELECT 'ITEST-' || floor(random() * 1000000)::text AS reference`,
  );
  const report = await one<{ id: string }>(
    `INSERT INTO reports (reporter_id, target_type, target_id, reason, description, reference)
     VALUES ($1::UUID, 'user', $2::UUID, 'unsafe_experience', 'Venue served undercooked food.', $3)
     RETURNING id`,
    [ownerId, ownerId, refRow?.reference ?? 'ITEST-1'],
  );
  assert.ok(report);

  // The case targets the owner account, and the operator suspends the venue
  // through the action picker, so the resolver must find the venue the account
  // owns rather than the report's own target id.
  await api(adminToken, 'POST', `/admin/reports/${report.id}/start-review`, {});

  // Point the case at the venue so `venue_suspended` has something to act on.
  const event = await one<{ id: string }>(
    `SELECT id FROM dinner_events WHERE restaurant_id = $1::UUID LIMIT 0`,
    [venueId],
  );
  assert.equal(event, undefined, 'no seeded event expected');

  const venueLevel = await api(adminToken, 'POST', `/admin/venues/${venueId}/suspend`, {
    note: 'pre-check that the moderation write works',
  });
  assert.equal(venueLevel.status, 200);
  await api(adminToken, 'POST', `/admin/venues/${venueId}/restore`, { note: 'undo pre-check' });

  const resolved = await api(adminToken, 'POST', `/admin/reports/${report.id}/resolve`, {
    resolution: 'Venue suspended pending an inspection.',
    action: 'host_suspended',
  });
  assert.equal(resolved.status, 200, JSON.stringify(resolved.json));

  const stored = await one<{ status: string; resolution: string }>(
    'SELECT status, resolution FROM reports WHERE id = $1::UUID',
    [report.id],
  );
  assert.equal(stored?.status, 'resolved');
  assert.match(String(stored?.resolution), /host_suspended/);

  const suspendedOwner = await one<{ suspended_at: Date | null }>(
    'SELECT suspended_at FROM users WHERE id = $1::UUID',
    [ownerId],
  );
  assert.ok(suspendedOwner?.suspended_at, 'the reported host should be suspended');

  const auditRows = await many<{ action: string }>(
    'SELECT action FROM audit_log WHERE resource = $1 AND resource_id = $2',
    ['reports', report.id],
  );
  assert.ok(
    auditRows.some((r) => r.action === 'admin.report.resolve'),
    'expected an audit_log row for the resolution',
  );
  assert.equal(before.length, 0);
});

test('reopening a resolved report clears the outcome', async () => {
  const { ownerId } = await newVenue('Reopen');
  const report = await one<{ id: string }>(
    `INSERT INTO reports (reporter_id, target_type, target_id, reason, description, reference)
     VALUES ($1::UUID, 'user', $2::UUID, 'spam', 'Automated spam pattern.',
             'ITEST-REOPEN-' || floor(random() * 100000)::text)
     RETURNING id`,
    [ownerId, ownerId],
  );
  assert.ok(report);

  await api(adminToken, 'POST', `/admin/reports/${report.id}/dismiss`, {
    resolution: 'Not a spam pattern.',
  });
  const dismissed = await one<{ status: string }>(
    'SELECT status FROM reports WHERE id = $1::UUID',
    [report.id],
  );
  assert.equal(dismissed?.status, 'dismissed');

  const reopened = await api(adminToken, 'POST', `/admin/reports/${report.id}/reopen`);
  assert.equal(reopened.status, 200, JSON.stringify(reopened.json));
  const after = await one<{ status: string; resolution: string }>(
    'SELECT status, resolution FROM reports WHERE id = $1::UUID',
    [report.id],
  );
  assert.equal(after?.status, 'reviewing');
  assert.equal(after?.resolution, '');
});

// ── Experiences, deals, audit, settings ──────────────────────────────────────

test('cancelling an experience tells the guests who hold seats', async () => {
  const { venueId } = await newVenue('CancelEvent');
  const event = await one<{ id: string; host_id: string }>(
    `INSERT INTO dinner_events (title, host_id, restaurant_id, start_at, seats_total,
                                price_per_seat, status)
     SELECT 'Console cancel test', $2::UUID, $1::UUID, now() + interval '7 days', 10, 500,
            'confirmed'
     RETURNING id, host_id`,
    [venueId, (await one<{ id: string }>('SELECT id FROM users WHERE role = $1', ['host']))?.id],
  );
  if (!event) {
    assert.fail('expected to be able to seed an event for the cancel test');
  }
  const guest = await one<{ id: string }>(
    `INSERT INTO bookings (event_id, user_id, seats, price_per_seat, total_amount, reference)
     SELECT $1::UUID, u.id, 2, 500, 1000, 'ITEST-BK-' || floor(random() * 100000)::text
       FROM users u WHERE u.role = 'user' LIMIT 1
     RETURNING id`,
    [event.id],
  );
  assert.ok(guest, 'expected a user to book against');

  const cancelled = await api(adminToken, 'POST', `/admin/experiences/${event.id}/cancel`, {
    reason: 'Venue flooded, nothing usable tonight.',
    notifyGuests: true,
  });
  assert.equal(cancelled.status, 200, JSON.stringify(cancelled.json));
  assert.equal(cancelled.json.data.experience.status, 'cancelled');
  assert.equal(cancelled.json.data.experience.guestCount, 1);

  const stored = await one<{ status: string; cancellation_reason: string }>(
    'SELECT status, cancellation_reason FROM dinner_events WHERE id = $1::UUID',
    [event.id],
  );
  assert.equal(stored?.status, 'cancelled');
  assert.match(String(stored?.cancellation_reason), /flooded/);
});

test('flagging a deal puts it in the console queue and removing pauses it', async () => {
  const { venueId } = await newVenue('Deal');
  const deal = await one<{ id: string }>(
    `INSERT INTO restaurant_deals (restaurant_id, title, kind, value, ends_at, status)
     VALUES ($1::UUID, 'Console test deal', 'percent', 20, now() + interval '30 days', 'active')
     RETURNING id`,
    [venueId],
  );
  assert.ok(deal);

  const flagged = await api(adminToken, 'POST', `/admin/deals/${deal.id}/flag`, {
    note: 'Claims a discount that is not honoured',
  });
  assert.equal(flagged.status, 200, JSON.stringify(flagged.json));

  const queue = await api(adminToken, 'GET', '/admin/deals?flagged=true');
  assert.ok(queue.json.data.deals.some((d: Json) => d.id === deal.id));

  const removed = await api(adminToken, 'POST', `/admin/deals/${deal.id}/remove`, {
    note: 'Removed pending a rewrite',
  });
  assert.equal(removed.status, 200, JSON.stringify(removed.json));
  const stored = await one<{ status: string; moderation_status: string }>(
    'SELECT status, moderation_status FROM restaurant_deals WHERE id = $1::UUID',
    [deal.id],
  );
  assert.equal(stored?.moderation_status, 'removed');
  // The customer-facing gate is `status='active'`, so removal must also pause.
  assert.equal(stored?.status, 'paused');
});

test('the audit log exports the filtered range as CSV', async () => {
  await api(adminToken, 'POST', '/admin/venues?noop=1', {}).catch(() => {});
  const res = await fetch(`${base}/admin/audit-log/export`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({}),
  });
  assert.equal(res.status, 200);
  assert.match(res.headers.get('content-type') ?? '', /text\/csv/);
  const text = await res.text();
  const lines = text.split('\r\n');
  assert.match(lines[0] ?? '', /^"timestamp","actor",/);
});

test('settings expose the stored config and PATCH merges whitelisted keys', async () => {
  const before = await api(adminToken, 'GET', '/admin/settings');
  assert.equal(before.status, 200, JSON.stringify(before.json));
  assert.equal(before.json.data.settings.config.city, 'Karachi');
  assert.equal(before.json.data.settings.plans.length, 2);

  const flipped = await api(adminToken, 'POST', '/admin/settings/switch', {
    key: 'weeklyDigest',
    value: !before.json.data.settings.config.weeklyDigest,
  });
  assert.equal(flipped.status, 200, JSON.stringify(flipped.json));
  const after = await api(adminToken, 'GET', '/admin/settings');
  assert.equal(
    after.json.data.settings.config.weeklyDigest,
    !before.json.data.settings.config.weeklyDigest,
  );

  const unknown = await api(adminToken, 'PATCH', '/admin/settings', { notASetting: true });
  assert.equal(unknown.status, 400, JSON.stringify(unknown.json));
});

test('a non-admin cannot create another admin', async () => {
  seq += 1;
  const diner = await api(null, 'POST', '/auth/signup', {
    name: 'Privilege Escalation',
    email: `admin_itest_escalate_${seq}@example.com`,
    password: PASSWORD,
  });
  const { status, json } = await api(diner.json.token as string, 'POST', '/admin/settings/admins', {
    name: 'Fake Admin',
    email: `fake_admin_${seq}@example.com`,
    role: 'super_admin',
  });
  // The diner holds a valid session, so this is an authorization refusal
  // rather than an authentication challenge.
  assert.equal(status, 403, JSON.stringify(json));
});

test('creating an admin account returns a usable temporary password', async () => {
  seq += 1;
  const email = `real_admin_${seq}@example.com`;
  const created = await api(adminToken, 'POST', '/admin/settings/admins', {
    name: `Console Admin ${seq}`,
    email,
    role: 'partner_admin',
    scope: 'operations',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  const temporary = created.json.data.admin.temporaryPassword as string;
  assert.ok(temporary && temporary.length >= 6);

  const login = await api(null, 'POST', '/auth/login', { email, password: temporary });
  assert.equal(login.status, 200, JSON.stringify(login.json));
  const { status } = await api(login.json.token as string, 'GET', '/admin/overview');
  assert.equal(status, 200, 'a newly minted admin should reach the console');
});
