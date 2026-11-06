import { Router } from 'express';
import { z } from 'zod';
import type pg from 'pg';
import { query, withTransaction } from '../db.js';
import { ApiError, notFound, forbidden } from '../context.js';
import { isBlockedPair } from '../blocks.js';

const router = Router();

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Human-readable booking reference, e.g. `DC-7K3MQ`. */
function makeReference(): string {
  let code = '';
  for (let i = 0; i < 5; i++) {
    code += ALPHABET[Math.floor(Math.random() * ALPHABET.length)] ?? 'X';
  }
  return `DC-${code}`;
}

type BookingRow = {
  id: string;
  event_id: string;
  user_id: string;
  seats: number;
  price_per_seat: string;
  total_amount: string;
  created_at: Date;
  reference: string;
  payment_label: string;
  payment_status: string;
  status: string;
  checked_in: boolean;
  title: string;
  start_at: Date;
  cover_image: string;
  host_name: string | null;
  restaurant_name: string | null;
};

const BOOKING_SELECT = `
  SELECT b.*, e.title, e.start_at, e.cover_image,
         u.name AS host_name, r.name AS restaurant_name
  FROM bookings b
  JOIN dinner_events e ON e.id = b.event_id
  LEFT JOIN users u ON u.id = e.host_id
  LEFT JOIN restaurants r ON r.id = e.restaurant_id`;

function serialize(row: BookingRow) {
  return {
    id: row.id,
    eventId: row.event_id,
    eventTitle: row.title,
    eventCoverImage: row.cover_image,
    hostName: row.host_name,
    restaurantName: row.restaurant_name,
    userId: row.user_id,
    seats: row.seats,
    pricePerSeat: Number(row.price_per_seat),
    total: Number(row.total_amount),
    reference: row.reference,
    paymentLabel: row.payment_label,
    paymentStatus: row.payment_status,
    status: row.status,
    checkedIn: row.checked_in,
    createdAt: row.created_at,
    startAt: row.start_at,
    isUpcoming: new Date(row.start_at).getTime() > Date.now(),
  };
}

// GET /api/bookings — one user's tickets (My Tables). Always the acting
// user; `?eventId=` returns a host's guest list for one event. (The former
// `?userId=` override was a horizontal-authorization gap and is removed.)
router.get('/bookings', async (req, res) => {
  const userId = req.userId;
  const eventId =
    typeof req.query.eventId === 'string' && req.query.eventId.trim() !== ''
      ? req.query.eventId.trim()
      : null;

  if (eventId !== null) {
    const [event] = await query<{ host_id: string }>(
      'SELECT host_id FROM dinner_events WHERE id = $1::UUID',
      [eventId],
    );
    if (!event) throw notFound('Event');
    if (event.host_id !== req.userId) {
      throw forbidden('Only the host can see this guest list');
    }
    const guests = await query<BookingRow>(
      `${BOOKING_SELECT} WHERE b.event_id = $1::UUID ORDER BY b.created_at ASC`,
      [eventId],
    );
    res.json({ bookings: guests.map(serialize), count: guests.length });
    return;
  }

  const [guest] = await query<{ id: string }>(
    'SELECT id FROM users WHERE id = $1::UUID',
    [userId],
  );
  if (!guest) throw notFound('Guest');

  const rows = await query<BookingRow>(
    `${BOOKING_SELECT} WHERE b.user_id = $1::UUID ORDER BY e.start_at ASC`,
    [userId],
  );
  const all = rows.map(serialize);
  res.json({
    bookings: all,
    upcoming: all.filter((b) => b.isUpcoming && b.status !== 'cancelled'),
    past: all.filter((b) => !b.isUpcoming),
    cancelled: all.filter((b) => b.status === 'cancelled'),
    count: all.length,
  });
});

const createBookingSchema = z.object({
  seats: z.coerce.number().int().min(1).max(10).default(1),
  // Guests settle with the venue directly, so a booking that carries no
  // method from the client must not be labelled with a card brand nobody used.
  paymentLabel: z.string().trim().min(1).max(40).default('Pay at venue'),
  promoCode: z.string().trim().max(24).optional(),
});

