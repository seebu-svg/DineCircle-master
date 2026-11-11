import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import {
  restoreVenue,
  setVenueBookings,
  suspendVenue,
} from '../../moderation.js';
import {
  adminPage,
  noteSchema,
  pushSearch,
  renderList,
  searchTerm,
} from './_shared.js';

/**
 * Restaurant Management.
 *
 * "Verified" is not its own column: approval sets `partnership_status`,
 * `is_partner` and `verified_at` together (see `verification_review.ts`), so
 * this module reads those and only owns the moderation half, `suspended`, which
 * is a new column pair on the venue row.
 *
 * Suspension drives `accepting_bookings=false` as well as `moderation_status`,
 * because discovery already filters on that boolean. That is deliberate: it
 * keeps the shipped Customer App untouched.
 */
const router = Router();

const VENUE_SELECT = `
  r.id, r.name, r.tagline, r.city, r.neighborhood, r.address, r.cuisines,
  r.price_range, r.rating, r.review_count, r.seats, r.tables_count,
  r.is_partner, r.partnership_status, r.accepting_bookings, r.verified_at,
  r.moderation_status, r.moderation_note, r.moderated_at, r.profile_completion,
  r.cover_image, r.created_at,
  o.id AS owner_id, o.name AS owner_name, o.email AS owner_email,
  o.phone AS owner_phone, o.suspended_at AS owner_suspended_at,
  s.status AS subscription_status, s.plan AS subscription_plan,
  s.period_end AS subscription_period_end`;

const VENUE_FROM = `
  FROM restaurants r
  LEFT JOIN users o ON o.id = r.owner_id
  LEFT JOIN partner_subscriptions s ON s.restaurant_id = r.id`;

function shape(row: Record<string, unknown>) {
  const suspended = row.moderation_status === 'suspended';
  return {
    id: row.id,
    name: row.name,
    tagline: row.tagline,
    city: row.city,
    area: row.neighborhood,
    address: row.address,
    cuisines: row.cuisines,
    priceRange: row.price_range,
    rating: Number(row.rating ?? 0),
    reviewCount: row.review_count,
    seats: row.seats,
    tables: row.tables_count,
    isPartner: row.is_partner,
    partnershipStatus: row.partnership_status,
    // The console's single venue status: a suspended venue reads as suspended
    // whatever its partnership state is, because that is the operationally
    // interesting truth.
    status: suspended ? 'suspended' : String(row.partnership_status ?? 'unverified'),
    moderationStatus: row.moderation_status,
    moderationNote: row.moderation_note,
    moderatedAt: row.moderated_at,
    acceptingBookings: row.accepting_bookings,
    verifiedAt: row.verified_at,
    profileCompletion: row.profile_completion,
    coverImage: row.cover_image,
    createdAt: row.created_at,
    ownerId: row.owner_id,
    ownerName: row.owner_name,
    ownerEmail: row.owner_email,
    ownerPhone: row.owner_phone,
    ownerSuspended: row.owner_suspended_at !== null,
    subscriptionStatus: row.subscription_status ?? 'none',
    subscriptionPlan: row.subscription_plan,
    subscriptionPeriodEnd: row.subscription_period_end,
  };
}

const createSchema = z.object({
  name: z.string().trim().min(2).max(120),
  city: z.string().trim().max(60).default('Karachi'),
  neighborhood: z.string().trim().max(80).default(''),
  address: z.string().trim().max(200).default(''),
  phone: z.string().trim().max(40).default(''),
  email: z.string().trim().email().max(160).or(z.literal('')).default(''),
  cuisines: z.array(z.string().trim().min(1).max(40)).max(12).default([]),
  priceRange: z.enum(['$', '$$', '$$$', '$$$$']).default('$$'),
  seats: z.number().int().min(0).max(2000).default(0),
  ownerId: z.string().uuid().optional(),
  tagline: z.string().trim().max(160).default(''),
});

const patchSchema = createSchema.partial().extend({
  acceptingBookings: z.boolean().optional(),
});

const suspendSchema = z.object({ note: noteSchema });
const bookingsSchema = z.object({ value: z.boolean() });

