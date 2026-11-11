import { Router } from 'express';
import type { Request } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { notifyUser } from '../notify.js';
import { assertNoCapturedMoney, softCancel } from '../event_lifecycle.js';
import {
  requirePartner,
  requireVenueRole,
  scopedRestaurantIds,
  venueScopeClause,
} from '../access.js';

const router = Router();

/**
 * Operations surface shared by the Partner App: events, bookings, check-in,
 * special menus, analytics and notifications.
 *
 * The gate is `requirePartner` rather than a bare role check so that a venue's
 * staff/manager/owner,and a host who registered a venue,all reach it, and
 * every query is scoped through `scopedRestaurantIds` instead of `owner_id`,
 * which used to lock staff accounts out of their own venue.
 */
router.use(requirePartner);

// ── Events ───────────────────────────────────────────────────────────────────

const createPartnerEventSchema = z.object({
  restaurantId: z.string().uuid(),
  title: z.string().trim().min(3).max(120),
  tagline: z.string().trim().max(200).default(''),
  description: z.string().trim().max(4000).default(''),
  startAt: z.coerce.date(),
  endAt: z.coerce.date(),
  seatsTotal: z.number().int().min(1).max(200),
  pricePerSeat: z.number().positive().max(10000),
  type: z.enum(['dinner', 'tasting', 'supperClub', 'brunch', 'workshop', 'festival']).default('dinner'),
  audience: z.enum(['public', 'followers', 'friends', 'inviteOnly']).default('public'),
  menuStyle: z.enum(['setMenu', 'tastingMenu', 'familyStyle', 'sharing', 'buffet']).default('setMenu'),
  coverImage: z.string().default(''),
  tags: z.array(z.string()).default([]),
  collaboratorIds: z.array(z.string().uuid()).default([]),
  /**
   * Direction B: create the draft on a host's behalf and propose it to them.
   * When supplied the row is written as `draft` and owned by that host, so the
   * venue can never publish on their behalf — publishing is a host action
   * gated on the proposal being accepted.
   */
  hostId: z.string().uuid().optional(),
  status: z.enum(['draft', 'published']).default('published'),
});

/**
 * Fields only the host may change. A venue that edits a host's experience is
 * limited to operations (timing and capacity); the experience's identity and
 * pricing stay with the person whose name is on it.
 */
const HOST_OWNED_FIELDS = new Set([
  'title', 'tagline', 'description', 'pricePerSeat', 'coverImage', 'tags',
  'collaboratorIds',
]);

/** Load an event the caller operates, for a transition or an edit. */
async function loadVenueEvent(
  req: Request,
  eventId: string,
  minRole: 'staff' | 'manager' | 'owner' = 'manager',
): Promise<{ id: string; host_id: string; restaurant_id: string; title: string; status: string }> {
  const [event] = await query<{
    id: string; host_id: string; restaurant_id: string; title: string; status: string;
  }>(
    `SELECT id, host_id, restaurant_id, title, status
       FROM dinner_events WHERE id = $1::UUID`,
    [eventId],
  );
  if (!event) throw notFound('Event');
  await requireVenueRole(req, event.restaurant_id, minRole);
  return event;
}

/**
 * POST /api/partner/events, create a new event for a partner restaurant.
 *
 * Without `hostId` the acting operator becomes the host and the experience
 * publishes directly: a venue approving its own listing is meaningless
 * (`requires_host_approval` gates *host* submissions). With `hostId` the row is
 * a draft owned by that host, which the venue then proposes to.
 */
