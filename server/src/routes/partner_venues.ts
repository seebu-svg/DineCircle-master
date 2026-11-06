import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, forbidden } from '../context.js';
import {
  isVerifiedVenue,
  requirePartner,
  requireVenueRole,
  scopedRestaurantIds,
  requirePlatformAdmin,
} from '../access.js';
import type { PartnerRole } from '../access.js';
import { list, one, parsePagination } from '../api.js';

const router = Router();

/**
 * The verification queue lives on its own prefix (`/api/partner/verification`)
 * because it is platform-wide rather than venue-scoped. Keeping it in a second
 * router is not cosmetic: `GET /:restaurantId` is registered on `router`, so a
 * `GET /verification/requests` on the same instance would be swallowed by the
 * param route and answer 404 "Restaurant" for the literal id `verification`.
 */
const verificationRouter = Router();

// ── shared serializers ───────────────────────────────────────────────────────

type VenueRow = {
  id: string; owner_id: string | null; name: string; tagline: string; about: string;
  cuisines: string[]; neighborhood: string; address: string; city: string;
  phone: string; email: string; website: string; instagram: string;
  price_range: string; rating: string; review_count: number; seats: number;
  tables_count: number; since: string; owner_name: string; amenities: string[];
  opening_hours: Record<string, unknown>; profile_completion: number;
  accepting_bookings: boolean; dine_circle_plus: boolean; cover_image: string;
  logo: string;
  gallery: string[]; tags: string[]; is_partner: boolean; partnership_status: string;
  partner_perk: string | null; latitude: number | null; longitude: number | null;
  requires_host_approval: boolean; verified_at: Date | null; rejection_note: string;
};

/** Partner-facing venue shape (the Customer App's shape stays in restaurants.ts). */
function serializeVenue(v: VenueRow, role?: PartnerRole) {
  return {
    id: v.id,
    name: v.name,
    tagline: v.tagline,
    about: v.about,
    cuisines: v.cuisines,
    neighborhood: v.neighborhood,
    address: v.address,
    city: v.city,
    phone: v.phone,
    email: v.email,
    website: v.website,
    instagram: v.instagram,
    priceRange: v.price_range,
    rating: Number(v.rating),
    reviewCount: v.review_count,
    seats: v.seats,
    tablesCount: v.tables_count,
    since: v.since,
    ownerName: v.owner_name,
    amenities: v.amenities,
    openingHours: v.opening_hours,
    profileCompletion: v.profile_completion,
    acceptingBookings: v.accepting_bookings,
    dineCirclePlus: v.dine_circle_plus,
    coverImage: v.cover_image,
    logo: v.logo,
    gallery: v.gallery,
    tags: v.tags,
    isPartner: v.is_partner,
    partnershipStatus: v.partnership_status,
    // The single predicate every selling gate uses (`is_partner` *and* an
    // approved review). Exposed so the Partner App never re-derives it wrong.
    verified: v.is_partner && isVerifiedVenue(v.partnership_status),
    verifiedAt: v.verified_at,
    rejectionNote: v.rejection_note,
    partnerPerk: v.partner_perk,
    requiresHostApproval: v.requires_host_approval,
    latitude: v.latitude === null ? null : Number(v.latitude),
    longitude: v.longitude === null ? null : Number(v.longitude),
    ...(role === undefined ? {} : { myRole: role }),
  };
}

const WEEKDAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;

const hoursWindowSchema = z.object({
  open: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Expected HH:MM'),
  close: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, 'Expected HH:MM'),
});

const dayHoursSchema = z.object({
  closed: z.boolean().default(false),
  windows: z.array(hoursWindowSchema).max(4).default([]),
});

/**
 * Validates the weekly opening-hours map. Every day is optional (an absent day
 * means "not configured"), but a present day must carry a well-formed shape so
 * the Customer App never has to defend against garbage it cannot render.
 */
const openingHoursSchema = z.record(z.enum(WEEKDAYS), dayHoursSchema);

/** Weighted completion score over the fields hosts/diners actually look at. */
function profileCompletion(v: VenueRow): number {
  const checks = [
    v.name.trim() !== '',
    v.tagline.trim() !== '',
    v.about.trim().length >= 40,
    v.cuisines.length > 0,
    v.address.trim() !== '',
    v.city.trim() !== '',
    v.phone.trim() !== '',
    v.cover_image.trim() !== '',
    v.gallery.length > 0,
    v.seats > 0,
    Object.keys(v.opening_hours ?? {}).length > 0,
    v.latitude !== null && v.longitude !== null,
  ];
  const met = checks.filter(Boolean).length;
  return Math.round((met / checks.length) * 100);
}

// ── Venue list / registration ────────────────────────────────────────────────

