import { Router } from 'express';
import { z, ZodError } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, forbidden, hasHostCapabilities, requireHostStudio } from '../context.js';
import { notBlockedBetween } from '../blocks.js';

const router = Router();

// CHECK-constrained enums from schema.sql. Kept here so list filters can
// whitelist comma-separated values (multi-select discovery categories).
const EVENT_TYPES = ['dinner', 'tasting', 'supperClub', 'brunch', 'workshop', 'festival'] as const;
const AUDIENCES = ['public', 'followers', 'friends', 'inviteOnly'] as const;

/** Row shape shared by list and detail queries. */
export type EventRow = {
  id: string;
  title: string;
  tagline: string;
  description: string;
  host_id: string;
  restaurant_id: string;
  cover_image: string;
  gallery: string[];
  start_at: Date;
  duration_minutes: number;
  seats_total: number;
  seats_booked: number;
  price_per_seat: string;
  type: string;
  audience: string;
  menu_style: string;
  included: string[];
  tags: string[];
  is_featured: boolean;
  host_note: string;
  language: string;
  dress_code: string;
  cancellation: string;
  attendee_ids: string[];
  status: string;
  requires_approval: boolean;
  host_name: string | null;
  host_handle: string | null;
  host_avatar: string | null;
  host_role: string | null;
  host_badges: string[] | null;
  // Host food preferences (P1-5) — surfaced so the event's dietary card can
  // show what the host eats, not just what the menu says.
  host_dietary: string[] | null;
  restaurant_name: string | null;
  restaurant_neighborhood: string | null;
  // Venue coordinates (map markers for dinner cards). pg returns float8 as number.
  restaurant_latitude: number | string | null;
  restaurant_longitude: number | string | null;
};

export const EVENT_SELECT = `
  SELECT e.*, u.name AS host_name, u.handle AS host_handle, u.avatar_url AS host_avatar,
         u.role AS host_role, u.badges AS host_badges, u.dietary AS host_dietary,
         r.name AS restaurant_name, r.neighborhood AS restaurant_neighborhood,
         r.latitude AS restaurant_latitude, r.longitude AS restaurant_longitude
  FROM dinner_events e
  LEFT JOIN users u ON u.id = e.host_id
  LEFT JOIN restaurants r ON r.id = e.restaurant_id`;

export function serializeEvent(row: EventRow) {
  const seatsLeft = Math.max(0, row.seats_total - row.seats_booked);
  return {
    id: row.id,
    title: row.title,
    tagline: row.tagline,
    description: row.description,
    hostId: row.host_id,
    host: row.host_name === null ? null : {
      id: row.host_id,
      name: row.host_name,
      handle: row.host_handle,
      avatarUrl: row.host_avatar,
      // Tier flags so the app can render verified badges and the influencer
      // discovery filter straight off event payloads.
      isInfluencer: row.host_role === 'influencer',
      isVerified:
        (row.host_badges?.includes('verified') ?? false) ||
        row.host_role === 'influencer',
      // P1-5: host dietary preferences ride the same reference the UI already
      // renders, so the event's dietary card needs no extra round-trip.
      dietary: row.host_dietary ?? [],
    },
    restaurantId: row.restaurant_id,
    restaurant: row.restaurant_name === null ? null : {
      id: row.restaurant_id,
      name: row.restaurant_name,
      neighborhood: row.restaurant_neighborhood,
      latitude: row.restaurant_latitude === null || row.restaurant_latitude === undefined
        ? null : Number(row.restaurant_latitude),
      longitude: row.restaurant_longitude === null || row.restaurant_longitude === undefined
        ? null : Number(row.restaurant_longitude),
    },
    coverImage: row.cover_image,
    gallery: row.gallery,
    startAt: row.start_at,
    durationMinutes: row.duration_minutes,
    seatsTotal: row.seats_total,
    seatsBooked: row.seats_booked,
    seatsLeft,
    isSoldOut: seatsLeft <= 0,
    pricePerSeat: Number(row.price_per_seat),
    type: row.type,
    audience: row.audience,
    menuStyle: row.menu_style,
    included: row.included,
    tags: row.tags,
    isFeatured: row.is_featured,
    hostNote: row.host_note,
    language: row.language,
    dressCode: row.dress_code,
    cancellation: row.cancellation,
    attendeeIds: row.attendee_ids,
    status: row.status,
  };
}