type EventLockRow = {
  id: string;
  title: string;
  start_at: Date;
  seats_total: number;
  seats_booked: number;
  price_per_seat: string;
  audience: string;
  host_id: string;
  attendee_ids: string[];
  requires_approval: boolean;
  status: string;
};

// POST /api/events/:id/bookings — join & pay. The event row is locked with
// FOR UPDATE inside a single transaction so two guests can never oversell
// the last seat.
router.post('/events/:id/bookings', async (req, res) => {
  const input = createBookingSchema.parse(req.body ?? {});
  const eventId = req.params.id;
  const userId = req.userId;

  const [guest] = await query<{ id: string }>(
    'SELECT id FROM users WHERE id = $1::UUID',
    [userId],
  );
  if (!guest) throw new ApiError(422, `Unknown guest ${userId}`);

  // P2-1: blocked pairs cannot join NEW tables hosted by the other side, in
  // either direction. Bookings that already exist are never touched here —
  // they stay on record and follow the normal cancel/support path.
  const [hostRow] = await query<{ host_id: string }>(
    'SELECT host_id FROM dinner_events WHERE id = $1::UUID',
    [eventId],
  );
  if (hostRow && hostRow.host_id !== userId) {
    if (await isBlockedPair(userId, hostRow.host_id)) {
      throw forbidden('You cannot join this event');
    }
  }

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<EventLockRow>(
      `SELECT id, title, start_at, seats_total, seats_booked, price_per_seat,
              audience, host_id, attendee_ids, requires_approval, status
       FROM dinner_events WHERE id = $1::UUID FOR UPDATE`,
      [eventId],
    );
    const event = rows[0];
    // Drafts, venue-pending requests and venue-declined events are not bookable
    // — treat them as unknown to guests so the venue's decision cannot be
    // bypassed by holding a stale event id.
    if (!event || ['draft', 'requested', 'declined'].includes(event.status)) {
      throw notFound('Event');
    }

    if (event.audience === 'followers' && event.host_id !== userId) {
      const { rows: followsHost } = await client.query(
        'SELECT 1 FROM follows WHERE follower_id = $1 AND followee_id = $2',
        [userId, event.host_id],
      );
      if (followsHost.length === 0) {
        throw forbidden("This event is only for the host's followers");
      }
    }
    if (
      event.audience === 'inviteOnly' &&
      event.host_id !== userId &&
      !event.attendee_ids.includes(userId)
    ) {
      throw forbidden('This event is invite-only');
    }

    if (new Date(event.start_at).getTime() <= Date.now()) {
      throw new ApiError(409, 'This event has already started');
    }
    const seatsLeft = event.seats_total - event.seats_booked;
    if (seatsLeft < input.seats) {
      throw new ApiError(
        409,
        seatsLeft === 0
          ? 'This event is sold out'
          : `Only ${seatsLeft} seat(s) left`,
      );
    }

    const { rows: duplicates } = await client.query(
      `SELECT id FROM bookings
       WHERE event_id = $1 AND user_id = $2
         AND status IN ('confirmed', 'pending')`,
      [eventId, userId],
    );
    if (duplicates.length > 0) {
      throw new ApiError(
        409,
        'You already hold a seat request at this event',
      );
    }

    const totalAmount = input.seats * Number(event.price_per_seat);

    // Promo codes are validated server-side — the client never decides
    // whether a discount applies.
    let discount = 0;
    if (input.promoCode) {
      const promoRes = await client.query<{ discount_pct: string; active: boolean }>(
        'SELECT discount_pct, active FROM promo_codes WHERE code = $1',
        [input.promoCode.toUpperCase()],
      );
      const promo = promoRes.rows[0];
      if (!promo || !promo.active) {
        throw new ApiError(400, 'That promo code is not valid.');
      }
      discount = Math.round(
        (totalAmount * Number(promo.discount_pct)) / 100 * 100,
      ) / 100;
    }
    const finalAmount = Math.max(0, totalAmount - discount);

    // Phase 2a (D2): Stripe removed. All bookings settle immediately as
    // `paid`. Host-gated events still use `pending`/`authorized` for the
    // approval flow, but no payment gateway is involved.
    const initialStatus = event.requires_approval ? 'pending' : 'confirmed';
    const initialPayment = event.requires_approval ? 'authorized' : 'paid';
    const storedLabel = input.paymentLabel;

    const { rows: insertedRows } = await client.query<{
      id: string; event_id: string; user_id: string; seats: number;
      price_per_seat: string; total_amount: string; reference: string;
      payment_label: string; payment_status: string; status: string; created_at: Date;
    }>(
      `INSERT INTO bookings (event_id, user_id, seats, price_per_seat,
                             total_amount, reference, payment_label, status,
                             payment_status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING id, event_id, user_id, seats, price_per_seat, total_amount,
                 reference, payment_label, payment_status, status, created_at`,
      [
        eventId,
        userId,
        input.seats,
        event.price_per_seat,
        finalAmount,
        makeReference(),
        storedLabel,
        initialStatus,
        initialPayment,
      ],
    );
    const booking = insertedRows[0];
    if (!booking) throw new ApiError(500, 'Booking insert failed');

    const { rows: updated } = await client.query<{ seats_booked: number }>(
      `UPDATE dinner_events
         SET seats_booked = seats_booked + $2,
             attendee_ids = CASE WHEN $3 = ANY(attendee_ids)
                                 THEN attendee_ids
                                 ELSE array_append(attendee_ids, $3) END
       WHERE id = $1::UUID
       RETURNING seats_booked`,
      [eventId, input.seats, userId],
    );

    // Tell the host someone joined (actor_id = host so it appears in their feed).
    if (event.host_id && event.host_id !== userId) {
      await client.query(
        `INSERT INTO activity (actor_id, kind, title, body, event_id, amount, is_unread)
         VALUES ($1, 'newGuest', $2, $3, $4, $5, true)`,
        [
          event.host_id,
          input.seats === 1
            ? 'A new guest joined your event'
            : `${input.seats} new guests joined your event`,
          `${event.title} just sold ${input.seats} more ${input.seats === 1 ? 'seat' : 'seats'}.`,
          eventId,
          input.seats * Number(event.price_per_seat),
        ],
      );
    }

    // Add the guest to the event's conversation (if one exists yet, the
    // lazy ensureEventConversation in chat.ts will create it on first message).
    await client.query(
      `INSERT INTO conversation_participants (conversation_id, user_id, role)
       SELECT c.id, $2::UUID, 'member'
       FROM conversations c
       WHERE c.event_id = $1::UUID
       ON CONFLICT (conversation_id, user_id) DO NOTHING`,
      [eventId, userId],
    );

    return {
      booking,
      discount,
      finalAmount,
      requiresApproval: event.requires_approval,
      seatsBooked: updated[0]?.seats_booked ?? event.seats_booked + input.seats,
      seatsTotal: event.seats_total,
    };
  });

  const pricePerSeat = Number(result.booking.price_per_seat);
  res.status(201).json({
    booking: {
      id: result.booking.id,
      eventId: result.booking.event_id,
      userId: result.booking.user_id,
      seats: result.booking.seats,
      pricePerSeat,
      total: Number(result.booking.total_amount),
      discount: result.discount,
      reference: result.booking.reference,
      paymentLabel: result.booking.payment_label,
      paymentStatus: result.booking.payment_status,
      status: result.booking.status,
      createdAt: result.booking.created_at,
    },
    event: {
      id: eventId,
      seatsBooked: result.seatsBooked,
      seatsTotal: result.seatsTotal,
      seatsLeft: result.seatsTotal - result.seatsBooked,
    },
  });
});