// GET /api/partner/restaurants — venues this account may operate.
//
// Registration stays open to any signed-in account (see POST below), so the
// gate is per-route rather than router-wide: without it a plain diner would get
// `200 { restaurants: [] }` from a partner-only surface.
router.get('/', requirePartner, async (req, res) => {
  const scope = await scopedRestaurantIds(req.userId, req.userRole);
  const params: unknown[] = [];
  const scopeClause =
    scope === 'all' ? 'TRUE' : scope.length === 0 ? 'FALSE' : `r.id = ANY($1::uuid[])`;
  if (scope !== 'all' && scope.length > 0) params.push(scope);

  const rows = await query<VenueRow & { my_role: string | null }>(
    `SELECT r.*,
            CASE WHEN r.owner_id = $${params.length + 1}::UUID THEN 'owner'
                 ELSE s.role END AS my_role
       FROM restaurants r
       LEFT JOIN restaurant_staff s
         ON s.restaurant_id = r.id AND s.user_id = $${params.length + 1}::UUID
        AND s.status = 'active'
      WHERE ${scopeClause}
      ORDER BY r.name ASC`,
    [...params, req.userId],
  );

  res.json({
    data: {
      restaurants: rows.map((r) =>
        serializeVenue(r, (r.my_role ?? 'staff') as PartnerRole),
      ),
    },
    meta: { total: rows.length },
  });
});

const registerVenueSchema = z.object({
  name: z.string().trim().min(2).max(120),
  tagline: z.string().trim().max(160).default(''),
  about: z.string().trim().max(4000).default(''),
  cuisines: z.array(z.string().trim().min(1).max(40)).max(12).default([]),
  city: z.string().trim().min(2).max(80),
  timezone: z.string().trim().min(3).max(60).default('UTC'),
  area: z.string().trim().max(80).default(''),
  address: z.string().trim().max(300).default(''),
  phone: z.string().trim().max(40).default(''),
  email: z.string().trim().email().max(160).or(z.literal('')).default(''),
  website: z.string().trim().max(200).default(''),
  instagram: z.string().trim().max(80).default(''),
  priceRange: z.enum(['$', '$$', '$$$', '$$$$']).default('$$'),
  seats: z.coerce.number().int().min(0).max(5000).default(0),
  tablesCount: z.coerce.number().int().min(0).max(500).default(0),
  amenities: z.array(z.string().trim().max(60)).max(20).default([]),
  coverImage: z.string().trim().max(400).default(''),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
});

/**
 * POST /api/partner/restaurants — self-service venue registration.
 *
 * Creates the venue in `pending_review`, links the caller as its owner, gives
 * it a primary branch (so reservations/menus have a home), and opens a
 * verification request. Nothing is sellable until a platform admin approves:
 * `is_partner` stays false and `partnership_status` is not `verified`, which is
 * exactly what the host publishing gate in events.ts already checks.
 */
router.post('/', async (req, res) => {
  const input = registerVenueSchema.parse(req.body ?? {});

  const created = await withTransaction(async (client) => {
    const { rows: venueRows } = await client.query<VenueRow>(
      `INSERT INTO restaurants
         (owner_id, name, tagline, about, cuisines, neighborhood, address, city,
          phone, email, website, instagram, price_range, seats, tables_count,
          amenities, cover_image, latitude, longitude, is_partner,
          partnership_status, requires_host_approval)
       VALUES ($1::UUID,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,
               $17,$18,$19,false,'pending_review',false)
       RETURNING *`,
      [
        req.userId, input.name, input.tagline, input.about, input.cuisines,
        input.area, input.address, input.city, input.phone, input.email,
        input.website, input.instagram, input.priceRange, input.seats,
        input.tablesCount, input.amenities, input.coverImage,
        input.latitude ?? null, input.longitude ?? null,
      ],
    );
    const venue = venueRows[0];
    if (!venue) throw new ApiError(500, 'Restaurant registration failed');

    // Membership + primary branch + verification request are one unit: a venue
    // without an owner row or a branch would be unreachable from the app.
    await client.query(
      `INSERT INTO restaurant_staff (user_id, restaurant_id, role, status)
       VALUES ($1::UUID, $2::UUID, 'owner', 'active')
       ON CONFLICT (user_id, restaurant_id)
       DO UPDATE SET role = 'owner', status = 'active', updated_at = now()`,
      [req.userId, venue.id],
    );

    await client.query(
      `INSERT INTO restaurant_branches
         (restaurant_id, name, address, area, city, phone, latitude, longitude,
          is_primary, timezone)
       VALUES ($1::UUID,$2,$3,$4,$5,$6,$7,$8,true,$9)`,
      [
        venue.id,
        `${input.name} — Main`,
        input.address,
        input.area,
        input.city,
        input.phone,
        input.latitude ?? null,
        input.longitude ?? null,
        input.timezone,
      ],
    );

    const { rows: verificationRows } = await client.query<{ id: string }>(
      `INSERT INTO partner_verification_requests (restaurant_id, requested_by, note)
       VALUES ($1::UUID, $2::UUID, $3) RETURNING id`,
      [venue.id, req.userId, 'Self-service registration'],
    );

    // A plain diner becomes a restaurant owner. Hosts/influencers keep their
    // existing role so registering a venue never removes publishing rights.
    await client.query(
      `UPDATE users SET role = 'restaurant_owner'
        WHERE id = $1::UUID AND role = 'user'`,
      [req.userId],
    );

    return { venue, verificationId: verificationRows[0]?.id ?? null };
  });

  res.status(201).json({
    data: {
      restaurant: serializeVenue(created.venue, 'owner'),
      verificationRequestId: created.verificationId,
      nextStep: 'A platform admin reviews new venues. Until then the venue is '
        + 'not listed and cannot accept host events or publish deals.',
    },
  });
});

