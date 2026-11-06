import { Router } from 'express';
import { query, withTransaction } from '../db.js';
import { notFound, forbidden } from '../context.js';
import { serializeRestaurant, type RestaurantRow } from './restaurants.js';

const router = Router();

type ActivityRow = {
  id: string;
  kind: string;
  title: string;
  body: string;
  actor_id: string | null;
  event_id: string | null;
  amount: string | null;
  is_unread: boolean;
  created_at: Date;
  actor_name: string | null;
  actor_handle: string | null;
  actor_avatar: string | null;
};

const ACTIVITY_SELECT = `
  SELECT a.*, u.name AS actor_name, u.handle AS actor_handle,
         u.avatar_url AS actor_avatar
  FROM activity a
  LEFT JOIN users u ON u.id = a.actor_id`;

// GET /api/activity — the signed-in user's feed, newest first.
router.get('/activity', async (req, res) => {
  const rows = await query<ActivityRow>(
    `${ACTIVITY_SELECT}
     WHERE a.actor_id = $1
     ORDER BY a.created_at DESC
     LIMIT 100`,
    [req.userId],
  );

  res.json({
    activity: rows.map((a) => ({
      id: a.id,
      kind: a.kind,
      title: a.title,
      body: a.body,
      eventId: a.event_id,
      amount: a.amount === null ? null : Number(a.amount),
      isUnread: a.is_unread,
      createdAt: a.created_at,
      actor: a.actor_id === null ? null : {
        id: a.actor_id,
        name: a.actor_name,
        handle: a.actor_handle,
        avatarUrl: a.actor_avatar,
      },
    })),
    unreadCount: rows.filter((a) => a.is_unread).length,
  });
});

// POST /api/activity/read — marks every item as read.
router.post('/activity/read', async (req, res) => {
  await query(
    'UPDATE activity SET is_unread = false WHERE actor_id = $1',
    [req.userId],
  );
  res.json({ read: true });
});

// GET /api/users/me/notifications — unified alerts surface.
//
// Computed on read (no cron, no new table). Unions three sources:
//   1. Activity rows for the user (existing feed)
//   2. Reminders synthesized from confirmed bookings whose event starts
//      within the next 24 hours
//   3. Offers synthesized from active promo_codes for venues the user follows
// Each item: { id, kind, title, body, createdAt, isRead, eventId? }.
// Synthesized items get deterministic ids so the client can key lists.
router.get('/users/me/notifications', async (req, res) => {
  // 1. Activity rows (existing feed)
  const activityRows = await query<ActivityRow>(
    `${ACTIVITY_SELECT}
     WHERE a.actor_id = $1
     ORDER BY a.created_at DESC
     LIMIT 50`,
    [req.userId],
  );
  const activityItems = activityRows.map((a) => ({
    id: a.id,
    kind: 'activity' as const,
    title: a.title,
    body: a.body,
    createdAt: a.created_at,
    isRead: !a.is_unread,
    eventId: a.event_id,
    actor: a.actor_id === null ? null : {
      id: a.actor_id,
      name: a.actor_name,
      handle: a.actor_handle,
      avatarUrl: a.actor_avatar,
    },
  }));

  // 2. Reminders: confirmed bookings starting within 24 hours
  const reminderRows = await query<{
    booking_id: string;
    event_id: string;
    event_title: string;
    restaurant_name: string;
    start_at: Date;
  }>(
    `SELECT b.id AS booking_id, e.id AS event_id, e.title AS event_title,
            r.name AS restaurant_name, e.start_at
     FROM bookings b
     JOIN dinner_events e ON e.id = b.event_id
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE b.user_id = $1::UUID
       AND b.status = 'confirmed'
       AND e.start_at BETWEEN now() AND now() + interval '24 hours'
     ORDER BY e.start_at ASC`,
    [req.userId],
  );
  const reminderItems = reminderRows.map((r) => ({
    id: `reminder:${r.booking_id}`,
    kind: 'reminder' as const,
    title: `Upcoming: ${r.event_title}`,
    body: `Your table at ${r.restaurant_name} starts soon.`,
    createdAt: new Date(r.start_at.getTime() - 2 * 3600_000),
    isRead: true,
    eventId: r.event_id,
    actor: null,
  }));

  // Merge all sources, newest first, cap at 100.
  const all = [...activityItems, ...reminderItems]
    .sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime())
    .slice(0, 100);

  res.json({
    notifications: all,
    unreadCount: all.filter((n) => !n.isRead).length,
  });
});

// -- Saved events -----------------------------------------------------------

type SavedEventRow = {
  id: string;
  title: string;
  tagline: string;
  start_at: Date;
  cover_image: string;
  seats_total: number;
  seats_booked: number;
  price_per_seat: string;
  type: string;
  host_name: string | null;
};

// GET /api/me/saved — events the user bookmarked.
router.get('/me/saved', async (req, res) => {
  const rows = await query<SavedEventRow>(
    `SELECT e.id, e.title, e.tagline, e.start_at, e.cover_image,
            e.seats_total, e.seats_booked, e.price_per_seat, e.type,
            u.name AS host_name
     FROM saved_events s
     JOIN dinner_events e ON e.id = s.event_id
     LEFT JOIN users u ON u.id = e.host_id
     WHERE s.user_id = $1
     ORDER BY e.start_at ASC`,
    [req.userId],
  );

  res.json({
    saved: rows.map((e) => ({
      id: e.id,
      title: e.title,
      tagline: e.tagline,
      startAt: e.start_at,
      coverImage: e.cover_image,
      seatsTotal: e.seats_total,
      seatsBooked: e.seats_booked,
      seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
      pricePerSeat: Number(e.price_per_seat),
      type: e.type,
      hostName: e.host_name,
    })),
  });
});

