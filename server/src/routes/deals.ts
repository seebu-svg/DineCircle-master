import { Router } from 'express';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { parsePagination } from '../api.js';
import { likeTerm, rankSql } from '../search.js';

const router = Router();

// Venue-scoped deals get their own router. Mounting the feed router on
// `/api/restaurants` as well would shadow the diner venue list, because its
// `GET /` handler answers any request to that prefix.
const venueRouter = Router();

/**
 * Public deals surface, intentionally unauthenticated.
 *
 * Diners browse active deals from partner restaurants. The payload is the same
 * data the partner dashboard edits (active deals, not expired), minus any
 * internal fields like max_redemptions or redemptions count.
 */

export type DealRow = {
  id: string;
  restaurant_id: string;
  restaurant_name: string;
  title: string;
  description: string;
  terms: string;
  kind: string;
  value: string;
  code: string | null;
  starts_at: Date;
  ends_at: Date;
  max_redemptions: number | null;
  redemptions: number;
  status: string;
  city: string | null;
  cover_image: string | null;
};

export function serializeDeal(d: DealRow) {
  return {
    id: d.id,
    restaurantId: d.restaurant_id,
    restaurantName: d.restaurant_name,
    title: d.title,
    description: d.description,
    terms: d.terms ?? '',
    kind: d.kind,
    value: Number(d.value),
    code: d.code,
    startsAt: d.starts_at.toISOString(),
    endsAt: d.ends_at.toISOString(),
    maxRedemptions: d.max_redemptions,
    redemptions: d.redemptions,
    status: d.status,
    city: d.city,
    coverImage: d.cover_image,
  };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/deals?city=&kind=&q=, unauthenticated diner-facing deals feed.
// `q` searches the whole active set server-side, so the Deals tab can stop
// filtering the first page client-side (which silently hid later pages).
router.get('/', async (req, res) => {
  const { city, kind, q } = req.query;
  const { limit, offset } = parsePagination(req.query);
  const search = typeof q === 'string' ? q.trim() : '';

  const conditions: string[] = ["d.status = 'active'", 'd.ends_at > now()'];
  const params: unknown[] = [];

  if (typeof city === 'string' && city.trim()) {
    params.push(city.trim());
    conditions.push(`r.city ILIKE $${params.length}`);
  }

  if (typeof kind === 'string' && kind.trim() && kind !== 'all' && kind !== 'any') {
    params.push(kind.trim());
    conditions.push(`d.kind = $${params.length}`);
  }

  if (search !== '') {
    params.push(likeTerm(search));
    const term = `$${params.length}`;
    conditions.push(`(d.title ILIKE ${term} OR d.description ILIKE ${term}
      OR COALESCE(d.code, '') ILIKE ${term} OR r.name ILIKE ${term})`);
  }

  const whereClause = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  // The raw term rides a separate parameter list: the count query below must
  // not receive it, or Postgres rejects the extra bind parameter.
  const mainParams = [...params];
  let orderBy = 'd.starts_at DESC';
  if (search !== '') {
    mainParams.push(search);
    orderBy = `${rankSql('d', `$${mainParams.length}`, 'title')}, d.starts_at DESC`;
  }
  const limitIndex = mainParams.push(limit);
  const offsetIndex = mainParams.push(offset);

  const rows = await query<DealRow>(
    `SELECT d.id, d.restaurant_id, r.name AS restaurant_name, d.title, d.description,
            d.terms, d.kind, d.value, d.code, d.starts_at, d.ends_at, d.max_redemptions,
            d.redemptions, d.status, r.city,
            COALESCE(NULLIF(d.image_url, ''), r.cover_image) AS cover_image
       FROM restaurant_deals d
       JOIN restaurants r ON r.id = d.restaurant_id
       ${whereClause}
      ORDER BY ${orderBy}
      LIMIT $${limitIndex} OFFSET $${offsetIndex}`,
    mainParams,
  );

  const count = await query<{ total: number }>(
    `SELECT count(*)::int AS total
       FROM restaurant_deals d
       JOIN restaurants r ON r.id = d.restaurant_id
       ${whereClause}`,
    params,
  );

  res.json({
    deals: rows.map(serializeDeal),
    total: count[0]?.total ?? 0,
    limit,
    offset,
  });
});

// GET /api/restaurants/:id/deals, unauthenticated deals for one venue.
venueRouter.get('/:restaurantId/deals', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  const [restaurant] = await query<{ id: string }>(
    `SELECT id FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant');

  const rows = await query<DealRow>(
    `SELECT d.id, d.restaurant_id, r.name AS restaurant_name, d.title, d.description,
            d.terms, d.kind, d.value, d.code, d.starts_at, d.ends_at, d.max_redemptions,
            d.redemptions, d.status, r.city,
            COALESCE(NULLIF(d.image_url, ''), r.cover_image) AS cover_image
       FROM restaurant_deals d
       JOIN restaurants r ON r.id = d.restaurant_id
      WHERE d.restaurant_id = $1::UUID
        AND d.status = 'active'
        AND d.ends_at > now()
      ORDER BY d.starts_at DESC`,
    [restaurantId],
  );

  res.json({
    deals: rows.map(serializeDeal),
  });
});

export default router;

// Mounted at `/api/restaurants` (before requireAuth).
export { venueRouter as venueDealsRouter };