router.post('/events', async (req, res) => {
  const input = createPartnerEventSchema.parse(req.body);

  // Creating a dining event on a venue is an operations action: manager+ only.
  await requireVenueRole(req, input.restaurantId, 'manager');

  const targetHostId = input.hostId ?? req.userId;
  if (input.hostId && input.hostId !== req.userId) {
    const [host] = await query<{ id: string }>(
      `SELECT id FROM users
        WHERE id = $1::UUID AND account_type = 'professional'`,
      [input.hostId],
    );
    if (!host) throw notFound('Host');
  }
  // A venue-created draft for somebody else is never published straight away.
  const isDraft = input.hostId !== undefined || input.status === 'draft';
  const initialStatus = isDraft ? 'draft' : 'confirmed';

  const durationMinutes = Math.round(
    (input.endAt.getTime() - input.startAt.getTime()) / 60000,
  );

  const [created] = await query<{
    id: string; title: string; restaurant_id: string; status: string;
    start_at: Date; seats_total: number; seats_booked: number;
    price_per_seat: string; host_id: string;
  }>(
    `INSERT INTO dinner_events (
       host_id, restaurant_id, title, tagline, description, start_at, end_at,
       duration_minutes, seats_total, seats_booked, price_per_seat,
       type, audience, status, menu_style, cover_image, tags, collaborator_ids
     ) VALUES ($1::UUID,$2::UUID,$3,$4,$5,$6,$7,$8,$9,0,$10,$11,$12,$13,$14,$15,$16,$17)
     RETURNING id, title, restaurant_id, status, start_at, seats_total,
               seats_booked, price_per_seat, host_id`,
    [
      targetHostId, input.restaurantId, input.title, input.tagline, input.description,
      input.startAt, input.endAt, durationMinutes, input.seatsTotal,
      input.pricePerSeat, input.type, input.audience, initialStatus,
      input.menuStyle, input.coverImage, input.tags, input.collaboratorIds,
    ],
  );

  if (!created) throw new ApiError(500, 'Event creation failed');

  res.status(201).json({
    data: {
      event: {
        id: created.id,
        title: created.title,
        restaurantId: created.restaurant_id,
        hostId: created.host_id,
        status: created.status,
        startAt: created.start_at,
        seatsTotal: created.seats_total,
        seatsBooked: created.seats_booked,
        pricePerSeat: Number(created.price_per_seat),
      },
    },
  });
});

// PUT /api/partner/events/:id, update an event the caller operates.
//
// `status` is deliberately absent from the accepted body. It used to be a raw
// column write, which meant a venue could set *any* status on *any* host's
// event — including reverting a confirmed experience to draft or pushing a
// requested one live. Status now moves only through the explicit transitions
// below, and only the fields the venue actually owns may be written.
router.put('/events/:id', async (req, res) => {
  const eventId = String(req.params.id);
  const body = (req.body ?? {}) as Record<string, unknown>;

  if ('status' in body) {
    throw new ApiError(
      400,
      'status cannot be written directly; use POST /events/:id/{cancel,complete,reopen}',
    );
  }
  if ('hostId' in body || 'restaurantId' in body) {
    throw new ApiError(400, 'An event cannot be moved to another host or venue');
  }

  const updateSchema = createPartnerEventSchema
    .omit({ hostId: true, status: true, restaurantId: true })
    .partial();
  const input = updateSchema.parse(body);
  const provided = new Set(Object.keys(body));

  const event = await loadVenueEvent(req, eventId, 'manager');
  const venueIsNotTheHost = event.host_id !== req.userId;

  if (venueIsNotTheHost) {
    for (const field of provided) {
      if (HOST_OWNED_FIELDS.has(field)) {
        throw new ApiError(403, `Host-owned field: ${field}`);
      }
    }
  }

  if (event.status === 'cancelled' || event.status === 'completed') {
    throw new ApiError(
      409,
      `A ${event.status} experience can no longer be edited`,
    );
  }

  // Drive the SET list off the keys the caller actually sent. `.partial()` does
  // not strip `.default()`s, so trusting `input` alone made `PUT {}` reset
  // tagline/description/type/audience/menu_style/cover_image/tags to defaults.
  const columnMap: Record<string, string> = {
    title: 'title',
    tagline: 'tagline',
    description: 'description',
    startAt: 'start_at',
    endAt: 'end_at',
    seatsTotal: 'seats_total',
    pricePerSeat: 'price_per_seat',
    type: 'type',
    audience: 'audience',
    menuStyle: 'menu_style',
    coverImage: 'cover_image',
    tags: 'tags',
    collaboratorIds: 'collaborator_ids',
  };

  const changed: string[] = [];
  const sets: string[] = [];
  const params: unknown[] = [];
  for (const [field, column] of Object.entries(columnMap)) {
    if (!provided.has(field)) continue;
    const value = (input as Record<string, unknown>)[field];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
    changed.push(field);
  }

  // An empty PUT is a client bug, not a success: answering 200 with
  // `updated: false` hides it.
  if (sets.length === 0) {
    throw new ApiError(400, 'No updatable fields were provided');
  }
  sets.push('updated_at = now()');

  params.push(eventId);
  const [updated] = await query<{ id: string; title: string; status: string }>(
    `UPDATE dinner_events SET ${sets.join(', ')} WHERE id = $${params.length}::UUID
     RETURNING id, title, status`,
    params,
  );

  // The host has to be able to see what the venue changed under them.
  if (venueIsNotTheHost) {
    await notifyUser(null, event.host_id, {
      kind: 'approval',
      title: 'Your venue updated this experience',
      body: `${event.title}: ${changed.join(', ')} changed by the venue.`,
      eventId,
    });
  }

  res.json({ data: { event: updated, changedFields: changed } });
});

