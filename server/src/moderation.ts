import { query, withTransaction } from './db.js';
import { ApiError, notFound } from './context.js';
import { notifyUser } from './notify.js';

/**
 * One implementation per moderation effect.
 *
 * The admin console exposes every one of these as a direct action on its own
 * route, and `POST /api/admin/reports/:id/resolve` offers the same set as its
 * `action` picker. If the report path wrote its own SQL, the two would drift
 * within a release: a venue suspended from a report case would keep accepting
 * bookings while one suspended from the venue table did not. So both surfaces
 * call the functions here and nothing else touches these columns.
 *
 * Venue suspension deliberately drives `accepting_bookings=false` in addition
 * to the new `moderation_status`, because discovery already filters on that
 * boolean (`routes/restaurants.ts`). That is what lets the console pull a venue
 * offline without any change to the shipped Customer App queries.
 */

export type ModerationState = 'clean' | 'flagged' | 'removed';

/** Allowlisted targets for the generic content moderation write. */
const MODERATION_TABLES: Record<string, string> = {
  deal: 'restaurant_deals',
  experience: 'dinner_events',
  review: 'reviews',
  image: 'venue_images',
  menu_item: 'restaurant_menu_items',
};

export type ModerationKind = keyof typeof MODERATION_TABLES;

export function isModerationKind(value: string): value is ModerationKind {
  return Object.prototype.hasOwnProperty.call(MODERATION_TABLES, value);
}

type Executor = Pick<import('pg').PoolClient, 'query'>;

async function run(db: Executor | null, text: string, params: unknown[]) {
  if (db) {
    const result = await db.query(text, params);
    return result.rows;
  }
  return query(text, params);
}

/** Take a venue offline: hidden from discovery, flagged in the venue row. */
export async function suspendVenue(input: {
  restaurantId: string;
  note: string;
  actorId: string;
}): Promise<{ restaurantId: string; moderationStatus: 'suspended' }> {
  const [venue] = await query<{ id: string; name: string }>(
    `UPDATE restaurants
        SET moderation_status = 'suspended',
            moderation_note = $2,
            moderated_by = $3::UUID,
            moderated_at = now(),
            accepting_bookings = false
      WHERE id = $1::UUID
      RETURNING id, name`,
    [input.restaurantId, input.note.slice(0, 1000), input.actorId],
  );
  if (!venue) throw notFound('Restaurant');
  return { restaurantId: venue.id, moderationStatus: 'suspended' };
}

/** Put a venue back online. Bookings resume, moderation note is cleared. */
export async function restoreVenue(input: {
  restaurantId: string;
  note?: string;
  actorId: string;
}): Promise<{ restaurantId: string; moderationStatus: 'active' }> {
  const [venue] = await query<{ id: string }>(
    `UPDATE restaurants
        SET moderation_status = 'active',
            moderation_note = $2,
            moderated_by = $3::UUID,
            moderated_at = now(),
            accepting_bookings = true
      WHERE id = $1::UUID
      RETURNING id`,
    [input.restaurantId, (input.note ?? '').slice(0, 1000), input.actorId],
  );
  if (!venue) throw notFound('Restaurant');
  return { restaurantId: venue.id, moderationStatus: 'active' };
}

/**
 * The accepting-bookings switch on its own. Partners use it for a private
 * dinner night; the console uses it to pause a venue without a moderation
 * verdict, so it never writes `moderation_status`.
 */
export async function setVenueBookings(input: {
  restaurantId: string;
  value: boolean;
}): Promise<{ restaurantId: string; acceptingBookings: boolean }> {
  const [venue] = await query<{ id: string }>(
    `UPDATE restaurants SET accepting_bookings = $2
      WHERE id = $1::UUID RETURNING id`,
    [input.restaurantId, input.value],
  );
  if (!venue) throw notFound('Restaurant');
  return { restaurantId: venue.id, acceptingBookings: input.value };
}

/** Freeze an account. `requireAuth` rejects the session while this is set. */
export async function suspendUser(input: {
  userId: string;
  reason: string;
}): Promise<{ userId: string; suspendedAt: Date }> {
  const [user] = await query<{ id: string; suspended_at: Date }>(
    `UPDATE users SET suspended_at = now(), suspension_reason = $2
      WHERE id = $1::UUID AND is_deleted = false
      RETURNING id, suspended_at`,
    [input.userId, input.reason.slice(0, 1000)],
  );
  if (!user) throw notFound('User');
  return { userId: user.id, suspendedAt: user.suspended_at };
}

