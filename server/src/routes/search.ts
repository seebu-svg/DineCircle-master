import { Router } from 'express';
import { query } from '../db.js';
import { ApiError } from '../context.js';
import { notBlockedBetween } from '../blocks.js';
import {
  SUGGESTIONS_MAX,
  likeTerm,
  mergeSuggestions,
  parseSearchParams,
  rankSql,
  suggestionRank,
  type SearchParams,
  type Suggestion,
  type SuggestionKind,
} from '../search.js';
import {
  serializeRestaurant,
  type RestaurantRow,
} from './restaurants.js';
import { serializeDeal, type DealRow } from './deals.js';
import { AUDIENCE_GATE, EVENT_SELECT, serializeEvent, type EventRow } from './events.js';
import { serializePublic, type UserRow } from './users.js';

const router = Router();

/** `COUNT(*) OVER ()` arrives as a bigint, i.e. a decimal string. */
type Measured = { total_count: string | number };

/** A page of one category: the rows, the unpaged total, and whether more exist. */
type Bucket<T> = { items: T[]; total: number; hasMore: boolean };

/**
 * Sequential parameter binder. Every query owns its own list, so the SQL reads
 * top-to-bottom in the same order as the `$n` placeholders it produces.
 */
function binder(initial: unknown[] = []) {
  const params = [...initial];
  const push = (value: unknown): string => {
    params.push(value);
    return `$${params.length}`;
  };
  return { params, push };
}

function totalOf(rows: ReadonlyArray<Measured>): number {
  const raw = rows[0]?.total_count;
  return raw === undefined ? 0 : Number(raw);
}

function bucket<T, R extends Measured>(
  rows: R[],
  map: (row: R) => T,
  params: SearchParams,
): Bucket<T> {
  const total = totalOf(rows);
  return {
    items: rows.map(map),
    total,
    hasMore: params.offset + rows.length < total,
  };
}

/** Venue filters shared by the restaurant and menu-item searches. */
function addVenueFilters(
  conditions: string[],
  p: SearchParams,
  push: (value: unknown) => string,
  alias: string,
): void {
  if (p.city) {
    conditions.push(`${alias}.city ILIKE ${push(likeTerm(p.city))}`);
  }
  if (p.cuisine) {
    const term = push(likeTerm(p.cuisine));
    conditions.push(
      `EXISTS (SELECT 1 FROM unnest(${alias}.cuisines) c(value) WHERE c.value ILIKE ${term})`,
    );
  }
  // "Restaurant type" is the union of tags (rooftop, cafe, family…) and
  // cuisines: the same axis `/api/restaurants?tag=` already exposes.
  if (p.venueType) {
    const term = push(likeTerm(p.venueType));
    conditions.push(
      `(EXISTS (SELECT 1 FROM unnest(${alias}.tags) t(value) WHERE t.value ILIKE ${term})
        OR EXISTS (SELECT 1 FROM unnest(${alias}.cuisines) c(value) WHERE c.value ILIKE ${term}))`,
    );
  }
}