// Local alias so the existing handlers keep reading like before.
const serialize = serializeEvent;

/**
 * Visibility rule: public and friends tables are open; follower tables need
 * a follow; invite-only tables need a seat. Hosts and booked guests always
 * see their own tables.
 *
 * Exported so the universal search (`routes/search.ts`) applies the identical
 * audience gate instead of re-implementing it.
 */
export const AUDIENCE_GATE = `(e.audience IN ('public','friends')
     OR e.host_id = $VIEWER_UUID
     OR (e.audience = 'followers' AND EXISTS (
           SELECT 1 FROM follows f
           WHERE f.follower_id = $VIEWER_UUID AND f.followee_id = e.host_id))
     OR (e.audience = 'inviteOnly' AND $VIEWER = ANY(e.attendee_ids))
     OR EXISTS (
           SELECT 1 FROM bookings b
           WHERE b.event_id = e.id AND b.user_id = $VIEWER_UUID
             AND b.status <> 'cancelled'))`;

// GET /api/events — filterable feed of events the viewer may see.
router.get('/', async (req, res) => {
  // Fire-and-forget token cleanup: delete expired auth_tokens, otp_codes,
  // and email_change_challenges.
  const {
    type, audience, featured, hostId, venueId, upcoming, q, maxPrice, from, to,
    city, neighborhood, sort,
    limit = '50', offset = '0',
  } = req.query;

  const conditions: string[] = [];
  const params: unknown[] = [req.userId, req.userId]; // $1 = text (attendee_ids), $2 = UUID
  conditions.push(
    AUDIENCE_GATE.replaceAll('$VIEWER_UUID', '$2').replaceAll('$VIEWER', '$1'),
  );
  // Drafts and venue-pending events are visible only to their host.
  conditions.push(
    "(e.status NOT IN ('draft','requested','declined') OR e.host_id = $2)",
  );
  // P2-1: events hosted by anyone in a blocked pair with the viewer leave the
  // personalized feed/search — in both directions (the blocked host stops
  // seeing the blocker's tables too). Existing tickets are unaffected; the
  // bookings surfaces read them straight from `bookings`.
  conditions.push(notBlockedBetween('$2', 'e.host_id'));

  const add = (sqlFragment: string, value: unknown) => {
    params.push(value);
    conditions.push(sqlFragment.replace('?', `$${params.length}`));
  };

  // Multi-value filter: split on commas, keep only whitelisted tokens, and
  // build an `IN (...)` list. Invalid tokens are ignored (single values and
  // `a,b,c` both work; all-invalid input is a no-op). Returns nothing when
  // nothing valid survives so the caller can fall through to no predicate.
  const addIn = (
    column: string,
    raw: string,
    allowed: readonly string[],
  ) => {
    const tokens = raw
      .split(',')
      .map((t) => t.trim())
      .filter((t) => allowed.includes(t));
    if (tokens.length === 0) return;
    const placeholders = tokens.map((t) => {
      params.push(t);
      return `$${params.length}`;
    });
    conditions.push(`${column} IN (${placeholders.join(', ')})`);
  };

  if (typeof type === 'string' && type !== '') {
    addIn('e.type', type, EVENT_TYPES);
  }
  if (typeof audience === 'string' && audience !== '') {
    addIn('e.audience', audience, AUDIENCES);
  }
  if (featured === 'true') conditions.push('e.is_featured');
  if (typeof hostId === 'string' && hostId !== '') add('e.host_id = ?::UUID', hostId);
  if (typeof venueId === 'string' && venueId !== '') {
    add('e.restaurant_id = ?::UUID', venueId);
  }
  // Location discovery: the venue JOIN (`r`) is already present, so we can
  // scope the feed to a city / neighborhood the way `/restaurants` and
  // `/offers` do. Empty values are a no-op.
  if (typeof city === 'string' && city.trim() !== '') {
    add('r.city ILIKE ?', `%${city.trim()}%`);
  }
  if (typeof neighborhood === 'string' && neighborhood.trim() !== '') {
    add('r.neighborhood ILIKE ?', `%${neighborhood.trim()}%`);
  }
  if (upcoming === 'false') {
    conditions.push('e.start_at < now()');
  } else if (upcoming !== 'all') {
    conditions.push('e.start_at >= now()');
  }
  if (typeof q === 'string' && q.trim() !== '') {
    params.push(`%${q.trim()}%`);
    const i = params.length;
    // Venue names ride the existing `r` JOIN so "Kolachi" finds dinners there.
    conditions.push(
      `(e.title ILIKE $${i} OR e.tagline ILIKE $${i} OR r.name ILIKE $${i} OR EXISTS (
         SELECT 1 FROM unnest(e.tags) tag WHERE tag ILIKE $${i}))`,
    );
  }
  const parsedMaxPrice = Number(maxPrice);
  if (Number.isFinite(parsedMaxPrice) && parsedMaxPrice >= 0) {
    add('e.price_per_seat <= ?', parsedMaxPrice);
  }
  // ISO bounds on start_at; invalid timestamps are ignored rather than 400.
  if (typeof from === 'string' && from.trim() !== '' && !Number.isNaN(Date.parse(from))) {
    add('e.start_at >= ?::TIMESTAMPTZ', from.trim());
  }
  if (typeof to === 'string' && to.trim() !== '' && !Number.isNaN(Date.parse(to))) {
    add('e.start_at <= ?::TIMESTAMPTZ', to.trim());
  }

  const where = conditions.length === 0 ? '' : `WHERE ${conditions.join(' AND ')}`;
  const parsedLimit = Math.min(Number(limit) || 50, 200);
  const parsedOffset = Math.max(Number(offset) || 0, 0);

  // Sort modes for the Home rails: `soon` (default), `trending` (fill ratio),
  // and `forYou` (venue cuisines overlapping the viewer's tastes).
  const sortMode = typeof sort === 'string' ? sort.trim() : '';
  let orderBy: string;
  if (sortMode === 'trending') {
    orderBy = `(e.seats_booked::numeric / GREATEST(e.seats_total, 1)) DESC, e.start_at ASC`;
  } else if (sortMode === 'forYou') {
    // Pull the viewer's taste list once; if empty, degrade to `soon` ordering
    // so we never return an empty feed just because the user hasn't picked
    // preferences yet.
    const [prefs] = await query<{ tastes: string[] }>(
      'SELECT tastes FROM users WHERE id = $1::UUID',
      [req.userId],
    );
    const tastes = prefs?.tastes ?? [];
    if (tastes.length === 0) {
      orderBy = `e.start_at ASC`;
    } else {
      params.push(tastes);
      const tastesParam = `$${params.length}::text[]`;
      orderBy = `cardinality(ARRAY(SELECT unnest(r.cuisines) INTERSECT SELECT unnest(${tastesParam}))) DESC, e.start_at ASC`;
    }
  } else {
    orderBy = `e.start_at ASC`;
  }

  const rows = await query<EventRow>(
    `${EVENT_SELECT} ${where} ORDER BY ${orderBy} LIMIT ${parsedLimit} OFFSET ${parsedOffset}`,
    params,
  );
  res.json({ events: rows.map(serialize), count: rows.length });
});

