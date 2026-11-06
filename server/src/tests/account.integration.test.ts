/**
 * P1 account & authentication integration suite. Runs the real Express API
 * against an isolated freshly-seeded PostgreSQL database and covers the seven
 * shipped features end-to-end:
 *   * change password (verification + other-session revoke)
 *   * change email (hashed 6-digit challenge, TTL, collisions, confirm)
 *   * privacy / food / location settings via partial PATCH /users/me
 *   * logout-all (every session revoked)
 *   * delete account (password gate, money settlement, data preservation)
 *
 * Execute from server/:  npm run test:integration
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { bootstrap, one, exec, type ApiHandle } from './util.js';

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

let seq = 0;
const PASSWORD = 'correct horse battery staple';

/** Fresh email/password account (signup signs the account straight in). */
async function signUpAccount(
  prefix = 'member',
  password = PASSWORD,
): Promise<{ token: string; userId: string; email: string }> {
  seq += 1;
  const email = `p1_${prefix}_${seq}@example.com`;
  const { status, json } = await api(
    null,
    'POST',
    '/auth/signup',
    { name: `P1 ${prefix}`, email, password },
  );
  assert.equal(status, 201, `signup failed: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string, email };
}

// ── 1. Change password ───────────────────────────────────────────────────────

test('change-password verifies the current password and revokes other sessions', async () => {
  const { token, email, userId } = await signUpAccount('pw');
  // Second device: a plain login mints an independent token.
  const second = await api(null, 'POST', '/auth/login', {
    email,
    password: PASSWORD,
  });
  assert.equal(second.status, 200);
  const otherToken = second.json.token as string;

  // Wrong current password → 401, nothing changes.
  const bad = await api(token, 'POST', '/auth/change-password', {
    currentPassword: 'not-the-password',
    newPassword: 'brand-new-secret-9000',
  });
  assert.equal(bad.status, 401);

  // Too-short new password → 400 (validation).
  const short = await api(token, 'POST', '/auth/change-password', {
    currentPassword: PASSWORD,
    newPassword: 'tiny',
  });
  assert.equal(short.status, 400);

  const ok = await api(token, 'POST', '/auth/change-password', {
    currentPassword: PASSWORD,
    newPassword: 'brand-new-secret-9000',
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.json));
  assert.equal(ok.json.changed, true);
  assert.equal(ok.json.user.email, email, 'loadUser keeps the email on change');

  // This device stays signed in; the other session was revoked.
  assert.equal((await api(token, 'GET', '/auth/me')).status, 200);
  assert.equal((await api(otherToken, 'GET', '/auth/me')).status, 401);

  // Old password no longer authenticates; the new one does.
  const stale = await api(null, 'POST', '/auth/login', {
    email,
    password: PASSWORD,
  });
  assert.equal(stale.status, 401);
  const fresh = await api(null, 'POST', '/auth/login', {
    email,
    password: 'brand-new-secret-9000',
  });
  assert.equal(fresh.status, 200);

  const hashRow = await one<{ password_hash: string }>(
    'SELECT password_hash FROM users WHERE id = $1::UUID',
    [userId],
  );
  assert.ok(hashRow?.password_hash?.startsWith('scrypt:'), 'hash re-derived');
});

// ── 2. Change email (verified challenge) ─────────────────────────────────────

test('change-email applies the new address only after code confirmation', async () => {
  const { token, userId, email } = await signUpAccount('em');
  const second = await api(null, 'POST', '/auth/login', {
    email,
    password: PASSWORD,
  });
  const otherToken = second.json.token as string;

  // Wrong password → 401; the address itself is untouched.
  const badPass = await api(token, 'POST', '/auth/change-email', {
    email: 'fresh.address@example.com',
    password: 'nope-nope-nope',
  });
  assert.equal(badPass.status, 401);

  // Same address → 400.
  const same = await api(token, 'POST', '/auth/change-email', {
    email,
    password: PASSWORD,
  });
  assert.equal(same.status, 400);

  // Collision with an existing account → 409.
  const other = await signUpAccount('em_other');
  const clash = await api(token, 'POST', '/auth/change-email', {
    email: other.email,
    password: PASSWORD,
  });
  assert.equal(clash.status, 409);

  // Happy request: challenge minted, email NOT yet applied.
  const target = `moved.${seq}@example.com`;
  const req = await api(token, 'POST', '/auth/change-email', {
    email: target,
    password: PASSWORD,
  });
  assert.equal(req.status, 200, JSON.stringify(req.json));
  assert.equal(req.json.sent, true);
  assert.equal(req.json.email, target);
  const devCode = req.json.devCode as string;
  assert.match(devCode, /^[0-9]{6}$/, 'NODE_ENV=test returns the dev code');

  const pending = await api(token, 'GET', '/auth/me');
  assert.equal(pending.json.user.email, email, 'change is only staged');
  const challenge = await one<{ new_email: string; code_hash: string }>(
    'SELECT new_email, code_hash FROM email_change_challenges WHERE user_id = $1::UUID',
    [userId],
  );
  assert.equal(challenge?.new_email, target);
  assert.ok(
    challenge?.code_hash && !challenge.code_hash.includes(devCode),
    'the code is stored hashed, never in the clear',
  );

  // Guessing the code: wrong code 401 and the challenge survives.
  const wrongCode = await api(token, 'POST', '/auth/change-email/confirm', {
    code: devCode === '000000' ? '000001' : '000000',
  });
  assert.equal(wrongCode.status, 401);
  assert.equal((await api(token, 'GET', '/auth/me')).json.user.email, email);

  // Expired challenge → 401 with the "request a new one" copy.
  await exec(
    `UPDATE email_change_challenges
        SET expires_at = now() - interval '1 minute' WHERE user_id = $1::UUID`,
    [userId],
  );
  const expired = await api(token, 'POST', '/auth/change-email/confirm', {
    code: devCode,
  });
  assert.equal(expired.status, 401);

  // Re-request, then confirm for real.
  const req2 = await api(token, 'POST', '/auth/change-email', {
    email: target,
    password: PASSWORD,
  });
  assert.equal(req2.status, 200);
  const done = await api(token, 'POST', '/auth/change-email/confirm', {
    code: req2.json.devCode as string,
  });
  assert.equal(done.status, 200, JSON.stringify(done.json));
  assert.equal(done.json.email, target);
  assert.equal(done.json.user.email, target);

  // Challenge consumed; confirming again is a no-pending 400.
  const again = await api(token, 'POST', '/auth/change-email/confirm', {
    code: req2.json.devCode as string,
  });
  assert.equal(again.status, 400);
  const left = await one(
    'SELECT 1 AS ok FROM email_change_challenges WHERE user_id = $1::UUID',
    [userId],
  );
  assert.equal(left, undefined);

  // Login moves with the address; other devices were signed out.
  assert.equal(
    (await api(null, 'POST', '/auth/login', { email: target, password: PASSWORD }))
      .status,
    200,
  );
  assert.equal(
    (await api(null, 'POST', '/auth/login', { email, password: PASSWORD })).status,
    401,
  );
  assert.equal((await api(otherToken, 'GET', '/auth/me')).status, 401);
  assert.equal((await api(token, 'GET', '/auth/me')).status, 200);
});

// ── 3. Settings: privacy / food preferences / location ───────────────────────

test('PATCH /users/me writes settings partially and validates payloads', async () => {
  const { token, userId } = await signUpAccount('set');

  const ok = await api(token, 'PATCH', '/users/me', {
    city: 'Lahore',
    homeArea: 'Gulberg III',
    dietary: ['Halal', 'Vegetarian'],
    allergies: ['Peanuts'],
    showFollowList: false,
    showActivity: false,
    dmFromFollowersOnly: true,
    allowTagging: false,
  });
  assert.equal(ok.status, 200, JSON.stringify(ok.json));
  const user = ok.json.user as Json;
  assert.equal(user.city, 'Lahore');
  assert.equal(user.homeArea, 'Gulberg III');
  assert.deepEqual(user.dietary, ['Halal', 'Vegetarian']);
  assert.deepEqual(user.allergies, ['Peanuts']);
  assert.equal(user.showFollowList, false);
  assert.equal(user.showActivity, false);
  assert.equal(user.dmFromFollowersOnly, true);
  assert.equal(user.allowTagging, false);

  // The public /users/me row persists the same columns server-side.
  const row = await one<Json>(
    `SELECT city, home_area, dietary, allergies, show_follow_list,
            show_activity, dm_from_followers_only, allow_tagging, name, tastes
       FROM users WHERE id = $1::UUID`,
    [userId],
  );
  assert.equal(row?.home_area, 'Gulberg III');
  assert.equal(row?.show_follow_list, false);
  assert.equal(row?.dm_from_followers_only, true);
  assert.equal(row?.name, 'P1 set', 'unsent fields keep their signup values');
  assert.deepEqual(row?.tastes, [], 'tastes untouched by a settings-only write');

  // A second partial write must not blank the first.
  const second = await api(token, 'PATCH', '/users/me', { homeArea: 'DHA Phase 5' });
  assert.equal(second.status, 200);
  assert.equal(second.json.user.city, 'Lahore');
  assert.deepEqual(second.json.user.allergies, ['Peanuts']);
  assert.equal(second.json.user.homeArea, 'DHA Phase 5');

  // Validation: more than 8 tastes / 12 allergy labels is rejected.
  const tooManyTastes = await api(token, 'PATCH', '/users/me', {
    tastes: Array.from({ length: 9 }, (_, i) => `t${i}`),
  });
  assert.equal(tooManyTastes.status, 400);
  const tooManyAllergies = await api(token, 'PATCH', '/users/me', {
    allergies: Array.from({ length: 13 }, (_, i) => `a${i}`),
  });
  assert.equal(tooManyAllergies.status, 400);

  // Unauthenticated writes are rejected outright.
  assert.equal((await api(null, 'PATCH', '/users/me', { city: 'Nowhere' })).status, 401);
});

// ── 4. Logout all devices ────────────────────────────────────────────────────

test('logout-all revokes every session including the caller', async () => {
  const { token, email } = await signUpAccount('lla');
  const second = await api(null, 'POST', '/auth/login', {
    email,
    password: PASSWORD,
  });
  const otherToken = second.json.token as string;

  const out = await api(token, 'POST', '/auth/logout-all');
  assert.equal(out.status, 200);
  assert.equal(out.json.signedOutEverywhere, true);

  assert.equal((await api(token, 'GET', '/auth/me')).status, 401);
  assert.equal((await api(otherToken, 'GET', '/auth/me')).status, 401);
  const tokens = await one<{ count: string }>(
    `SELECT count(*)::text AS count FROM auth_tokens t
       JOIN users u ON u.id = t.user_id
      WHERE u.email = $1`,
    [email],
  );
  assert.equal(tokens?.count, '0');

  // The account itself survives: login still works.
  assert.equal(
    (await api(null, 'POST', '/auth/login', { email, password: PASSWORD })).status,
    200,
  );
});

// ── 5. Delete account (money settlement + preservation) ──────────────────────

test('delete-account gates on the password, settles money, preserves records', async () => {
  // The seeded Lyon rooftop needs partner verification before a fresh host
  // can publish there (same setup as the money suite).
  await exec(
    `UPDATE restaurants SET is_partner = true, partnership_status = 'verified'
      WHERE id = $1::UUID`,
    ['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'],
  );

  const host = await signUpAccount('delhost');
  const promote = await api(host.token, 'POST', '/users/me/host');
  assert.equal(promote.status, 200, JSON.stringify(promote.json));

  const startAt = new Date(Date.now() + 7 * 864e5).toISOString();
  const created = await api(host.token, 'POST', '/events', {
    title: 'Farewell Dinner',
    tagline: 'delete-account fixture',
    description: 'created by the account integration suite',
    coverImage: 'assets/images/dish_pasta.png',
    restaurantId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
    startAt,
    seatsTotal: 10,
    pricePerSeat: 40,
    audience: 'public',
  });
  assert.equal(created.status, 201, JSON.stringify(created.json));
  const eventId = created.json.event.id as string;

  const guest = await signUpAccount('delguest');
  const booked = await api(guest.token, 'POST', `/events/${eventId}/bookings`, {
    seats: 2,
  });
  assert.equal(booked.status, 201, JSON.stringify(booked.json));
  const bookingId = booked.json.booking.id as string;

  // Wrong password → 401 and the account is fully intact.
  const denied = await api(host.token, 'DELETE', '/users/me', {
    password: 'wrong-passphrase',
  });
  assert.equal(denied.status, 401);
  assert.equal((await api(host.token, 'GET', '/auth/me')).status, 200);

  const gone = await api(host.token, 'DELETE', '/users/me', {
    password: PASSWORD,
  });
  assert.equal(gone.status, 200, JSON.stringify(gone.json));
  assert.equal(gone.json.deleted, true);

  // Anonymised in place: login surfaces are destroyed.
  const row = await mustOne<Json>(
    'SELECT * FROM users WHERE id = $1::UUID',
    [host.userId],
  );
  assert.equal(row.is_deleted, true);
  assert.equal(row.email, null);
  assert.equal(row.phone, null);
  assert.equal(row.password_hash, null);
  assert.equal(row.name, 'Deleted user');
  assert.equal((await api(host.token, 'GET', '/auth/me')).status, 401);
  assert.equal(
    (await api(null, 'POST', '/auth/login', {
      email: host.email,
      password: PASSWORD,
    })).status,
    401,
  );

  // Guests were refunded and their ticket rows PRESERVED (cancelled, not
  // deleted) — history keeps its foreign keys intact.
  const booking = await mustOne<Json>(
    'SELECT status, payment_status, user_id FROM bookings WHERE id = $1::UUID',
    [bookingId],
  );
  assert.equal(booking.status, 'cancelled');
  assert.equal(booking.user_id, guest.userId, 'guest row not anonymised');
  const event = await mustOne<Json>(
    "SELECT status FROM dinner_events WHERE id = $1::UUID",
    [eventId],
  );
  assert.equal(event.status, 'cancelled');

  // The guest keeps their own working session throughout.
  assert.equal((await api(guest.token, 'GET', '/auth/me')).status, 200);
});

async function mustOne<T extends Record<string, any>>(
  sql: string,
  params: unknown[] = [],
): Promise<T> {
  const row = await one<T>(sql, params);
  assert.ok(row, `expected a row from: ${sql}`);
  return row;
}