/**
 * GET /api/admin/venues?page&limit&status&q&city
 * `status` accepts `suspended` as a moderation state and everything else as a
 * partnership state, which is how the console's filter dropdown reads.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status !== '' && status !== 'all') {
    if (status === 'suspended') {
      where.push(`r.moderation_status = 'suspended'`);
    } else if (status === 'active') {
      where.push(`r.moderation_status = 'active'`);
    } else {
      params.push(status);
      where.push(`r.partnership_status = $${params.length}`);
    }
  }

  const city = String(req.query.city ?? '').trim();
  if (city !== '' && city !== 'all') {
    params.push(city);
    where.push(`r.city ILIKE $${params.length}`);
  }

  pushSearch(where, params, searchTerm(req), [
    'r.name',
    'r.neighborhood',
    'r.city',
    'o.name',
  ]);

  await renderList(res, 'venues', {
    select: VENUE_SELECT,
    from: VENUE_FROM,
    where,
    params,
    order: 'r.name ASC',
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/venues/:restaurantId, venue plus the desk's recent history.
router.get('/:restaurantId', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${VENUE_SELECT}, r.about, r.website, r.instagram, r.rejection_note,
            r.gallery, r.tags, r.amenities, r.opening_hours, r.since, r.owner_name
       ${VENUE_FROM}
      WHERE r.id = $1::UUID`,
    [req.params.restaurantId],
  );
  if (!row) throw notFound('Restaurant');

  const [staff, applications, deals, stats] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT s.user_id, u.name, u.email, u.phone, s.role, s.status, s.updated_at
         FROM restaurant_staff s JOIN users u ON u.id = s.user_id
        WHERE s.restaurant_id = $1::UUID
        ORDER BY CASE s.role WHEN 'owner' THEN 0 WHEN 'manager' THEN 1 ELSE 2 END, u.name`,
      [req.params.restaurantId],
    ),
    query<Record<string, unknown>>(
      `SELECT v.id, v.status, v.note, v.reviewer_note, v.created_at, v.reviewed_at,
              rv.name AS reviewer_name
         FROM partner_verification_requests v
         LEFT JOIN users rv ON rv.id = v.reviewed_by
        WHERE v.restaurant_id = $1::UUID ORDER BY v.created_at DESC`,
      [req.params.restaurantId],
    ),
    query<Record<string, unknown>>(
      `SELECT id, title, kind, value, status, moderation_status, ends_at
         FROM restaurant_deals WHERE restaurant_id = $1::UUID
        ORDER BY created_at DESC LIMIT 20`,
      [req.params.restaurantId],
    ),
    query<Record<string, number>>(
      `SELECT
         (SELECT count(*)::int FROM table_reservations
           WHERE restaurant_id = $1::UUID) AS reservations,
         (SELECT count(*)::int FROM dinner_events
           WHERE restaurant_id = $1::UUID AND status <> 'cancelled') AS experiences,
         (SELECT count(*)::int FROM reviews
           WHERE restaurant_id = $1::UUID) AS reviews,
         (SELECT count(*)::int FROM qr_scans
           WHERE restaurant_id = $1::UUID) AS qrScans,
         (SELECT count(*)::int FROM reports rp
           WHERE rp.target_type = 'user' AND rp.status IN ('pending','reviewing')
             AND rp.target_id = (SELECT owner_id FROM restaurants WHERE id = $1::UUID))
       AS openReports`,
      [req.params.restaurantId],
    ),
  ]);

  res.json(
    one('venue', {
      ...shape(row),
      about: row.about,
      website: row.website,
      instagram: row.instagram,
      rejectionNote: row.rejection_note,
      gallery: row.gallery,
      tags: row.tags,
      amenities: row.amenities,
      openingHours: row.opening_hours,
      since: row.since,
      staff: staff.map((s) => ({
        userId: s.user_id,
        name: s.name,
        email: s.email,
        phone: s.phone,
        role: s.role,
        status: s.status,
        updatedAt: s.updated_at,
      })),
      decisions: applications.map((a) => ({
        id: a.id,
        status: a.status,
        note: a.note,
        reviewerNote: a.reviewer_note,
        createdAt: a.created_at,
        reviewedAt: a.reviewed_at,
        reviewer: a.reviewer_name,
      })),
      deals: deals.map((d) => ({
        id: d.id,
        title: d.title,
        kind: d.kind,
        value: Number(d.value),
        status: d.status,
        moderationStatus: d.moderation_status,
        endsAt: d.ends_at,
      })),
      stats: stats[0] ?? {},
    }),
  );
});

/**
 * POST /api/admin/venues, an admin-created venue. It enters the queue at
 * `pending_review` rather than verified, so the same review path that partners
 * go through still decides who is a partner.
 */