async function searchRestaurants(
  viewerId: string,
  p: SearchParams,
): Promise<Bucket<ReturnType<typeof serializeRestaurant>>> {
  const { params, push } = binder();
  const viewer = push(viewerId);
  const like = push(likeTerm(p.query));
  const raw = push(p.query);
  const conditions = [
    'r.accepting_bookings',
    `(r.name ILIKE ${like} OR r.neighborhood ILIKE ${like} OR r.city ILIKE ${like}
      OR EXISTS (SELECT 1 FROM unnest(r.cuisines) c(value) WHERE c.value ILIKE ${like})
      OR EXISTS (SELECT 1 FROM unnest(r.tags) t(value) WHERE t.value ILIKE ${like}))`,
  ];
  addVenueFilters(conditions, p, push, 'r');
  const limit = push(p.limit);
  const offset = push(p.offset);
  const order =
    p.sort === 'rating'
      ? 'r.rating DESC, r.review_count DESC'
      : `${rankSql('r', raw)}, r.is_partner DESC, r.rating DESC`;

  const rows = await query<RestaurantRow & Measured>(
    `SELECT r.*, EXISTS (
       SELECT 1 FROM venue_follows vf
       WHERE vf.restaurant_id = r.id AND vf.user_id = ${viewer}::UUID
     ) AS is_following, COUNT(*) OVER () AS total_count
     FROM restaurants r
     WHERE ${conditions.join(' AND ')}
     ORDER BY ${order}
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );
  return bucket(rows, serializeRestaurant, p);
}

type MenuRow = Measured & {
  id: string;
  name: string;
  description: string;
  price: string;
  photo_url: string;
  dietary_tags: string[];
  section_name: string;
  restaurant_id: string;
  restaurant_name: string;
  neighborhood: string;
  city: string;
  cover_image: string;
};

async function searchMenu(p: SearchParams): Promise<Bucket<unknown>> {
  const { params, push } = binder();
  const like = push(likeTerm(p.query));
  const raw = push(p.query);
  const conditions = [
    'i.is_available',
    's.is_active',
    'r.accepting_bookings',
    `(i.name ILIKE ${like} OR i.description ILIKE ${like} OR s.name ILIKE ${like})`,
  ];
  addVenueFilters(conditions, p, push, 'r');
  const limit = push(p.limit);
  const offset = push(p.offset);
  const order =
    p.sort === 'priceAsc' ? 'i.price ASC' : `${rankSql('i', raw)}, i.price ASC`;

  const rows = await query<MenuRow>(
    `SELECT i.id, i.name, i.description, i.price, i.photo_url, i.dietary_tags,
            s.name AS section_name,
            r.id AS restaurant_id, r.name AS restaurant_name,
            r.neighborhood, r.city, r.cover_image,
            COUNT(*) OVER () AS total_count
     FROM restaurant_menu_items i
     JOIN restaurant_menu_sections s ON s.id = i.section_id
     JOIN restaurants r ON r.id = i.restaurant_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY ${order}
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );
  return bucket(
    rows,
    (row) => ({
      id: row.id,
      name: row.name,
      description: row.description,
      price: Number(row.price),
      photoUrl: row.photo_url,
      sectionName: row.section_name,
      dietaryTags: row.dietary_tags,
      restaurant: {
        id: row.restaurant_id,
        name: row.restaurant_name,
        neighborhood: row.neighborhood,
        city: row.city,
        coverImage: row.cover_image,
      },
    }),
    p,
  );
}

async function searchDeals(p: SearchParams): Promise<Bucket<unknown>> {
  const { params, push } = binder();
  const like = push(likeTerm(p.query));
  const raw = push(p.query);
  const conditions = [
    "d.status = 'active'",
    'd.ends_at > now()',
    'd.starts_at <= now()',
    `(d.title ILIKE ${like} OR d.description ILIKE ${like}
      OR COALESCE(d.code, '') ILIKE ${like} OR r.name ILIKE ${like})`,
  ];
  if (p.city) conditions.push(`r.city ILIKE ${push(likeTerm(p.city))}`);
  if (p.dealKind) conditions.push(`d.kind = ${push(p.dealKind)}`);
  if (p.cuisine) {
    const term = push(likeTerm(p.cuisine));
    conditions.push(
      `EXISTS (SELECT 1 FROM unnest(r.cuisines) c(value) WHERE c.value ILIKE ${term})`,
    );
  }
  const limit = push(p.limit);
  const offset = push(p.offset);
  const order =
    p.sort === 'relevant'
      ? `${rankSql('d', raw, 'title')}, d.ends_at ASC`
      : 'd.ends_at ASC';

  const rows = await query<DealRow & Measured>(
    `SELECT d.id, d.restaurant_id, r.name AS restaurant_name, d.title, d.description,
            d.terms, d.kind, d.value, d.code, d.starts_at, d.ends_at, d.max_redemptions,
            d.redemptions, d.status, r.city,
            COALESCE(NULLIF(d.image_url, ''), r.cover_image) AS cover_image,
            COUNT(*) OVER () AS total_count
     FROM restaurant_deals d
     JOIN restaurants r ON r.id = d.restaurant_id
     WHERE ${conditions.join(' AND ')}
     ORDER BY ${order}
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );
  return bucket(rows, serializeDeal, p);
}

/**
 * `EVENT_SELECT` is the one payload every event surface shares, so the search
 * borrows it verbatim and only injects the paging total into its column list.
 */
const EXPERIENCE_SELECT = EVENT_SELECT.replace(
  'SELECT e.*,',
  'SELECT e.*, COUNT(*) OVER () AS total_count,',
);

async function searchExperiences(
  viewerId: string,
  p: SearchParams,
): Promise<Bucket<unknown>> {
  const { params, push } = binder([viewerId, viewerId]);
  const conditions = [
    AUDIENCE_GATE.replaceAll('$VIEWER_UUID', '$2').replaceAll('$VIEWER', '$1'),
    "(e.status NOT IN ('draft','requested','declined') OR e.host_id = $2)",
    notBlockedBetween('$2', 'e.host_id'),
  ];
  const like = push(likeTerm(p.query));
  const raw = push(p.query);
  conditions.push(
    `(e.title ILIKE ${like} OR e.tagline ILIKE ${like} OR r.name ILIKE ${like}
      OR EXISTS (SELECT 1 FROM unnest(e.tags) tag WHERE tag ILIKE ${like}))`,
  );
  if (p.city) conditions.push(`r.city ILIKE ${push(likeTerm(p.city))}`);
  if (p.venueType) {
    const term = push(likeTerm(p.venueType));
    conditions.push(
      `EXISTS (SELECT 1 FROM unnest(r.tags) t(value) WHERE t.value ILIKE ${term})`,
    );
  }
  if (p.from) conditions.push(`e.start_at >= ${push(p.from)}::TIMESTAMPTZ`);
  if (p.to) conditions.push(`e.start_at <= ${push(p.to)}::TIMESTAMPTZ`);
  // Without an explicit window the feed stays "what is still bookable".
  if (!p.from && !p.to) conditions.push('e.start_at >= now()');
  if (p.availableOnly) conditions.push('e.seats_booked < e.seats_total');
  const limit = push(p.limit);
  const offset = push(p.offset);
  const order =
    p.sort === 'soon'
      ? 'e.start_at ASC'
      : `${rankSql('e', raw, 'title')}, e.start_at ASC`;

  const rows = await query<EventRow & Measured>(
    `${EXPERIENCE_SELECT}
     WHERE ${conditions.join(' AND ')}
     ORDER BY ${order}
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );
  return bucket(rows, serializeEvent, p);
}