// ── Venue profile ────────────────────────────────────────────────────────────

// GET /api/partner/restaurants/:restaurantId
router.get('/:restaurantId', async (req, res) => {
  const role = await requireVenueRole(req, req.params.restaurantId);
  const [venue] = await query<VenueRow>(
    'SELECT * FROM restaurants WHERE id = $1::UUID',
    [req.params.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');

  const [counts] = await query<{
    branches: number; tables: number; menu_items: number;
    upcoming_events: number; pending_reservations: number;
  }>(
    `SELECT
       (SELECT count(*)::int FROM restaurant_branches WHERE restaurant_id = $1::UUID) AS branches,
       (SELECT count(*)::int FROM restaurant_tables WHERE restaurant_id = $1::UUID AND is_active) AS tables,
       (SELECT count(*)::int FROM restaurant_menu_items WHERE restaurant_id = $1::UUID) AS menu_items,
       (SELECT count(*)::int FROM dinner_events WHERE restaurant_id = $1::UUID
          AND start_at >= now() AND status IN ('confirmed','live')) AS upcoming_events,
       (SELECT count(*)::int FROM table_reservations WHERE restaurant_id = $1::UUID
          AND status = 'pending') AS pending_reservations`,
    [req.params.restaurantId],
  );

  res.json({
    data: { restaurant: serializeVenue(venue, role), counts: counts ?? null },
  });
});

const patchVenueSchema = z.object({
  name: z.string().trim().min(2).max(120).optional(),
  tagline: z.string().trim().max(160).optional(),
  about: z.string().trim().max(4000).optional(),
  cuisines: z.array(z.string().trim().min(1).max(40)).max(12).optional(),
  neighborhood: z.string().trim().max(80).optional(),
  address: z.string().trim().max(300).optional(),
  city: z.string().trim().min(2).max(80).optional(),
  phone: z.string().trim().max(40).optional(),
  email: z.string().trim().email().max(160).or(z.literal('')).optional(),
  website: z.string().trim().max(200).optional(),
  instagram: z.string().trim().max(80).optional(),
  priceRange: z.enum(['$', '$$', '$$$', '$$$$']).optional(),
  seats: z.coerce.number().int().min(0).max(5000).optional(),
  tablesCount: z.coerce.number().int().min(0).max(500).optional(),
  amenities: z.array(z.string().trim().max(60)).max(20).optional(),
  coverImage: z.string().trim().max(400).optional(),
  logo: z.string().trim().max(400).optional(),
  gallery: z.array(z.string().trim().max(400)).max(20).optional(),
  tags: z.array(z.string().trim().max(40)).max(20).optional(),
  partnerPerk: z.string().trim().max(200).nullable().optional(),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  acceptingBookings: z.boolean().optional(),
  requiresHostApproval: z.boolean().optional(),
});

/** Column map keeps the whitelist explicit — no dynamic column names. */
const PATCHABLE: Record<string, string> = {
  name: 'name',
  tagline: 'tagline',
  about: 'about',
  cuisines: 'cuisines',
  neighborhood: 'neighborhood',
  address: 'address',
  city: 'city',
  phone: 'phone',
  email: 'email',
  website: 'website',
  instagram: 'instagram',
  priceRange: 'price_range',
  seats: 'seats',
  tablesCount: 'tables_count',
  amenities: 'amenities',
  coverImage: 'cover_image',
  logo: 'logo',
  gallery: 'gallery',
  tags: 'tags',
  partnerPerk: 'partner_perk',
  latitude: 'latitude',
  longitude: 'longitude',
  acceptingBookings: 'accepting_bookings',
  requiresHostApproval: 'requires_host_approval',
};

// PATCH /api/partner/restaurants/:restaurantId — profile management.
router.patch('/:restaurantId', async (req, res) => {
  const role = await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchVenueSchema.parse(req.body ?? {});

  // Approval policy and payout-critical switches belong to the owner only.
  if (input.requiresHostApproval !== undefined && role !== 'owner') {
    throw forbidden('Only the venue owner can change the host-approval policy');
  }

  const sets: string[] = [];
  const params: unknown[] = [];
  for (const [key, column] of Object.entries(PATCHABLE)) {
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }

  params.push(req.params.restaurantId);
  const [updated] = await query<VenueRow>(
    `UPDATE restaurants SET ${sets.join(', ')}
      WHERE id = $${params.length}::UUID RETURNING *`,
    params,
  );
  if (!updated) throw notFound('Restaurant');

  // Completion is derived, never client-supplied.
  const completion = profileCompletion(updated);
  const [finalRow] = await query<VenueRow>(
    'UPDATE restaurants SET profile_completion = $2 WHERE id = $1::UUID RETURNING *',
    [updated.id, completion],
  );

  res.json({ data: { restaurant: serializeVenue(finalRow ?? updated, role) } });
});

// ── Verification ─────────────────────────────────────────────────────────────

/**
 * GET /api/partner/verification/requests — the queue. super_admin sees every
 * pending request; a partner sees only their own venues' history.
 */
verificationRouter.get('/requests', async (req, res) => {
  const page = parsePagination(req.query as Record<string, unknown>);
  const params: unknown[] = [];
  const conditions: string[] = [];

  if (req.userRole === 'super_admin') {
    if (typeof req.query.status === 'string' && req.query.status !== '') {
      params.push(req.query.status);
      conditions.push(`v.status = $${params.length}`);
    }
  } else {
    const scope = await scopedRestaurantIds(req.userId, req.userRole);
    if (scope === 'all') {
      conditions.push('TRUE');
    } else if (scope.length === 0) {
      conditions.push('FALSE');
    } else {
      params.push(scope);
      conditions.push(`v.restaurant_id = ANY($${params.length}::uuid[])`);
    }
  }

  const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';
  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM partner_verification_requests v ${where}`,
    params,
  );

  params.push(page.limit, page.offset);
  const rows = await query<{
    id: string; restaurant_id: string; restaurant_name: string; status: string;
    note: string; reviewer_note: string; reviewed_at: Date | null; created_at: Date;
  }>(
    `SELECT v.id, v.restaurant_id, r.name AS restaurant_name, v.status, v.note,
            v.reviewer_note, v.reviewed_at, v.created_at
       FROM partner_verification_requests v
       JOIN restaurants r ON r.id = v.restaurant_id
       ${where}
      ORDER BY v.created_at DESC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );

  res.json(
    list(
      'requests',
      rows.map((r) => ({
        id: r.id,
        restaurantId: r.restaurant_id,
        restaurantName: r.restaurant_name,
        status: r.status,
        note: r.note,
        reviewerNote: r.reviewer_note,
        reviewedAt: r.reviewed_at,
        createdAt: r.created_at,
      })),
      page,
      totalRow?.count ?? 0,
    ),
  );
});

// POST /api/partner/restaurants/:restaurantId/verification — (re)submit.
router.post('/:restaurantId/verification', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  const [venue] = await query<{ id: string; partnership_status: string }>(
    'SELECT id, partnership_status FROM restaurants WHERE id = $1::UUID',
    [req.params.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');
  if (venue.partnership_status === 'verified') {
    throw new ApiError(409, 'This venue is already verified');
  }

  const [pending] = await query<{ id: string }>(
    `SELECT id FROM partner_verification_requests
      WHERE restaurant_id = $1::UUID AND status = 'pending' LIMIT 1`,
    [req.params.restaurantId],
  );
  if (pending) {
    res.json({ data: { requestId: pending.id, status: 'pending' } });
    return;
  }

  const note = typeof req.body?.note === 'string' ? req.body.note.slice(0, 1000) : '';
  const [created] = await query<{ id: string }>(
    `INSERT INTO partner_verification_requests (restaurant_id, requested_by, note)
     VALUES ($1::UUID, $2::UUID, $3) RETURNING id`,
    [req.params.restaurantId, req.userId, note],
  );
  await query(
    `UPDATE restaurants SET partnership_status = 'pending_review', rejection_note = ''
      WHERE id = $1::UUID AND partnership_status <> 'verified'`,
    [req.params.restaurantId],
  );

  res.status(201).json({ data: { requestId: created?.id ?? null, status: 'pending' } });
});

const reviewSchema = z.object({
  decision: z.enum(['approved', 'rejected']),
  reviewerNote: z.string().trim().max(1000).default(''),
});

/**
 * POST /api/partner/verification/requests/:requestId/review — platform admin
 * decision. Approval is what flips the venue into `verified` + `is_partner`,
 * the two flags every downstream gate (host publishing, deals, payouts) reads.
 */
verificationRouter.post('/requests/:requestId/review', async (req, res) => {
  requirePlatformAdmin(req);
  const input = reviewSchema.parse(req.body ?? {});

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<{ id: string; restaurant_id: string; status: string }>(
      `SELECT id, restaurant_id, status FROM partner_verification_requests
        WHERE id = $1::UUID FOR UPDATE`,
      [req.params.requestId],
    );
    const request = rows[0];
    if (!request) throw notFound('Verification request');
    if (request.status !== 'pending') {
      throw new ApiError(409, `This request was already ${request.status}`);
    }

    await client.query(
      `UPDATE partner_verification_requests
          SET status = $2, reviewer_note = $3, reviewed_by = $4::UUID,
              reviewed_at = now()
        WHERE id = $1::UUID`,
      [request.id, input.decision, input.reviewerNote, req.userId],
    );

    const approved = input.decision === 'approved';
    const { rows: venues } = await client.query<{ id: string; name: string; owner_id: string | null }>(
      `UPDATE restaurants
          SET partnership_status = $2,
              is_partner = $3,
              verified_at = CASE WHEN $3 THEN now() ELSE verified_at END,
              rejection_note = CASE WHEN $3 THEN '' ELSE $4 END
        WHERE id = $1::UUID
        RETURNING id, name, owner_id`,
      [request.restaurant_id, approved ? 'verified' : 'rejected', approved, input.reviewerNote],
    );

    const venue = venues[0];
    if (venue) {
      // The venue desk is told either way; a rejection that only lands in an
      // admin queue would leave the partner app showing a silent spinner.
      await client.query(
        `INSERT INTO notifications (restaurant_id, title, body, category, read)
         VALUES ($1::UUID, $2, $3, 'verification', false)`,
        [
          venue.id,
          approved ? 'Venue verified' : 'Verification needs work',
          approved
            ? 'Your venue is verified. You can now accept host event requests, publish deals and receive payouts.'
            : `Verification was declined. ${input.reviewerNote}`.trim(),
        ],
      );
    }

    return { requestId: request.id, status: input.decision, restaurantId: request.restaurant_id };
  });

  res.json({ data: result });
});