type CancelRow = {
  id: string;
  event_id: string;
  user_id: string;
  seats: number;
  price_per_seat: string;
  total_amount: string;
  payment_label: string;
  status: string;
  payment_status: string;
};

// POST /api/bookings/:id/cancel — release the seats and mark the booking cancelled.
router.post('/bookings/:id/cancel', async (req, res) => {
  const bookingId = req.params.id;

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<CancelRow & { cancellation: string }>(
      `SELECT b.id, b.event_id, b.user_id, b.seats, b.price_per_seat,
              b.total_amount, b.payment_label, b.status, b.payment_status,
              e.cancellation
       FROM bookings b
       JOIN dinner_events e ON e.id = b.event_id
       WHERE b.id = $1::UUID
       FOR UPDATE OF b`,
      [bookingId],
    );
    const booking = rows[0];
    if (!booking) throw notFound('Booking');
    if (booking.user_id !== req.userId) {
      throw new ApiError(403, 'This booking belongs to another guest');
    }
    if (booking.status === 'cancelled') {
      throw new ApiError(409, 'This booking is already cancelled');
    }
    if (booking.status === 'completed') {
      throw new ApiError(409, 'Completed bookings cannot be cancelled');
    }

    const { rows: cancelledRows } = await client.query<CancelRow>(
      `UPDATE bookings
          SET status = 'cancelled',
              checked_in = false,
              payment_status = CASE WHEN payment_status IN ('paid', 'authorized')
                                    THEN 'refunded' ELSE payment_status END
        WHERE id = $1::UUID
        RETURNING id, event_id, user_id, seats, price_per_seat, total_amount,
                  payment_label, status, payment_status`,
      [bookingId],
    );
    const cancelled = cancelledRows[0];
    if (!cancelled) throw new ApiError(500, 'Cancel failed');

    const { rows: released } = await client.query<{ seats_booked: number }>(
      `UPDATE dinner_events
         SET seats_booked = GREATEST(0, seats_booked - $2),
             attendee_ids = array_remove(attendee_ids, $3::text)
       WHERE id = $1::UUID
       RETURNING seats_booked`,
      [cancelled.event_id, cancelled.seats, cancelled.user_id],
    );

    return {
      cancelled,
      seatsBooked: released[0]?.seats_booked ?? 0,
    };
  });

  res.json({
    booking: {
      id: result.cancelled.id,
      eventId: result.cancelled.event_id,
      userId: result.cancelled.user_id,
      seats: result.cancelled.seats,
      status: result.cancelled.status,
    },
    event: {
      id: result.cancelled.event_id,
      seatsBooked: result.seatsBooked,
    },
  });
});

