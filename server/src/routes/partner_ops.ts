import { Router } from 'express';
import type pg from 'pg';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, patchKeys } from '../context.js';
import { requireVenueRole, isVerifiedVenue } from '../access.js';
import { list, parsePagination, optionalDate } from '../api.js';

// Phase 2a: 0% commission: DineCircle takes no cut. The constant is inlined
// so the pricing module can be deleted.
const PLATFORM_COMMISSION_RATE = 0;

const router = Router();

/**
 * Operations surface the Partner App needs beyond "edit my profile": the host
 * event approval queue, deals/promotions, the earnings & payout report, and the
 * one-call dashboard.
 *
 * Mounted at `/api/partner/restaurants`, so every path here is
 * `/:restaurantId/...` and every handler opens with `requireVenueRole`, a
 * partner can never read another venue's numbers by guessing an id.
 */

// ── Dashboard ────────────────────────────────────────────────────────────────

/**
 * GET /api/partner/restaurants/:restaurantId/dashboard
 *
 * One round trip for the app's home screen. Everything is derived from live
 * rows on read: no cached counters to go stale, and the customer app sees the
 * same numbers the moment a partner acts.
 */
router.get('/:restaurantId/dashboard', async (req, res) => {
  const { restaurantId } = req.params;
  await requireVenueRole(req, restaurantId);

  const [venue] = await query<{
    id: string; name: string; partnership_status: string; is_partner: boolean;
    accepting_bookings: boolean; requires_host_approval: boolean;
    profile_completion: number; seats: number; timezone: string | null;
  }>(
    `SELECT r.id, r.name, r.partnership_status, r.is_partner, r.accepting_bookings,
            r.requires_host_approval, r.profile_completion, r.seats,
            (SELECT b.timezone FROM restaurant_branches b
              WHERE b.restaurant_id = r.id ORDER BY b.is_primary DESC LIMIT 1) AS timezone
       FROM restaurants r WHERE r.id = $1::UUID`,
    [restaurantId],
  );
  if (!venue) throw notFound('Restaurant');
  const timeZone = venue.timezone ?? 'UTC';

  // Today in the *venue's* timezone, a Karachi desk at 01:00 must not be shown
  // yesterday's service just because the server clock is UTC.
  const [today] = await query<{ date: string }>(
    'SELECT (now() AT TIME ZONE $1)::date::text AS date',
    [timeZone],
  );
  const serviceDate = today?.date ?? new Date().toISOString().slice(0, 10);

  const [todayRows] = await query<{
    pending: number; confirmed: number; seated: number; completed: number;
    cancelled: number; no_show: number; covers: number;
  }>(
    `SELECT
       count(*) FILTER (WHERE status = 'pending')::int   AS pending,
       count(*) FILTER (WHERE status = 'confirmed')::int AS confirmed,
       count(*) FILTER (WHERE status = 'seated')::int    AS seated,
       count(*) FILTER (WHERE status = 'completed')::int AS completed,
       count(*) FILTER (WHERE status = 'cancelled')::int AS cancelled,
       count(*) FILTER (WHERE status = 'no_show')::int   AS no_show,
       COALESCE(SUM(party_size) FILTER (
         WHERE status IN ('pending','confirmed','seated','completed')), 0)::int AS covers
     FROM table_reservations
     WHERE restaurant_id = $1::UUID
       AND (start_at AT TIME ZONE $2)::date = $3::date`,
    [restaurantId, timeZone, serviceDate],
  );

  const [capacity] = await query<{ seats: number | null; tables: number }>(
    `SELECT SUM(seats)::int AS seats, count(*)::int AS tables
       FROM restaurant_tables WHERE restaurant_id = $1::UUID AND is_active`,
    [restaurantId],
  );
  const totalSeats = capacity?.seats ?? venue.seats;

  const [events] = await query<{
    upcoming: number; pending_requests: number; live: number;
  }>(
    `SELECT
       count(*) FILTER (WHERE start_at >= now()
                          AND status IN ('confirmed','live'))::int AS upcoming,
       count(*) FILTER (WHERE status = 'requested')::int             AS pending_requests,
       count(*) FILTER (WHERE status = 'live')::int                  AS live
     FROM dinner_events WHERE restaurant_id = $1::UUID`,
    [restaurantId],
  );

  const [deals] = await query<{ active: number; scheduled: number }>(
    `SELECT
       count(*) FILTER (WHERE status = 'active' AND ends_at > now())::int AS active,
       count(*) FILTER (WHERE status = 'draft')::int                      AS scheduled
     FROM restaurant_deals WHERE restaurant_id = $1::UUID`,
    [restaurantId],
  );

  const [unread] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM notifications
      WHERE restaurant_id = $1::UUID AND read = false`,
    [restaurantId],
  );

  // QR scan analytics: today, last 7 days, last 30 days.
  const [scans] = await query<{ today: number; week: number; month: number }>(
    `SELECT
       count(*) FILTER (WHERE scanned_at >= date_trunc('day', now()))::int AS today,
       count(*) FILTER (WHERE scanned_at >= now() - interval '7 days')::int AS week,
       count(*) FILTER (WHERE scanned_at >= now() - interval '30 days')::int AS month
     FROM qr_scans
     WHERE restaurant_id = $1::UUID`,
    [restaurantId],
  );

  // Month-to-date venue share of captured ticket revenue.
  const [month] = await query<{ gross: string; refunds: string }>(
    `SELECT COALESCE(SUM(b.total_amount), 0)::text AS gross,
            COALESCE((
              SELECT SUM(rf.amount) FROM refunds rf
                JOIN dinner_events e2 ON e2.id = rf.event_id
               WHERE e2.restaurant_id = $1::UUID
                 AND rf.created_at >= date_trunc('month', now())
            ), 0)::text AS refunds
       FROM bookings b
       JOIN dinner_events e ON e.id = b.event_id
      WHERE e.restaurant_id = $1::UUID
        AND b.payment_status = 'paid'
        AND b.created_at >= date_trunc('month', now())`,
    [restaurantId],
  );
  const monthGross = Number(month?.gross ?? 0);
  const monthRefunds = Number(month?.refunds ?? 0);
  const monthCommission = round2((monthGross - monthRefunds) * PLATFORM_COMMISSION_RATE);

  // Hourly reservation trend for today (venue timezone), so the home screen
  // can draw a mini bar chart of how the service day is progressing.
  const trendRows = await query<{ hour: number; count: number }>(
    `SELECT extract(hour FROM start_at AT TIME ZONE $2)::int AS hour,
            count(*)::int AS count
       FROM table_reservations
      WHERE restaurant_id = $1::UUID
        AND (start_at AT TIME ZONE $2)::date = $3::date
      GROUP BY hour ORDER BY hour`,
    [restaurantId, timeZone, serviceDate],
  );
  const trend = trendRows.map((r) => ({ hour: r.hour, count: r.count }));

  // Yesterday's covers: the comparison the desk cares about first thing in
  // the morning is "how are we doing vs the same day last week".
  const [yesterday] = await query<{ covers: number }>(
    `SELECT COALESCE(SUM(party_size), 0)::int AS covers
       FROM table_reservations
      WHERE restaurant_id = $1::UUID
        AND (start_at AT TIME ZONE $2)::date = ($3::date - 1)`,
    [restaurantId, timeZone, serviceDate],
  );

  // Next upcoming confirmed/pending reservation, so the home screen can show
  // "Next booking in 45 min" when it is within the next two hours.
  const [nextBooking] = await query<{ start_at: Date }>(
    `SELECT start_at FROM table_reservations
      WHERE restaurant_id = $1::UUID
        AND status IN ('pending','confirmed')
        AND start_at > now()
      ORDER BY start_at LIMIT 1`,
    [restaurantId],
  );

  res.json({
    data: {
      restaurant: {
        id: venue.id,
        name: venue.name,
        partnershipStatus: venue.partnership_status,
        verified: venue.is_partner && isVerifiedVenue(venue.partnership_status),
        acceptingBookings: venue.accepting_bookings,
        requiresHostApproval: venue.requires_host_approval,
        profileCompletion: venue.profile_completion,
      },
      today: {
        date: serviceDate,
        timeZone,
        reservations: {
          pending: todayRows?.pending ?? 0,
          confirmed: todayRows?.confirmed ?? 0,
          seated: todayRows?.seated ?? 0,
          completed: todayRows?.completed ?? 0,
          cancelled: todayRows?.cancelled ?? 0,
          noShow: todayRows?.no_show ?? 0,
        },
        covers: todayRows?.covers ?? 0,
        capacity: totalSeats,
        tables: capacity?.tables ?? 0,
        occupancy: totalSeats > 0
          ? Math.min(1, (todayRows?.covers ?? 0) / totalSeats)
          : 0,
        trend,
        yesterdayCovers: yesterday?.covers ?? 0,
        nextBookingAt: nextBooking?.start_at ?? null,
      },
      events: {
        upcoming: events?.upcoming ?? 0,
        live: events?.live ?? 0,
        pendingRequests: events?.pending_requests ?? 0,
      },
      deals: {
        active: deals?.active ?? 0,
        drafts: deals?.scheduled ?? 0,
      },
      scans: {
        today: scans?.today ?? 0,
        week: scans?.week ?? 0,
        month: scans?.month ?? 0,
      },
      earnings: {
        monthGross: round2(monthGross),
        monthRefunds: round2(monthRefunds),
        monthCommission,
        monthNet: round2(monthGross - monthRefunds - monthCommission),
        commissionRate: PLATFORM_COMMISSION_RATE,
      },
      notifications: { unread: unread?.count ?? 0 },
    },
  });
});

// ── Host event approvals ─────────────────────────────────────────────────────

type MenuItemRow = {
  event_id: string; id: string; position: number; name: string;
  description: string; pairing: string | null; signature: boolean;
};

type RequestRow = {
  id: string; title: string; tagline: string; description: string;
  host_id: string; host_name: string; host_handle: string | null;
  host_avatar: string | null;
  start_at: Date; end_at: Date | null;
  seats_total: number; seats_booked: number; price_per_seat: string;
  type: string; status: string; cover_image: string; created_at: Date;
  decline_reason: string; restaurant_approved_at: Date | null;
  approval_stale_at: Date | null; requires_host_approval: boolean;
  gallery: string[]; audience: string; menu_style: string;
  included: string[]; tags: string[]; host_note: string;
  duration_minutes: number; language: string; dress_code: string;
  cancelled_at: Date | null; cancellation_reason: string;
};

function serializeRequest(e: RequestRow, menu: MenuItemRow[] = []) {
  return {
    id: e.id,
    title: e.title,
    tagline: e.tagline,
    description: e.description,
    hostId: e.host_id,
    hostName: e.host_name,
    host: {
      id: e.host_id,
      name: e.host_name,
      handle: e.host_handle,
      avatarUrl: e.host_avatar,
    },
    startAt: e.start_at,
    endAt: e.end_at,
    durationMinutes: e.duration_minutes,
    seatsTotal: e.seats_total,
    seatsBooked: e.seats_booked,
    seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
    pricePerSeat: Number(e.price_per_seat),
    type: e.type,
    status: e.status,
    coverImage: e.cover_image,
    gallery: e.gallery ?? [],
    audience: e.audience,
    menuStyle: e.menu_style,
    included: e.included ?? [],
    tags: e.tags ?? [],
    hostNote: e.host_note,
    language: e.language,
    dressCode: e.dress_code,
    menu: menu.map((m) => ({
      id: m.id,
      position: m.position,
      name: m.name,
      description: m.description,
      pairing: m.pairing,
      isSignature: m.signature,
    })),
    declineReason: e.decline_reason,
    approvedAt: e.restaurant_approved_at,
    requiresApproval: e.requires_host_approval,
    // A re-request after a host edit carries a newer `approval_stale_at` than
    // the venue's last decision, which is what the "Changed since approval"
    // badge in the Partner App reads.
    approvalStaleAt: e.approval_stale_at,
    isReapproval: e.approval_stale_at !== null
      && (e.restaurant_approved_at === null || e.approval_stale_at > e.restaurant_approved_at),
    cancelledAt: e.cancelled_at,
    cancellationReason: e.cancellation_reason,
    createdAt: e.created_at,
  };
}

const REQUEST_SELECT = `
  SELECT e.id, e.title, e.tagline, e.description, e.host_id, u.name AS host_name,
         u.handle AS host_handle, u.avatar_url AS host_avatar,
         e.start_at, e.end_at, e.seats_total, e.seats_booked, e.price_per_seat,
         e.type, e.status, e.cover_image, e.created_at, e.decline_reason,
         e.restaurant_approved_at, e.approval_stale_at,
         r.requires_host_approval, e.gallery, e.audience, e.menu_style,
         e.included, e.tags, e.host_note, e.duration_minutes, e.language,
         e.dress_code, e.cancelled_at, e.cancellation_reason
    FROM dinner_events e
    JOIN users u ON u.id = e.host_id
    JOIN restaurants r ON r.id = e.restaurant_id`;

/** Menu rows for a set of events, grouped by event id. */
async function menusFor(eventIds: string[]): Promise<Map<string, MenuItemRow[]>> {
  const grouped = new Map<string, MenuItemRow[]>();
  if (eventIds.length === 0) return grouped;
  const rows = await query<MenuItemRow>(
    `SELECT event_id, id, position, name, description, pairing, signature
       FROM menu_items WHERE event_id = ANY($1::UUID[]) ORDER BY position ASC`,
    [eventIds],
  );
  for (const row of rows) {
    const bucket = grouped.get(row.event_id) ?? [];
    bucket.push(row);
    grouped.set(row.event_id, bucket);
  }
  return grouped;
}

// GET /api/partner/restaurants/:restaurantId/event-requests
router.get('/:restaurantId/event-requests', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const page = parsePagination(req.query as Record<string, unknown>, { defaultLimit: 50 });
  const status = typeof req.query.status === 'string' && req.query.status !== ''
    ? req.query.status
    : 'requested';
  if (!['requested', 'confirmed', 'declined', 'completed'].includes(status)) {
    throw new ApiError(400, 'status must be requested, confirmed, declined or completed');
  }

  const params: unknown[] = [req.params.restaurantId, status];
  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM dinner_events
      WHERE restaurant_id = $1::UUID AND status = $2`,
    params,
  );

  params.push(page.limit, page.offset);
  const rows = await query<RequestRow>(
    `${REQUEST_SELECT}
      WHERE e.restaurant_id = $1::UUID AND e.status = $2
      ORDER BY e.start_at ASC
      LIMIT $3 OFFSET $4`,
    params,
  );

  const menus = await menusFor(rows.map((r) => r.id));
  res.json(
    list('requests', rows.map((r) => serializeRequest(r, menus.get(r.id) ?? [])), page, totalRow?.count ?? 0),
  );
});

