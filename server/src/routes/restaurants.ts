import { Router } from 'express';
import { query } from '../db.js';
import { notFound } from '../context.js';
import { likeTerm, rankSql } from '../search.js';

const router = Router();

export type RestaurantRow = {
  id: string; name: string; cuisines: string[]; neighborhood: string; address: string;
  rating: string; review_count: number; price_range: string;
  cover_image: string; gallery: string[]; about: string; tags: string[];
  is_partner: boolean; partner_perk: string | null; opening_hours: object;
  amenities: string[];
  seats: number; city: string; partnership_status: string;
  latitude: number | string | null; longitude: number | string | null;
  is_following: boolean;
  distance_km?: string | number | null;
  phone: string; email: string; website: string; instagram: string;
  facebook: string; twitter: string; logo: string;
};

/**
 * One venue payload for every surface that lists restaurants. Exported so the
 * viewer-scoped "saved restaurants" read in `social.ts` returns exactly the
 * same shape the discover/map/search feeds do.
 */
export function serializeRestaurant(r: RestaurantRow) {
  return {
    id: r.id,
    name: r.name,
    cuisines: r.cuisines,
    neighborhood: r.neighborhood,
    address: r.address,
    city: r.city,
    rating: Number(r.rating),
    reviewCount: r.review_count,
    priceRange: r.price_range,
    coverImage: r.cover_image,
    imagePath: r.cover_image, // alias for Flutter client
    gallery: r.gallery,
    about: r.about,
    description: r.about, // alias for Flutter client
    tags: r.tags,
    isPartner: r.is_partner,
    partnershipStatus: r.partnership_status,
    partnerPerk: r.partner_perk,
    openingHours: r.opening_hours,
    amenities: r.amenities,
    seats: r.seats,
    latitude: r.latitude === null || r.latitude === undefined ? null : Number(r.latitude),
    longitude: r.longitude === null || r.longitude === undefined ? null : Number(r.longitude),
    isFollowing: r.is_following === true,
    phoneNumber: r.phone,
    phone: r.phone,
    email: r.email,
    website: r.website,
    instagram: r.instagram,
    facebook: r.facebook,
    twitter: r.twitter,
    logo: r.logo,
    logoPath: r.logo, // alias for Flutter client
    cuisine: r.cuisines.length > 0 ? r.cuisines[0] : '',
    ...(r.distance_km === undefined
      ? {}
      : { distanceKm: r.distance_km === null ? null : Number(r.distance_km) }),
  };
}

// Local alias so the existing handlers keep reading like before.
const serialize = serializeRestaurant;

