import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { notifyVenue } from '../../notify.js';
import {
  adminPage,
  noteSchema,
  pushEquals,
  pushSearch,
  renderList,
  searchTerm,
} from './_shared.js';

/**
 * Subscriptions & Payments.
 *
 * Money arrives offline: a partner pays by bank transfer, JazzCash or
 * Easypaisa, an admin records the receipt, and verifying that receipt is what
 * activates the subscription. Nothing here pretends a gateway exists, and no
 * response claims an email was sent.
 *
 * The subscription row itself is still owned by `partner_venues.ts`, whose
 * `POST /api/admin/restaurants/:id/subscription/activate` stays mounted for the
 * shipped Partner App. `setStatus()` below is the same write so the console and
 * that endpoint cannot disagree.
 */
const router = Router();

const RECEIPT_SELECT = `
  p.id, p.restaurant_id, p.amount_pkr, p.method, p.reference, p.proof_path,
  p.status, p.rejection_reason, p.created_at, p.verified_at,
  r.name AS venue_name, r.city,
  up.name AS uploaded_name, vf.name AS verified_name,
  s.plan AS subscription_plan, s.status AS subscription_status,
  s.period_end AS subscription_period_end`;

const RECEIPT_FROM = `
  FROM partner_payment_receipts p
  JOIN restaurants r ON r.id = p.restaurant_id
  LEFT JOIN users up ON up.id = p.uploaded_by
  LEFT JOIN users vf ON vf.id = p.verified_by
  LEFT JOIN partner_subscriptions s ON s.restaurant_id = p.restaurant_id`;

function shapeReceipt(row: Record<string, unknown>) {
  return {
    id: row.id,
    restaurantId: row.restaurant_id,
    venueId: row.restaurant_id,
    venueName: row.venue_name,
    city: row.city,
    amount: Number(row.amount_pkr ?? 0),
    amountPkr: Number(row.amount_pkr ?? 0),
    method: row.method,
    reference: row.reference,
    proofPath: row.proof_path,
    status: row.status,
    rejectionReason: row.rejection_reason,
    createdAt: row.created_at,
    uploadedAt: row.created_at,
    verifiedAt: row.verified_at,
    uploadedBy: row.uploaded_name,
    verifiedBy: row.verified_name,
    subscriptionPlan: row.subscription_plan,
    subscriptionStatus: row.subscription_status ?? 'none',
    subscriptionPeriodEnd: row.subscription_period_end,
  };
}

/** `nextExpiry` equivalent: whole-month / whole-year from a base date. */
export function addCycle(from: Date, cycle: 'month' | 'year'): Date {
  const next = new Date(from.getTime());
  if (cycle === 'year') next.setFullYear(next.getFullYear() + 1);
  else next.setMonth(next.getMonth() + 1);
  return next;
}

/** Mirrors `POST /api/admin/restaurants/:id/subscription/activate`. */
async function setStatus(
  restaurantId: string,
  status: 'active' | 'past_due' | 'cancelled',
): Promise<Record<string, unknown>> {
  const now = new Date();
  return withTransaction(async (client) => {
    const { rows } = await client.query<Record<string, unknown>>(
      `SELECT * FROM partner_subscriptions WHERE restaurant_id = $1::UUID FOR UPDATE`,
      [restaurantId],
    );
    const current = rows[0];
    if (!current) throw notFound('Subscription');

    const { rows: updated } = await client.query<Record<string, unknown>>(
      `UPDATE partner_subscriptions
          SET status = $2,
              cancelled_at = CASE WHEN $2 = 'cancelled' THEN $3::timestamptz
                                  ELSE cancelled_at END,
              period_start = CASE WHEN $2 = 'active' AND period_start IS NULL
                                  THEN $3::timestamptz ELSE period_start END,
              period_end = CASE WHEN $2 = 'active' AND period_end IS NULL
                                THEN make_timestamptz(
                                       EXTRACT(year FROM $3::timestamptz)::int,
                                       EXTRACT(month FROM $3::timestamptz)::int + 1,
                                       1, 'UTC')
                                ELSE period_end END,
              updated_at = now()
        WHERE restaurant_id = $1::UUID
        RETURNING *`,
      [restaurantId, status, now],
    );
    return updated[0]!;
  });
}

const planRow = async (planId: string) =>
  (
    await query<{ id: string; cycle: string; price_pkr: number; name: string }>(
      'SELECT id, cycle, price_pkr, name FROM subscription_plans WHERE id = $1',
      [planId],
    )
  )[0];

