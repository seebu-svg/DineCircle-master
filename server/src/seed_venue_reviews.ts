/**
 * Venue review seed, demo social proof for the restaurant storefronts.
 *
 * The event world already carries guest reviews for dinner editions, but no
 * script has ever written a `restaurant_id` review. Every storefront therefore
 * opens on "No reviews yet" and the partner reviews inbox is empty, even
 * though `restaurants.review_count` holds a number. This module closes that
 * gap and is shared by two callers:
 *
 *   • `npm run db:seed:reviews` (src/seed_reviews.ts), safe to run against a
 *     live database as often as needed;
 *   • `npm run db:seed` (src/seed.ts), so a full reseed never loses them.
 *
 * The curated venue script (`db:seed:karachi`) deletes every restaurant, so
 * run `npm run db:seed:reviews` after it to put the feed back.
 *
 * It is additive and idempotent: it deletes nothing. It ensures a pool of
 * demo reviewer accounts exists, gives each one a completed table reservation
 * at the venue it reviews (the same gate POST /restaurants/:id/reviews
 * enforces), writes one review per reviewer per venue, and finally recomputes
 * `restaurants.rating` / `review_count` from the reviews table so the profile
 * header, the search ranking and the partner aggregate all agree with the list
 * the customer actually scrolls.
 *
 * Every row here is test content: the accounts are `is_demo`, they have no
 * password hash (nothing can sign in as them) and the copy is written for the
 * seed, not collected from guests.
 */
import { query } from './db.js';

/** Reviews written per venue, one per reviewer in the rotation below. */
const REVIEWERS_PER_VENUE = 5;

/** Deterministic reviewer accounts, stable across re-seeds. */
const REVIEWERS = [
  {
    id: 'dddddddd-0000-4000-8000-0000000000d1',
    name: 'Sana Iqbal',
    handle: 'sana.reviews',
    homeArea: 'Clifton',
    avatar: 'assets/images/portrait_3.png',
  },
  {
    id: 'dddddddd-0000-4000-8000-0000000000d2',
    name: 'Bilal Ahmad',
    handle: 'bilal.reviews',
    homeArea: 'PECHS',
    avatar: 'assets/images/portrait_1.png',
  },
  {
    id: 'dddddddd-0000-4000-8000-0000000000d3',
    name: 'Hira Memon',
    handle: 'hira.reviews',
    homeArea: 'Bahadurabad',
    avatar: 'assets/images/portrait_2.png',
  },
  {
    id: 'dddddddd-0000-4000-8000-0000000000d4',
    name: 'Usman Qureshi',
    handle: 'usman.reviews',
    homeArea: 'Gulshan-e-Iqbal',
    avatar: 'assets/images/portrait_4.png',
  },
  {
    id: 'dddddddd-0000-4000-8000-0000000000d5',
    name: 'Zoya Ansari',
    handle: 'zoya.reviews',
    homeArea: 'DHA Phase 6',
    avatar: 'assets/images/portrait_5.png',
  },
  {
    id: 'dddddddd-0000-4000-8000-0000000000d6',
    name: 'Danish Siddiqui',
    handle: 'danish.reviews',
    homeArea: 'North Nazimabad',
    avatar: 'assets/images/portrait_6.png',
  },
] as const;

type Sample = {
  /** numeric(3,2) string, the same shape the seed's event reviews use. */
  rating: string;
  text: string;
  /** Partner reply, written in the venue's voice. Omitted on some rows. */
  reply?: string;
};

/**
 * Reviews rotate through this pool, so neighbouring venues do not repeat the
 * same sentence. Ratings stay between 3.90 and 5.00: a demo venue with a two
 * star outlier reads as broken content rather than a bad dinner.
 */
