import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, forbidden } from '../context.js';

const router = Router();

type ReviewRow = {
  id: string;
  event_id: string;
  event_title: string;
  rating: string;
  text: string;
  created_at: Date;
  author_id: string;
  author_name: string | null;
  author_handle: string | null;
  author_avatar: string | null;
};

// GET /api/reviews, filterable by host, event or author, newest first.
router.get('/reviews', async (req, res) => {
  const { hostId, eventId, authorId, limit = '50' } = req.query;

  const conditions: string[] = [];
  const params: unknown[] = [];

  const add = (sqlFragment: string, value: string) => {
    params.push(value);
    conditions.push(sqlFragment.replace('?', `$${params.length}`));
  };

  if (typeof hostId === 'string' && hostId !== '') add('e.host_id = ?', hostId);
  if (typeof eventId === 'string' && eventId !== '') {
    add('rv.event_id = ?', eventId);
  }
  if (typeof authorId === 'string' && authorId !== '') {
    add('rv.author_id = ?', authorId);
  }

  const where = conditions.length === 0 ? '' : `WHERE ${conditions.join(' AND ')}`;
  const parsedLimit = Math.min(Number(limit) || 50, 200);

  const rows = await query<ReviewRow>(
    `SELECT rv.*, e.title AS event_title,
            u.name AS author_name, u.handle AS author_handle,
            u.avatar_url AS author_avatar
     FROM reviews rv
     LEFT JOIN users u ON u.id = rv.author_id
     LEFT JOIN dinner_events e ON e.id = rv.event_id
     ${where}
     ORDER BY rv.created_at DESC
     LIMIT ${parsedLimit}`,
    params,
  );

  res.json({
    reviews: rows.map((r) => ({
      id: r.id,
      eventId: r.event_id,
      eventTitle: r.event_title,
      rating: Number(r.rating),
      text: r.text,
      createdAt: r.created_at,
      author: {
        id: r.author_id,
        name: r.author_name,
        handle: r.author_handle,
        avatarUrl: r.author_avatar,
      },
    })),
    count: rows.length,
  });
});

const createReviewSchema = z.object({
  rating: z.coerce.number().min(1).max(5),
  text: z.string().trim().min(10).max(1000),
});

// POST /api/events/:id/reviews, a guest reviews an event they attended.
router.post('/events/:id/reviews', async (req, res) => {
  const { rating, text } = createReviewSchema.parse(req.body ?? {});
  const eventId = req.params.id;

  const [event] = await query<{ id: string; title: string; host_id: string }>(
    'SELECT id, title, host_id FROM dinner_events WHERE id = $1::UUID',
    [eventId],
  );
  if (!event) throw notFound('Event');
  if (event.host_id === req.userId) {
    throw forbidden('Hosts cannot review their own events');
  }

  const [attended] = await query<{ id: string }>(
    `SELECT id FROM bookings
     WHERE event_id = $1 AND user_id = $2 AND status = 'completed'`,
    [eventId, req.userId],
  );
  if (!attended) {
    throw forbidden('Only guests who attended can review');
  }

  const [duplicate] = await query<{ id: string }>(
    'SELECT id FROM reviews WHERE event_id = $1 AND author_id = $2',
    [eventId, req.userId],
  );
  if (duplicate) {
    throw new ApiError(409, 'You already reviewed this event');
  }

  // The review insert, the host's aggregate rating/review_count recompute,
  // and the activity feed row must all succeed or fail together, otherwise
  // a crash between the two UPDATEs would leave the host's denormalised
  // rating permanently out of sync with the reviews table.
  await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO reviews (author_id, event_id, rating, text)
       VALUES ($1, $2, $3, $4)`,
      [req.userId, eventId, rating, text],
    );

    // Recompute the host's aggregate rating as the mean of all their
    // reviews, and review_count as the row count. This is cheaper than it
    // looks because reviews are append-only and the WHERE is indexed on
    // dinner_events.host_id + reviews.event_id.
    await client.query(
      `UPDATE users
       SET review_count = sub.cnt,
           rating = sub.avg_rating
       FROM (
         SELECT COUNT(*)::int AS cnt,
                COALESCE(ROUND(AVG(rv.rating)::numeric, 2), 0) AS avg_rating
         FROM reviews rv
         JOIN dinner_events e ON e.id = rv.event_id
         WHERE e.host_id = $1
       ) sub
       WHERE id = $1::UUID`,
      [event.host_id],
    );

    const authorResult = await client.query<{ name: string }>(
      'SELECT name FROM users WHERE id = $1::UUID',
      [req.userId],
    );
    const author = authorResult.rows[0];
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1, 'review', $2, $3, $4, true)`,
      [
        event.host_id,
        `New review for ${event.title}`,
        `"${text.length > 80 ? `${text.slice(0, 77)}...` : text}": ${author?.name ?? 'A guest'}`,
        eventId,
      ],
    );
  });

  res.status(201).json({
    review: {
      eventId,
      eventTitle: event.title,
      rating,
      text,
      createdAt: new Date().toISOString(),
      authorId: req.userId,
    },
  });
});

export default router;