async function searchHosts(
  viewerId: string,
  p: SearchParams,
): Promise<Bucket<unknown>> {
  const { params, push } = binder();
  const viewer = push(viewerId);
  const like = push(likeTerm(p.query));
  const raw = push(p.query);
  const conditions = [
    'u.is_deleted = false',
    notBlockedBetween(viewer, 'u.id'),
    `(u.name ILIKE ${like} OR u.handle ILIKE ${like} OR u.bio ILIKE ${like})`,
    // "Host" means someone who can publish or already has: the ladder roles,
    // plus anyone with a hosted dinner on record. Personal accounts are private
    // and are never surfaced as hosts.
    `u.account_type = 'professional'
      AND (u.role IN ('host','influencer','partner_admin','super_admin')
           OR EXISTS (SELECT 1 FROM dinner_events e WHERE e.host_id = u.id))`,
  ];
  if (p.city) conditions.push(`u.city ILIKE ${push(likeTerm(p.city))}`);
  const limit = push(p.limit);
  const offset = push(p.offset);

  const rows = await query<UserRow & Measured & { is_following: boolean }>(
    `SELECT u.*, EXISTS (
       SELECT 1 FROM follows f
       WHERE f.follower_id = ${viewer}::UUID AND f.followee_id = u.id
     ) AS is_following, COUNT(*) OVER () AS total_count
     FROM users u
     WHERE ${conditions.join(' AND ')}
     ORDER BY ${rankSql('u', raw)}, u.followers_count DESC, u.name ASC
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );
  return bucket(
    rows,
    (row) => ({ ...serializePublic(row), isFollowing: row.is_following }),
    p,
  );
}

// GET /api/search — one ranked, categorised page per requested entity type.
router.get('/', async (req, res) => {
  const params = parseSearchParams(req.query as Record<string, unknown>);
  if (!params.valid) {
    throw new ApiError(400, 'q must be between 1 and 80 characters');
  }
  const wanted = new Set(params.categories);
  const empty = <T>(): Bucket<T> => ({ items: [], total: 0, hasMore: false });

  const [restaurants, menu, deals, experiences, hosts] = await Promise.all([
    wanted.has('restaurants') ? searchRestaurants(req.userId, params) : empty(),
    wanted.has('menu') ? searchMenu(params) : empty(),
    wanted.has('deals') ? searchDeals(params) : empty(),
    wanted.has('experiences') ? searchExperiences(req.userId, params) : empty(),
    wanted.has('hosts') ? searchHosts(req.userId, params) : empty(),
  ]);

  res.json({
    query: params.query,
    page: params.page,
    limit: params.limit,
    counts: {
      restaurants: restaurants.total,
      menu: menu.total,
      deals: deals.total,
      experiences: experiences.total,
      hosts: hosts.total,
    },
    hasMore: {
      restaurants: restaurants.hasMore,
      menu: menu.hasMore,
      deals: deals.hasMore,
      experiences: experiences.hasMore,
      hosts: hosts.hasMore,
    },
    restaurants: restaurants.items,
    menu: menu.items,
    deals: deals.items,
    experiences: experiences.items,
    hosts: hosts.items,
  });
});

// GET /api/search/suggest?q= — typeahead strings across every source.
router.get('/suggest', async (req, res) => {
  const raw = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  if (raw.length < 2) {
    res.json({ suggestions: [] });
    return;
  }
  const like = likeTerm(raw);
  const take = SUGGESTIONS_MAX;

  const [venues, cuisines, dishes, deals, experiences, hosts] = await Promise.all([
    query<{ text: string; ref_id: string }>(
      `SELECT r.name AS text, r.id::text AS ref_id
       FROM restaurants r
       WHERE r.accepting_bookings AND r.name ILIKE $1
       LIMIT ${take}`,
      [like],
    ),
    query<{ text: string; ref_id: string | null }>(
      `SELECT DISTINCT c.value AS text, NULL::text AS ref_id
       FROM restaurants r, unnest(r.cuisines) AS c(value)
       WHERE r.accepting_bookings AND c.value ILIKE $1
       LIMIT ${take}`,
      [like],
    ),
    query<{ text: string; ref_id: string }>(
      `SELECT i.name AS text, i.restaurant_id::text AS ref_id
       FROM restaurant_menu_items i
       JOIN restaurant_menu_sections s ON s.id = i.section_id
       JOIN restaurants r ON r.id = i.restaurant_id
       WHERE i.is_available AND s.is_active AND r.accepting_bookings AND i.name ILIKE $1
       GROUP BY i.name, i.restaurant_id
       LIMIT ${take}`,
      [like],
    ),
    query<{ text: string; ref_id: string }>(
      `SELECT d.title AS text, d.id::text AS ref_id
       FROM restaurant_deals d
       WHERE d.status = 'active' AND d.ends_at > now() AND d.title ILIKE $1
       GROUP BY d.title, d.id
       LIMIT ${take}`,
      [like],
    ),
    query<{ text: string; ref_id: string }>(
      `SELECT e.title AS text, e.id::text AS ref_id
       FROM dinner_events e
       WHERE e.status NOT IN ('draft','requested','declined') AND e.start_at >= now()
         AND e.title ILIKE $1
       LIMIT ${take}`,
      [like],
    ),
    query<{ text: string; ref_id: string }>(
      `SELECT u.name AS text, u.id::text AS ref_id
       FROM users u
       WHERE u.is_deleted = false AND (u.name ILIKE $1 OR u.handle ILIKE $1)
       ORDER BY u.followers_count DESC
       LIMIT ${take}`,
      [like],
    ),
  ]);

  const rows: Suggestion[] = [
    ...venues.map((row) => suggestion('restaurant', row, raw)),
    ...cuisines.map((row) => suggestion('cuisine', row, raw)),
    ...dishes.map((row) => suggestion('menu', row, raw)),
    ...deals.map((row) => suggestion('deal', row, raw)),
    ...experiences.map((row) => suggestion('experience', row, raw)),
    ...hosts.map((row) => suggestion('host', row, raw)),
  ];

  res.json({
    suggestions: mergeSuggestions(rows).map(({ text, kind, refId }) => ({
      text,
      kind,
      refId,
    })),
  });
});

function suggestion(
  kind: SuggestionKind,
  row: { text: string; ref_id: string | null },
  queryText: string,
): Suggestion {
  return {
    text: row.text,
    kind,
    refId: row.ref_id,
    rank: suggestionRank(row.text, queryText),
  };
}

export default router;