router.post('/', async (req, res) => {
  requireAdminConsole(req);
  const input = createSchema.parse(req.body ?? {});

  const [owner] = input.ownerId
    ? await query<{ id: string; name: string }>(
        'SELECT id, name FROM users WHERE id = $1::UUID',
        [input.ownerId],
      )
    : [undefined];
  if (input.ownerId && !owner) throw notFound('Owner account');

  const [created] = await query<Record<string, unknown>>(
    `INSERT INTO restaurants (owner_id, name, tagline, city, neighborhood, address,
                              phone, email, cuisines, price_range, seats,
                              partnership_status, owner_name)
     VALUES ($1::UUID, $2, $3, $4, $5, $6, $7, $8, $9::text[], $10, $11,
             'pending_review', $12)
     RETURNING id`,
    [
      owner?.id ?? req.userId,
      input.name,
      input.tagline,
      input.city,
      input.neighborhood,
      input.address,
      input.phone,
      input.email,
      input.cuisines,
      input.priceRange,
      input.seats,
      owner?.name ?? '',
    ],
  );
  if (!created) throw new ApiError(500, 'Could not create the venue');

  const [venue] = await query<Record<string, unknown>>(
    `SELECT ${VENUE_SELECT} ${VENUE_FROM} WHERE r.id = $1::UUID`,
    [created.id],
  );
  if (!venue) throw notFound('Restaurant');
  res.status(201).json(one('venue', shape(venue)));
});

// PATCH /api/admin/venues/:restaurantId, the corrections an admin may make.
router.patch('/:restaurantId', async (req, res) => {
  requireAdminConsole(req);
  const input = patchSchema.parse(req.body ?? {});

  const columnFor: Record<string, string> = {
    name: 'name',
    tagline: 'tagline',
    city: 'city',
    neighborhood: 'neighborhood',
    address: 'address',
    phone: 'phone',
    email: 'email',
    priceRange: 'price_range',
    seats: 'seats',
    acceptingBookings: 'accepting_bookings',
  };

  const sets: string[] = [];
  const params: unknown[] = [];
  for (const [key, column] of Object.entries(columnFor)) {
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (input.cuisines !== undefined) {
    params.push(input.cuisines);
    sets.push(`cuisines = $${params.length}::text[]`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }

  params.push(req.params.restaurantId);
  const [updated] = await query<{ id: string }>(
    `UPDATE restaurants SET ${sets.join(', ')} WHERE id = $${params.length}::UUID RETURNING id`,
    params,
  );
  if (!updated) throw notFound('Restaurant');

  const [venue] = await query<Record<string, unknown>>(
    `SELECT ${VENUE_SELECT} ${VENUE_FROM} WHERE r.id = $1::UUID`,
    [updated.id],
  );
  if (!venue) throw notFound('Restaurant');
  res.json(one('venue', shape(venue)));
});

/**
 * POST /api/admin/venues/:restaurantId/verify
 * Direct verification, for the case where the paperwork is already settled
 * offline and no application row exists. It writes the same three flags an
 * approval does, so downstream gates behave identically.
 */
router.post('/:restaurantId/verify', async (req, res) => {
  requireAdminConsole(req);
  const [venue] = await query<Record<string, unknown>>(
    `UPDATE restaurants
        SET partnership_status = 'verified', is_partner = true,
            verified_at = COALESCE(verified_at, now()), rejection_note = ''
      WHERE id = $1::UUID
      RETURNING id, name`,
    [req.params.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');

  await query(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'Venue verified', $2, 'verification', false)`,
    [
      venue.id,
      'Your venue is verified. You can now accept host event requests, publish deals and receive payouts.',
    ],
  );

  // Any open application for this venue is now answered.
  await query(
    `UPDATE partner_verification_requests
        SET status = 'approved', reviewer_note = 'Verified directly by the platform team.',
            reviewed_by = $2::UUID, reviewed_at = now()
      WHERE restaurant_id = $1::UUID AND status = 'pending'`,
    [venue.id, req.userId],
  );

  res.json(one('venue', { id: venue.id, name: venue.name, partnershipStatus: 'verified' }));
});

// POST /api/admin/venues/:restaurantId/suspend
router.post('/:restaurantId/suspend', async (req, res) => {
  requireAdminConsole(req);
  const input = suspendSchema.parse(req.body ?? {});
  const result = await suspendVenue({
    restaurantId: req.params.restaurantId,
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('venue', result));
});

// POST /api/admin/venues/:restaurantId/restore
router.post('/:restaurantId/restore', async (req, res) => {
  requireAdminConsole(req);
  const input = suspendSchema.parse(req.body ?? {});
  const result = await restoreVenue({
    restaurantId: req.params.restaurantId,
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('venue', result));
});

// POST /api/admin/venues/:restaurantId/accepting-bookings
router.post('/:restaurantId/accepting-bookings', async (req, res) => {
  requireAdminConsole(req);
  const input = bookingsSchema.parse(req.body ?? {});
  const result = await setVenueBookings({
    restaurantId: req.params.restaurantId,
    value: input.value,
  });
  res.json(one('venue', result));
});

export default router;
