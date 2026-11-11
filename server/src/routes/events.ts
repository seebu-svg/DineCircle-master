import { Router } from 'express';
import type pg from 'pg';
import { z, ZodError } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, forbidden, hasHostCapabilities, requireHostStudio } from '../context.js';
import { notBlockedBetween } from '../blocks.js';
import { notifyVenue } from '../notify.js';
import { assertNoCapturedMoney, softCancel } from '../event_lifecycle.js';

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
  decline_reason: string | null;
  restaurant_approved_at: Date | null;
  approval_stale_at: Date | null;
  cancelled_at: Date | null;
  cancellation_reason: string | null;
  updated_at: Date | null;
  created_at: Date;
  host_name: string | null;
  host_handle: string | null;
  host_avatar: string | null;
  host_role: string | null;
  host_badges: string[] | null;
  // Host food preferences (P1-5), surfaced so the event's dietary card can
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
    // Approval + cancellation trail. The host app renders "Pending venue
    // approval", "Declined by venue: <reason>" and "Cancelled" straight off
    // these fields; before they existed the client showed "Published" for an
    // experience the venue had never seen.
    declineReason: row.decline_reason ?? '',
    restaurantApprovedAt: row.restaurant_approved_at,
    requiresApproval: row.requires_approval,
    approvalStaleAt: row.approval_stale_at,
    cancelledAt: row.cancelled_at,
    cancellationReason: row.cancellation_reason ?? '',
    updatedAt: row.updated_at ?? null,
    createdAt: row.created_at,
  };
}

// Local alias so the existing handlers keep reading like before.
const serialize = serializeEvent;

/** The venue fields that decide whether a new experience needs sign-off. */
export type VenueApprovalPolicy = {
  owner_id: string | null;
  requires_host_approval: boolean;
};

/**
 * The single place that decides where a published experience lands.
 *
 * A venue that opted into host approvals reserves the right to see a request
 * first: a host's published event lands in `requested` (invisible to diners)
 * until the Partner App approves or declines it. The venue operating its own
 * event, and every venue with the default policy, keep publishing directly.
 *
 * `POST /` and the publishing branch of `PATCH /:id` used to compute this
 * separately and PATCH hard-coded `'confirmed'`, which let a host publish a
 * draft straight past the approval queue. Both paths call this now.
 */
export function resolveInitialStatus(
  venue: VenueApprovalPolicy,
  callerId: string,
  isDraft: boolean,
): 'draft' | 'requested' | 'confirmed' {
  if (isDraft) return 'draft';
  return venue.requires_host_approval && venue.owner_id !== callerId
    ? 'requested'
    : 'confirmed';
}

/**
 * Whether a content change by `callerId` has to be re-approved by the venue.
 * The venue publishing its own experience never re-approves itself.
 */
export function venueMustReapprove(
  venue: VenueApprovalPolicy,
  callerId: string,
): boolean {
  return venue.requires_host_approval && venue.owner_id !== callerId;
}

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

// GET /api/events, filterable feed of events the viewer may see.
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
  // Drafts and venue-pending events are visible only to their host, and a
  // cancelled experience leaves the public feed entirely instead of lingering
  // as a bookable ghost.
  conditions.push(
    "(e.status NOT IN ('draft','requested','declined','cancelled') OR e.host_id = $2)",
  );
  // P2-1: events hosted by anyone in a blocked pair with the viewer leave the
  // personalized feed/search, in both directions (the blocked host stops
  // seeing the blocker's tables too). Existing tickets are unaffected; the
  // bookings surfaces read them straight from `bookings`.
  conditions.push(notBlockedBetween('$2', 'e.host_id'));
  // Platform moderation: an experience an admin removed leaves the public feed
  // as well. `flagged` deliberately still shows, because flagging means "an
  // operator should look", not "guests may not see it".
  conditions.push(`e.moderation_status <> 'removed'`);

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

