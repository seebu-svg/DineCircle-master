import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { restoreUser, suspendUser } from '../../moderation.js';
import { adminPage, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Customer Management.
 *
 * A customer is simply `users WHERE role = 'user'`. Suspension writes
 * `suspended_at`, which `requireAuth` reads on every authenticated request, so
 * freezing an account here logs it out of both mobile apps immediately without
 * a client-side change.
 */
const router = Router();

const CUSTOMER_SELECT = `
  u.id, u.name, u.handle, u.email, u.phone, u.city, u.avatar_url, u.role,
  u.account_type, u.created_at, u.dinners_joined, u.dinners_hosted,
  u.followers_count, u.rating, u.is_deleted, u.suspended_at, u.suspension_reason,
  (SELECT count(*)::int FROM table_reservations t
     WHERE t.user_id = u.id)                                    AS reservations,
  (SELECT count(*)::int FROM bookings b
     WHERE b.user_id = u.id)                                    AS bookings,
  (SELECT count(*)::int FROM reports r
     JOIN users rep ON rep.id = r.reporter_id
     WHERE rep.id = u.id)                                       AS reports_filed,
  (SELECT count(*)::int FROM reports r
     WHERE r.target_type = 'user' AND r.target_id = u.id
       AND r.status IN ('pending','reviewing'))                 AS open_reports`;

function shape(row: Record<string, unknown>) {
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
    joinedAt: row.created_at,
    dinnersJoined: row.dinners_joined,
    dinnersHosted: row.dinners_hosted,
    followers: row.followers_count,
    rating: Number(row.rating ?? 0),
    deleted: row.is_deleted,
    suspendedAt: row.suspended_at,
    suspensionReason: row.suspension_reason ?? '',
    status: row.is_deleted
      ? 'deleted'
      : row.suspended_at
        ? 'suspended'
        : 'active',
    reservations: row.reservations,
    bookings: row.bookings,
    reportsFiled: row.reports_filed,
    openReports: row.open_reports,
  };
}

/**
 * GET /api/admin/customers?page&limit&status&q
 * `status` is `active`, `suspended` or `deleted`; there is no partial state.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [`u.role = 'user'`];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status === 'suspended') where.push('u.suspended_at IS NOT NULL');
  else if (status === 'active') where.push('u.suspended_at IS NULL AND NOT u.is_deleted');
  else if (status === 'deleted') where.push('u.is_deleted');

  pushSearch(where, params, searchTerm(req), ['u.name', 'u.email', 'u.handle', 'u.city']);

  await renderList(res, 'customers', {
    select: CUSTOMER_SELECT,
    from: 'FROM users u',
    where,
    params,
    order: 'u.created_at DESC',
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/customers/:userId
router.get('/:userId', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${CUSTOMER_SELECT}, u.bio, u.badges, u.tastes, u.home_area,
            u.dietary, u.allergies
       FROM users u WHERE u.id = $1::UUID`,
    [req.params.userId],
  );
  if (!row) throw notFound('Customer');

  const [recentReservations, tickets, reports] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT t.id, t.reference, t.party_size, t.start_at, t.status, r.name AS venue_name
         FROM table_reservations t
         JOIN restaurants r ON r.id = t.restaurant_id
        WHERE t.user_id = $1::UUID ORDER BY t.created_at DESC LIMIT 20`,
      [req.params.userId],
    ),
    query<Record<string, unknown>>(
      `SELECT id, ticket, category, subject, status, created_at
         FROM feedback WHERE user_id = $1::UUID
           AND status IN ('open','in_progress')
        ORDER BY created_at DESC LIMIT 20`,
      [req.params.userId],
    ),
    query<Record<string, unknown>>(
      `SELECT r.id, r.reference, r.target_type, r.reason, r.status, r.created_at
         FROM reports r
         JOIN users rep ON rep.id = r.reporter_id
        WHERE rep.id = $1::UUID ORDER BY r.created_at DESC LIMIT 20`,
      [req.params.userId],
    ),
  ]);

  res.json(
    one('customer', {
      ...shape(row),
      bio: row.bio,
      badges: row.badges,
      tastes: row.tastes,
      homeArea: row.home_area,
      dietary: row.dietary,
      allergies: row.allergies,
      reservations: recentReservations.map((t) => ({
        id: t.id,
        reference: t.reference,
        venueName: t.venue_name,
        partySize: t.party_size,
        startAt: t.start_at,
        status: t.status,
      })),
      openTickets: tickets.map((t) => ({
        id: t.id,
        ticket: t.ticket,
        category: t.category,
        subject: t.subject,
        status: t.status,
        createdAt: t.created_at,
      })),
      reportsFiled: reports.map((r) => ({
        id: r.id,
        reference: r.reference,
        targetType: r.target_type,
        reason: r.reason,
        status: r.status,
        createdAt: r.created_at,
      })),
    }),
  );
});

const suspendSchema = z.object({ reason: z.string().trim().min(3).max(1000) });

// POST /api/admin/customers/:userId/suspend
router.post('/:userId/suspend', async (req, res) => {
  requireAdminConsole(req);
  const input = suspendSchema.parse(req.body ?? {});
  const result = await suspendUser({
    userId: req.params.userId,
    reason: input.reason,
  });
  res.json(one('customer', { ...result, status: 'suspended' }));
});

// POST /api/admin/customers/:userId/restore
router.post('/:userId/restore', async (req, res) => {
  requireAdminConsole(req);
  const result = await restoreUser({ userId: req.params.userId });
  res.json(one('customer', { userId: result.userId, status: 'active' }));
});

export default router;
