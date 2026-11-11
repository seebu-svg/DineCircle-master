/**
 * `npm run db:seed:reviews`, demo venue reviews for the customer and partner
 * apps, without touching anything else in the database.
 *
 * Unlike `db:seed` this script never truncates and never deletes a venue, so
 * it is the safe way to fill the review feed on a live test environment:
 *
 *   npm run db:seed:reviews                     every restaurant
 *   npm run db:seed:reviews -- <uuid> [<uuid>]  only these venues
 *
 * Re-running it is a no-op for reviews that already exist, and it refreshes
 * `restaurants.rating` / `review_count` either way.
 */
import { pool } from './db.js';
import { seedVenueReviews } from './seed_venue_reviews.js';

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function main(): Promise<void> {
  const restaurantIds = process.argv.slice(2).filter((arg) => UUID_PATTERN.test(arg));

  if (restaurantIds.length > 0) {
    console.log(`Seeding reviews for ${restaurantIds.length} venue(s)…`);
  } else {
    console.log('Seeding reviews for every restaurant…');
  }

  const summary = await seedVenueReviews({ restaurantIds, log: console.log });

  console.log('\nSeeded:');
  console.log(`  venues              ${summary.venues}`);
  console.log(`  reviews             ${summary.reviews} new`);
  console.log(`  partner replies     ${summary.replies} new`);
  console.log(`  reservations        ${summary.reservations} new`);

  const [totals] = await pool
    .query<{ reviews: string; replied: string; avg_rating: string }>(
      `SELECT count(*)::text AS reviews,
              count(*) FILTER (WHERE partner_reply IS NOT NULL)::text AS replied,
              COALESCE(ROUND(AVG(rating), 2), 0)::text AS avg_rating
         FROM reviews
        WHERE restaurant_id IS NOT NULL`,
    )
    .then((result) => result.rows);

  console.log('\nVenue reviews now in the database:', totals);
}

main()
  .catch((error) => {
    console.error('Review seed failed:', error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