// GET /api/events/mine, the host's own events, drafts included, newest first.
// Registered before `/:id` so the literal path wins.
router.get('/mine', async (req, res) => {
  const rows = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.host_id = $1::UUID ORDER BY e.created_at DESC LIMIT 200`,
    [req.userId],
  );
  res.json({ events: rows.map(serialize), count: rows.length });
});

// GET /api/events/:id, one visible event with menu, host and venue.
// Venue staff may read *any* status: the approval queue and the Direction-B
// invitation both need to show the host's draft in full, and it used to 404.
router.get('/:id', async (req, res) => {
  const [event] = await query<EventRow>(
    `${EVENT_SELECT}
     WHERE e.id = $1::UUID
       AND (e.status NOT IN ('draft','requested','declined') OR e.host_id = $3
            OR EXISTS (
              SELECT 1 FROM restaurant_staff rs
               WHERE rs.restaurant_id = e.restaurant_id AND rs.user_id = $3::UUID
                 AND rs.status = 'active')
            OR EXISTS (
              SELECT 1 FROM restaurants r2
               WHERE r2.id = e.restaurant_id AND r2.owner_id = $3::UUID))
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
  if (req.userId !== event.host_id && event.status === 'confirmed') {
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
  // isFeatured is a platform-admin flag, hosts cannot set it. The column
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

// POST /api/events, publish a new event (hosts and partner admins only).
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
  // Force hostId to the caller, prevent impersonation
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
  // first; the shared resolver keeps this identical to the PATCH publish path.
  const initialStatus = resolveInitialStatus(venue, req.userId, isDraft);
  const needsVenueApproval = initialStatus === 'requested';

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
  // nobody is told about is how host requests rot for a week. `notifyVenue`
  // reaches every active staff account, not just the seed `owner_id`.
  if (needsVenueApproval) {
    await notifyVenue(null, input.restaurantId, {
      kind: 'approval',
      title: 'New host event request',
      body: `${input.title} (${input.seatsTotal} seats) was requested by a host for `
        + `${new Date(input.startAt ?? Date.now()).toISOString()}.`,
      eventId: created.id,
    });
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
  // Only the two publishing transitions are addressable through PATCH. A raw
  // `status` write was exactly how the venue's approval queue got bypassed, so
  // every other status lives behind an explicit transition endpoint.
  status: z.enum(['published', 'cancelled']).optional(),
  cancellationReason: z.string().trim().max(500).optional(),
});

/** Statuses whose content a host may still change. */
const EDITABLE_STATUSES = new Set(['draft', 'requested', 'declined', 'confirmed']);

/**
 * Publishing is refused while the venue's Direction-B proposal for this
 * experience is unanswered: the host has to accept the collaboration before the
 * partner's draft may go public on their behalf.
 */
async function assertDirectionBAccepted(eventId: string): Promise<void> {
  const [open] = await query<{ id: string; status: string }>(
    `SELECT id, status FROM collaboration_invites
      WHERE experience_id = $1::UUID AND proposed_by = 'restaurant'
        AND status <> 'accepted'
      LIMIT 1`,
    [eventId],
  );
  if (open) {
    throw new ApiError(
      409,
      `This experience was proposed by the venue and the proposal is still `
        + `${open.status}. Accept the collaboration before publishing.`,
    );
  }
}

/**
 * PATCH /api/events/:id, the host edits their own experience, publishes a
 * draft, or cancels.
 *
 * Two rules make this handler safe:
 *   1. `status` may only be `published` or `cancelled`. Everything else is a
 *      venue or ops decision and has an explicit endpoint.
 *   2. Publishing goes through `resolveInitialStatus`, the same function POST
 *      uses, so a draft published at an approval-required venue lands in
 *      `requested` instead of jumping straight to `confirmed`.
 *
 * A content edit made after the venue has decided reopens the request
 * (`requested` + `approval_stale_at`) and re-notifies the venue; there is no
 * silent edit of an already-approved experience.
 */
router.patch('/:id', requireHostStudio, async (req, res) => {
  const eventId = String(req.params.id);
  const rawStatus = (req.body as { status?: unknown } | undefined)?.status;
  if (rawStatus !== undefined && !['published', 'cancelled'].includes(String(rawStatus))) {
    throw new ApiError(400, "status may only be 'published' or 'cancelled'");
  }

  const [existing] = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.id = $1::UUID`, [eventId],
  );
  if (!existing) throw notFound('Event');
  if (existing.host_id !== req.userId) {
    throw forbidden('Only the host can edit this event');
  }

  const input = patchEventSchema.parse(req.body ?? {});

  // Cancel shares the DELETE implementation so both entry points leave the
  // same audit trail (and the same guest notifications).
  if (input.status === 'cancelled') {
    if (existing.status === 'cancelled') {
      throw new ApiError(409, 'This event is already cancelled');
    }
    await withTransaction(async (client) => {
      const { rows } = await client.query<{ id: string }>(
        'SELECT id FROM dinner_events WHERE id = $1 FOR UPDATE', [eventId],
      );
      if (!rows[0]) throw notFound('Event');
      await assertNoCapturedMoney(client, eventId);
      await softCancel(
        client, { id: eventId, title: existing.title },
        req.userId, input.cancellationReason ?? '',
      );
    });
    const [cancelled] = await query<EventRow>(
      `${EVENT_SELECT} WHERE e.id = $1::UUID`, [eventId],
    );
    res.json({ event: serialize(cancelled!), cancelled: true });
    return;
  }

  if (!EDITABLE_STATUSES.has(existing.status)) {
    throw new ApiError(400, `A ${existing.status} experience can no longer be edited`);
  }

  const targetRestaurantId = input.restaurantId ?? existing.restaurant_id;
  const [venue] = await query<{
    owner_id: string | null; requires_host_approval: boolean; name: string;
  }>(
    `SELECT owner_id, requires_host_approval, name
       FROM restaurants WHERE id = $1::UUID`,
    [targetRestaurantId],
  );
  if (!venue) throw new ApiError(422, `Unknown restaurant ${targetRestaurantId}`);
  const policy: VenueApprovalPolicy = {
    owner_id: venue.owner_id,
    requires_host_approval: venue.requires_host_approval,
  };
  const reapprove = venueMustReapprove(policy, req.userId);

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

  const publishing = input.status === 'published';
  if (publishing && existing.status !== 'draft' && existing.status !== 'declined') {
    throw new ApiError(400, `A ${existing.status} experience is already published`);
  }
  if (!publishing && provided.length === 0) {
    throw new ApiError(400, 'Nothing to update');
  }

  let nextStatus = existing.status;
  let staleApproval = false;

  if (publishing) {
    // Publishing re-validates the merged row against the full create schema.
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

    await assertDirectionBAccepted(eventId);
    nextStatus = resolveInitialStatus(policy, req.userId, false);
    // Re-publishing a declined experience is a change to a decided request.
    staleApproval = nextStatus === 'requested' && existing.status === 'declined';
  } else if (reapprove && existing.status !== 'draft') {
    // A decided experience changed: send it back for sign-off.
    nextStatus = 'requested';
    staleApproval = true;
  }

  await withTransaction(async (client) => {
    const sets: string[] = [];
    const params: unknown[] = [];
    for (const [key, value] of provided) {
      params.push(value);
      sets.push(`${columnMap[key]} = $${params.length}`);
    }

    if (publishing || nextStatus !== existing.status) {
      params.push(nextStatus);
      sets.push(`status = $${params.length}`);
    }
    if (publishing) {
      params.push(staleApproval ? new Date() : null);
      sets.push(`approval_stale_at = $${params.length}`);
      // A fresh submission clears the previous decline explanation.
      sets.push(`decline_reason = ''`);
    } else if (staleApproval) {
      params.push(new Date());
      sets.push(`approval_stale_at = $${params.length}`);
      sets.push(`decline_reason = ''`);
    }
    sets.push('updated_at = now()');

    params.push(eventId);
    await client.query(
      `UPDATE dinner_events SET ${sets.join(', ')} WHERE id = $${params.length}::UUID`,
      params,
    );

    // One notification per publish request, and one per re-approval request.
    if (nextStatus === 'requested' && (publishing || staleApproval)) {
      await notifyVenue(client, targetRestaurantId, {
        kind: 'approval',
        title: staleApproval
          ? 'Experience changed and needs re-approval'
          : 'New experience awaiting approval',
        body: staleApproval
          ? `${input.title ?? existing.title} was edited after your decision and is `
            + 'waiting for approval again.'
          : `${input.title ?? existing.title} is waiting for your approval.`,
        eventId,
      });
    }
  });

  const [full] = await query<EventRow>(
    `${EVENT_SELECT} WHERE e.id = $1::UUID`, [eventId],
  );
  res.json({ event: serialize(full!) });
});

// DELETE /api/events/:id, the host cancels an event.
//
// This is a soft cancel: the row survives so guests, payouts and the proposal
// that produced it still resolve, but it leaves the feed, search and the
// booking surface. Old clients keep working because they only check that the
// call succeeded.
router.delete('/:id', requireHostStudio, async (req, res) => {
  const eventId = String(req.params.id);
  const reason = typeof (req.body as { reason?: unknown } | undefined)?.reason === 'string'
    ? String((req.body as { reason?: unknown }).reason).trim().slice(0, 500)
    : '';

  await withTransaction(async (client) => {
    const { rows } = await client.query<{
      host_id: string; title: string; status: string;
    }>(
      'SELECT host_id, title, status FROM dinner_events WHERE id = $1 FOR UPDATE',
      [eventId],
    );
    const event = rows[0];
    if (!event) throw notFound('Event');
    if (event.host_id !== req.userId) {
      throw forbidden('Only the host can cancel this event');
    }
    if (event.status === 'cancelled') {
      throw new ApiError(409, 'This event is already cancelled');
    }

    await assertNoCapturedMoney(client, eventId);
    await softCancel(client, { id: eventId, title: event.title }, req.userId, reason);
  });

  res.json({ cancelled: true, eventId });
});

export default router;
