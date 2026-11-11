import { Router } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';
import { query } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole, requireSuperAdmin } from '../../access.js';
import { one } from '../../api.js';
import { inviteStaffToVenue } from '../../partner_staff.js';
import { restoreUser, suspendUser } from '../../moderation.js';
import { hashPassword } from '../../passwords.js';
import { adminPage, noteSchema, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Partner Accounts.
 *
 * A partner "account" is a `users` row with a partner role plus its venue
 * memberships in `restaurant_staff`; there is no separate table. The list
 * therefore aggregates memberships per person, and the console's status column
 * is derived: a suspended account outranks the membership state, because that
 * is the thing an operator has to act on.
 */
const router = Router();

const ACCOUNT_SELECT = `
  u.id, u.name, u.handle, u.email, u.phone, u.city, u.role, u.account_type,
  u.avatar_url, u.created_at, u.suspended_at, u.suspension_reason,
  COALESCE(jsonb_agg(jsonb_build_object(
      'restaurantId', s.restaurant_id, 'name', r.name, 'city', r.city,
      'role', s.role, 'status', s.status, 'updatedAt', s.updated_at)
      ORDER BY r.name) FILTER (WHERE s.restaurant_id IS NOT NULL), '[]') AS venues,
  COALESCE(max(s.status), 'none') AS membership_status`;

const ACCOUNT_FROM = `
  FROM users u
  LEFT JOIN restaurant_staff s ON s.user_id = u.id
  LEFT JOIN restaurants r ON r.id = s.restaurant_id`;

const ACCOUNT_WHERE = `u.role IN ('restaurant_owner','restaurant_staff','partner_admin')`;

function shape(row: Record<string, unknown>) {
  const venues = (row.venues ?? []) as Array<Record<string, unknown>>;
  const membership = String(row.membership_status ?? 'none');
  return {
    id: row.id,
    userId: row.id,
    name: row.name,
    handle: row.handle,
    email: row.email,
    phone: row.phone,
    city: row.city,
    role: row.role,
    accountType: row.account_type,
    avatarUrl: row.avatar_url,
    createdAt: row.created_at,
    venues,
    venueCount: venues.length,
    // The console shows one line per venue membership, so a multi-venue partner
    // surfaces its richest state here.
    membershipStatus: membership,
    status: row.suspended_at ? 'suspended' : membership === 'none' ? 'none' : membership,
    suspendedAt: row.suspended_at,
    suspensionReason: row.suspension_reason ?? '',
  };
}

/**
 * GET /api/admin/partner-accounts?page&limit&status&q
 * `status` matches the membership state (`invited`/`active`/`revoked`) or
 * `suspended`, which lives on the account rather than the membership.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [ACCOUNT_WHERE];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status === 'suspended') {
    where.push('u.suspended_at IS NOT NULL');
  } else if (status !== '' && status !== 'all' && status !== 'none') {
    where.push(`s.status = $${params.length + 1}`);
    params.push(status);
  }

  pushSearch(where, params, searchTerm(req), ['u.name', 'u.email', 'u.handle', 'r.name']);

  // Aggregated per account, so the count helper has to count groups.
  await renderList(res, 'partnerAccounts', {
    select: ACCOUNT_SELECT,
    from: ACCOUNT_FROM,
    where,
    params,
    order: 'u.name ASC',
    page: adminPage(req),
    groupBy: 'GROUP BY u.id',
  }, shape);
});

// GET /api/admin/partner-accounts/:userId
router.get('/:userId', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${ACCOUNT_SELECT}, u.admin_scope
       ${ACCOUNT_FROM}
      WHERE u.id = $1::UUID
      GROUP BY u.id`,
    [req.params.userId],
  );
  if (!row) throw notFound('Partner account');

  const [applications, receipts] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT v.id, v.status, v.note, v.reviewer_note, v.created_at, v.reviewed_at,
              r.name AS venue_name
         FROM partner_verification_requests v
         JOIN restaurants r ON r.id = v.restaurant_id
         JOIN restaurant_staff s ON s.restaurant_id = r.id
        WHERE s.user_id = $1::UUID
        ORDER BY v.created_at DESC LIMIT 20`,
      [req.params.userId],
    ),
    query<Record<string, unknown>>(
      `SELECT p.id, p.amount_pkr, p.method, p.status, p.created_at, r.name AS venue_name
         FROM partner_payment_receipts p
         JOIN restaurants r ON r.id = p.restaurant_id
         JOIN restaurant_staff s ON s.restaurant_id = r.id
        WHERE s.user_id = $1::UUID
        ORDER BY p.created_at DESC LIMIT 20`,
      [req.params.userId],
    ),
  ]);

  res.json(
    one('partnerAccount', {
      ...shape(row),
      adminScope: row.admin_scope,
      applications: applications.map((a) => ({
        id: a.id,
        venueName: a.venue_name,
        status: a.status,
        note: a.note,
        reviewerNote: a.reviewer_note,
        createdAt: a.created_at,
        reviewedAt: a.reviewed_at,
      })),
      receipts: receipts.map((r) => ({
        id: r.id,
        venueName: r.venue_name,
        amount: Number(r.amount_pkr),
        method: r.method,
        status: r.status,
        createdAt: r.created_at,
      })),
    }),
  );
});

const createSchema = z.object({
  name: z.string().trim().min(2).max(120),
  email: z.string().trim().email().max(160),
  restaurantId: z.string().uuid(),
  // The console mints the account the same way `create_individual_partner_accounts.sql`
  // does, so a new partner always arrives as an owner of exactly one venue.
  role: z.enum(['restaurant_owner']).default('restaurant_owner'),
  city: z.string().trim().max(60).default('Karachi'),
});

/**
 * POST /api/admin/partner-accounts
 * Creates the user, an `invited` owner membership on the venue, and the desk
 * notification, all through the shared invite helper so the row set matches a
 * partner-side invite.
 */
router.post('/', async (req, res) => {
  requireSuperAdmin(req);
  const input = createSchema.parse(req.body ?? {});

  const [venue] = await query<{ id: string; name: string }>(
    'SELECT id, name FROM restaurants WHERE id = $1::UUID',
    [input.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');

  const created = await inviteStaffToVenue({
    restaurantId: venue.id,
    role: 'owner',
    actorId: req.userId,
    actorIsAdmin: true,
    email: input.email,
    name: input.name,
    createIfMissing: true,
  });

  if (created.created) {
    const [user] = await query<{ id: string }>(
      `UPDATE users SET role = $2, city = $3
        WHERE id = $1::UUID RETURNING id`,
      [created.userId, input.role, input.city],
    );
    if (!user) throw new ApiError(500, 'Could not finish creating the account');
  }

  const [row] = await query<Record<string, unknown>>(
    `SELECT ${ACCOUNT_SELECT} ${ACCOUNT_FROM} WHERE u.id = $1::UUID GROUP BY u.id`,
    [created.userId],
  );
  if (!row) throw notFound('Partner account');
  res.status(201).json(one('partnerAccount', shape(row)));
});

const venuesSchema = z.object({
  restaurantIds: z.array(z.string().uuid()).max(50),
  roles: z.record(z.string().uuid(), z.enum(['owner', 'manager', 'staff'])).default({}),
});

/**
 * PATCH /api/admin/partner-accounts/:userId/venues
 * Replaces the account's non-owner memberships with the submitted set. Rows
 * outside the set are revoked rather than deleted, so the venue keeps its
 * history of who had access. An admin assigns membership directly instead of
 * inviting, which is why the write goes through here and not the invite helper.
 */
router.patch('/:userId/venues', async (req, res) => {
  requireAdminConsole(req);
  const input = venuesSchema.parse(req.body ?? {});

  const [account] = await query<{ id: string; phone: string | null }>(
    `SELECT id, phone FROM users
      WHERE id = $1::UUID AND role IN ('restaurant_owner','restaurant_staff','partner_admin')`,
    [req.params.userId],
  );
  if (!account) throw notFound('Partner account');

  const wanted = new Set(input.restaurantIds);
  if (wanted.size > 0) {
    const [present] = await query<{ count: number }>(
      `SELECT count(DISTINCT id)::int AS count FROM restaurants
        WHERE id = ANY($1::uuid[])`,
      [[...wanted]],
    );
    if ((present?.count ?? 0) !== wanted.size) throw notFound('Restaurant');
  }

  const existing = await query<{ restaurant_id: string }>(
    `SELECT restaurant_id FROM restaurant_staff
      WHERE user_id = $1::UUID AND role <> 'owner' AND status <> 'revoked'`,
    [req.params.userId],
  );
  for (const membership of existing) {
    if (wanted.has(membership.restaurant_id)) continue;
    await query(
      `UPDATE restaurant_staff SET status = 'revoked', updated_at = now()
        WHERE user_id = $1::UUID AND restaurant_id = $2::UUID`,
      [req.params.userId, membership.restaurant_id],
    );
  }

  for (const restaurantId of wanted) {
    await query(
      `INSERT INTO restaurant_staff (user_id, restaurant_id, role, status, invited_by)
       VALUES ($1::UUID, $2::UUID, $3, 'active', $4::UUID)
       ON CONFLICT (user_id, restaurant_id)
       DO UPDATE SET role = EXCLUDED.role, status = 'active', updated_at = now()`,
      [req.params.userId, restaurantId, input.roles[restaurantId] ?? 'staff', req.userId],
    );
  }

  const [row] = await query<Record<string, unknown>>(
    `SELECT ${ACCOUNT_SELECT} ${ACCOUNT_FROM} WHERE u.id = $1::UUID GROUP BY u.id`,
    [req.params.userId],
  );
  if (!row) throw notFound('Partner account');
  res.json(one('partnerAccount', shape(row)));
});

// POST /api/admin/partner-accounts/:userId/suspend
router.post('/:userId/suspend', async (req, res) => {
  requireAdminConsole(req);
  const input = noteSchema.parse(req.body?.reason ?? '');
  const result = await suspendUser({
    userId: req.params.userId,
    reason: typeof input === 'string' ? input : '',
  });
  res.json(one('partnerAccount', result));
});

// POST /api/admin/partner-accounts/:userId/restore
router.post('/:userId/restore', async (req, res) => {
  requireAdminConsole(req);
  const result = await restoreUser({ userId: req.params.userId });
  res.json(one('partnerAccount', result));
});

/**
 * POST /api/admin/partner-accounts/:userId/reset-password
 * No mail provider is configured on this deployment, so the temporary password
 * is returned to the console once and the operator reads it to the partner.
 * The response never claims a message was sent.
 */
router.post('/:userId/reset-password', async (req, res) => {
  requireSuperAdmin(req);
  const [account] = await query<{ id: string; name: string; email: string | null }>(
    `SELECT id, name, email FROM users
      WHERE id = $1::UUID AND role IN ('restaurant_owner','restaurant_staff','partner_admin')`,
    [req.params.userId],
  );
  if (!account) throw notFound('Partner account');

  const temporary = crypto.randomBytes(6).toString('base64url');
  await query('UPDATE users SET password_hash = $2 WHERE id = $1::UUID', [
    account.id,
    await hashPassword(temporary),
  ]);

  res.json(
    one('reset', {
      userId: account.id,
      name: account.name,
      email: account.email,
      temporaryPassword: temporary,
      delivered: 'read-aloud',
      note: 'No email provider is configured, so share this with the partner directly.',
    }),
  );
});

export default router;