// ── Staff ────────────────────────────────────────────────────────────────────

// GET /api/partner/restaurants/:restaurantId/staff
router.get('/:restaurantId/staff', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const rows = await query<{
    user_id: string; name: string; email: string | null; phone: string | null;
    role: string; status: string; created_at: Date;
  }>(
    `SELECT s.user_id, u.name, u.email, u.phone, s.role, s.status, s.created_at
       FROM restaurant_staff s
       JOIN users u ON u.id = s.user_id
      WHERE s.restaurant_id = $1::UUID
      ORDER BY CASE s.role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 ELSE 2 END,
               u.name ASC`,
    [req.params.restaurantId],
  );
  res.json({
    data: {
      staff: rows.map((s) => ({
        userId: s.user_id,
        name: s.name,
        email: s.email,
        phone: s.phone,
        role: s.role,
        status: s.status,
        createdAt: s.created_at,
      })),
    },
    meta: { total: rows.length },
  });
});

const inviteStaffSchema = z.object({
  email: z.string().trim().email().max(160).optional(),
  phone: z.string().trim().min(6).max(40).optional(),
  role: z.enum(['manager', 'staff']).default('staff'),
});

/**
 * POST /api/partner/restaurants/:restaurantId/staff — invite an existing
 * account into the venue. Requires an already-registered user: the Partner App
 * cannot mint accounts, which keeps account creation on the single auth path.
 */