// ── Host request approval ────────────────────────────────────────────────────
// A booking on a `requires_approval` event is parked as `pending`. These two
// routes let the event's host confirm (capture) or decline (refund + release
// the held seat) the request. Both lock the parent event so the seat count can
// never drift.

type RequestRow = {
  id: string;
  event_id: string;
  user_id: string;
  seats: number;
  status: string;
  payment_status: string;
  total_amount: string;
  title: string;
  host_id: string;
};

const REQUEST_SELECT = `
  SELECT b.id, b.event_id, b.user_id, b.seats, b.status, b.payment_status,
         b.total_amount, e.title, e.host_id
  FROM bookings b
  JOIN dinner_events e ON e.id = b.event_id
  WHERE b.id = $1::UUID`;

async function loadPendingRequest(
  client: pg.PoolClient,
  bookingId: string,
  hostId: string,
): Promise<RequestRow> {
  const { rows } = await client.query<RequestRow>(
    `${REQUEST_SELECT} FOR UPDATE OF b`,
    [bookingId],
  );
  const booking = rows[0];
  if (!booking) throw notFound('Booking');
  if (booking.host_id !== hostId) {
    throw forbidden('Only the host can manage this request');
  }
  if (booking.status !== 'pending') {
    throw new ApiError(409, 'This request is no longer pending');
  }
  return booking;
}