/**
 * GET /api/partner/restaurants/:restaurantId/event-requests/:eventId
 *
 * The full record the venue is being asked to approve. The list used to be the
 * only surface, so a partner approved an experience having seen a title, a date
 * and a price — never the menu, the gallery or the host's note.
 */
router.get('/:restaurantId/event-requests/:eventId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);

  const [row] = await query<RequestRow>(
    `${REQUEST_SELECT}
      WHERE e.id = $1::UUID AND e.restaurant_id = $2::UUID`,
    [req.params.eventId, req.params.restaurantId],
  );
  if (!row) throw notFound('Event request');

  const menus = await menusFor([row.id]);
  res.json({ data: { request: serializeRequest(row, menus.get(row.id) ?? []) } });
});

/**
 * Loads one event for a decision, locking the row so a double-tapped Approve
 * cannot produce two conflicting transitions (or two host notifications).
 */
async function lockRequest(
  client: pg.PoolClient,
  restaurantId: string,
  eventId: string,
): Promise<RequestRow> {
  const { rows } = await client.query<RequestRow>(
    `${REQUEST_SELECT}
      WHERE e.id = $1::UUID AND e.restaurant_id = $2::UUID
      FOR UPDATE OF e`,
    [eventId, restaurantId],
  );
  const row = rows[0];
  if (!row) throw notFound('Event request');
  if (row.status !== 'requested') {
    throw new ApiError(409, `This event is already ${row.status}`);
  }
  return row;
}