const REVIEW_POOL: readonly Sample[] = [
  {
    rating: '5.00',
    text: 'Booked for a family dinner and the staff found us a quiet corner without being asked. Food came out hot and together.',
    reply: 'Thank you for bringing the family in. Ask for the corner tables when you book and we will hold one.',
  },
  {
    rating: '4.80',
    text: 'Portions are generous and the karahi was properly cooked. Parking took a while on a Saturday night.',
    reply: 'Glad the food landed well. Valet has extra hands after seven on weekends, just pull up at the gate.',
  },
  {
    rating: '4.60',
    text: 'Went for lunch on a weekday, service was quick and the bill matched the menu prices. Will come back for the grill.',
  },
  {
    rating: '5.00',
    text: 'The naan never stopped coming and the tea at the end was on the house. Exactly what we wanted.',
    reply: 'A full table is the whole point. See you next time.',
  },
  {
    rating: '4.20',
    text: 'Good food, slightly slow between courses once the hall filled up. The manager checked on us twice.',
    reply: 'Fair note. We added a runner on the floor this week to keep the gap between courses short.',
  },
  {
    rating: '4.90',
    text: 'Reserved through DineCircle and the table was ready at the minute we walked in. Smoothest booking I have had in Karachi.',
  },
  {
    rating: '4.50',
    text: 'Biryani was well balanced and the raita was fresh. Air conditioning could be stronger in the family section.',
    reply: 'The family section unit is on the list for service this month. Thank you for flagging it.',
  },
  {
    rating: '3.90',
    text: 'Tasty food but the wait ran twenty minutes past the booking. Staff apologised with a free dessert.',
    reply: 'Sorry about the wait. We hold tables for fifteen minutes and will keep the floor tighter on busy evenings.',
  },
  {
    rating: '5.00',
    text: 'Took visiting relatives here and everyone asked to come back. The grilled seafood is worth the price.',
  },
  {
    rating: '4.70',
    text: 'Clean, well lit and the staff knew the menu. Good option for a weeknight dinner that does not drag.',
  },
  {
    rating: '4.40',
    text: 'Solid meal at a fair price. The dessert menu is short, would love to see more options on it.',
    reply: 'Noted, two more desserts join the card next month.',
  },
  {
    rating: '4.80',
    text: 'Booked a table for a small birthday. They kept the cake in their fridge and brought it out when asked.',
  },
  {
    rating: '4.30',
    text: 'Loud on a Friday, as expected. The food made up for it and the servers were quick with refills.',
    reply: 'Friday nights do get busy. The terrace side is quieter if you want a calmer table next time.',
  },
  {
    rating: '5.00',
    text: 'Third visit this month. Consistency is the reason, the same dish tastes the same every time.',
  },
  {
    rating: '4.60',
    text: 'Nice outdoor seating and the staff did not rush us out after we finished. We stayed on for tea.',
  },
  {
    rating: '4.10',
    text: 'Decent dinner, though the bread arrived after the curry had gone cold. Would still give it another try.',
    reply: 'Thank you for the patience. The pass now sends bread with the curry instead of after it.',
  },
  {
    rating: '4.75',
    text: 'The set menu was good value and we only needed one extra dish. Handy for a group that cannot decide.',
  },
  {
    rating: '4.50',
    text: 'Easy to find, valet worked and the food was on the table within twenty minutes of ordering.',
  },
];

/** Wall-clock moment `days` ago, so the feed always reads as recent history. */
function daysAgo(days: number, hour = 21): string {
  const d = new Date();
  d.setHours(hour, 15, 0, 0);
  d.setDate(d.getDate() - days);
  return d.toISOString();
}

export type SeedVenueReviewsOptions = {
  /** Restrict the run to these venues. Defaults to every restaurant row. */
  restaurantIds?: readonly string[];
  /** Collect human-readable progress, mainly for the CLI. */
  log?: (message: string) => void;
};

export type SeedVenueReviewsSummary = {
  venues: number;
  reviews: number;
  replies: number;
  reservations: number;
};

type VenueRow = {
  id: string;
  name: string;
  branch_id: string | null;
  table_id: string | null;
};

/**
 * Find or create one demo reviewer and return the id to attribute reviews to.
 * Lookup is by deterministic id or handle, so re-runs never duplicate accounts.
 */
async function ensureReviewer(reviewer: (typeof REVIEWERS)[number]): Promise<string> {
  const [existing] = await query<{ id: string }>(
    'SELECT id FROM users WHERE id = $1::uuid OR handle = $2 LIMIT 1',
    [reviewer.id, reviewer.handle],
  );
  if (existing) return existing.id;

  await query(
    `INSERT INTO users
       (id, name, handle, email, role, city, home_area, bio, avatar_url, is_demo, joined_year)
     VALUES ($1::uuid, $2, $3, $4, 'user', 'Karachi', $5, $6, $7, true, 2025)`,
    [
      reviewer.id,
      reviewer.name,
      reviewer.handle,
      `${reviewer.handle}@example.test`,
      reviewer.homeArea,
      'Demo reviewer account: the reviews written by the seed are sample content, not collected from real guests.',
      reviewer.avatar,
    ],
  );
  return reviewer.id;
}

/**
 * Recompute the denormalised rating columns on `restaurants` from the reviews
 * table. Both review surfaces read them (the customer profile header and the
 * partner inbox aggregate), and the API computes its averages from `reviews`
 * directly, so the two drift apart the moment a seed writes reviews without
 * touching the columns.
 */
