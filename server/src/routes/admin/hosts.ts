import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { restoreUser, suspendUser } from '../../moderation.js';
import { activeHostedExperiences } from '../users.js';
import { adminPage, noteSchema, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Host Management.
 *
 * Hosts are recognised the way the platform already recognises them: an
 * account in Professional mode, or on the host/influencer rung. The switch is
 * `account_type`, so a host who once went Professional and came back keeps
 * appearing here as long as they host.
 */
const router = Router();

const HOST_WHERE = `(u.account_type = 'professional' OR u.role IN ('host','influencer'))`;

const HOST_SELECT = `
  u.id, u.name, u.handle, u.email, u.phone, u.city, u.bio, u.role,
  u.account_type, u.avatar_url, u.badges, u.created_at, u.professional_since,
  u.dinners_hosted, u.followers_count, u.rating, u.review_count,
  u.suspended_at, u.suspension_reason,
  (SELECT count(*)::int FROM dinner_events e
     WHERE e.host_id = u.id AND e.status IN ('confirmed','live'))  AS live_events,
  (SELECT count(*)::int FROM dinner_events e
     WHERE e.host_id = u.id AND e.status = 'cancelled')            AS cancelled_events,
  (SELECT count(*)::int FROM reviews r
     JOIN dinner_events e ON e.id = r.event_id
     WHERE e.host_id = u.id)                                       AS reviews,
  (SELECT COALESCE(round(avg(r.rating), 2), 0)::numeric FROM reviews r
     JOIN dinner_events e ON e.id = r.event_id
     WHERE e.host_id = u.id)                                       AS avg_rating,
  (SELECT count(*)::int FROM reports rp
     WHERE rp.target_type = 'user' AND rp.target_id = u.id
       AND rp.status IN ('pending','reviewing'))                    AS open_reports`;

function shape(row: Record<string, unknown>) {
  return {
    id: row.id,
    userId: row.id,
    name: row.name,
    handle: row.handle,
    email: row.email,
    phone: row.phone,
    city: row.city,
    bio: row.bio,
    role: row.role,
    accountType: row.account_type,
    avatarUrl: row.avatar_url,
    badges: row.badges,
    createdAt: row.created_at,
    since: row.professional_since,
    hosted: row.dinners_hosted,
    followers: row.followers_count,
    rating: Number(row.avg_rating ?? row.rating ?? 0),
    reviewCount: row.review_count,
    liveEvents: row.live_events,
    cancelledEvents: row.cancelled_events,
    reviewTotal: row.reviews,
    openReports: row.open_reports,
    suspendedAt: row.suspended_at,
    suspensionReason: row.suspension_reason ?? '',
    status: row.suspended_at
      ? 'suspended'
      : Number(row.open_reports ?? 0) > 0
        ? 'under_review'
        : 'active',
  };
}

/**
 * GET /api/admin/hosts?page&limit&status&q
 * `status` is `active`, `suspended` or `under_review` (has an open report), so
 * the console's "flagged hosts" badge and this filter agree.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [HOST_WHERE];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status === 'suspended') where.push('u.suspended_at IS NOT NULL');
  else if (status === 'under_review') where.push(
    `(SELECT count(*)::int FROM reports rp
       WHERE rp.target_type = 'user' AND rp.target_id = u.id
         AND rp.status IN ('pending','reviewing')) > 0`,
  );
  else if (status === 'active') where.push('u.suspended_at IS NULL');

  pushSearch(where, params, searchTerm(req), ['u.name', 'u.email', 'u.handle', 'u.city']);

  await renderList(res, 'hosts', {
    select: HOST_SELECT,
    from: 'FROM users u',
    where,
    params,
    order: 'u.dinners_hosted DESC, u.name ASC',
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/hosts/:userId
router.get('/:userId', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${HOST_SELECT} FROM users u WHERE u.id = $1::UUID`,
    [req.params.userId],
  );
  if (!row) throw notFound('Host');

  const [events, reports] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT e.id, e.title, e.start_at, e.status, e.moderation_status, e.seats_total,
              e.seats_booked, e.price_per_seat, r.name AS venue_name
         FROM dinner_events e
         LEFT JOIN restaurants r ON r.id = e.restaurant_id
        WHERE e.host_id = $1::UUID ORDER BY e.start_at DESC LIMIT 30`,
      [req.params.userId],
    ),
    query<Record<string, unknown>>(
      `SELECT rp.id, rp.reference, rp.reason, rp.status, rp.severity, rp.created_at,
              rep.name AS reporter_name
         FROM reports rp
         JOIN users rep ON rep.id = rp.reporter_id
        WHERE rp.target_type = 'user' AND rp.target_id = $1::UUID
        ORDER BY rp.created_at DESC LIMIT 30`,
      [req.params.userId],
    ),
  ]);

  res.json(
    one('host', {
      ...shape(row),
      events: events.map((e) => ({
        id: e.id,
        title: e.title,
        venueName: e.venue_name,
        startAt: e.start_at,
        status: e.status,
        moderationStatus: e.moderation_status,
        seatsTotal: e.seats_total,
        seatsBooked: e.seats_booked,
        pricePerSeat: Number(e.price_per_seat),
      })),
      reports: reports.map((r) => ({
        id: r.id,
        reference: r.reference,
        reason: r.reason,
        status: r.status,
        severity: r.severity,
        reporterName: r.reporter_name,
        createdAt: r.created_at,
      })),
    }),
  );
});

// POST /api/admin/hosts/:userId/suspend
router.post('/:userId/suspend', async (req, res) => {
  requireAdminConsole(req);
  const input = z.object({ reason: noteSchema }).parse(req.body ?? {});
  const result = await suspendUser({
    userId: req.params.userId,
    reason: input.reason || 'Suspended from the admin console.',
  });
  res.json(one('host', { userId: result.userId, status: 'suspended' }));
});

// POST /api/admin/hosts/:userId/restore
router.post('/:userId/restore', async (req, res) => {
  requireAdminConsole(req);
  const result = await restoreUser({ userId: req.params.userId });
  res.json(one('host', { userId: result.userId, status: 'active' }));
});

/**
 * POST /api/admin/hosts/:userId/downgrade
 * Runs the platform's existing professional-to-personal guard, so an admin
 * cannot unpublish a host who still has guests booked. The 409 carries the
 * blocking list rather than only a count, so the drawer can show what to fix.
 */
router.post('/:userId/downgrade', async (req, res) => {
  requireAdminConsole(req);
  const [host] = await query<{ id: string; name: string; account_type: string }>(
    'SELECT id, name, account_type FROM users WHERE id = $1::UUID',
    [req.params.userId],
  );
  if (!host) throw notFound('Host');
  if (host.account_type !== 'professional') {
    res.json(one('host', { userId: host.id, accountType: 'personal', changed: false }));
    return;
  }

  const blockers = await activeHostedExperiences(host.id);
  if (blockers.length > 0) {
    throw new ApiError(
      409,
      `This host has ${blockers.length} upcoming experience${blockers.length === 1 ? '' : 's'}. ` +
        'Cancel or complete them before switching to Personal.',
      { blockers: blockers.map((b) => ({ id: b.id, title: b.title, startAt: b.start_at })) },
    );
  }

  await query(`UPDATE users SET account_type = 'personal' WHERE id = $1::UUID`, [host.id]);
  res.json(one('host', { userId: host.id, accountType: 'personal', changed: true }));
});

export default router;