const declineSchema = z.object({
  reason: z.string().trim().max(500).default(''),
});

// POST /api/partner/restaurants/:restaurantId/event-requests/:eventId/approve
router.post('/:restaurantId/event-requests/:eventId/approve', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');

  const result = await withTransaction(async (client) => {
    const request = await lockRequest(client, req.params.restaurantId, req.params.eventId);

    await client.query(
      `UPDATE dinner_events
          SET status = 'confirmed', restaurant_approved_at = now(),
              restaurant_approved_by = $2::UUID, decline_reason = '',
              approval_stale_at = NULL, updated_at = now()
        WHERE id = $1::UUID`,
      [request.id, req.userId],
    );

    // The host sees the decision in their own activity feed, and the desk keeps
    // a venue-side record; without both, one side of the marketplace is blind.
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1::UUID, 'approval', $2, $3, $4::UUID, true)`,
      [
        request.host_id,
        'Event approved by the venue',
        `${request.title} was approved and is now bookable.`,
        request.id,
      ],
    );
    await client.query(
      `INSERT INTO notifications (restaurant_id, title, body, category, read)
       VALUES ($1::UUID, 'Event approved', $2, 'event', false)`,
      [req.params.restaurantId, `${request.title} is now confirmed at your venue.`],
    );

    return { eventId: request.id, status: 'confirmed' };
  });

  res.json({ data: { request: result } });
});

// POST /api/partner/restaurants/:restaurantId/event-requests/:eventId/decline
router.post('/:restaurantId/event-requests/:eventId/decline', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = declineSchema.parse(req.body ?? {});

  const result = await withTransaction(async (client) => {
    const request = await lockRequest(client, req.params.restaurantId, req.params.eventId);

    await client.query(
      `UPDATE dinner_events
          SET status = 'declined', decline_reason = $2,
              restaurant_approved_by = $3::UUID, updated_at = now()
        WHERE id = $1::UUID`,
      [request.id, input.reason, req.userId],
    );
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1::UUID, 'approval', $2, $3, $4::UUID, true)`,
      [
        request.host_id,
        'Event declined by the venue',
        input.reason === ''
          ? `${request.title} was declined by the venue.`
          : `${request.title} was declined: ${input.reason}`,
        request.id,
      ],
    );

    return { eventId: request.id, status: 'declined', reason: input.reason };
  });

  res.json({ data: { request: result } });
});

