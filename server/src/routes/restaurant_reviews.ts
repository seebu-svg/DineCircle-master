import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { parsePagination } from '../api.js';

const router = Router();

/**
 * Restaurant reviews, public read, authenticated write.
 *
 * Customers can review restaurants (not just dinner events). Requires a
 * completed table reservation to post. Partners can reply to reviews.
 */

type ReviewRow = {
  id: string;
  author_id: string;
  author_name: string;
  restaurant_id: string;
  rating: string;
  text: string;
  partner_reply: string | null;
  partner_replied_at: Date | null;
  created_at: Date;
};

function serializeReview(r: ReviewRow) {
  return {
    id: r.id,
    authorId: r.author_id,
    authorName: r.author_name,
    restaurantId: r.restaurant_id,
    rating: Number(r.rating),
    text: r.text,
    partnerReply: r.partner_reply,
    partnerRepliedAt: r.partner_replied_at?.toISOString() ?? null,
    createdAt: r.created_at.toISOString(),
  };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/restaurants/:id/reviews, public, paginated.
router.get('/:restaurantId/reviews', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  const [restaurant] = await query<{ id: string }>(
    `SELECT id FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant');

  const { limit, offset } = parsePagination(req.query);

  const reviews = await query<ReviewRow>(
    `SELECT r.id, r.author_id, u.name AS author_name, r.restaurant_id,
            r.rating, r.text, r.partner_reply, r.partner_replied_at, r.created_at
       FROM reviews r
       JOIN users u ON u.id = r.author_id
      WHERE r.restaurant_id = $1::UUID
      ORDER BY r.created_at DESC
      LIMIT $2 OFFSET $3`,
    [restaurantId, limit, offset],
  );

  const [aggregate] = await query<{ avg_rating: string; count: number }>(
    `SELECT COALESCE(AVG(rating), 0)::text AS avg_rating, count(*)::int AS count
       FROM reviews
      WHERE restaurant_id = $1::UUID`,
    [restaurantId],
  );

  res.json({
    reviews: reviews.map(serializeReview),
    aggregate: {
      rating: Number(aggregate?.avg_rating ?? 0),
      count: aggregate?.count ?? 0,
    },
    limit,
    offset,
  });
});

// POST /api/restaurants/:id/reviews, authenticated, requires completed reservation.
const postReviewSchema = z.object({
  rating: z.number().min(0).max(5),
  text: z.string().min(1).max(2000),
});

router.post('/:restaurantId/reviews', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  const userId = req.userId;
  if (!userId) {
    throw new ApiError(401, 'Authentication required');
  }

  const [restaurant] = await query<{ id: string }>(
    `SELECT id FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant');

  const input = postReviewSchema.parse(req.body ?? {});

  // Check for completed reservation (mirrors event-review gate).
  const [reservation] = await query<{ id: string }>(
    `SELECT id FROM table_reservations
      WHERE restaurant_id = $1::UUID
        AND user_id = $2::UUID
        AND status = 'completed'
      LIMIT 1`,
    [restaurantId, userId],
  );

  if (!reservation) {
    throw new ApiError(
      403,
      'You can only review a restaurant after a completed reservation',
    );
  }

  // Check for duplicate review.
  const [existing] = await query<{ id: string }>(
    `SELECT id FROM reviews
      WHERE restaurant_id = $1::UUID AND author_id = $2::UUID`,
    [restaurantId, userId],
  );

  if (existing) {
    throw new ApiError(409, 'You have already reviewed this restaurant');
  }

  const [review] = await query<ReviewRow>(
    `INSERT INTO reviews (author_id, restaurant_id, rating, text)
     VALUES ($1::UUID, $2::UUID, $3, $4)
     RETURNING id, author_id, restaurant_id, rating, text, partner_reply, partner_replied_at, created_at`,
    [userId, restaurantId, input.rating, input.text],
  );

  if (!review) {
    throw new ApiError(500, 'Failed to create review');
  }

  // Fetch author name for response.
  const [author] = await query<{ name: string }>(
    `SELECT name FROM users WHERE id = $1::UUID`,
    [userId],
  );

  res.status(201).json({
    review: serializeReview({
      id: review.id,
      author_id: review.author_id,
      author_name: author?.name ?? '',
      restaurant_id: review.restaurant_id,
      rating: review.rating,
      text: review.text,
      partner_reply: review.partner_reply,
      partner_replied_at: review.partner_replied_at,
      created_at: review.created_at,
    }),
  });
});

export default router;