// GET /api/events/mine — the host's own events, drafts included, newest first.
// Registered before `/:id` so the literal path wins.
router.get('/mine', async (req, res) => {
  const rows = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.host_id = $1::UUID ORDER BY e.created_at DESC LIMIT 200`,
    [req.userId],
  );
  res.json({ events: rows.map(serialize), count: rows.length });
});

// GET /api/events/:id — one visible event with menu, host and venue.
router.get('/:id', async (req, res) => {
  const [event] = await query<EventRow>(
    `${EVENT_SELECT}
     WHERE e.id = $1::UUID
       AND (e.status NOT IN ('draft','requested','declined') OR e.host_id = $3)
       AND ${AUDIENCE_GATE.replaceAll('$VIEWER_UUID', '$3').replaceAll('$VIEWER', '$2')}
       AND (${notBlockedBetween('$3', 'e.host_id')}
         OR e.host_id = $3::UUID
         OR EXISTS (
           SELECT 1 FROM bookings b
           WHERE b.event_id = e.id AND b.user_id = $3::UUID
             AND b.status <> 'cancelled'))`,
    [req.params.id, req.userId, req.userId],
  );
  if (!event) throw notFound('Event');

  // Real view counting (host-studio analytics): every non-host glance bumps the
  // counter. Fire-and-forget so it never blocks or fails the detail response.
  if (req.userId !== event.host_id && event.status !== 'draft') {
    void query('UPDATE dinner_events SET views = views + 1 WHERE id = $1::UUID', [
      req.params.id,
    ]).catch(() => {});
  }

  const menu = await query<{
    id: string; position: number; name: string;
    description: string; pairing: string | null; signature: boolean;
  }>(
    `SELECT id, position, name, description, pairing, signature
     FROM menu_items WHERE event_id = $1 ORDER BY position ASC`,
    [req.params.id],
  );

  const [venue] = await query<{
    id: string; name: string; cuisines: string[]; neighborhood: string;
    address: string; rating: string; review_count: number; price_range: string;
    cover_image: string; gallery: string[];
    about: string; tags: string[]; is_partner: boolean;
    partner_perk: string | null; opening_hours: object; seats: number;
  }>(
    `SELECT * FROM restaurants WHERE id = $1`,
    [event.restaurant_id],
  );

  const attendees = await query<{
    id: string; name: string; handle: string; avatar_url: string | null;
  }>(
    `SELECT id, name, handle, avatar_url FROM users
     WHERE id::text = ANY($1::text[])`,
    [event.attendee_ids],
  );

  res.json({
    event: {
      ...serialize(event),
      menu: menu.map((m) => ({
        id: m.id,
        position: m.position,
        name: m.name,
        description: m.description,
        pairing: m.pairing,
        isSignature: m.signature,
      })),
      venue: venue === undefined ? null : {
        id: venue.id,
        name: venue.name,
        cuisines: venue.cuisines,
        neighborhood: venue.neighborhood,
        address: venue.address,
        rating: Number(venue.rating),
        reviewCount: venue.review_count,
        priceRange: venue.price_range,
        coverImage: venue.cover_image,
        gallery: venue.gallery,
        about: venue.about,
        tags: venue.tags,
        isPartner: venue.is_partner,
        partnerPerk: venue.partner_perk,
        openingHours: venue.opening_hours,
      },
      attendees: attendees.map((a) => ({
        id: a.id, name: a.name, handle: a.handle, avatarUrl: a.avatar_url,
      })),
    },
  });
});

const createEventSchema = z.object({
  title: z.string().trim().min(3).max(120),
  tagline: z.string().trim().max(200).default(''),
  description: z.string().trim().max(4000).default(''),
  restaurantId: z.string().min(1),
  hostId: z.string().min(1).optional(),
  coverImage: z.string().min(1),
  gallery: z.array(z.string()).default([]),
  startAt: z.coerce.date(),
  durationMinutes: z.number().int().min(30).max(600).default(150),
  seatsTotal: z.number().int().min(1).max(100),
  // Free dinners are allowed (price 0); the app's wizard has a free tier.
  pricePerSeat: z.number().min(0).max(10000),
  type: z.enum(['dinner', 'tasting', 'supperClub', 'brunch', 'workshop', 'festival']).default('dinner'),
  audience: z.enum(['public', 'followers', 'friends', 'inviteOnly']).default('public'),
  menuStyle: z.enum(['setMenu', 'tastingMenu', 'familyStyle', 'sharing', 'buffet']).default('familyStyle'),
  included: z.array(z.string()).default([]),
  tags: z.array(z.string()).default([]),
  // isFeatured is a platform-admin flag — hosts cannot set it. The column
  // defaults to false in the schema, and only super_admin routes may flip it.
  hostNote: z.string().trim().max(1000).default(''),
  requiresApproval: z.boolean().default(false),
  menu: z.array(z.object({
    name: z.string().trim().min(1).max(120),
    description: z.string().trim().max(400).default(''),
    pairing: z.string().trim().max(120).optional(),
    isSignature: z.boolean().default(false),
  })).default([]),
});

// Drafts skip the published path's date/seats strictness so a host can park a
// half-finished dinner and polish it later; publishing re-validates fully.
const draftEventSchema = createEventSchema.extend({
  title: z.string().trim().min(1).max(120),
  coverImage: z.string().min(1).default('assets/images/hero_tasting.png'),
  startAt: z.coerce.date().optional(),
  seatsTotal: z.number().int().min(0).max(100).default(8),
  pricePerSeat: z.number().min(0).max(10000).default(0),
});

// POST /api/events — publish a new event (hosts and partner admins only).
// `status: 'draft'` saves an unfinished draft instead of publishing.
// `requireHostStudio` is the account-type gate: a Personal account cannot
// publish even if it once earned the host role.
router.post('/', requireHostStudio, async (req, res) => {
  // Publishing rides the single-account ladder: host, influencer and the
  // publishing admins may create events.
  if (!hasHostCapabilities(req.userRole)) {
    throw new ApiError(403, 'Only hosts or partners can create events');
  }

  const requestedStatus = z.enum(['draft', 'published'])
    .default('published')
    .parse((req.body as { status?: unknown } | undefined)?.status);
  const isDraft = requestedStatus === 'draft';
  const input = isDraft
    ? draftEventSchema.parse(req.body)
    : createEventSchema.parse(req.body);
  // Force hostId to the caller — prevent impersonation
  const hostId = req.userId;

  const [venue] = await query<{
    id: string; owner_id: string; is_partner: boolean; partnership_status: string;
    requires_host_approval: boolean;
  }>(
    `SELECT id, owner_id, is_partner, partnership_status, requires_host_approval
       FROM restaurants WHERE id = $1::UUID`,
    [input.restaurantId],
  );
  if (!venue) throw new ApiError(422, `Unknown restaurant ${input.restaurantId}`);

  // Hosts and influencers may publish at any verified partner venue;
  // partner/super admins stay restricted to venues they own.
  if (req.userRole === 'host' || req.userRole === 'influencer') {
    if (!venue.is_partner || venue.partnership_status !== 'verified') {
      throw new ApiError(403, 'Venue not verified yet');
    }
  } else if (venue.owner_id !== req.userId) {
    throw new ApiError(403, 'You do not own this restaurant');
  }

  const gallery = input.gallery.length > 0 ? input.gallery : [input.coverImage];

  // A venue that opted into host approvals reserves the right to see a request
  // first: a host's published event lands in `requested` (invisible to diners)
  // until the Partner App approves or declines it. The venue operating its own
  // event, and every venue with the default policy, keep publishing directly.
  const needsVenueApproval = !isDraft
    && venue.requires_host_approval
    && venue.owner_id !== req.userId;
  const initialStatus = isDraft
    ? 'draft'
    : needsVenueApproval ? 'requested' : 'confirmed';

  const [created] = await query<EventRow>(
    `INSERT INTO dinner_events (title, tagline, description, host_id,
                                restaurant_id, cover_image, gallery, start_at,
                                duration_minutes, seats_total, seats_booked,
                                price_per_seat, type, audience, menu_style,
                                included, tags, is_featured, host_note,
                                requires_approval, status)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20,$21)
     RETURNING *`,
    [input.title, input.tagline, input.description, hostId,
     input.restaurantId, input.coverImage, gallery,
     input.startAt ?? new Date(Date.now() + 7 * 864e5),
     input.durationMinutes, input.seatsTotal, 0,
     input.pricePerSeat, input.type, input.audience, input.menuStyle,
     input.included, input.tags, false, input.hostNote,
     input.requiresApproval, initialStatus],
  );

  if (!created) throw new ApiError(500, 'Event creation failed');

  // Create an event_group conversation and add the host as participant.
  const [conv] = await query<{ id: string }>(
    `INSERT INTO conversations (kind, event_id, title)
     VALUES ('event_group', $1::UUID, $2)
     ON CONFLICT (event_id) WHERE event_id IS NOT NULL DO NOTHING
     RETURNING id`,
    [created.id, created.title],
  );
  if (conv) {
    await query(
      `INSERT INTO conversation_participants (conversation_id, user_id, role)
       VALUES ($1::UUID, $2::UUID, 'host')
       ON CONFLICT (conversation_id, user_id) DO NOTHING`,
      [conv.id, hostId],
    );
  }

  // Put the request in front of the venue desk immediately; an approval queue
  // nobody is told about is how host requests rot for a week.
  if (needsVenueApproval) {
    await query(
      `INSERT INTO notifications (restaurant_id, title, body, category, read)
       VALUES ($1::UUID, 'New host event request', $2, 'event', false)`,
      [
        input.restaurantId,
        `${input.title} (${input.seatsTotal} seats) was requested by a host for `
          + `${new Date(input.startAt ?? Date.now()).toISOString()}.`,
      ],
    );
  }

  for (const [i, item] of input.menu.entries()) {
    await query(
      `INSERT INTO menu_items (event_id, position, name, description, pairing, signature)
       VALUES ($1,$2,$3,$4,$5,$6)`,
      [created.id, i, item.name, item.description, item.pairing ?? null, item.isSignature],
    );
  }

  // Re-fetch with JOINs for full serialization
  const [full] = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.id = $1::UUID`, [created.id],
  );
  res.status(201).json({ event: serialize(full!) });
});