export async function restoreUser(input: {
  userId: string;
}): Promise<{ userId: string }> {
  const [user] = await query<{ id: string }>(
    `UPDATE users SET suspended_at = NULL, suspension_reason = ''
      WHERE id = $1::UUID RETURNING id`,
    [input.userId],
  );
  if (!user) throw notFound('User');
  return { userId: user.id };
}

/**
 * Flag, clear or remove a moderation target. `deal` removal additionally pauses
 * the row, because the deal visibility gate is `status='active'` and a removed
 * deal that is still `active` would keep showing in the Customer App.
 */
export async function setModeration(input: {
  kind: ModerationKind;
  id: string;
  state: ModerationState;
  note?: string;
  actorId?: string;
  db?: Executor | null;
}): Promise<{ id: string; moderationStatus: ModerationState }> {
  const table = MODERATION_TABLES[input.kind];
  if (!table) throw new ApiError(400, 'Unknown moderation target');
  const db = input.db ?? null;

  const rows = await run(
    db,
    `UPDATE ${table}
        SET moderation_status = $2,
            moderation_note = $3
      WHERE id = $1::UUID
      RETURNING id`,
    [input.id, input.state, (input.note ?? '').slice(0, 1000)],
  );
  const target = rows[0] as { id: string } | undefined;
  if (!target) throw notFound('Content');

  if (input.kind === 'deal' && input.state === 'removed') {
    await run(db, `UPDATE restaurant_deals SET status = 'paused' WHERE id = $1::UUID`, [
      input.id,
    ]);
  }

  return { id: target.id, moderationStatus: input.state };
}

/**
 * Cancel an experience and tell every guest holding a seat.
 *
 * Guests are notified through `notifyUser` rather than `notifyVenue` because
 * the `notifications` table is venue-scoped with a NOT NULL restaurant id; the
 * per-person `activity` feed is what the Customer App actually reads.
 */
export async function cancelExperience(input: {
  eventId: string;
  reason: string;
  notifyGuests: boolean;
  actorId?: string;
}): Promise<{
  eventId: string;
  status: 'cancelled';
  guestCount: number;
  hostId: string;
  title: string;
}> {
  return withTransaction(async (client) => {
    const { rows } = await client.query<{
      id: string;
      host_id: string;
      title: string;
      status: string;
    }>(
      `SELECT id, host_id, title, status FROM dinner_events
        WHERE id = $1::UUID FOR UPDATE`,
      [input.eventId],
    );
    const event = rows[0];
    if (!event) throw notFound('Event');
    if (event.status === 'cancelled') {
      throw new ApiError(409, 'This experience is already cancelled');
    }

    await client.query(
      `UPDATE dinner_events
          SET status = 'cancelled', cancelled_at = now(),
              cancelled_by = $2::UUID, cancellation_reason = $3
        WHERE id = $1::UUID`,
      [event.id, input.actorId ?? null, input.reason.slice(0, 1000)],
    );

    const guests = await client.query<{ user_id: string }>(
      `SELECT DISTINCT user_id FROM bookings
        WHERE event_id = $1::UUID AND status <> 'cancelled'`,
      [event.id],
    );

    if (input.notifyGuests) {
      const note = input.reason.trim();
      for (const guest of guests.rows) {
        await notifyUser(client, guest.user_id, {
          title: `${event.title} was cancelled`,
          body: note
            ? `Your host cancelled this experience. ${note}`
            : 'Your host cancelled this experience. Anything you paid is being returned.',
          kind: 'reminder',
          eventId: event.id,
        });
      }
      await notifyUser(client, event.host_id, {
        title: 'Experience cancelled',
        body: `${event.title} was cancelled by the platform team. ${note}`.trim(),
        kind: 'approval',
        eventId: event.id,
      });
    }

    return {
      eventId: event.id,
      status: 'cancelled' as const,
      guestCount: guests.rows.length,
      hostId: event.host_id,
      title: event.title,
    };
  });
}