// ── Explicit status transitions ──────────────────────────────────────────────
//
// The only way a venue moves an experience's status. Each one is guarded, and
// each one tells the host, because the host is the account that owns the
// listing and the guests.

const transitionSchema = z.object({ reason: z.string().trim().max(500).optional() });

/** POST /api/partner/events/:id/cancel, soft cancel an experience. */
router.post('/events/:id/cancel', async (req, res) => {
  const eventId = String(req.params.id);
  const reason = transitionSchema.parse(req.body ?? {}).reason ?? '';

  const event = await loadVenueEvent(req, eventId, 'manager');
  if (event.status === 'cancelled') {
    throw new ApiError(409, 'This event is already cancelled');
  }

  await withTransaction(async (client) => {
    await assertNoCapturedMoney(client, eventId);
    await softCancel(
      client, { id: eventId, title: event.title }, req.userId, reason,
      'was cancelled by the venue.',
    );
  });

  await notifyUser(null, event.host_id, {
    kind: 'approval',
    title: 'Your experience was cancelled by the venue',
    body: reason
      ? `${event.title} was cancelled: ${reason}`
      : `${event.title} was cancelled by the venue.`,
    eventId,
  });

  res.json({ data: { eventId, status: 'cancelled' } });
});

/** POST /api/partner/events/:id/complete, close out a finished experience. */
router.post('/events/:id/complete', async (req, res) => {
  const eventId = String(req.params.id);
  const event = await loadVenueEvent(req, eventId, 'manager');
  if (!['confirmed', 'live'].includes(event.status)) {
    throw new ApiError(409, `A ${event.status} experience cannot be completed`);
  }

  const [updated] = await query<{ id: string; status: string }>(
    `UPDATE dinner_events SET status = 'completed', updated_at = now()
      WHERE id = $1::UUID AND status IN ('confirmed','live')
      RETURNING id, status`,
    [eventId],
  );
  if (!updated) throw new ApiError(409, 'This experience can no longer be completed');

  await notifyUser(null, event.host_id, {
    kind: 'approval',
    title: 'Your experience was marked complete',
    body: `${event.title} was closed out by the venue.`,
    eventId,
  });

  res.json({ data: { event: updated } });
});

/** POST /api/partner/events/:id/reopen, put a completed experience back up. */
router.post('/events/:id/reopen', async (req, res) => {
  const eventId = String(req.params.id);
  const event = await loadVenueEvent(req, eventId, 'manager');
  if (event.status !== 'completed') {
    throw new ApiError(409, `Only a completed experience can be reopened`);
  }

  const [updated] = await query<{ id: string; status: string }>(
    `UPDATE dinner_events SET status = 'confirmed', updated_at = now()
      WHERE id = $1::UUID AND status = 'completed'
      RETURNING id, status`,
    [eventId],
  );
  if (!updated) throw new ApiError(409, 'This experience can no longer be reopened');

  await notifyUser(null, event.host_id, {
    kind: 'approval',
    title: 'Your experience was reopened',
    body: `${event.title} is bookable again.`,
    eventId,
  });

  res.json({ data: { event: updated } });
});

// GET /api/partner/events, all events for the partner's restaurants.
router.get('/events', async (req, res) => {
  const { status, limit = '50' } = req.query;
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];
  const conditions: string[] = [venueScopeClause('r.id', scope, params)];

  if (typeof status === 'string' && status !== '') {
    params.push(status);
    conditions.push(`e.status = $${params.length}`);
  }

  const where = conditions.join(' AND ');
  const parsedLimit = Math.min(Number(limit) || 50, 200);

  const rows = await query<{
    id: string; title: string; tagline: string; cover_image: string;
    restaurant_name: string; start_at: Date;
    seats_total: number; seats_booked: number; price_per_seat: string;
    status: string; type: string; restaurant_id: string; host_id: string;
  }>(
    `SELECT e.id, e.title, e.tagline, e.cover_image, r.name AS restaurant_name,
            e.start_at, e.seats_total, e.seats_booked, e.price_per_seat,
            e.status, e.type, e.restaurant_id, e.host_id
     FROM dinner_events e
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE ${where}
     ORDER BY e.start_at DESC
     LIMIT ${parsedLimit}`,
    params,
  );

  const events = rows.map((e) => ({
      id: e.id,
      title: e.title,
      // The partner card renders the tagline and the venue's own photo. Both
      // are written by the create/edit routes above and were simply never
      // selected here, so the app could not show what the venue had saved.
      tagline: e.tagline,
      coverImage: e.cover_image,
      restaurantName: e.restaurant_name,
      // The app needs both to offer a draft for attachment to a proposal: the
      // server only accepts a draft that belongs to this venue *and* to the
      // host being asked, so a venue must be able to tell which rows qualify.
      restaurantId: e.restaurant_id,
      hostId: e.host_id,
      startAt: e.start_at,
      seatsTotal: e.seats_total,
      seatsBooked: e.seats_booked,
      seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
      pricePerSeat: Number(e.price_per_seat),
      status: e.status,
      type: e.type,
    }));

  res.json({ data: { events }, meta: { total: events.length } });
});