const patchEventSchema = createEventSchema.partial().extend({
  status: z.enum(['published']).optional(),
});

// PATCH /api/events/:id — the host edits their own draft, or publishes it.
// Publishing re-validates the merged row against the full create schema.
router.patch('/:id', requireHostStudio, async (req, res) => {
  const eventId = req.params.id;
  const bodyStatus = (req.body as { status?: unknown } | undefined)?.status;
  if (bodyStatus === 'draft') {
    throw new ApiError(400, 'Published events cannot be reverted to draft');
  }

  const [existing] = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.id = $1::UUID`, [eventId],
  );
  if (!existing) throw notFound('Event');
  if (existing.host_id !== req.userId) {
    throw forbidden('Only the host can edit this event');
  }

  const input = patchEventSchema.parse(req.body ?? {});
  const columnMap: Record<string, string> = {
    title: 'title', tagline: 'tagline', description: 'description',
    restaurantId: 'restaurant_id', coverImage: 'cover_image',
    gallery: 'gallery', startAt: 'start_at',
    durationMinutes: 'duration_minutes', seatsTotal: 'seats_total',
    pricePerSeat: 'price_per_seat', type: 'type', audience: 'audience',
    menuStyle: 'menu_style', included: 'included', tags: 'tags',
    // isFeatured is intentionally absent: only super_admin routes may set it.
    hostNote: 'host_note',
    requiresApproval: 'requires_approval',
  };
  const provided = Object.entries(input).filter(
    ([key, value]) => key in columnMap && value !== undefined,
  );

  if (existing.status !== 'draft' && provided.length > 0) {
    throw new ApiError(400, 'Only drafts can be edited');
  }
  const publishing = input.status === 'published' && existing.status === 'draft';

  if (publishing) {
    const merged = {
      title: input.title ?? existing.title,
      tagline: input.tagline ?? existing.tagline,
      description: input.description ?? existing.description,
      restaurantId: input.restaurantId ?? existing.restaurant_id,
      coverImage: input.coverImage ?? existing.cover_image,
      gallery: input.gallery ?? existing.gallery,
      startAt: input.startAt ?? existing.start_at,
      durationMinutes: input.durationMinutes ?? existing.duration_minutes,
      seatsTotal: input.seatsTotal ?? existing.seats_total,
      pricePerSeat: input.pricePerSeat ?? Number(existing.price_per_seat),
      type: input.type ?? existing.type,
      audience: input.audience ?? existing.audience,
      menuStyle: input.menuStyle ?? existing.menu_style,
      included: input.included ?? existing.included,
      tags: input.tags ?? existing.tags,
      // isFeatured is forced to false because hosts cannot set it; the merged
      // object is only used for validation, not for the UPDATE.
      isFeatured: existing.is_featured,
      hostNote: input.hostNote ?? existing.host_note,
      requiresApproval: input.requiresApproval ?? existing.requires_approval,
      menu: input.menu ?? [],
    };
    try {
      createEventSchema.parse(merged);
    } catch (validationError) {
      const issues = validationError instanceof ZodError
        ? validationError.issues.map((i) => i.path.join('.')).join(', ')
        : 'invalid data';
      throw new ApiError(422, `Draft not ready to publish: ${issues}`);
    }
  }

  if (provided.length > 0 || publishing) {
    const sets: string[] = [];
    const params: unknown[] = [];
    for (const [key, value] of provided) {
      params.push(value);
      sets.push(`${columnMap[key]} = $${params.length}`);
    }
    if (publishing) {
      params.push('confirmed');
      sets.push(`status = $${params.length}`);
    }
    params.push(eventId);
    await query(
      `UPDATE dinner_events SET ${sets.join(', ')} WHERE id = $${params.length}::UUID`,
      params,
    );
  }

  const [full] = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.id = $1::UUID`, [eventId],
  );
  res.json({ event: serialize(full!) });
});