router.post('/:restaurantId/staff', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  const input = inviteStaffSchema.parse(req.body ?? {});
  if (!input.email && !input.phone) {
    throw new ApiError(400, 'Provide the email or phone of an existing account');
  }

  const [staffUser] = await query<{ id: string; role: string; name: string }>(
    `SELECT id, role, name FROM users
      WHERE ($1::text IS NOT NULL AND lower(email) = lower($1))
         OR ($2::text IS NOT NULL AND phone = $2)
      LIMIT 1`,
    [input.email ?? null, input.phone ?? null],
  );
  if (!staffUser) {
    throw notFound('Account for that email/phone');
  }

  await query(
    `INSERT INTO restaurant_staff (user_id, restaurant_id, role, status, invited_by)
     VALUES ($1::UUID, $2::UUID, $3, 'invited', $4::UUID)
     ON CONFLICT (user_id, restaurant_id)
     DO UPDATE SET role = EXCLUDED.role, status = 'invited',
                   invited_by = EXCLUDED.invited_by, updated_at = now()`,
    [staffUser.id, req.params.restaurantId, input.role, req.userId],
  );

  // The invitee is promoted only on acceptance (see the accept endpoint), so a
  // mis-typed invite can never silently grant partner-role access.
  await query(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'Staff invite', $2, 'staff', false)`,
    [req.params.restaurantId, `${req.userRole === 'super_admin' ? 'An admin' : 'A venue owner'} invited ${staffUser.name} as ${input.role}.`],
  );

  res.status(201).json({
    data: { userId: staffUser.id, name: staffUser.name, role: input.role, status: 'invited' },
  });
});

// POST /api/partner/restaurants/:restaurantId/staff/accept — invitee accepts.
// Registered on the venue prefix like every other staff action; the invite is
// identified by the caller's own membership row, not by a token in the path.
router.post('/:restaurantId/staff/accept', async (req, res) => {
  // A conditional write prevents an invite revoked concurrently from being
  // reactivated between the old SELECT and UPDATE.
  const [accepted] = await query<{ role: string }>(
    `UPDATE restaurant_staff SET status = 'active', updated_at = now()
      WHERE user_id = $1::UUID AND restaurant_id = $2::UUID AND status = 'invited'
      RETURNING role`,
    [req.userId, req.params.restaurantId],
  );
  if (!accepted) {
    const [membership] = await query<{ status: string }>(
      `SELECT status FROM restaurant_staff
        WHERE user_id = $1::UUID AND restaurant_id = $2::UUID`,
      [req.userId, req.params.restaurantId],
    );
    if (!membership) throw notFound('Invite');
    if (membership.status !== 'active') throw new ApiError(409, 'This invite was revoked');
    res.json({ data: { restaurantId: req.params.restaurantId, status: 'active' } });
    return;
  }
  // Accepting is the moment the account gains venue-scoped access; promote the
  // platform role too so the Partner App's role switch has something to show.
  await query(
    `UPDATE users SET role = 'restaurant_staff'
      WHERE id = $1::UUID AND role = 'user'`,
    [req.userId],
  );

  res.json({
    data: { restaurantId: req.params.restaurantId, role: accepted.role, status: 'active' },
  });
});

const patchStaffSchema = z.object({
  role: z.enum(['manager', 'staff']).optional(),
  status: z.enum(['active', 'revoked']).optional(),
});

// PATCH /api/partner/restaurants/:restaurantId/staff/:userId
router.patch('/:restaurantId/staff/:userId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  const input = patchStaffSchema.parse(req.body ?? {});
  if (req.params.userId === req.userId) {
    throw forbidden('Owners cannot change their own membership');
  }

  const sets: string[] = [];
  const params: unknown[] = [];
  if (input.role !== undefined) {
    params.push(input.role);
    sets.push(`role = $${params.length}`);
  }
  if (input.status !== undefined) {
    params.push(input.status);
    sets.push(`status = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }
  params.push(req.params.restaurantId, req.params.userId);
  const [updated] = await query<{ user_id: string; role: string; status: string }>(
    `UPDATE restaurant_staff SET ${sets.join(', ')}, updated_at = now()
      WHERE restaurant_id = $${params.length - 1}::UUID
        AND user_id = $${params.length}::UUID
        AND role <> 'owner'
      RETURNING user_id, role, status`,
    params,
  );
  if (!updated) throw notFound('Staff member');

  res.json({
    data: { userId: updated.user_id, role: updated.role, status: updated.status },
  });
});

