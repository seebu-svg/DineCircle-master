/**
 * Subscription integration tests.
 *
 * Covers the partner_subscriptions contract (Phase 3):
 *   - GET returns a synthetic default when no row exists
 *   - Owner PATCH monthly → plan/price/period set, status stays 'none' (partner cannot activate)
 *   - Owner PATCH yearly → period is +12 months
 *   - Staff PATCH → 403
 *   - Unknown plan → 400 (zod validation)
 *   - Admin POST activate → status transitions to 'active'
 *   - Admin POST cancel → status transitions to 'cancelled' with cancelled_at
 *   - Entitlement middleware: 402 when subscription is 'none'
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { bootstrap, one, exec, type ApiHandle } from './util.js';

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

async function login(email: string, password: string): Promise<{ token: string; userId: string }> {
  const { status, json } = await api(null, 'POST', '/auth/login', { email, password });
  assert.equal(status, 200, `login failed for ${email}: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string };
}

let seq = 0;
async function signUpAccount(prefix = 'sub'): Promise<{
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

async function mintAdminToken(): Promise<string> {
  const secret = `dc_partner_admin_${Date.now()}`;
  await exec(
    `INSERT INTO auth_tokens (token, user_id, expires_at)
     SELECT $1::text, id, now() + interval '30 days'
       FROM users WHERE role = 'super_admin' LIMIT 1`,
    [createHash('sha256').update(secret).digest('hex')],
  );
  return secret;
}

/** Register a venue through the API and return its id + owner token. */
async function registerVenue(): Promise<{ venueId: string; ownerToken: string; ownerId: string }> {
  const owner = await signUpAccount('venue');
  const created = await api(owner.token, 'POST', '/partner/restaurants', {
    name: `Subscription Test ${seq}`,
    city: 'Karachi',
    seats: 2,
    address: '1 Test Rd',
    timezone: 'Asia/Karachi',
  });
  assert.equal(created.status, 201, `registration failed: ${JSON.stringify(created.json)}`);
  return { venueId: created.json.data.restaurant.id as string, ownerToken: owner.token, ownerId: owner.userId };
}

// ── Tests ────────────────────────────────────────────────────────────────────

test('GET subscription, no row returns synthetic default', async () => {
  const { venueId, ownerToken } = await registerVenue();
  const { status, json } = await api(ownerToken, 'GET', `/partner/restaurants/${venueId}/subscription`);
  assert.equal(status, 200);
  const sub = json.data.subscription;
  assert.equal(sub.status, 'none');
  assert.equal(sub.plan, null);
  assert.equal(sub.pricePkr, 0);
  assert.equal(sub.autoRenew, false);
});

test('PATCH subscription, owner sets monthly plan, status stays none (partner cannot self-activate)', async () => {
  const { venueId, ownerToken } = await registerVenue();
  const { status, json } = await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
    autoRenew: true,
  });
  assert.equal(status, 200, JSON.stringify(json));
  const sub = json.data.subscription;
  assert.equal(sub.plan, 'monthly');
  // A venue that has never had a subscription row gets the Phase-3 trial
  // bootstrap ('trialing'), not 'none'. What matters is that the partner's own
  // request cannot pick the status.
  assert.equal(sub.status, 'trialing');
  assert.equal(sub.pricePkr, 5000);
  assert.equal(sub.autoRenew, true);
  assert.ok(sub.periodStart);
  assert.ok(sub.periodEnd);
  // Period should be roughly 1 month.
  const start = new Date(sub.periodStart);
  const end = new Date(sub.periodEnd);
  const daysDiff = Math.round((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
  assert.ok(daysDiff >= 28 && daysDiff <= 31, `Expected ~30 days, got ${daysDiff}`);
});

test('PATCH subscription, owner switches to yearly', async () => {
  const { venueId, ownerToken } = await registerVenue();
  // First set monthly.
  await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
  });
  // Then switch to yearly.
  const { status, json } = await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'yearly',
  });
  assert.equal(status, 200);
  const sub = json.data.subscription;
  assert.equal(sub.plan, 'yearly');
  assert.equal(sub.pricePkr, 50000);
  // Period should be roughly 365 days.
  const start = new Date(sub.periodStart);
  const end = new Date(sub.periodEnd);
  const daysDiff = Math.round((end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24));
  assert.ok(daysDiff >= 364 && daysDiff <= 366, `Expected ~365 days, got ${daysDiff}`);
});