// ── Bookings for partner events ──────────────────────────────────────────────

// GET /api/partner/bookings, all bookings for the partner's events.
router.get('/bookings', async (req, res) => {
  const { eventId, status, limit = '100' } = req.query;
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];
  const conditions: string[] = [venueScopeClause('r.id', scope, params)];

  if (typeof eventId === 'string' && eventId !== '') {
    params.push(eventId);
    conditions.push(`e.id = $${params.length}`);
  }
  if (typeof status === 'string' && status !== '') {
    params.push(status);
    conditions.push(`b.status = $${params.length}`);
  }

  const where = conditions.join(' AND ');
  const parsedLimit = Math.min(Number(limit) || 100, 500);

  const rows = await query<{
    id: string; event_id: string; event_title: string; user_id: string;
    user_name: string; seats: number; total_amount: string;
    status: string; payment_status: string; reference: string;
    checked_in: boolean; created_at: Date;
  }>(
    `SELECT b.id, b.event_id, e.title AS event_title,
            b.user_id, u.name AS user_name,
            b.seats, b.total_amount, b.status, b.payment_status,
            b.reference, b.checked_in, b.created_at
     FROM bookings b
     JOIN dinner_events e ON e.id = b.event_id
     JOIN restaurants r ON r.id = e.restaurant_id
     JOIN users u ON u.id = b.user_id
     WHERE ${where}
     ORDER BY b.created_at DESC
     LIMIT ${parsedLimit}`,
    params,
  );

  const bookings = rows.map((b) => ({
      id: b.id,
      eventId: b.event_id,
      eventTitle: b.event_title,
      userId: b.user_id,
      userName: b.user_name,
      seats: b.seats,
      totalAmount: Number(b.total_amount),
      status: b.status,
      paymentStatus: b.payment_status,
      reference: b.reference,
      checkedIn: b.checked_in,
      createdAt: b.created_at,
    }));

  res.json({ data: { bookings }, meta: { total: bookings.length } });
});

// POST /api/partner/bookings/:id/checkin, check in a guest.
router.post('/bookings/:id/checkin', async (req, res) => {
  const bookingId = req.params.id;

  // Verify the booking belongs to one of the partner's events
  const [booking] = await query<{
    id: string; event_id: string; user_id: string; seats: number;
    status: string; checked_in: boolean;
  }>(
    `SELECT b.id, b.event_id, b.user_id, b.seats, b.status, b.checked_in
     FROM bookings b
     WHERE b.id = $1::UUID`,
    [bookingId],
  );
  if (!booking) throw notFound('Booking');

  // Check-in is a door action, so `staff` on the venue is enough.
  const [event] = await query<{ restaurant_id: string }>(
    'SELECT restaurant_id FROM dinner_events WHERE id = $1::UUID',
    [booking.event_id],
  );
  if (!event) throw notFound('Event');
  await requireVenueRole(req, event.restaurant_id, 'staff');
  if (booking.status === 'cancelled') {
    throw new ApiError(409, 'Cancelled bookings cannot be checked in');
  }
  if (booking.checked_in) {
    throw new ApiError(409, 'Already checked in');
  }

  await query(
    'UPDATE bookings SET checked_in = true, checked_in_at = now() WHERE id = $1::UUID',
    [bookingId],
  );

  res.json({
    data: {
      booking: {
        id: booking.id,
        eventId: booking.event_id,
        userId: booking.user_id,
        seats: booking.seats,
        checkedIn: true,
      },
    },
  });
});

// ── Special Menus ────────────────────────────────────────────────────────────