// DELETE /api/partner/restaurants/:restaurantId/staff/:userId — revoke access.
router.delete('/:restaurantId/staff/:userId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  if (req.params.userId === req.userId) {
    throw forbidden('Owners cannot remove their own membership');
  }
  const [revoked] = await query<{ user_id: string }>(
    `UPDATE restaurant_staff SET status = 'revoked', updated_at = now()
      WHERE restaurant_id = $1::UUID AND user_id = $2::UUID AND role <> 'owner'
      RETURNING user_id`,
    [req.params.restaurantId, req.params.userId],
  );
  if (!revoked) throw notFound('Staff member');
  res.json({ data: { userId: revoked.user_id, status: 'revoked' } });
});

// ── Branches ─────────────────────────────────────────────────────────────────

type BranchRow = {
  id: string; restaurant_id: string; name: string; address: string; area: string;
  city: string; phone: string; latitude: number | null; longitude: number | null;
  is_primary: boolean; accepting_reservations: boolean; timezone: string;
  opening_hours: Record<string, unknown>; created_at: Date;
};

function serializeBranch(b: BranchRow) {
  return {
    id: b.id,
    restaurantId: b.restaurant_id,
    name: b.name,
    address: b.address,
    area: b.area,
    city: b.city,
    phone: b.phone,
    latitude: b.latitude === null ? null : Number(b.latitude),
    longitude: b.longitude === null ? null : Number(b.longitude),
    isPrimary: b.is_primary,
    acceptingReservations: b.accepting_reservations,
    timeZone: b.timezone,
    openingHours: b.opening_hours,
    createdAt: b.created_at,
  };
}

// GET /api/partner/restaurants/:restaurantId/branches
router.get('/:restaurantId/branches', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const rows = await query<BranchRow>(
    `SELECT * FROM restaurant_branches
      WHERE restaurant_id = $1::UUID
      ORDER BY is_primary DESC, name ASC`,
    [req.params.restaurantId],
  );
  res.json({
    data: { branches: rows.map(serializeBranch) },
    meta: { total: rows.length },
  });
});

const branchSchema = z.object({
  name: z.string().trim().min(2).max(120),
  address: z.string().trim().max(300).default(''),
  area: z.string().trim().max(80).default(''),
  city: z.string().trim().max(80).default(''),
  phone: z.string().trim().max(40).default(''),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  isPrimary: z.boolean().default(false),
  acceptingReservations: z.boolean().default(true),
  timezone: z.string().trim().min(3).max(60).default('UTC'),
});

// POST /api/partner/restaurants/:restaurantId/branches
router.post('/:restaurantId/branches', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = branchSchema.parse(req.body ?? {});

  const created = await withTransaction(async (client) => {
    // Only one primary branch: demote the incumbent inside the same unit.
    if (input.isPrimary) {
      await client.query(
        'UPDATE restaurant_branches SET is_primary = false WHERE restaurant_id = $1::UUID',
        [req.params.restaurantId],
      );
    }
    const { rows } = await client.query<BranchRow>(
      `INSERT INTO restaurant_branches
         (restaurant_id, name, address, area, city, phone, latitude, longitude,
          is_primary, accepting_reservations, timezone)
       VALUES ($1::UUID,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)
       RETURNING *`,
      [
        req.params.restaurantId, input.name, input.address, input.area,
        input.city, input.phone, input.latitude ?? null, input.longitude ?? null,
        input.isPrimary, input.acceptingReservations, input.timezone,
      ],
    );
    return rows[0]!;
  });

  res.status(201).json({ data: { branch: serializeBranch(created) } });
});

const patchBranchSchema = branchSchema.partial();