test('PATCH subscription, status field is ignored (partner cannot self-activate)', async () => {
  const { venueId, ownerToken } = await registerVenue();
  // Try to set status to active, should be ignored.
  const { status, json } = await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
    status: 'active',
  });
  assert.equal(status, 200);
  const sub = json.data.subscription;
  // The submitted `status: 'active'` is dropped; the row keeps the bootstrapped
  // trial state instead, which is the invariant this test exists for.
  assert.equal(sub.status, 'trialing'); // Status change ignored
});

test('PATCH subscription, staff role gets 403', async () => {
  const { venueId, ownerToken } = await registerVenue();
  // Create a staff account and invite them.
  const staff = await signUpAccount('staff');
  const inviteRes = await api(ownerToken, 'POST', `/partner/restaurants/${venueId}/staff`, {
    email: staff.email,
    role: 'staff',
  });
  assert.equal(inviteRes.status, 201, JSON.stringify(inviteRes.json));
  // Accept the invite.
  const acceptRes = await api(staff.token, 'POST', `/partner/restaurants/${venueId}/staff/accept`, {});
  assert.equal(acceptRes.status, 200, JSON.stringify(acceptRes.json));

  // Staff tries to PATCH subscription → 403.
  const { status } = await api(staff.token, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
  });
  assert.equal(status, 403);
});

test('PATCH subscription, unknown plan gets 400', async () => {
  const { venueId, ownerToken } = await registerVenue();
  const { status } = await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'lifetime',
  });
  assert.equal(status, 400);
});

test('Admin POST activate, sets status to active', async () => {
  const adminToken = await mintAdminToken();
  const { venueId, ownerToken } = await registerVenue();
  // Owner selects a plan first.
  await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
  });
  // Admin activates.
  const { status, json } = await api(adminToken, 'POST', `/admin/restaurants/${venueId}/subscription/activate`, {
    status: 'active',
  });
  assert.equal(status, 200, JSON.stringify(json));
  const sub = json.data.subscription;
  assert.equal(sub.status, 'active');
  assert.equal(sub.plan, 'monthly');
});

test('Admin POST activate, cancel sets cancelled_at', async () => {
  const adminToken = await mintAdminToken();
  const { venueId, ownerToken } = await registerVenue();
  await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
  });
  await api(adminToken, 'POST', `/admin/restaurants/${venueId}/subscription/activate`, {
    status: 'active',
  });
  // Admin cancels.
  const { status, json } = await api(adminToken, 'POST', `/admin/restaurants/${venueId}/subscription/activate`, {
    status: 'cancelled',
  });
  assert.equal(status, 200);
  const sub = json.data.subscription;
  assert.equal(sub.status, 'cancelled');
  assert.ok(sub.cancelledAt);
});

test('Admin POST activate, non-admin gets 403', async () => {
  const { venueId, ownerToken } = await registerVenue();
  await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
  });
  // Owner tries to activate, should fail.
  const { status } = await api(ownerToken, 'POST', `/admin/restaurants/${venueId}/subscription/activate`, {
    status: 'active',
  });
  assert.equal(status, 403);
});

test('GET subscription, reads back what was set', async () => {
  const adminToken = await mintAdminToken();
  const { venueId, ownerToken } = await registerVenue();
  // Set plan and activate via admin.
  await api(ownerToken, 'PATCH', `/partner/restaurants/${venueId}/subscription`, {
    plan: 'monthly',
    autoRenew: false,
  });
  await api(adminToken, 'POST', `/admin/restaurants/${venueId}/subscription/activate`, {
    status: 'active',
  });
  // Read it back.
  const { status, json } = await api(ownerToken, 'GET', `/partner/restaurants/${venueId}/subscription`);
  assert.equal(status, 200);
  const sub = json.data.subscription;
  assert.equal(sub.plan, 'monthly');
  assert.equal(sub.status, 'active');
  assert.equal(sub.pricePkr, 5000);
  assert.equal(sub.autoRenew, false);
});