// ── Deals & promotions ───────────────────────────────────────────────────────

type DealRow = {
  id: string; restaurant_id: string; title: string; description: string;
  kind: string; value: string; code: string | null; starts_at: Date; ends_at: Date;
  max_redemptions: number | null; redemptions: number; status: string;
  image_url: string; terms: string;
  created_at: Date; updated_at: Date;
};

function serializeDeal(d: DealRow) {
  return {
    id: d.id,
    restaurantId: d.restaurant_id,
    title: d.title,
    description: d.description,
    kind: d.kind,
    value: Number(d.value),
    // An empty code and no code are the same promise to a guest, and the app
    // hides the chip on either. Normalise so clearing the field really clears it.
    code: d.code || null,
    startsAt: d.starts_at,
    endsAt: d.ends_at,
    maxRedemptions: d.max_redemptions,
    redemptions: d.redemptions,
    status: d.status,
    imageUrl: d.image_url,
    // Guest-facing conditions and redemption steps. The public deals route has
    // always returned this; the partner route dropped it, so a partner could
    // not see or edit the conditions their own guests read.
    terms: d.terms ?? '',
    createdAt: d.created_at,
    updatedAt: d.updated_at,
  };
}

const dealBaseSchema = z.object({
  title: z.string().trim().min(3).max(120),
  description: z.string().trim().max(2000).default(''),
  kind: z.enum(['percent', 'fixed', 'package']).default('percent'),
  value: z.coerce.number().positive().max(100000),
  code: z.string().trim().max(24).nullable().optional(),
  startsAt: z.coerce.date().optional(),
  endsAt: z.coerce.date(),
  maxRedemptions: z.coerce.number().int().positive().max(100000).nullable().optional(),
  imageUrl: z.string().trim().max(400).default(''),
  terms: z.string().trim().max(2000).default(''),
});

