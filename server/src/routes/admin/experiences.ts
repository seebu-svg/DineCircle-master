import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { cancelExperience, setModeration } from '../../moderation.js';
import { adminPage, noteSchema, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Experience Management.
 *
 * `dinner_events.status` has no `flagged` value, and inventing one would mean
 * touching every host-facing state machine. So flagging lives in the new
 * `moderation_status` column while cancellation keeps using the real lifecycle
 * value `cancelled`. A removed experience sets both: it stays listed in the
 * host's history as cancelled, and `moderation_status='removed'` hides it from
 * the public event queries.
 */
const router = Router();

const EXPERIENCE_SELECT = `
  e.id, e.title, e.tagline, e.status, e.moderation_status, e.moderation_note,
  e.start_at, e.end_at, e.seats_total, e.seats_booked, e.price_per_seat,
  e.type, e.audience, e.is_featured, e.cover_image, e.created_at, e.views,
  h.id AS host_id, h.name AS host_name, h.email AS host_email,
  h.account_type AS host_account_type, h.suspended_at AS host_suspended_at,
  r.id AS restaurant_id, r.name AS venue_name, r.city,
  (SELECT count(*)::int FROM bookings b
     WHERE b.event_id = e.id AND b.status <> 'cancelled')          AS rsvps,
  (SELECT COALESCE(sum(b.seats), 0)::int FROM bookings b
     WHERE b.event_id = e.id AND b.status <> 'cancelled')          AS covers,
  (SELECT count(*)::int FROM reports rp
     WHERE rp.target_type = 'event' AND rp.target_id = e.id
       AND rp.status IN ('pending','reviewing'))                    AS open_reports`;

const EXPERIENCE_FROM = `
  FROM dinner_events e
  JOIN users h ON h.id = e.host_id
  JOIN restaurants r ON r.id = e.restaurant_id`;

function shape(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    tagline: row.tagline,
    status: row.status,
    moderationStatus: row.moderation_status,
    moderationNote: row.moderation_note,
    flagged: row.moderation_status === 'flagged',
    startAt: row.start_at,
    endAt: row.end_at,
    date: row.start_at,
    seatsTotal: row.seats_total,
    seatsBooked: row.seats_booked,
    rsvps: row.rsvps,
    covers: row.covers,
    pricePerSeat: Number(row.price_per_seat ?? 0),
    type: row.type,
    audience: row.audience,
    featured: row.is_featured,
    coverImage: row.cover_image,
    views: row.views,
    createdAt: row.created_at,
    hostId: row.host_id,
    hostName: row.host_name,
    hostEmail: row.host_email,
    hostStatus: row.host_suspended_at ? 'suspended' : row.host_account_type,
    venueId: row.restaurant_id,
    venueName: row.venue_name,
    city: row.city,
    openReports: row.open_reports,
  };
}

/**
 * GET /api/admin/experiences?page&limit&status&flagged&q
 * `flagged=true` narrows to the moderation queue; `status` is the real
 * lifecycle value.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status !== '' && status !== 'all') {
    params.push(status);
    where.push(`e.status = $${params.length}`);
  }
  if (String(req.query.flagged ?? '').trim() === 'true') {
    where.push(`e.moderation_status = 'flagged'`);
  }
  pushSearch(where, params, searchTerm(req), ['e.title', 'h.name', 'r.name', 'e.tagline']);

  await renderList(res, 'experiences', {
    select: EXPERIENCE_SELECT,
    from: EXPERIENCE_FROM,
    where,
    params,
    order: 'e.start_at DESC',
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/experiences/:id
router.get('/:id', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${EXPERIENCE_SELECT}, e.description, e.host_note, e.cancellation,
            e.included, e.tags, e.menu_style, e.cancelled_at, e.cancellation_reason
       ${EXPERIENCE_FROM}
      WHERE e.id = $1::UUID`,
    [req.params.id],
  );
  if (!row) throw notFound('Experience');

  const [guests, reports] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT b.id, b.reference, b.seats, b.total_amount, b.status, b.created_at,
              coalesce(nullif(b.guest_name, ''), u.name) AS guest_name, u.email
         FROM bookings b
         JOIN users u ON u.id = b.user_id
        WHERE b.event_id = $1::UUID ORDER BY b.created_at DESC LIMIT 100`,
      [req.params.id],
    ),
    query<Record<string, unknown>>(
      `SELECT rp.id, rp.reference, rp.reason, rp.status, rp.severity, rp.created_at,
              rep.name AS reporter_name
         FROM reports rp
         JOIN users rep ON rep.id = rp.reporter_id
        WHERE rp.target_type = 'event' AND rp.target_id = $1::UUID
        ORDER BY rp.created_at DESC LIMIT 20`,
      [req.params.id],
    ),
  ]);

  res.json(
    one('experience', {
      ...shape(row),
      description: row.description,
      hostNote: row.host_note,
      cancellationPolicy: row.cancellation,
      included: row.included,
      tags: row.tags,
      menuStyle: row.menu_style,
      cancelledAt: row.cancelled_at,
      cancellationReason: row.cancellation_reason,
      guests: guests.map((g) => ({
        id: g.id,
        reference: g.reference,
        guestName: g.guest_name,
        email: g.email,
        seats: g.seats,
        amount: Number(g.total_amount),
        status: g.status,
        createdAt: g.created_at,
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

const flagSchema = z.object({ note: noteSchema });

/**
 * POST /api/admin/experiences/:id/flag
 * Puts the experience in the moderation queue without touching the host's own
 * lifecycle state, so their app keeps showing what they scheduled.
 */
router.post('/:id/flag', async (req, res) => {
  requireAdminConsole(req);
  const input = flagSchema.parse(req.body ?? {});
  const result = await setModeration({
    kind: 'experience',
    id: req.params.id,
    state: 'flagged',
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('experience', result));
});

// POST /api/admin/experiences/:id/clear
router.post('/:id/clear', async (req, res) => {
  requireAdminConsole(req);
  const input = flagSchema.parse(req.body ?? {});
  const result = await setModeration({
    kind: 'experience',
    id: req.params.id,
    state: 'clean',
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('experience', result));
});

const cancelSchema = z.object({
  reason: noteSchema,
  notifyGuests: z.boolean().default(true),
});

/**
 * POST /api/admin/experiences/:id/cancel
 * Cancellation always notifies the guests who hold seats, because a silently
 * vanished experience is the worst outcome for a diner. `notifyGuests=false` is
 * for draft and requested events nobody has booked.
 */
router.post('/:id/cancel', async (req, res) => {
  requireAdminConsole(req);
  const input = cancelSchema.parse(req.body ?? {});
  const result = await cancelExperience({
    eventId: req.params.id,
    reason: input.reason,
    notifyGuests: input.notifyGuests,
    actorId: req.userId,
  });
  res.json(one('experience', result));
});

/**
 * POST /api/admin/experiences/:id/remove
 * Removes it from public listing while keeping the row, so refunds, receipts
 * and the host's history stay intact and auditable.
 */
router.post('/:id/remove', async (req, res) => {
  requireAdminConsole(req);
  const input = flagSchema.parse(req.body ?? {});
  const result = await setModeration({
    kind: 'experience',
    id: req.params.id,
    state: 'removed',
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('experience', result));
});

export default router;