export async function refreshVenueRatingAggregates(
  restaurantIds?: readonly string[],
): Promise<void> {
  const scoped = restaurantIds !== undefined && restaurantIds.length > 0;
  const scope = scoped ? 'AND r.id = ANY($1::uuid[])' : '';
  const params = scoped ? [restaurantIds] : [];

  await query(
    `UPDATE restaurants r
        SET rating = agg.avg_rating,
            review_count = agg.cnt
       FROM (
         SELECT restaurant_id,
                ROUND(AVG(rating), 2) AS avg_rating,
                COUNT(*)::int          AS cnt
           FROM reviews
          WHERE restaurant_id IS NOT NULL
          GROUP BY restaurant_id
       ) agg
      WHERE r.id = agg.restaurant_id
        ${scope}`,
    params,
  );

  // A venue with no reviews reads 0, never whatever a previous seed invented.
  await query(
    `UPDATE restaurants r
        SET rating = 0,
            review_count = 0
      WHERE NOT EXISTS (SELECT 1 FROM reviews rv WHERE rv.restaurant_id = r.id)
        ${scope}`,
    params,
  );
}

/**
 * Write demo venue reviews. Safe to run repeatedly: reviews are keyed by the
 * (restaurant_id, author_id) unique index and reservations by their reference,
 * so an existing row is left alone instead of duplicated or overwritten.
 */
export async function seedVenueReviews(
  options: SeedVenueReviewsOptions = {},
): Promise<SeedVenueReviewsSummary> {
  const log = options.log ?? (() => {});
  const scoped = options.restaurantIds !== undefined && options.restaurantIds.length > 0;
  const scope = scoped ? 'WHERE r.id = ANY($1::uuid[])' : '';
  const params = scoped ? [options.restaurantIds] : [];

  const venues = await query<VenueRow>(
    `SELECT r.id, r.name,
            (SELECT b.id FROM restaurant_branches b
              WHERE b.restaurant_id = r.id
              ORDER BY b.is_primary DESC, b.created_at
              LIMIT 1) AS branch_id,
            (SELECT t.id FROM restaurant_tables t
              WHERE t.restaurant_id = r.id AND t.is_active
              ORDER BY t.seats
              LIMIT 1) AS table_id
       FROM restaurants r
       ${scope}
      ORDER BY r.name, r.id`,
    params,
  );

  const reviewerIds: string[] = [];
  for (const reviewer of REVIEWERS) {
    reviewerIds.push(await ensureReviewer(reviewer));
  }

  const summary: SeedVenueReviewsSummary = {
    venues: venues.length,
    reviews: 0,
    replies: 0,
    reservations: 0,
  };

  for (const [venueIndex, venue] of venues.entries()) {
    for (let slot = 0; slot < REVIEWERS_PER_VENUE; slot += 1) {
      const sequence = venueIndex * REVIEWERS_PER_VENUE + slot;
      const reviewerIndex = sequence % REVIEWERS.length;
      const reviewer = REVIEWERS[reviewerIndex]!;
      const authorId = reviewerIds[reviewerIndex]!;
      const sample = REVIEW_POOL[sequence % REVIEW_POOL.length]!;
      // The visit, then the review two days later, then any partner reply.
      const offset = (sequence * 5) % 84;
      const visitedAt = daysAgo(10 + offset);
      const reviewedAt = daysAgo(8 + offset);
      const repliedAt = sample.reply ? daysAgo(6 + offset) : null;

      // The POST route only accepts a review from a guest with a completed
      // table reservation, so the seeded history carries one too.
      const reservation = await query<{ id: string }>(
        `INSERT INTO table_reservations
           (restaurant_id, branch_id, table_id, user_id, guest_name, guest_phone,
            party_size, start_at, duration_minutes, status, reference, notes, source)
         VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, $5, $6,
                 2, $7::timestamptz, 90, 'completed', $8, $9, 'customer')
         ON CONFLICT (reference) DO NOTHING
         RETURNING id`,
        [
          venue.id,
          venue.branch_id,
          venue.table_id,
          authorId,
          reviewer.name,
          `+9233${String(4100000 + sequence).padStart(7, '0')}`,
          visitedAt,
          `DC-RV-${String(venueIndex + 1).padStart(3, '0')}-${reviewerIndex + 1}`,
          'Demo visit behind a seeded venue review.',
        ],
      );
      if (reservation.length > 0) summary.reservations += 1;

      const inserted = await query<{ id: string }>(
        `INSERT INTO reviews
           (author_id, restaurant_id, rating, text, partner_reply, partner_replied_at, created_at)
         VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6::timestamptz, $7::timestamptz)
         ON CONFLICT (restaurant_id, author_id) WHERE restaurant_id IS NOT NULL DO NOTHING
         RETURNING id`,
        [authorId, venue.id, sample.rating, sample.text, sample.reply ?? null, repliedAt, reviewedAt],
      );
      if (inserted.length > 0) {
        summary.reviews += 1;
        if (sample.reply) summary.replies += 1;
      }
    }
    log(`  ok ${venue.name} (${REVIEWERS_PER_VENUE} reviews)`);
  }

  await refreshVenueRatingAggregates(options.restaurantIds);
  return summary;
}