const dealSchema = dealBaseSchema.superRefine((deal, ctx) => {
  // A percent deal over 100 would invert the bill; the DB only knows `>= 0`.
  if (deal.kind === 'percent' && deal.value > 100) {
    ctx.addIssue({ code: 'custom', path: ['value'], message: 'Percent deals must be 1-100' });
  }
  if (deal.endsAt.getTime() <= Date.now()) {
    ctx.addIssue({ code: 'custom', path: ['endsAt'], message: 'endsAt must be in the future' });
  }
  if (deal.startsAt && deal.startsAt.getTime() >= deal.endsAt.getTime()) {
    ctx.addIssue({ code: 'custom', path: ['endsAt'], message: 'endsAt must be after startsAt' });
  }
});

/** Deals are a customer-facing promise, so only verified venues may run them. */
async function requireSellableVenue(restaurantId: string): Promise<void> {
  const [venue] = await query<{ partnership_status: string; is_partner: boolean }>(
    'SELECT partnership_status, is_partner FROM restaurants WHERE id = $1::UUID',
    [restaurantId],
  );
  if (!venue) throw notFound('Restaurant');
  if (!venue.is_partner || !isVerifiedVenue(venue.partnership_status)) {
    throw new ApiError(403, 'Only verified venues can publish deals');
  }
}

// GET /api/partner/restaurants/:restaurantId/deals
router.get('/:restaurantId/deals', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const page = parsePagination(req.query as Record<string, unknown>, { defaultLimit: 50 });
  const params: unknown[] = [req.params.restaurantId];
  const conditions = ['restaurant_id = $1::UUID'];

  if (typeof req.query.status === 'string' && req.query.status !== '') {
    params.push(req.query.status);
    conditions.push(`status = $${params.length}`);
  }
  const where = conditions.join(' AND ');

  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM restaurant_deals WHERE ${where}`,
    params,
  );

  params.push(page.limit, page.offset);
  const rows = await query<DealRow>(
    `SELECT * FROM restaurant_deals WHERE ${where}
      ORDER BY (status = 'active') DESC, ends_at ASC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );

  res.json(list('deals', rows.map(serializeDeal), page, totalRow?.count ?? 0));
});

// POST /api/partner/restaurants/:restaurantId/deals
router.post('/:restaurantId/deals', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = dealSchema.parse(req.body ?? {});
  await requireSellableVenue(req.params.restaurantId);

  const startsAt = input.startsAt ?? new Date();
  const code = input.code ? input.code.toUpperCase() : null;

  if (code !== null) {
    const [clash] = await query<{ id: string }>(
      `SELECT id FROM restaurant_deals
        WHERE restaurant_id = $1::UUID AND upper(code) = $2
          AND status <> 'expired' LIMIT 1`,
      [req.params.restaurantId, code],
    );
    if (clash) {
      throw new ApiError(409, `Deal code "${code}" is already in use at this venue`);
    }
  }

  const [created] = await query<DealRow>(
    `INSERT INTO restaurant_deals
       (restaurant_id, title, description, kind, value, code, starts_at, ends_at,
        max_redemptions, image_url, terms, status)
     VALUES ($1::UUID,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,'draft')
     RETURNING *`,
    [
      req.params.restaurantId, input.title, input.description, input.kind,
      input.value, code, startsAt, input.endsAt, input.maxRedemptions ?? null,
      input.imageUrl, input.terms,
    ],
  );
  if (!created) throw new ApiError(500, 'Deal creation failed');

  res.status(201).json({ data: { deal: serializeDeal(created) } });
});