const createMenuSchema = z.object({
  restaurantId: z.string().uuid(),
  name: z.string().trim().min(2).max(120),
  description: z.string().trim().max(2000).default(''),
  pricePerGuest: z.number().positive().max(10000),
  minGuests: z.number().int().min(1).default(2),
  tags: z.array(z.string()).default([]),
  coverImage: z.string().default(''),
});

// POST /api/partner/menus, create a special menu.
router.post('/menus', async (req, res) => {
  const input = createMenuSchema.parse(req.body);

  await requireVenueRole(req, input.restaurantId, 'manager');

  const [created] = await query<{
    id: string; name: string; restaurant_id: string; status: string;
    price_per_guest: string;
  }>(
    `INSERT INTO special_menus (restaurant_id, name, description, price_per_guest, min_guests, tags, cover_image)
     VALUES ($1,$2,$3,$4,$5,$6,$7)
     RETURNING id, name, restaurant_id, status, price_per_guest`,
    [input.restaurantId, input.name, input.description, input.pricePerGuest, input.minGuests, input.tags, input.coverImage],
  );

  if (!created) throw new ApiError(500, 'Menu creation failed');

  res.status(201).json({
    data: {
      menu: {
        id: created.id,
        name: created.name,
        restaurantId: created.restaurant_id,
        status: created.status,
        pricePerGuest: Number(created.price_per_guest),
      },
    },
  });
});

// GET /api/partner/menus, special menus for the partner's restaurants.
router.get('/menus', async (req, res) => {
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];
  const rows = await query<{
    id: string; restaurant_id: string; restaurant_name: string;
    name: string; description: string; status: string;
    price_per_guest: string; min_guests: number; tags: string[];
    views_this_week: number; bookings_count: number;
  }>(
    `SELECT sm.id, sm.restaurant_id, r.name AS restaurant_name,
            sm.name, sm.description, sm.status, sm.price_per_guest,
            sm.min_guests, sm.tags, sm.views_this_week, sm.bookings_count
     FROM special_menus sm
     JOIN restaurants r ON r.id = sm.restaurant_id
     WHERE ${venueScopeClause('r.id', scope, params)}
     ORDER BY sm.created_at DESC`,
    params,
  );

  const menus = rows.map((m) => ({
      id: m.id,
      restaurantId: m.restaurant_id,
      restaurantName: m.restaurant_name,
      name: m.name,
      description: m.description,
      status: m.status,
      pricePerGuest: Number(m.price_per_guest),
      minGuests: m.min_guests,
      tags: m.tags,
      viewsThisWeek: m.views_this_week,
      bookingsCount: m.bookings_count,
    }));

  res.json({ data: { menus }, meta: { total: menus.length } });
});

// ── Analytics ────────────────────────────────────────────────────────────────