// DELETE /api/events/:id — the host cancels an event. Bookings vanish via
// cascade; every still-active guest gets an activity note about it.
// Financial-history guard: once any payment has been captured (or earnings
// accrued) the delete is refused, because the cascade would silently destroy
// the refund/earnings trail. Those events must stay queryable and each booking
// is refunded individually through POST /bookings/:id/cancel.
router.delete('/:id', requireHostStudio, async (req, res) => {
  const eventId = req.params.id;

  await withTransaction(async (client) => {
    const { rows } = await client.query<{ host_id: string; title: string }>(
      'SELECT host_id, title FROM dinner_events WHERE id = $1 FOR UPDATE',
      [eventId],
    );
    const event = rows[0];
    if (!event) throw notFound('Event');
    if (event.host_id !== req.userId) {
      throw forbidden('Only the host can cancel this event');
    }

    const { rows: money } = await client.query<{ captured: number; accrued: number }>(
      `SELECT
         (SELECT count(*) FROM bookings
           WHERE event_id = $1 AND payment_status = 'paid')::int AS captured,
         (SELECT count(*) FROM payouts
           WHERE event_id = $1 AND seats_sold > 0)::int AS accrued`,
      [eventId],
    );
    if ((money[0]?.captured ?? 0) > 0 || (money[0]?.accrued ?? 0) > 0) {
      throw new ApiError(
        409,
        'This event has captured payments or accrued earnings and must stay '
          + 'on the books. Cancel it by refunding each booking individually '
          + 'instead of deleting it.',
      );
    }

    const { rows: guests } = await client.query<{ user_id: string }>(
      `SELECT DISTINCT user_id FROM bookings
       WHERE event_id = $1 AND status <> 'cancelled'`,
      [eventId],
    );

    for (const guest of guests) {
      await client.query(
        `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
         VALUES ($1, 'reminder', $2, $3, $4, true)`,
        [
          guest.user_id,
          'An event you booked was cancelled',
          `${event.title} was cancelled by the host. Your payment will be refunded.`,
          eventId,
        ],
      );
    }

    await client.query('DELETE FROM dinner_events WHERE id = $1', [eventId]);
  });

  res.json({ deleted: true, eventId });
});

export default router;