const DEAL_TRANSITIONS: Record<string, readonly string[]> = {
  draft: ['active', 'expired'],
  active: ['paused', 'expired'],
  paused: ['active', 'expired'],
  expired: [],
};

const patchDealSchema = dealBaseSchema.partial().extend({
  status: z.enum(['active', 'paused', 'expired']).optional(),
});

// PATCH /api/partner/restaurants/:restaurantId/deals/:dealId
router.patch('/:restaurantId/deals/:dealId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchDealSchema.parse(req.body ?? {});
  const provided = patchKeys(req.body);

  const [existing] = await query<DealRow>(
    'SELECT * FROM restaurant_deals WHERE id = $1::UUID AND restaurant_id = $2::UUID',
    [req.params.dealId, req.params.restaurantId],
  );
  if (!existing) throw notFound('Deal');

  // The PATCH schema is built from `dealBaseSchema` rather than `dealSchema`,
  // so the percent ceiling that `superRefine` applies on create never runs
  // here. Re-check it against the row as it will exist after this write:
  // otherwise a package deal edited via `PATCH {status}` would keep its money
  // value while flipping `kind`, and render as e.g. "5999% off".
  // `input.kind` cannot be trusted on its own: `.partial()` still applies the
  // `.default('percent')`, so read the effective value through `provided`.
  const nextKind = provided.has('kind') && input.kind !== undefined ? input.kind : existing.kind;
  const nextValue =
    provided.has('value') && input.value !== undefined ? input.value : Number(existing.value);
  if (nextKind === 'percent' && nextValue > 100) {
    throw new ApiError(422, 'Percent deals must be 1-100');
  }

  if (input.status !== undefined) {
    const allowed = DEAL_TRANSITIONS[existing.status] ?? [];
    if (!allowed.includes(input.status)) {
      throw new ApiError(
        409, `Cannot move a ${existing.status} deal to ${input.status}`,
      );
    }
    if (input.status === 'active') {
      await requireSellableVenue(req.params.restaurantId);
      if (new Date(existing.ends_at).getTime() <= Date.now()) {
        throw new ApiError(409, 'This deal has already passed its end date');
      }
    }
  }

  const map: Record<string, string> = {
    title: 'title', description: 'description', kind: 'kind', value: 'value',
    code: 'code', startsAt: 'starts_at', endsAt: 'ends_at',
    maxRedemptions: 'max_redemptions', imageUrl: 'image_url', terms: 'terms',
    status: 'status',
  };
  const sets: string[] = [];
  const params: unknown[] = [];
  for (const [key, column] of Object.entries(map)) {
    if (!provided.has(key)) continue;
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(key === 'code' && typeof value === 'string' ? value.toUpperCase() : value);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }

  params.push(req.params.dealId, req.params.restaurantId);
  const [updated] = await query<DealRow>(
    `UPDATE restaurant_deals SET ${sets.join(', ')}, updated_at = now()
      WHERE id = $${params.length - 1}::UUID AND restaurant_id = $${params.length}::UUID
      RETURNING *`,
    params,
  ).catch((error: { code?: string }) => {
    if (error.code === '23514') {
      throw new ApiError(422, 'Deal violates its value or date constraints');
    }
    if (error.code === '23505') {
      throw new ApiError(409, 'That deal code is already in use at this venue');
    }
    throw error;
  });
  if (!updated) throw notFound('Deal');

  res.json({ data: { deal: serializeDeal(updated) } });
});

/**
 * DELETE /api/partner/restaurants/:restaurantId/deals/:dealId
 * Deals expire rather than vanish: a customer may already have seen the offer,
 * and `redemptions` is part of the earnings story, so the row is retired.
 */
router.delete('/:restaurantId/deals/:dealId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');

  const [deleted] = await query<{ id: string }>(
    `DELETE FROM restaurant_deals
      WHERE id = $1::UUID AND restaurant_id = $2::UUID AND status = 'draft'
      RETURNING id`,
    [req.params.dealId, req.params.restaurantId],
  );
  if (deleted) {
    res.json({ data: { id: deleted.id, deleted: true } });
    return;
  }

  const [retired] = await query<{ id: string }>(
    `UPDATE restaurant_deals SET status = 'expired', updated_at = now()
      WHERE id = $1::UUID AND restaurant_id = $2::UUID RETURNING id`,
    [req.params.dealId, req.params.restaurantId],
  );
  if (!retired) throw notFound('Deal');
  res.json({ data: { id: retired.id, status: 'expired' } });
});

/**
 * POST /api/partner/restaurants/:restaurantId/deals/:dealId/redeem
 *
 * Counts one use of a deal at the table. Deliberately `staff`, not `manager`:
 * the person who honours the offer is whoever is on the floor, and refusing
 * them would push the count into a spreadsheet.
 *
 * The whole guard lives in the WHERE clause, so the check and the increment are
 * one statement. Two waiters tapping at the same moment can never push
 * `redemptions` past `max_redemptions`, which a read-then-write would allow.
 */