// GET /api/partner/analytics, business insights for the partner dashboard.
router.get('/analytics', async (req, res) => {
  const scope = await scopedRestaurantIds(req.userId, req.userRole);

  // Revenue summary across all partner restaurants
  const revenueParams: unknown[] = [];
  const [revenue] = await query<{
    total_revenue: string;
    total_bookings: number;
    total_events: number;
    avg_price_per_seat: string;
    total_covers: number;
  }>(
    `SELECT
       COALESCE(SUM(b.total_amount), 0)::text AS total_revenue,
       COUNT(b.id)::int AS total_bookings,
       COUNT(DISTINCT e.id)::int AS total_events,
       COALESCE(AVG(b.price_per_seat), 0)::text AS avg_price_per_seat,
       COALESCE(SUM(b.seats), 0)::int AS total_covers
     FROM bookings b
     JOIN dinner_events e ON e.id = b.event_id
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE ${venueScopeClause('r.id', scope, revenueParams)}
       AND b.status <> 'cancelled'`,
    revenueParams,
  );

  // Upcoming events count
  const upcomingParams: unknown[] = [];
  const [upcoming] = await query<{ count: number }>(
    `SELECT COUNT(*)::int AS count
     FROM dinner_events e
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE ${venueScopeClause('r.id', scope, upcomingParams)}
       AND e.start_at >= now()
       AND e.status IN ('confirmed', 'live', 'requested')`,
    upcomingParams,
  );

  // Average fill rate
  const fillParams: unknown[] = [];
  const [fillRate] = await query<{ avg_fill: number }>(
    `SELECT COALESCE(AVG(e.seats_booked::numeric / GREATEST(e.seats_total, 1)), 0)::float8 AS avg_fill
     FROM dinner_events e
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE ${venueScopeClause('r.id', scope, fillParams)}
       AND e.start_at < now()`,
    fillParams,
  );

  // Recent bookings (last 10)
  const recentParams: unknown[] = [];
  const recentBookings = await query<{
    id: string; event_title: string; user_name: string;
    seats: number; total_amount: string; status: string; created_at: Date;
  }>(
    `SELECT b.id, e.title AS event_title, u.name AS user_name,
            b.seats, b.total_amount, b.status, b.created_at
     FROM bookings b
     JOIN dinner_events e ON e.id = b.event_id
     JOIN restaurants r ON r.id = e.restaurant_id
     JOIN users u ON u.id = b.user_id
     WHERE ${venueScopeClause('r.id', scope, recentParams)}
     ORDER BY b.created_at DESC
     LIMIT 10`,
    recentParams,
  );

  const analytics = {
    totalRevenue: Number(revenue?.total_revenue ?? 0),
    totalBookings: revenue?.total_bookings ?? 0,
    totalEvents: revenue?.total_events ?? 0,
    avgPricePerSeat: Number(revenue?.avg_price_per_seat ?? 0),
    totalCovers: revenue?.total_covers ?? 0,
    upcomingEvents: upcoming?.count ?? 0,
    avgFillRate: fillRate?.avg_fill ?? 0,
  };

  const recent = recentBookings.map((b) => ({
      id: b.id,
      eventTitle: b.event_title,
      userName: b.user_name,
      seats: b.seats,
      totalAmount: Number(b.total_amount),
      status: b.status,
      createdAt: b.created_at,
    }));

  res.json({ data: { analytics, recentBookings: recent } });
});

// ── Notifications ────────────────────────────────────────────────────────────

// GET /api/partner/notifications, notifications for the partner's restaurants.
router.get('/notifications', async (req, res) => {
  const { unreadOnly, limit = '50' } = req.query;
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];
  const conditions: string[] = [
    venueScopeClause('n.restaurant_id', scope, params),
  ];

  if (unreadOnly === 'true') {
    conditions.push('n.read = false');
  }

  const where = conditions.join(' AND ');
  const parsedLimit = Math.min(Number(limit) || 50, 200);

  const rows = await query<{
    id: string; restaurant_id: string; title: string; body: string;
    category: string; read: boolean; icon: string | null; tint: string | null;
    notification_time: Date;
  }>(
    `SELECT n.* FROM notifications n
     WHERE ${where}
     ORDER BY n.notification_time DESC
     LIMIT ${parsedLimit}`,
    params,
  );

  const notifications = rows.map((n) => ({
      id: n.id,
      restaurantId: n.restaurant_id,
      title: n.title,
      body: n.body,
      category: n.category,
      read: n.read,
      icon: n.icon,
      tint: n.tint,
      notificationTime: n.notification_time,
    }));

  // The unread badge lives on the same call so the app never has to total the
  // page it was given: `unreadOnly` would otherwise be the only way to know.
  const unreadParams: unknown[] = [];
  const [unread] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM notifications n
      WHERE n.read = false
        AND ${venueScopeClause('n.restaurant_id', scope, unreadParams)}`,
    unreadParams,
  );

  res.json({
    data: { notifications },
    meta: { total: notifications.length, unread: unread?.count ?? 0 },
  });
});

// POST /api/partner/notifications/:notificationId/read, clear one badge.
//
// Without this the dashboard's `notifications.unread` could only ever grow:
// the Partner App had no way to acknowledge what it had shown.
router.post('/notifications/:notificationId/read', async (req, res) => {
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [req.params.notificationId];

  const rows = await query<{ id: string }>(
    `UPDATE notifications n SET read = true
      WHERE n.id = $1::UUID
        AND ${venueScopeClause('n.restaurant_id', scope, params)}
      RETURNING n.id`,
    params,
  );
  const notification = rows[0];
  if (!notification) throw notFound('Notification');

  res.json({ data: { notification: { id: notification.id, read: true } } });
});

// POST /api/partner/notifications/read-all, acknowledge the whole inbox.
router.post('/notifications/read-all', async (req, res) => {
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];

  const rows = await query<{ id: string }>(
    `UPDATE notifications n SET read = true
      WHERE n.read = false
        AND ${venueScopeClause('n.restaurant_id', scope, params)}
      RETURNING n.id`,
    params,
  );

  res.json({ data: { updated: rows.length } });
});

export default router;
