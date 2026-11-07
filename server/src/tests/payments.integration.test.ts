/**
 * Stripe deferred-payment integration suite (audit plan Phase 4 / M2+M5).
 *
 * Boots the REAL API in PAYMENTS_MODE=mock: Stripe-shaped gateway semantics
 * offline, with genuine webhook signature verification through the Stripe
 * SDK (generateTestHeaderString / constructEvent are pure local crypto,
 * no network, no live keys). This exercises the whole ladder:
 *   checkout → pending_payment → webhook → paid (+ card label + payout),
 *   authorization → approve/decline, cancel → pending_gateway → confirmed,
 *   failure + abandoned-checkout sweeps, idempotent replays, amount guard.
 *
 * Execute from server/:  npm run test:integration
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import Stripe from 'stripe';
import { bootstrap, one, exec, type ApiHandle } from './util.js';

// The mock gateway must be chosen BEFORE the API child boots (util.ts
// spreads process.env into the spawned server).
process.env.PAYMENTS_MODE = 'mock';
const WEBHOOK_SECRET = 'whsec_itest_local_secret';
process.env.STRIPE_WEBHOOK_SECRET = WEBHOOK_SECRET;

const handle: ApiHandle = await bootstrap();
after(async () => { await handle.close(); });
const base = handle.base;

// Test-process twin of the server's MockGateway signing: the exact same
// local HMAC path Stripe itself documents for webhook testing.
const signer = new Stripe('sk_test_signature_only_local');

// Promote the rooftop venue so Nora (seeded host) can publish there.
await exec(
  `UPDATE restaurants SET is_partner = true, partnership_status = 'verified'
   WHERE id = $1::UUID`,
  ['aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1'],
);

const NORA_PHONE = '+15550002222';
const ROOFTOP = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';

type Json = Record<string, any>;

async function mustOne<T extends Record<string, any>>(
  sql: string,
  params: unknown[] = [],
): Promise<T> {
  const row = await one<T>(sql, params);
  assert.ok(row, `expected a row from: ${sql}`);
  return row;
}

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

const tokens = new Map<string, string>();
async function signIn(phone: string): Promise<string> {
  const cached = tokens.get(phone);
  if (cached) return cached;
  const { status, json } = await api(null, 'POST', '/auth/signin', { phone });
  assert.equal(status, 200, `signin ${phone} failed`);
  const token = json.token as string;
  tokens.set(phone, token);
  return token;
}

let seq = 0;
/** Publish an event as Nora ($50/seat, 20 seats), optional approval gate. */
async function newEvent(token: string, extra: Json = {}): Promise<string> {
  seq += 1;
  const startAt = new Date(Date.now() + 7 * 864e5).toISOString();
  const { status, json } = await api(token, 'POST', '/events', {
    title: `Stripe IT ${seq}`,
    tagline: 'integration fixture',
    description: 'created by the payments integration suite',
    coverImage: 'assets/images/dish_pasta.png',
    restaurantId: ROOFTOP,
    startAt,
    seatsTotal: 20,
    pricePerSeat: 50,
    audience: 'public',
    ...extra,
  });
  assert.equal(status, 201, `create event failed: ${JSON.stringify(json)}`);
  return json.event.id as string;
}

async function freshGuest(): Promise<string> {
  seq += 1;
  return signIn(`+15558${String(seq).padStart(7, '0')}`);
}

const bookingRow = (id: string) =>
  mustOne<Json>('SELECT * FROM bookings WHERE id = $1::UUID', [id]);
const eventRow = (id: string) =>
  mustOne<Json>('SELECT seats_booked, attendee_ids FROM dinner_events WHERE id = $1::UUID', [id]);
const payoutRow = (eventId: string) =>
  one<Json>('SELECT * FROM payouts WHERE event_id = $1::UUID', [eventId]);
const refundRow = (bookingId: string) =>
  mustOne<Json>('SELECT * FROM refunds WHERE booking_id = $1::UUID', [bookingId]);

// ── Webhook fixture delivery (through the REAL signature verification) ──────

let eventSeq = 0;
function paymentIntentEvent(
  type: string,
  booking: Json,
  overrides: Json = {},
): Json {
  eventSeq += 1;
  return {
    id: `evt_itest_${eventSeq}`,
    object: 'event',
    type,
    created: Math.floor(Date.now() / 1000),
    livemode: false,
    data: {
      object: {
        id: booking.stripe_payment_intent_id ?? 'pi_itest_intent',
        object: 'payment_intent',
        amount: booking.stripe_amount_cents,
        currency: 'usd',
        status: type === 'payment_intent.succeeded' ? 'succeeded' : 'requires_payment_method',
        metadata: {
          booking_id: booking.id,
          event_id: booking.event_id,
          user_id: booking.user_id,
        },
        ...overrides,
      },
    },
  };
}