router.post('/:restaurantId/deals/:dealId/redeem', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);

  const include = 'id = $1::UUID AND restaurant_id = $2::UUID';
  const [redeemed] = await query<DealRow>(
    `UPDATE restaurant_deals
        SET redemptions = redemptions + 1, updated_at = now()
      WHERE ${include}
        AND status = 'active'
        AND starts_at <= now()
        AND ends_at > now()
        AND (max_redemptions IS NULL OR redemptions < max_redemptions)
      RETURNING *`,
    [req.params.dealId, req.params.restaurantId],
  );
  if (redeemed) {
    res.json({ data: { deal: serializeDeal(redeemed) } });
    return;
  }

  // Nothing was counted. Say which guard refused so the desk knows whether to
  // fix the deal or to stop honouring it, instead of a bare 409.
  const [existing] = await query<DealRow>(
    `SELECT * FROM restaurant_deals WHERE ${include}`,
    [req.params.dealId, req.params.restaurantId],
  );
  if (!existing) throw notFound('Deal');
  if (existing.status !== 'active') {
    throw new ApiError(
      409, `This deal is ${existing.status} and cannot be redeemed`,
    );
  }
  if (new Date(existing.starts_at).getTime() > Date.now()) {
    throw new ApiError(409, 'This deal has not started yet');
  }
  if (new Date(existing.ends_at).getTime() <= Date.now()) {
    throw new ApiError(409, 'This deal has already passed its end date');
  }
  throw new ApiError(409, 'This deal has reached its redemption limit');
});

// ── Earnings & payouts ───────────────────────────────────────────────────────

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

const DAY_MS = 86_400_000;

/**
 * GET /api/partner/restaurants/:restaurantId/earnings?from&to
 *
 * The venue's share of captured ticket revenue for a window (default: the last
 * 30 days). Refunds are subtracted before commission, so a cancelled guest
 * never costs the venue commission on money it did not keep.
 */
router.get('/:restaurantId/earnings', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');

  const to = optionalDate(req.query.to) ?? new Date();
  const from = optionalDate(req.query.from) ?? new Date(to.getTime() - 30 * DAY_MS);
  if (from.getTime() > to.getTime()) {
    throw new ApiError(422, 'from must be before to');
  }

  const [revenue] = await query<{
    gross: string; bookings: number; covers: number; paid_bookings: number;
  }>(
    `SELECT
       COALESCE(SUM(b.total_amount) FILTER (WHERE b.payment_status = 'paid'), 0)::text AS gross,
       count(b.id)::int AS bookings,
       COALESCE(SUM(b.seats) FILTER (WHERE b.status <> 'cancelled'), 0)::int AS covers,
       count(*) FILTER (WHERE b.payment_status = 'paid')::int AS paid_bookings
     FROM bookings b
     JOIN dinner_events e ON e.id = b.event_id
     WHERE e.restaurant_id = $1::UUID
       AND b.created_at >= $2::timestamptz AND b.created_at <= $3::timestamptz`,
    [req.params.restaurantId, from, to],
  );

  const [refunded] = await query<{ amount: string; count: number }>(
    `SELECT COALESCE(SUM(rf.amount), 0)::text AS amount, count(*)::int AS count
       FROM refunds rf
       JOIN dinner_events e ON e.id = rf.event_id
      WHERE e.restaurant_id = $1::UUID
        AND rf.status = 'refunded'
        AND rf.created_at >= $2::timestamptz AND rf.created_at <= $3::timestamptz`,
    [req.params.restaurantId, from, to],
  );

  const gross = Number(revenue?.gross ?? 0);
  const refundAmount = Number(refunded?.amount ?? 0);
  const commission = round2((gross - refundAmount) * PLATFORM_COMMISSION_RATE);

  const [payouts] = await query<{
    pending: string | null; paid: string | null; last_period_end: Date | null;
  }>(
    `SELECT COALESCE(SUM(net) FILTER (WHERE status <> 'paid'), 0)::text AS pending,
            COALESCE(SUM(net) FILTER (WHERE status = 'paid'), 0)::text AS paid,
            MAX(period_end) FILTER (WHERE status = 'paid') AS last_period_end
       FROM restaurant_payouts WHERE restaurant_id = $1::UUID`,
    [req.params.restaurantId],
  );

  res.json({
    data: {
      earnings: {
        from,
        to,
        gross: round2(gross),
        refunds: round2(refundAmount),
        commission,
        commissionRate: PLATFORM_COMMISSION_RATE,
        net: round2(gross - refundAmount - commission),
        bookings: revenue?.bookings ?? 0,
        paidBookings: revenue?.paid_bookings ?? 0,
        covers: revenue?.covers ?? 0,
        refundCount: refunded?.count ?? 0,
      },
      payouts: {
        pending: round2(Number(payouts?.pending ?? 0)),
        paid: round2(Number(payouts?.paid ?? 0)),
        lastPaidAt: payouts?.last_period_end ?? null,
      },
    },
  });
});