// GET /api/restaurants, partner venues, filterable (P0-4: live search axes).
router.get('/', async (req, res) => {
  const { partner, q, city, tag, priceMax, limit = '50', offset = '0' } = req.query;
  const conditions: string[] = ['accepting_bookings'];
  const params: unknown[] = [];
  const search = typeof q === 'string' ? q.trim() : '';

  if (partner === 'true') conditions.push('is_partner');
  if (search !== '') {
    params.push(likeTerm(search));
    const i = params.length;
    conditions.push(
      `(name ILIKE $${i} OR neighborhood ILIKE $${i} OR city ILIKE $${i}
        OR EXISTS (SELECT 1 FROM unnest(cuisines) AS t(x) WHERE t.x ILIKE $${i})
        OR EXISTS (SELECT 1 FROM unnest(tags) AS t(x) WHERE t.x ILIKE $${i}))`,
    );
  }
  if (typeof city === 'string' && city.trim() !== '') {
    params.push(likeTerm(city.trim()));
    conditions.push(`city ILIKE $${params.length}`);
  }
  // tag matches the union of the tags and cuisines arrays.
  if (typeof tag === 'string' && tag.trim() !== '') {
    params.push(likeTerm(tag.trim()));
    const i = params.length;
    conditions.push(
      `(EXISTS (SELECT 1 FROM unnest(tags) AS t(x) WHERE t.x ILIKE $${i})
        OR EXISTS (SELECT 1 FROM unnest(cuisines) AS t(x) WHERE t.x ILIKE $${i}))`,
    );
  }
  // priceMax is 1–4 ("$".."$$$$"); the $$ count is the length of price_range.
  const parsedPriceMax = Number(priceMax);
  if (Number.isFinite(parsedPriceMax) && parsedPriceMax >= 1 && parsedPriceMax <= 4) {
    conditions.push(`length(price_range) <= ${Math.floor(parsedPriceMax)}`);
  }

  const where = `WHERE ${conditions.join(' AND ')}`;
  const parsedLimit = Math.min(Number(limit) || 50, 200);
  const parsedOffset = Math.max(Number(offset) || 0, 0);

  // Viewer-scoped follow flag: one extra param after the filter params.
  params.push(req.userId);
  const viewerId = `$${params.length}`;

  // With a query the list is relevance-ordered (exact name, prefix, word
  // prefix, then anything else); without one the shipped partner-first order
  // is untouched. The raw term rides its own parameter list so the count-free
  // main query stays contiguous.
  const mainParams = [...params];
  let orderBy = 'is_partner DESC, rating DESC';
  if (search !== '') {
    mainParams.push(search);
    orderBy = `${rankSql('restaurants', `$${mainParams.length}`)}, is_partner DESC, rating DESC`;
  }
  const limitIndex = mainParams.push(parsedLimit);
  const offsetIndex = mainParams.push(parsedOffset);

  const rows = await query<RestaurantRow & { total_count: string | number }>(
    `SELECT restaurants.*, EXISTS (
       SELECT 1 FROM venue_follows vf
       WHERE vf.restaurant_id = restaurants.id AND vf.user_id = ${viewerId}::UUID
     ) AS is_following, COUNT(*) OVER () AS total_count
     FROM restaurants ${where}
     ORDER BY ${orderBy} LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
    mainParams,
  );
  res.json({
    restaurants: rows.map(serialize),
    count: rows.length,
    total: rows.length === 0 ? 0 : Number(rows[0]?.total_count ?? 0),
    offset: parsedOffset,
  });
});

// GET /api/restaurants/nearby, venues within `radiusKm` of a live GPS fix,
// distance-ordered (WS-A map/location). Equirectangular ball-park on a bbox
// first so the index-friendly comparison happens before the exact km calc.
router.get('/nearby', async (req, res) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ error: 'lat and lng are required numbers' });
  }
  const radiusKm = Math.min(Math.max(Number(req.query.radiusKm) || 25, 1), 100);
  const degLat = radiusKm / 111.32;
  const degLng = radiusKm / (111.32 * Math.max(0.01, Math.cos(lat * Math.PI / 180)));

  const rows = await query<RestaurantRow>(
    `SELECT restaurants.*,
            (6371 * acos(least(1, greatest(-1,
               cos(radians($3::float8)) * cos(radians(latitude))
               * cos(radians(longitude) - radians($4::float8))
               + sin(radians($3::float8)) * sin(radians(latitude))
            )))) AS distance_km
     FROM restaurants
     WHERE accepting_bookings
       AND latitude IS NOT NULL AND longitude IS NOT NULL
       AND latitude BETWEEN $1::float8 - $5::float8 AND $1::float8 + $5::float8
       AND longitude BETWEEN $2::float8 - $6::float8 AND $2::float8 + $6::float8
     ORDER BY distance_km ASC
     LIMIT ${Math.min(Number(req.query.limit) || 50, 100)}`,
    [lat, lng, lat, lng, degLat, degLng],
  );
  res.json({
    restaurants: rows.map(serialize),
    count: rows.length,
    radiusKm,
  });
});

// GET /api/restaurants/:id, venue profile plus upcoming events.
router.get('/:id', async (req, res) => {
  const [venue] = await query<RestaurantRow>(
    `SELECT restaurants.*, EXISTS (
       SELECT 1 FROM venue_follows vf
       WHERE vf.restaurant_id = restaurants.id AND vf.user_id = $2::UUID
     ) AS is_following
     FROM restaurants WHERE id = $1::UUID`,
    [req.params.id, req.userId],
  );
  if (!venue) throw notFound('Restaurant');

  const events = await query<{
    id: string; title: string; tagline: string; start_at: Date;
    seats_total: number; seats_booked: number; price_per_seat: string;
    type: string; cover_image: string; host_name: string | null;
  }>(
    `SELECT e.id, e.title, e.tagline, e.start_at, e.seats_total, e.seats_booked,
            e.price_per_seat, e.type, e.cover_image, u.name AS host_name
     FROM dinner_events e LEFT JOIN users u ON u.id = e.host_id
     WHERE e.restaurant_id = $1 AND e.start_at >= now()
     ORDER BY e.start_at ASC`,
    [req.params.id],
  );

  res.json({
    restaurant: serialize(venue),
    upcomingEvents: events.map((e) => ({
      id: e.id,
      title: e.title,
      tagline: e.tagline,
      startAt: e.start_at,
      seatsTotal: e.seats_total,
      seatsBooked: e.seats_booked,
      seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
      pricePerSeat: Number(e.price_per_seat),
      type: e.type,
      coverImage: e.cover_image,
      hostName: e.host_name,
    })),
  });
});

// POST /api/restaurants/:id/follow, the viewer follows the venue (idempotent).
router.post('/:id/follow', async (req, res) => {
  const [venue] = await query<{ id: string }>(
    'SELECT id FROM restaurants WHERE id = $1::UUID', [req.params.id],
  );
  if (!venue) throw notFound('Restaurant');
  await query(
    `INSERT INTO venue_follows (user_id, restaurant_id)
     VALUES ($1::UUID, $2::UUID) ON CONFLICT DO NOTHING`,
    [req.userId, req.params.id],
  );
  res.json({ ok: true, isFollowing: true });
});

// DELETE /api/restaurants/:id/follow, the viewer unfollows the venue.
router.delete('/:id/follow', async (req, res) => {
  const [venue] = await query<{ id: string }>(
    'SELECT id FROM restaurants WHERE id = $1::UUID', [req.params.id],
  );
  if (!venue) throw notFound('Restaurant');
  await query(
    `DELETE FROM venue_follows
     WHERE user_id = $1::UUID AND restaurant_id = $2::UUID`,
    [req.userId, req.params.id],
  );
  res.json({ ok: true, isFollowing: false });
});

export default router;
