import type pg from 'pg';

import { ApiError } from './context.js';

/**
 * Shared experience lifecycle transitions.
 *
 * These live outside `routes/events.ts` because two surfaces drive the same
 * row: the host edits their own experience there, and the venue manages the
 * experiences it hosts under `/api/partner/events/:id`. Keeping the guards in
 * one module is what stops the two from drifting apart again — the partner
 * `PUT` used to accept a raw `status` write that bypassed every one of them.
 */

/**
 * Financial-history guard. Once any payment has been captured (or earnings
 * accrued) the row must stay on the books: cancelling is still allowed, but the
 * trail is never destroyed, and each booking is refunded individually through
 * `POST /bookings/:id/cancel`.
 */
export async function assertNoCapturedMoney(
  client: pg.PoolClient,
  eventId: string,
): Promise<void> {
  const { rows } = await client.query<{ captured: number; accrued: number }>(
    `SELECT
       (SELECT count(*) FROM bookings
         WHERE event_id = $1 AND payment_status = 'paid')::int AS captured,
       (SELECT count(*) FROM payouts
         WHERE event_id = $1 AND seats_sold > 0)::int AS accrued`,
    [eventId],
  );
  if ((rows[0]?.captured ?? 0) > 0 || (rows[0]?.accrued ?? 0) > 0) {
    throw new ApiError(
      409,
      'This event has captured payments or accrued earnings and must stay '
        + 'on the books. Cancel it by refunding each booking individually '
        + 'instead of deleting it.',
    );
  }
}

/**
 * Soft cancel: the row is retained because guest bookings, payouts and the
 * proposal that produced it still reference it. It is delisted, made
 * non-bookable, and every still-active guest is told.
 *
 * Call inside a transaction so the state change and the guest notices commit
 * together.
 */
export async function softCancel(
  client: pg.PoolClient,
  event: { id: string; title: string },
  cancelledBy: string,
  reason: string,
  notice = 'was cancelled by the host.',
): Promise<void> {
  await client.query(
    `UPDATE dinner_events
        SET status = 'cancelled', cancelled_at = now(),
            cancelled_by = $2::UUID, cancellation_reason = $3, updated_at = now()
      WHERE id = $1::UUID`,
    [event.id, cancelledBy, reason],
  );

  const { rows: guests } = await client.query<{ user_id: string }>(
    `SELECT DISTINCT user_id FROM bookings
      WHERE event_id = $1::UUID AND status <> 'cancelled'`,
    [event.id],
  );

  for (const guest of guests) {
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1::UUID, 'reminder', $2, $3, $4::UUID, true)`,
      [
        guest.user_id,
        'An event you booked was cancelled',
        reason
          ? `${event.title} was cancelled: ${reason}`
          : `${event.title} ${notice}`,
        event.id,
      ],
    );
  }
}
