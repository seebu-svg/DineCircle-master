import type pg from 'pg';

import { query } from './db.js';

/**
 * Who is told about a proposal or an approval decision.
 *
 * The venue side used to notify `restaurants.owner_id` only. On this database
 * every verified venue still points at one seeded operator account, while the
 * real partner accounts exist as `restaurant_staff` rows, so proposals landed
 * in an inbox nobody could sign in to. Everything venue-facing now resolves its
 * audience through `venueRecipients()` instead.
 *
 * Both helpers accept an optional transaction client so a state change and the
 * notification that announces it commit together; pass `null` to run outside a
 * transaction.
 */
type Executor = Pick<pg.PoolClient, 'query'>;

async function rows<T extends pg.QueryResultRow>(
  db: Executor | null,
  text: string,
  params: readonly unknown[],
): Promise<T[]> {
  if (db) {
    const result = await db.query<T>(text, params as unknown[]);
    return result.rows;
  }
  return query<T>(text, params);
}

/**
 * Every account that should hear from this venue: active staff (owner, manager
 * or staff) plus the legacy `restaurants.owner_id` column, de-duplicated so a
 * staff member who is also the owner is notified once.
 */
export async function venueRecipients(
  restaurantId: string,
  db: Executor | null = null,
): Promise<string[]> {
  const found = await rows<{ user_id: string }>(
    db,
    `SELECT DISTINCT user_id FROM (
       SELECT s.user_id
         FROM restaurant_staff s
        WHERE s.restaurant_id = $1::UUID AND s.status = 'active'
       UNION
       SELECT r.owner_id
         FROM restaurants r
        WHERE r.id = $1::UUID AND r.owner_id IS NOT NULL
     ) recipients`,
    [restaurantId],
  );
  return found.map((r) => r.user_id);
}

export type NoticeKind = 'collab' | 'approval' | 'promotion' | 'reminder';

/**
 * Announce something to a venue: one row in the venue-scoped `notifications`
 * table (what the Partner App inbox reads) plus one `activity` row per
 * recipient (what the customer app's "Alerts" screen reads).
 */
export async function notifyVenue(
  db: Executor | null,
  restaurantId: string,
  notice: {
    title: string;
    body: string;
    kind?: NoticeKind;
    eventId?: string | null;
  },
): Promise<void> {
  const kind: NoticeKind = notice.kind ?? 'collab';
  const eventId = notice.eventId ?? null;

  await rows(
    db,
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, $2, $3, 'event', false)`,
    [restaurantId, notice.title, notice.body],
  );

  for (const userId of await venueRecipients(restaurantId, db)) {
    await rows(
      db,
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1::UUID, $2, $3, $4, $5::UUID, true)`,
      [userId, kind, notice.title, notice.body, eventId],
    );
  }
}

/**
 * Announce something to one person's own activity feed (the host side of a
 * decision, or a partner answering a proposal addressed to them).
 */
export async function notifyUser(
  db: Executor | null,
  userId: string,
  notice: {
    title: string;
    body: string;
    kind?: NoticeKind;
    eventId?: string | null;
  },
): Promise<void> {
  await rows(
    db,
    `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
     VALUES ($1::UUID, $2, $3, $4, $5::UUID, true)`,
    [userId, notice.kind ?? 'collab', notice.title, notice.body, notice.eventId ?? null],
  );
}