/**
 * GET /api/admin/subscriptions?page&limit&status&q
 * One row per venue subscription, with the payment trail folded in so the
 * drawer can show the last receipt without a second request.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  pushEquals(where, params, req.query.status as string | undefined, 's.status');
  pushSearch(where, params, searchTerm(req), ['r.name', 'r.city']);

  await renderList(res, 'subscriptions', {
    select: `
      s.id, s.restaurant_id, s.plan, s.status, s.price_pkr, s.period_start,
      s.period_end, s.auto_renew, s.cancelled_at, s.updated_at,
      r.name AS venue_name, r.city, r.partnership_status,
      (SELECT p2.created_at FROM partner_payment_receipts p2
        WHERE p2.restaurant_id = s.restaurant_id
        ORDER BY p2.created_at DESC LIMIT 1) AS last_payment_at,
      (SELECT p3.amount_pkr FROM partner_payment_receipts p3
        WHERE p3.restaurant_id = s.restaurant_id
        ORDER BY p3.created_at DESC LIMIT 1) AS last_amount_pkr,
      (SELECT count(*)::int FROM partner_payment_receipts p4
        WHERE p4.restaurant_id = s.restaurant_id
          AND p4.status = 'awaiting_verification') AS awaiting_count`,
    from: `
      FROM partner_subscriptions s
      JOIN restaurants r ON r.id = s.restaurant_id`,
    where,
    params,
    order: `CASE s.status WHEN 'past_due' THEN 0 WHEN 'active' THEN 1 ELSE 2 END,
            s.period_end NULLS LAST, r.name ASC`,
    page: adminPage(req),
  }, (row) => ({
    id: row.id,
    restaurantId: row.restaurant_id,
    venueId: row.restaurant_id,
    venueName: row.venue_name,
    city: row.city,
    plan: row.plan ?? 'none',
    status: row.status,
    price: Number(row.price_pkr ?? 0),
    partnershipStatus: row.partnership_status,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    expiry: row.period_end,
    autoRenew: row.auto_renew,
    cancelledAt: row.cancelled_at,
    lastPaymentAt: row.last_payment_at,
    lastAmount: row.last_amount_pkr === null ? null : Number(row.last_amount_pkr),
    awaitingReceipts: row.awaiting_count,
    updatedAt: row.updated_at,
  }));
});

/**
 * GET /api/admin/subscriptions/receipts?status=awaiting_verification
 * The verification queue. Registered before `/:restaurantId` so the literal
 * path is not swallowed by the parameter route.
 */
router.get('/receipts', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status === '' || status === 'all') {
    where.push(`p.status = 'awaiting_verification'`);
  } else {
    params.push(status);
    where.push(`p.status = $${params.length}`);
  }
  pushSearch(where, params, searchTerm(req), ['r.name', 'p.reference']);

  await renderList(res, 'receipts', {
    select: RECEIPT_SELECT,
    from: RECEIPT_FROM,
    where,
    params,
    order: 'p.created_at DESC',
    page: adminPage(req),
  }, shapeReceipt);
});

const verifySchema = z.object({ note: noteSchema });
const rejectSchema = z.object({ reason: z.string().trim().min(3).max(1000) });

/**
 * POST /api/admin/subscriptions/receipts/:id/verify
 * Verifying is the activation: the receipt flips to `verified`, the venue's
 * subscription goes active with a period derived from the plan cycle, and the
 * desk is told in the same transaction.
 */