// PATCH /api/partner/restaurants/:restaurantId/branches/:branchId
router.patch('/:restaurantId/branches/:branchId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchBranchSchema.parse(req.body ?? {});

  const updated = await withTransaction(async (client) => {
    const { rows: existing } = await client.query<BranchRow>(
      `SELECT * FROM restaurant_branches
        WHERE id = $1::UUID AND restaurant_id = $2::UUID FOR UPDATE`,
      [req.params.branchId, req.params.restaurantId],
    );
    const branch = existing[0];
    if (!branch) throw notFound('Branch');

    if (input.isPrimary === true && !branch.is_primary) {
      await client.query(
        'UPDATE restaurant_branches SET is_primary = false WHERE restaurant_id = $1::UUID',
        [req.params.restaurantId],
      );
    }

    const sets: string[] = [];
    const params: unknown[] = [];
    const map: Record<string, string> = {
      name: 'name', address: 'address', area: 'area', city: 'city', phone: 'phone',
      latitude: 'latitude', longitude: 'longitude', isPrimary: 'is_primary',
      acceptingReservations: 'accepting_reservations',
      timezone: 'timezone',
    };
    for (const [key, column] of Object.entries(map)) {
      const value = (input as Record<string, unknown>)[key];
      if (value === undefined) continue;
      params.push(value);
      sets.push(`${column} = $${params.length}`);
    }
    if (sets.length === 0) return branch;

    params.push(branch.id);
    const { rows } = await client.query<BranchRow>(
      `UPDATE restaurant_branches SET ${sets.join(', ')}, updated_at = now()
        WHERE id = $${params.length}::UUID RETURNING *`,
      params,
    );
    return rows[0] ?? branch;
  });

  res.json({ data: { branch: serializeBranch(updated) } });
});

// DELETE /api/partner/restaurants/:restaurantId/branches/:branchId
router.delete('/:restaurantId/branches/:branchId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  const [existing] = await query<{ id: string; is_primary: boolean }>(
    `SELECT id, is_primary FROM restaurant_branches
      WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
    [req.params.branchId, req.params.restaurantId],
  );
  if (!existing) throw notFound('Branch');
  if (existing.is_primary) {
    throw new ApiError(409, 'Promote another branch before removing the primary one');
  }
  await query('DELETE FROM restaurant_branches WHERE id = $1::UUID', [existing.id]);
  res.json({ data: { id: existing.id, deleted: true } });
});

/**
 * PUT /api/partner/restaurants/:restaurantId/branches/:branchId/hours — the
 * weekly service map. When the branch is primary its hours are mirrored onto
 * `restaurants.opening_hours`, which is the column the Customer App already
 * renders, so both apps show the same schedule with no extra client work.
 */
router.put('/:restaurantId/branches/:branchId/hours', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const hours = openingHoursSchema.parse(req.body ?? {});

  const branch = await withTransaction(async (client) => {
    const { rows } = await client.query<BranchRow>(
      `UPDATE restaurant_branches SET opening_hours = $3::jsonb, updated_at = now()
        WHERE id = $1::UUID AND restaurant_id = $2::UUID RETURNING *`,
      [req.params.branchId, req.params.restaurantId, JSON.stringify(hours)],
    );
    const updated = rows[0];
    if (!updated) throw notFound('Branch');
    if (updated.is_primary) {
      await client.query(
        'UPDATE restaurants SET opening_hours = $2::jsonb WHERE id = $1::UUID',
        [req.params.restaurantId, JSON.stringify(hours)],
      );
    }
    return updated;
  });

  res.json({ data: { branch: serializeBranch(branch) } });
});

// GET /api/partner/restaurants/:restaurantId/branches/:branchId/hours
router.get('/:restaurantId/branches/:branchId/hours', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const [branch] = await query<BranchRow>(
    `SELECT * FROM restaurant_branches
      WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
    [req.params.branchId, req.params.restaurantId],
  );
  if (!branch) throw notFound('Branch');
  res.json({ data: { branchId: branch.id, openingHours: branch.opening_hours } });
});


// ── Subscription ─────────────────────────────────────────────────────────────

/**
 * Server-side plan prices. The client NEVER sends a price — the PATCH handler
 * looks it up here so a tampered request cannot undercharge.
 */
const PLAN_PRICES: Record<string, number> = {
  monthly: 5000,
  yearly: 50000,
};

type SubscriptionRow = {
  id: string;
  restaurant_id: string;
  plan: string | null;
  status: string;
  price_pkr: number;
  period_start: Date | null;
  period_end: Date | null;
  auto_renew: boolean;
  cancelled_at: Date | null;
  created_at: Date;
  updated_at: Date;
};