// POST /api/bookings/:id/approve — the host confirms a pending seat request.
router.post('/bookings/:id/approve', async (req, res) => {
  const bookingId = req.params.id;

  const { eventId, guestUserId } = await withTransaction(async (client) => {
    const booking = await loadPendingRequest(client, bookingId, req.userId);

    await client.query(
      `UPDATE bookings SET status = 'confirmed', payment_status = 'paid'
       WHERE id = $1::UUID`,
      [bookingId],
    );
    await client.query(
      `UPDATE dinner_events
         SET attendee_ids = CASE WHEN $2 = ANY(attendee_ids)
                                  THEN attendee_ids
                                  ELSE array_append(attendee_ids, $2) END
       WHERE id = $1::UUID`,
      [booking.event_id, booking.user_id],
    );
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1, 'newGuest', $2, $3, $4, true)`,
      [
        booking.user_id,
        'Your seat request was approved',
        `The host confirmed your seat at ${booking.title}. See you there!`,
        booking.event_id,
      ],
    );
    return { eventId: booking.event_id, guestUserId: booking.user_id };
  });

  const [full] = await query<BookingRow>(
    `${BOOKING_SELECT} WHERE b.id = $1::UUID`,
    [bookingId],
  );
  if (!full) throw notFound('Booking');
  res.json({ booking: serialize(full), eventId, guestUserId });
});

// POST /api/bookings/:id/decline — the host rejects a pending seat request,
// releasing the held seat.
router.post('/bookings/:id/decline', async (req, res) => {
  const bookingId = req.params.id;

  const result = await withTransaction(async (client) => {
    const booking = await loadPendingRequest(client, bookingId, req.userId);

    await client.query(
      `UPDATE bookings
         SET status = 'cancelled', payment_status = 'refunded', checked_in = false
       WHERE id = $1::UUID`,
      [bookingId],
    );
    const { rows: released } = await client.query<{ seats_booked: number }>(
      `UPDATE dinner_events
         SET seats_booked = GREATEST(0, seats_booked - $2)
       WHERE id = $1::UUID
       RETURNING seats_booked`,
      [booking.event_id, booking.seats],
    );
    await client.query(
      `UPDATE dinner_events
         SET attendee_ids = array_remove(attendee_ids, $2::text)
       WHERE id = $1::UUID
         AND NOT EXISTS (
           SELECT 1 FROM bookings b2
           WHERE b2.event_id = $1 AND b2.user_id = $2::UUID
             AND b2.status <> 'cancelled')`,
      [booking.event_id, booking.user_id],
    );
    await client.query(
      `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
       VALUES ($1, 'reminder', $2, $3, $4, true)`,
      [
        booking.user_id,
        'Your seat request was declined',
        `The host declined your request for ${booking.title}. Your hold was released.`,
        booking.event_id,
      ],
    );
    return {
      seatsBooked: released[0]?.seats_booked ?? 0,
      guestUserId: booking.user_id,
    };
  });

  const [full] = await query<BookingRow>(
    `${BOOKING_SELECT} WHERE b.id = $1::UUID`,
    [bookingId],
  );
  if (!full) throw notFound('Booking');
  res.json({
    booking: serialize(full),
    event: { id: full.event_id, seatsBooked: result.seatsBooked },
    guestUserId: result.guestUserId,
  });
});

// POST /api/bookings/:id/checkin — mark a ticket used and settle attendance.
// A valid check-in finalises the booking: `confirmed`/`pending` → `completed`.
// This unlocks the post-dinner review flow. Runs under a row lock so a
// double-tap can never settle the same ticket twice.
router.post('/bookings/:id/checkin', async (req, res) => {
  const bookingId = req.params.id;

  const settled = await withTransaction(async (client) => {
    const { rows } = await client.query<{
      id: string; event_id: string; user_id: string; host_id: string;
      status: string; checked_in: boolean; seats: number;
    }>(
      `SELECT b.id, b.event_id, b.user_id, b.status, b.checked_in, b.seats,
              e.host_id
       FROM bookings b JOIN dinner_events e ON e.id = b.event_id
       WHERE b.id = $1::UUID
       FOR UPDATE OF b`,
      [bookingId],
    );
    const row = rows[0];
    if (!row) throw notFound('Booking');
    if (row.user_id !== req.userId && row.host_id !== req.userId) {
      throw forbidden('Only the guest or the host can check in');
    }
    if (row.status === 'cancelled') {
      throw new ApiError(409, 'Cancelled bookings cannot be checked in');
    }
    if (row.checked_in) {
      throw new ApiError(409, 'Already checked in');
    }

    const updated = await client.query<{ status: string }>(
      `UPDATE bookings
         SET checked_in = true,
             checked_in_at = now(),
             status = 'completed',
             payment_status = 'paid'
       WHERE id = $1::UUID
       RETURNING status`,
      [bookingId],
    );

    return {
      row,
      status: updated.rows[0]?.status ?? 'completed',
    };
  });

  res.json({
    booking: {
      id: settled.row.id,
      eventId: settled.row.event_id,
      userId: settled.row.user_id,
      seats: settled.row.seats,
      status: settled.status,
      checkedIn: true,
    },
  });
});

export default router;