// GET /api/me/followed-restaurants — venues the user saved from a restaurant
// profile or the Explore feed. Serialized with the same helper the venue feeds
// use, so a saved card renders identically wherever it appears.
router.get('/me/followed-restaurants', async (req, res) => {
  const rows = await query<RestaurantRow>(
    `SELECT r.*, TRUE AS is_following
       FROM venue_follows vf
       JOIN restaurants r ON r.id = vf.restaurant_id
      WHERE vf.user_id = $1::UUID
      ORDER BY vf.created_at DESC`,
    [req.userId],
  );
  res.json({ restaurants: rows.map(serializeRestaurant), count: rows.length });
});

// POST /api/events/:id/save — bookmark an event.
router.post('/events/:id/save', async (req, res) => {
  const [event] = await query<{ id: string }>(
    'SELECT id FROM dinner_events WHERE id = $1::UUID',
    [req.params.id],
  );
  if (!event) throw notFound('Event');

  await query(
    `INSERT INTO saved_events (user_id, event_id) VALUES ($1, $2)
     ON CONFLICT DO NOTHING`,
    [req.userId, req.params.id],
  );
  res.status(201).json({ saved: true, eventId: req.params.id });
});

// DELETE /api/events/:id/save — unbookmark.
router.delete('/events/:id/save', async (req, res) => {
  await query(
    'DELETE FROM saved_events WHERE user_id = $1 AND event_id = $2',
    [req.userId, req.params.id],
  );
  res.json({ saved: false, eventId: req.params.id });
});

// -- Blocking (P2-1) ----------------------------------------------------------

// POST /api/users/:id/block — block a user and sever the follow graph.
// Idempotent by design: the composite PK means a duplicate block changes
// nothing (still 200), and the whole operation runs in ONE transaction so a
// half-applied block can never leave a follower counting against a blocked
// host. Unblocking later does NOT restore these follows — that is deliberate.
router.post('/users/:id/block', async (req, res) => {
  const [target] = await query<{ id: string; name: string }>(
    'SELECT id, name FROM users WHERE id = $1::UUID AND is_deleted = false',
    [req.params.id],
  );
  if (!target) throw notFound('User');
  if (target.id === req.userId) {
    throw forbidden('You cannot block yourself');
  }

  const removedFollows = await withTransaction(async (client) => {
    await client.query(
      `INSERT INTO user_blocks (blocker_id, blocked_id)
       VALUES ($1::UUID, $2::UUID)
       ON CONFLICT DO NOTHING`,
      [req.userId, target.id],
    );
    const { rows } = await client.query<{
      follower_id: string;
      followee_id: string;
    }>(
      `DELETE FROM follows
       WHERE (follower_id = $1::UUID AND followee_id = $2::UUID)
          OR (follower_id = $2::UUID AND followee_id = $1::UUID)
       RETURNING follower_id, followee_id`,
      [req.userId, target.id],
    );
    for (const row of rows) {
      await client.query(
        'UPDATE users SET following_count = GREATEST(0, following_count - 1) WHERE id = $1::UUID',
        [row.follower_id],
      );
      await client.query(
        'UPDATE users SET followers_count = GREATEST(0, followers_count - 1) WHERE id = $1::UUID',
        [row.followee_id],
      );
    }
    return rows.length;
  });

  res.json({ blocked: true, userId: target.id, removedFollows });
});

// DELETE /api/users/:id/block — unblock. Deliberately does NOT restore the
// follows removed at block time (re-following must be a fresh, mutual choice),
// and existing chat threads/bookings stay exactly as they are.
router.delete('/users/:id/block', async (req, res) => {
  await query(
    'DELETE FROM user_blocks WHERE blocker_id = $1::UUID AND blocked_id = $2::UUID',
    [req.userId, req.params.id],
  );
  res.json({ blocked: false, userId: req.params.id });
});

// GET /api/users/me/blocked — the caller's own block list (Settings → Privacy
// → Blocked Users). Only ever the acting user's list; there is no endpoint
// that reveals who a third party has blocked.
router.get('/users/me/blocked', async (req, res) => {
  const rows = await query<{
    id: string;
    name: string;
    handle: string;
    avatar_url: string | null;
    role: string;
    blocked_at: Date;
  }>(
    `SELECT u.id, u.name, u.handle, u.avatar_url, u.role, b.created_at AS blocked_at
     FROM user_blocks b
     JOIN users u ON u.id = b.blocked_id
     WHERE b.blocker_id = $1::UUID
     ORDER BY b.created_at DESC
     LIMIT 100`,
    [req.userId],
  );

  res.json({
    blocked: rows.map((u) => ({
      id: u.id,
      name: u.name,
      handle: u.handle,
      avatarUrl: u.avatar_url,
      role: u.role,
      blockedAt: u.blocked_at,
    })),
    count: rows.length,
  });
});

export default router;