router.post('/receipts/:id/verify', async (req, res) => {
  requireAdminConsole(req);
  const input = verifySchema.parse(req.body ?? {});

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<Record<string, unknown>>(
      `SELECT id, restaurant_id, amount_pkr, status, method
         FROM partner_payment_receipts
        WHERE id = $1::UUID
        FOR UPDATE`,
      [req.params.id],
    );
    const receipt = rows[0];
    if (!receipt) throw notFound('Receipt');
    if (receipt.status !== 'awaiting_verification') {
      throw new ApiError(409, `This receipt was already ${receipt.status}`);
    }

    // The plan id lives in `subscription_plans` while the subscription's `plan`
    // column is the narrower 'monthly'|'yearly' enum. A renewal of an existing
    // yearly partner must not silently downgrade them to a monthly period, so
    // the cycle is taken from the venue's current plan when it has one.
    const { rows: owned } = await client.query<{ plan: string | null }>(
      'SELECT plan FROM partner_subscriptions WHERE restaurant_id = $1::UUID',
      [receipt.restaurant_id],
    );
    const wantedCycle = owned[0]?.plan === 'yearly' ? 'year' : 'month';
    const { rows: plans } = await client.query<{ cycle: string; price_pkr: number }>(
      `SELECT cycle, price_pkr FROM subscription_plans
        WHERE cycle = $1 AND is_active LIMIT 1`,
      [wantedCycle],
    );
    const cycle = plans[0]?.cycle ?? wantedCycle;
    const price = plans[0]?.price_pkr ?? (cycle === 'year' ? 50000 : 5000);
    const subscriptionPlan = cycle === 'year' ? 'yearly' : 'monthly';

    const now = new Date();
    const periodEnd = addCycle(now, cycle === 'year' ? 'year' : 'month');

    await client.query(
      `UPDATE partner_payment_receipts
          SET status = 'verified', verified_by = $2::UUID, verified_at = now(),
              rejection_reason = '', updated_at = now()
        WHERE id = $1::UUID`,
      [receipt.id, req.userId],
    );

    const { rows: subscribed } = await client.query<Record<string, unknown>>(
      `INSERT INTO partner_subscriptions
         (restaurant_id, plan, status, price_pkr, period_start, period_end, updated_at)
       VALUES ($1::UUID, $2, 'active', $3, $4::timestamptz, $5::timestamptz, now())
       ON CONFLICT (restaurant_id)
       DO UPDATE SET status = 'active', plan = EXCLUDED.plan,
                     price_pkr = EXCLUDED.price_pkr,
                     period_start = EXCLUDED.period_start,
                     period_end = GREATEST(
                       COALESCE(partner_subscriptions.period_end, EXCLUDED.period_end),
                       EXCLUDED.period_end),
                     cancelled_at = NULL, updated_at = now()
       RETURNING id, restaurant_id, plan, status, price_pkr, period_start, period_end`,
      [receipt.restaurant_id, subscriptionPlan, price, now, periodEnd],
    );

    await notifyVenue(client, String(receipt.restaurant_id), {
      title: 'Payment verified',
      body: `Your ${cycle === 'year' ? 'annual' : 'monthly'} payment of Rs. ${Number(
        receipt.amount_pkr,
      ).toLocaleString('en-GB')} is confirmed. Partner Pro runs to ${periodEnd
        .toISOString()
        .slice(0, 10)}.`,
      kind: 'approval',
    });

    return {
      receipt: receipt.id,
      restaurantId: receipt.restaurant_id,
      amountPkr: Number(receipt.amount_pkr),
      subscription: subscribed[0] ?? null,
      planCycle: cycle,
      note: input.note,
    };
  });

  res.json(one('verification', result));
});

// POST /api/admin/subscriptions/receipts/:id/reject
router.post('/receipts/:id/reject', async (req, res) => {
  requireAdminConsole(req);
  const input = rejectSchema.parse(req.body ?? {});

  const [receipt] = await query<Record<string, unknown>>(
    `SELECT id, restaurant_id, status FROM partner_payment_receipts
      WHERE id = $1::UUID`,
    [req.params.id],
  );
  if (!receipt) throw notFound('Receipt');
  if (receipt.status !== 'awaiting_verification') {
    throw new ApiError(409, `This receipt was already ${receipt.status}`);
  }

  const [updated] = await query<Record<string, unknown>>(
    `UPDATE partner_payment_receipts
        SET status = 'rejected', rejection_reason = $2, verified_by = $3::UUID,
            verified_at = now(), updated_at = now()
      WHERE id = $1::UUID RETURNING id, restaurant_id, amount_pkr, status`,
    [req.params.id, input.reason, req.userId],
  );

  await notifyVenue(null, String(updated!.restaurant_id), {
    title: 'Payment could not be verified',
    body: input.reason,
    kind: 'approval',
  });

  res.json(one('receipt', shapeReceipt({ ...updated, rejection_reason: input.reason })));
});

const recordSchema = z.object({
  amountPkr: z.number().int().min(0).max(10_000_000),
  method: z.enum(['bank_transfer', 'jazzcash', 'easypaisa']),
  reference: z.string().trim().max(120).default(''),
  proofPath: z.string().trim().max(400).default(''),
});

/**
 * POST /api/admin/subscriptions/:restaurantId/record-payment
 * The console's stand-in for the partner uploading a slip: an admin who was
 * handed the transfer screen keying it in on the venue's behalf. It lands in
 * the same awaiting-verification queue either way, so nothing gets activated by
 * typing the number.
 */