function serializeSubscription(r: SubscriptionRow) {
  return {
    id: r.id,
    restaurantId: r.restaurant_id,
    plan: r.plan,
    status: r.status,
    pricePkr: r.price_pkr,
    periodStart: r.period_start,
    periodEnd: r.period_end,
    autoRenew: r.auto_renew,
    cancelledAt: r.cancelled_at,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

/** The synthetic row returned when a venue has no subscription record. */
function defaultSubscription(restaurantId: string): SubscriptionRow {
  const now = new Date();
  return {
    id: '',
    restaurant_id: restaurantId,
    plan: null,
    status: 'none',
    price_pkr: 0,
    period_start: null,
    period_end: null,
    auto_renew: false,
    cancelled_at: null,
    created_at: now,
    updated_at: now,
  };
}

// GET /api/partner/restaurants/:restaurantId/subscription
router.get('/:restaurantId/subscription', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const [row] = await query<SubscriptionRow>(
    `SELECT * FROM partner_subscriptions
      WHERE restaurant_id = $1::UUID`,
    [req.params.restaurantId],
  );
  const sub = row ?? defaultSubscription(req.params.restaurantId);
  res.json(one('subscription', serializeSubscription(sub)));
});

const patchSubscriptionSchema = z.object({
  plan: z.enum(['monthly', 'yearly']).optional(),
  autoRenew: z.boolean().optional(),
  // Phase 3b: partners cannot set status themselves — only admin can activate.
});

/**
 * PATCH /api/partner/restaurants/:restaurantId/subscription — owner only.
 *
 * Phase 3b: Partners may change plan and autoRenew, but NOT status.
 * Status transitions are admin-only via POST /api/admin/restaurants/:id/subscription/activate.
 */
router.patch('/:restaurantId/subscription', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'owner');
  const input = patchSubscriptionSchema.parse(req.body ?? {});

  const result = await withTransaction(async (client) => {
    const { rows: existing } = await client.query<SubscriptionRow>(
      `SELECT * FROM partner_subscriptions
        WHERE restaurant_id = $1::UUID FOR UPDATE`,
      [req.params.restaurantId],
    );
    const current = existing[0];

    // Determine new plan/price/period.
    const newPlan = input.plan ?? current?.plan ?? null;
    const planChanged = input.plan !== undefined && input.plan !== (current?.plan ?? null);
    const newPrice = newPlan ? PLAN_PRICES[newPlan] ?? 0 : 0;
    const now = new Date();

    let newPeriodStart: Date | null = current?.period_start ?? null;
    let newPeriodEnd: Date | null = current?.period_end ?? null;
    if (planChanged && newPlan) {
      newPeriodStart = now;
      newPeriodEnd = input.plan === 'yearly'
        ? new Date(now.getFullYear() + 1, now.getMonth(), now.getDate())
        : new Date(now.getFullYear(), now.getMonth() + 1, now.getDate());
    }

    // Phase 3b: status cannot be changed by partners — preserve current.
    const newStatus = current?.status ?? 'none';
    const newAutoRenew = input.autoRenew ?? current?.auto_renew ?? true;

    if (current) {
      const { rows } = await client.query<SubscriptionRow>(
        `UPDATE partner_subscriptions
            SET plan = $2, price_pkr = $3,
                period_start = $4, period_end = $5,
                auto_renew = $6,
                updated_at = now()
          WHERE restaurant_id = $1::UUID
          RETURNING *`,
        [
          req.params.restaurantId, newPlan, newPrice,
          newPeriodStart, newPeriodEnd, newAutoRenew,
        ],
      );
      return rows[0]!;
    }

    const { rows } = await client.query<SubscriptionRow>(
      `INSERT INTO partner_subscriptions
         (restaurant_id, plan, status, price_pkr, period_start, period_end,
          auto_renew)
       VALUES ($1::UUID, $2, 'trialing', $3, $4, $5, $6)
       RETURNING *`,
      [
        req.params.restaurantId, newPlan, newPrice,
        newPeriodStart, newPeriodEnd, newAutoRenew,
      ],
    );
    return rows[0]!;
  });

  res.json(one('subscription', serializeSubscription(result)));
});

// ── Admin subscription activation ───────────────────────────────────────────

/**
 * Admin-only router for subscription activation.
 * Mounted at /api/admin/restaurants in server.ts.
 */
const adminRouter = Router();

const activateSubscriptionSchema = z.object({
  status: z.enum(['active', 'past_due', 'cancelled']),
});

/**
 * POST /api/admin/restaurants/:restaurantId/subscription/activate
 *
 * Admin-only: transition subscription status after verifying payment
 * (bank/JazzCash/Easypaisa receipt). This is the ONLY way to activate.
 */
adminRouter.post('/:restaurantId/subscription/activate', async (req, res) => {
  requirePlatformAdmin(req);
  const input = activateSubscriptionSchema.parse(req.body ?? {});
  const now = new Date();

  const result = await withTransaction(async (client) => {
    const { rows: existing } = await client.query<SubscriptionRow>(
      `SELECT * FROM partner_subscriptions
        WHERE restaurant_id = $1::UUID FOR UPDATE`,
      [req.params.restaurantId],
    );

    if (!existing[0]) {
      throw notFound('Subscription');
    }

    const current = existing[0];
    const newCancelledAt = input.status === 'cancelled' ? now : current.cancelled_at;

    const { rows } = await client.query<SubscriptionRow>(
      `UPDATE partner_subscriptions
          SET status = $2, cancelled_at = $3, updated_at = now()
        WHERE restaurant_id = $1::UUID
        RETURNING *`,
      [req.params.restaurantId, input.status, newCancelledAt],
    );
    return rows[0]!;
  });

  res.json(one('subscription', serializeSubscription(result)));
});


export { verificationRouter, adminRouter };
export default router;