// GET /api/partner/restaurants/:restaurantId/payouts
router.get('/:restaurantId/payouts', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const page = parsePagination(req.query as Record<string, unknown>, { defaultLimit: 24 });

  const [totalRow] = await query<{ count: number }>(
    'SELECT count(*)::int AS count FROM restaurant_payouts WHERE restaurant_id = $1::UUID',
    [req.params.restaurantId],
  );

  const rows = await query<{
    id: string; period_start: Date; period_end: Date; gross: string;
    commission: string; net: string; status: string; created_at: Date;
  }>(
    `SELECT id, period_start, period_end, gross, commission, net, status, created_at
       FROM restaurant_payouts WHERE restaurant_id = $1::UUID
      ORDER BY period_end DESC
      LIMIT $2 OFFSET $3`,
    [req.params.restaurantId, page.limit, page.offset],
  );

  res.json(
    list(
      'payouts',
      rows.map((p) => ({
        id: p.id,
        periodStart: p.period_start,
        periodEnd: p.period_end,
        gross: Number(p.gross),
        commission: Number(p.commission),
        net: Number(p.net),
        status: p.status,
        createdAt: p.created_at,
      })),
      page,
      totalRow?.count ?? 0,
    ),
  );
});

// ── Review replies ─────────────────────────────────────────────────────────────

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const replySchema = z.object({
  reply: z.string().min(1).max(1000),
});

/**
 * PATCH /api/partner/restaurants/:restaurantId/reviews/:reviewId/reply
 *
 * Partner replies to a customer review. Owner or staff role required.
 */
router.patch('/:restaurantId/reviews/:reviewId/reply', async (req, res) => {
  const { restaurantId, reviewId } = req.params;
  if (!UUID_PATTERN.test(restaurantId) || !UUID_PATTERN.test(reviewId)) {
    throw new ApiError(400, 'IDs must be UUIDs');
  }

  await requireVenueRole(req, restaurantId);

  const input = replySchema.parse(req.body ?? {});

  // Verify the review belongs to this restaurant.
  const [review] = await query<{ id: string; restaurant_id: string | null }>(
    `SELECT id, restaurant_id FROM reviews WHERE id = $1::UUID`,
    [reviewId],
  );

  if (!review || review.restaurant_id !== restaurantId) {
    throw notFound('Review');
  }

  const [updated] = await query<{
    id: string;
    partner_reply: string;
    partner_replied_at: Date;
  }>(
    `UPDATE reviews
        SET partner_reply = $2, partner_replied_at = now()
      WHERE id = $1::UUID
      RETURNING id, partner_reply, partner_replied_at`,
    [reviewId, input.reply],
  );

  if (!updated) {
    throw new ApiError(500, 'Failed to update review');
  }

  res.json({
    review: {
      id: updated.id,
      partnerReply: updated.partner_reply,
      partnerRepliedAt: updated.partner_replied_at.toISOString(),
    },
  });
});

/**
 * GET /api/partner/restaurants/:restaurantId/reviews
 *
 * Venue-scoped review feed for the partner app. Includes aggregate rating.
 */
router.get('/:restaurantId/reviews', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  await requireVenueRole(req, restaurantId);

  const { limit, offset } = parsePagination(req.query);

  const reviews = await query<{
    id: string;
    author_id: string;
    author_name: string;
    restaurant_id: string;
    rating: string;
    text: string;
    partner_reply: string | null;
    partner_replied_at: Date | null;
    created_at: Date;
  }>(
    `SELECT r.id, r.author_id, u.name AS author_name, r.restaurant_id,
            r.rating, r.text, r.partner_reply, r.partner_replied_at, r.created_at
       FROM reviews r
       JOIN users u ON u.id = r.author_id
      WHERE r.restaurant_id = $1::UUID
      ORDER BY r.created_at DESC
      LIMIT $2 OFFSET $3`,
    [restaurantId, limit, offset],
  );

  const [aggregate] = await query<{ avg_rating: string; count: number }>(
    `SELECT COALESCE(AVG(rating), 0)::text AS avg_rating, count(*)::int AS count
       FROM reviews
      WHERE restaurant_id = $1::UUID`,
    [restaurantId],
  );

  res.json({
    reviews: reviews.map((r) => ({
      id: r.id,
      authorId: r.author_id,
      authorName: r.author_name,
      restaurantId: r.restaurant_id,
      rating: Number(r.rating),
      text: r.text,
      partnerReply: r.partner_reply,
      partnerRepliedAt: r.partner_replied_at?.toISOString() ?? null,
      createdAt: r.created_at.toISOString(),
    })),
    aggregate: {
      rating: Number(aggregate?.avg_rating ?? 0),
      count: aggregate?.count ?? 0,
    },
    limit,
    offset,
  });
});

export default router;