router.post('/:restaurantId/record-payment', async (req, res) => {
  requireAdminConsole(req);
  const input = recordSchema.parse(req.body ?? {});

  const [venue] = await query<{ id: string }>(
    'SELECT id FROM restaurants WHERE id = $1::UUID',
    [req.params.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');

  const [created] = await query<Record<string, unknown>>(
    `INSERT INTO partner_payment_receipts
       (restaurant_id, amount_pkr, method, reference, proof_path, status, uploaded_by)
     VALUES ($1::UUID, $2, $3, $4, $5, 'awaiting_verification', $6::UUID)
     RETURNING id, restaurant_id, amount_pkr, method, reference, proof_path,
               status, created_at`,
    [
      venue.id,
      input.amountPkr,
      input.method,
      input.reference,
      input.proofPath,
      req.userId,
    ],
  );

  res.status(201).json(
    one('receipt', {
      ...shapeReceipt({ ...created, venue_name: '' }),
      uploadedBy: 'Platform team',
    }),
  );
});

const renewSchema = z.object({ plan: z.enum(['pro_monthly', 'pro_yearly']) });

/**
 * POST /api/admin/subscriptions/:restaurantId/renew
 * Extends the period from whichever is later: now, or the existing expiry, so
 * renewing early does not throw away days already paid for.
 */
router.post('/:restaurantId/renew', async (req, res) => {
  requireAdminConsole(req);
  const input = renewSchema.parse(req.body ?? {});

  const plan = await planRow(input.plan);
  if (!plan) throw notFound('Plan');
  const cycle = plan.cycle === 'year' ? 'year' : 'month';

  const [current] = await query<{ period_end: Date | null; status: string }>(
    `SELECT period_end, status FROM partner_subscriptions
      WHERE restaurant_id = $1::UUID`,
    [req.params.restaurantId],
  );
  if (!current) throw notFound('Subscription');

  const now = new Date();
  const existingEnd = current.period_end ? new Date(current.period_end) : now;
  const base = existingEnd > now ? existingEnd : now;
  const periodEnd = addCycle(base, cycle);

  const [updated] = await query<Record<string, unknown>>(
    `UPDATE partner_subscriptions
        SET plan = $2, price_pkr = $3, status = 'active',
            period_start = COALESCE(period_start, now()),
            period_end = $4::timestamptz, cancelled_at = NULL, updated_at = now()
      WHERE restaurant_id = $1::UUID
      RETURNING id, restaurant_id, plan, status, price_pkr, period_start, period_end`,
    [
      req.params.restaurantId,
      cycle === 'year' ? 'yearly' : 'monthly',
      plan.price_pkr,
      periodEnd,
    ],
  );

  res.json(one('subscription', { ...updated!, renewedFrom: base }));
});

const activateSchema = z.object({ status: z.enum(['active', 'past_due', 'cancelled']) });

/**
 * POST /api/admin/subscriptions/:restaurantId/activate
 * The console-side twin of the existing admin activate route, kept so the
 * console has one base path to talk to. It calls the same write.
 */
router.post('/:restaurantId/activate', async (req, res) => {
  requireAdminConsole(req);
  const input = activateSchema.parse(req.body ?? {});
  const subscription = await setStatus(req.params.restaurantId, input.status);
  res.json(one('subscription', subscription));
});

// GET /api/admin/subscriptions/plans, the two Partner Pro options.
router.get('/plans', async (req, res) => {
  requireAdminConsole(req);
  const rows = await query<Record<string, unknown>>(
    `SELECT id, name, cycle, price_pkr, is_active, inclusions
       FROM subscription_plans ORDER BY price_pkr ASC`,
  );
  res.json({
    data: {
      plans: rows.map((p) => ({
        id: p.id,
        name: p.name,
        cycle: p.cycle,
        price: Number(p.price_pkr),
        isActive: p.is_active,
        inclusions: p.inclusions,
      })),
    },
    meta: { total: rows.length },
  });
});

// GET /api/admin/subscriptions/:restaurantId, one venue's full payment history.
router.get('/:restaurantId', async (req, res) => {
  requireAdminConsole(req);
  const [subscription] = await query<Record<string, unknown>>(
    `SELECT s.id, s.restaurant_id, s.plan, s.status, s.price_pkr, s.period_start,
            s.period_end, s.auto_renew, s.cancelled_at, s.updated_at,
            r.name AS venue_name, r.city, r.partnership_status, r.is_partner
       FROM partner_subscriptions s
       JOIN restaurants r ON r.id = s.restaurant_id
      WHERE s.restaurant_id = $1::UUID`,
    [req.params.restaurantId],
  );
  if (!subscription) throw notFound('Subscription');

  const receipts = await query<Record<string, unknown>>(
    `SELECT ${RECEIPT_SELECT} ${RECEIPT_FROM}
      WHERE p.restaurant_id = $1::UUID ORDER BY p.created_at DESC LIMIT 50`,
    [req.params.restaurantId],
  );

  res.json(
    one('subscription', {
      ...subscription,
      venueId: subscription.restaurant_id,
      price: Number(subscription.price_pkr ?? 0),
      expiry: subscription.period_end,
      receipts: receipts.map(shapeReceipt),
    }),
  );
});

export default router;