const CARD_CHARGE = {
  id: 'ch_itest_charge',
  object: 'charge',
  payment_method_details: { type: 'card', card: { brand: 'visa', last4: '4242' } },
};

async function deliverWebhook(eventBody: Json): Promise<{ status: number; json: Json }> {
  const payload = JSON.stringify(eventBody);
  const signature = signer.webhooks.generateTestHeaderString({
    payload,
    secret: WEBHOOK_SECRET,
  });
  const res = await fetch(`${base}/stripe/webhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'stripe-signature': signature },
    body: payload,
  });
  const json = (await res.json().catch(() => ({}))) as Json;
  return { status: res.status, json };
}

/** Book N seats and return the DB row (the gateway truth, not the response). */
async function bookAndLoad(
  guestToken: string,
  eventId: string,
  seats = 2,
  extra: Json = {},
): Promise<Json> {
  const { status, json } = await api(
    guestToken, 'POST', `/events/${eventId}/bookings`, { seats, ...extra },
  );
  assert.equal(status, 201, `booking failed: ${JSON.stringify(json)}`);
  return bookingRow(json.booking.id as string);
}

// ── 1. Checkout holds at the gateway instead of settling instantly ──────────

let deferredBooking: Json; // carried through tests 2–4 and the cancel flow
let deferredEventId: string;

test('mock checkout returns pending_payment + clientSecret + gateway amount', async () => {
  const guest = await freshGuest();
  deferredEventId = await newEvent(await signIn(NORA_PHONE));
  const { status, json } = await api(guest, 'POST', `/events/${deferredEventId}/bookings`, {
    seats: 2,
    paymentLabel: 'Client-Dictated Label', // must never survive into a gateway hold
  });
  assert.equal(status, 201);
  assert.equal(json.booking.paymentStatus, 'pending_payment');
  assert.equal(json.booking.status, 'confirmed');
  assert.match(json.booking.clientSecret as string, /^pi_mock_/);
  assert.equal(json.booking.paymentLabel, '');

  deferredBooking = await bookingRow(json.booking.id as string);
  assert.match(deferredBooking.stripe_payment_intent_id, /^pi_mock_/);
  assert.equal(deferredBooking.stripe_amount_cents, 10000); // 2 × $50, integer cents
  assert.equal(deferredBooking.payment_status, 'pending_payment');

  // Host earnings must NOT accrue before the money webhook lands.
  assert.equal(await payoutRow(deferredEventId), undefined);
});

// ── 2. Webhook authentication is the signature ──────────────────────────────

test('webhook rejects tampered or missing signatures with 400', async () => {
  const payload = JSON.stringify(
    paymentIntentEvent('payment_intent.succeeded', deferredBooking, { latest_charge: CARD_CHARGE }),
  );
  const bad = await fetch(`${base}/stripe/webhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'stripe-signature': 't=1,v1=deadbeef' },
    body: payload,
  });
  assert.equal(bad.status, 400);

  const unsigned = await fetch(`${base}/stripe/webhook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: payload,
  });
  assert.equal(unsigned.status, 400);
  assert.equal((await bookingRow(deferredBooking.id)).payment_status, 'pending_payment');
});

// ── 3. Success webhook settles money + label + payout ───────────────────────

let succeededEvent: Json;

test('payment_intent.succeeded pays the booking with the real card label', async () => {
  succeededEvent = paymentIntentEvent(
    'payment_intent.succeeded', deferredBooking, { latest_charge: CARD_CHARGE },
  );
  const { status, json } = await deliverWebhook(succeededEvent);
  assert.equal(status, 200);
  assert.equal(json.received, true);
  assert.equal(json.duplicate, undefined);

  const row = await bookingRow(deferredBooking.id);
  assert.equal(row.payment_status, 'paid');
  // The webhook replaced the empty hold label with the intent's card truth.
  assert.equal(row.payment_label, 'Visa •••• 4242');

  const payout = await mustOne<Json>('SELECT * FROM payouts WHERE event_id = $1::UUID',
    [deferredEventId]);
  assert.equal(Number(payout.gross), 100);
  assert.equal(payout.seats_sold, 2);
});

// ── 4. Replays converge, they don't re-count ────────────────────────────────

test('replayed delivery is acknowledged as duplicate without reprocessing', async () => {
  const { status, json } = await deliverWebhook(succeededEvent);
  assert.equal(status, 200);
  assert.equal(json.duplicate, true);
  assert.equal((await bookingRow(deferredBooking.id)).payment_status, 'paid');
  const payout = await mustOne<Json>('SELECT gross FROM payouts WHERE event_id = $1::UUID',
    [deferredEventId]);
  assert.equal(Number(payout.gross), 100); // still single-counted
});

// ── 5. Amount guard: settle only what checkout asked for ────────────────────

test('succeeded webhook with a mismatched amount refuses to settle', async () => {
  const guest = await freshGuest();
  const eventId = await newEvent(await signIn(NORA_PHONE));
  const booking = await bookAndLoad(guest, eventId);
  const forged = paymentIntentEvent('payment_intent.succeeded', booking, {
    latest_charge: CARD_CHARGE,
  });
  forged.data.object.amount = 1; // pennies, not the $100.00 the booking holds
  const { status } = await deliverWebhook(forged);
  assert.equal(status, 200); // acknowledged (no retry storm) but not applied
  assert.equal((await bookingRow(booking.id)).payment_status, 'pending_payment');
});

// ── 6. Failed payment releases everything ───────────────────────────────────

test('payment_intent.payment_failed cancels the hold and releases seats', async () => {
  const guest = await freshGuest();
  const eventId = await newEvent(await signIn(NORA_PHONE));
  const { json } = await api(guest, 'POST', `/events/${eventId}/bookings`, { seats: 3 });
  assert.equal(json.booking.paymentStatus, 'pending_payment');
  assert.equal((await eventRow(eventId)).seats_booked, 3);

  const booking = await bookingRow(json.booking.id as string);
  const { status } = await deliverWebhook(
    paymentIntentEvent('payment_intent.payment_failed', booking),
  );
  assert.equal(status, 200);

  const row = await bookingRow(booking.id);
  assert.equal(row.status, 'cancelled');
  assert.equal(row.payment_status, 'failed');
  assert.equal((await eventRow(eventId)).seats_booked, 0);
  const note = await one('SELECT 1 FROM activity WHERE event_id = $1::UUID AND title = $2',
    [eventId, 'Payment did not complete']);
  assert.ok(note, 'guest should be told the payment did not go through');
});

// ── 7. Approval flow: authorize → approve → capture → webhook pays ──────────

test('approval-gated checkout authorizes; approve confirms, webhook pays', async () => {
  const nora = await signIn(NORA_PHONE);
  const eventId = await newEvent(nora, { requiresApproval: true });
  const guest = await freshGuest();
  const { json } = await api(guest, 'POST', `/events/${eventId}/bookings`, { seats: 1 });
  assert.equal(json.booking.status, 'pending');
  assert.equal(json.booking.paymentStatus, 'authorized');
  assert.match(json.booking.clientSecret as string, /^pi_mock_/);

  const booking = await bookingRow(json.booking.id as string);
  assert.equal(booking.stripe_amount_cents, 5000);

  // Approving captures at the gateway but the money only settles on webhook.
  const approved = await api(nora, 'POST', `/bookings/${booking.id}/approve`, {});
  assert.equal(approved.status, 200);
  assert.equal(approved.json.booking.status, 'confirmed');
  assert.equal(approved.json.booking.paymentStatus, 'authorized');
  assert.equal(await payoutRow(eventId), undefined);

  const { status } = await deliverWebhook(
    paymentIntentEvent('payment_intent.succeeded', booking, { latest_charge: CARD_CHARGE }),
  );
  assert.equal(status, 200);
  assert.equal((await bookingRow(booking.id)).payment_status, 'paid');
  const payout = await mustOne<Json>('SELECT gross FROM payouts WHERE event_id = $1::UUID',
    [eventId]);
  assert.equal(Number(payout.gross), 50);
});

// ── 8. Decline moves zero money and voids the authorization ─────────────────

test('host decline books a $0 released row and frees the seat', async () => {
  const nora = await signIn(NORA_PHONE);
  const eventId = await newEvent(nora, { requiresApproval: true });
  const guest = await freshGuest();
  const booking = await bookAndLoad(guest, eventId, 2);
  assert.equal(booking.payment_status, 'authorized');

  const { status } = await api(nora, 'POST', `/bookings/${booking.id}/decline`, {});
  assert.equal(status, 200);

  const row = await bookingRow(booking.id);
  assert.equal(row.status, 'cancelled');
  assert.equal(row.payment_status, 'refunded');
  const refund = await refundRow(booking.id);
  assert.equal(refund.status, 'released');
  assert.equal(Number(refund.amount), 0); // no captured money to return
  assert.equal(refund.gateway_status, 'simulated');
  assert.equal((await eventRow(eventId)).seats_booked, 0);
});

// ── 9. Cancel after settlement: ledger first, webhook confirms ──────────────

test('cancelling a paid booking books pending_gateway until charge.refunded lands', async () => {
  // The owning guest's phone is on the users row; signIn returns their token.
  const owner = await mustOne<Json>('SELECT phone FROM users WHERE id = $1::UUID',
    [deferredBooking.user_id]);
  const guest = await signIn(owner.phone as string);

  const { status, json } = await api(guest, 'POST', `/bookings/${deferredBooking.id}/cancel`, {});
  assert.equal(status, 200);
  assert.equal(json.refund.gatewayStatus, 'pending_gateway');

  const refund = await refundRow(deferredBooking.id);
  assert.equal(refund.status, 'refunded');
  assert.equal(Number(refund.amount), 100);
  assert.equal(refund.gateway_status, 'pending_gateway');
  assert.match(refund.stripe_refund_id, /^re_mock_/);

  // Host earnings rolled back at cancel time (ledger-first), independent of
  // the gateway confirmation which only flips the refund's status.
  const payout = await mustOne<Json>('SELECT gross FROM payouts WHERE event_id = $1::UUID',
    [deferredEventId]);
  assert.equal(Number(payout.gross), 0);

  const { status: ws } = await deliverWebhook({
    id: `evt_itest_refund_${++eventSeq}`,
    object: 'event',
    type: 'charge.refunded',
    created: Math.floor(Date.now() / 1000),
    livemode: false,
    data: {
      object: {
        id: 'ch_itest_charge',
        object: 'charge',
        refunds: {
          object: 'list',
          data: [{
            id: refund.stripe_refund_id,
            object: 'refund',
            metadata: { ledger_refund_id: refund.id },
          }],
        },
      },
    },
  });
  assert.equal(ws, 200);
  assert.equal((await refundRow(deferredBooking.id)).gateway_status, 'confirmed');
});

// ── 10. Abandoned checkouts get swept, not silently held ────────────────────

test('stale pending_payment holds are swept on the bookings read', async () => {
  const guest = await freshGuest();
  const eventId = await newEvent(await signIn(NORA_PHONE));
  const { json } = await api(guest, 'POST', `/events/${eventId}/bookings`, { seats: 4 });
  const booking = await bookingRow(json.booking.id as string);
  assert.equal(booking.payment_status, 'pending_payment');
  assert.equal((await eventRow(eventId)).seats_booked, 4);

  // Age the abandoned checkout past the 30-minute window.
  await exec(
    `UPDATE bookings SET created_at = now() - interval '40 minutes' WHERE id = $1::UUID`,
    [booking.id],
  );

  // `guest` already IS the signed-in token (freshGuest signs in for you);
  // this read triggers the lazy sweep before serializing the list.
  const { status } = await api(guest, 'GET', '/bookings');
  assert.equal(status, 200);

  const row = await bookingRow(booking.id);
  assert.equal(row.status, 'cancelled');
  assert.equal(row.payment_status, 'failed');
  assert.equal((await eventRow(eventId)).seats_booked, 0);
});

// ── 11. A fully-discounted total has nothing to authorize ───────────────────

test('100% promo checkout settles immediately with no payment intent', async () => {
  await exec(
    `INSERT INTO promo_codes (code, discount_pct, active)
     VALUES ('ITFULL100', 100, true) ON CONFLICT (code) DO NOTHING`,
  );
  const guest = await freshGuest();
  const eventId = await newEvent(await signIn(NORA_PHONE));
  const { status, json } = await api(guest, 'POST', `/events/${eventId}/bookings`, {
    seats: 1,
    promoCode: 'ITFULL100',
    paymentLabel: 'Visa •••• 4242',
  });
  assert.equal(status, 201);
  assert.equal(json.booking.paymentStatus, 'paid');
  assert.equal(json.booking.clientSecret, null);
  assert.equal(json.booking.total, 0);

  const row = await bookingRow(json.booking.id as string);
  assert.equal(row.stripe_payment_intent_id, null);
  assert.equal(row.stripe_amount_cents, null);
  assert.equal(row.payment_label, 'Visa •••• 4242');
});

// ── 12. Abandoned-sheet retry re-issues the client secret ─────────────────

test('refresh-payment re-issues the secret while pending, 409 once settled', async () => {
  const guest = await freshGuest();
  const eventId = await newEvent(await signIn(NORA_PHONE));
  const { json } = await api(guest, 'POST', `/events/${eventId}/bookings`, { seats: 1 });
  const booking = await bookingRow(json.booking.id as string);

  const first = await api(guest, 'POST', `/bookings/${booking.id}/refresh-payment`);
  assert.equal(first.status, 200);
  assert.equal(first.json.clientSecret, json.booking.clientSecret); // same hold

  // Another guest cannot mint secrets for someone else's hold.
  const other = await freshGuest();
  const denied = await api(other, 'POST', `/bookings/${booking.id}/refresh-payment`);
  assert.equal(denied.status, 403);

  // Once the webhook settles it, the retry window is closed.
  await deliverWebhook(
    paymentIntentEvent('payment_intent.succeeded', booking, { latest_charge: CARD_CHARGE }),
  );
  const late = await api(guest, 'POST', `/bookings/${booking.id}/refresh-payment`);
  assert.equal(late.status, 409);
});
