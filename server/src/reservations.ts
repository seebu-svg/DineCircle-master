import type pg from 'pg';
import { query, withTransaction } from './db.js';
import { ApiError, notFound } from './context.js';

/**
 * Table-reservation engine shared by both apps.
 *
 * The Customer App books through `POST /api/restaurants/:id/reservations`; the
 * Partner App reviews, seats and manages the same rows. All availability and
 * capacity maths lives here so the two clients can never disagree about
 * whether a table is free.
 *
 * Concurrency contract: every write happens inside `withTransaction` and takes
 * a `FOR UPDATE` lock on the *venue* row first. That serialises reservation
 * writes per venue, which is what makes "two guests, one last table" resolve
 * deterministically — the second request re-reads the held covers while the
 * first is still uncommitted, so it sees them instead of racing past.
 */

/** Statuses that hold capacity. Cancelled/completed/no-show release it. */
export const CAPACITY_HOLDING_STATUSES = ['pending', 'confirmed', 'seated'] as const;

/** Valid state transitions for the reservation lifecycle. */
const TRANSITIONS: Record<string, readonly string[]> = {
  pending: ['confirmed', 'cancelled', 'no_show'],
  confirmed: ['seated', 'cancelled', 'no_show'],
  seated: ['completed'],
  completed: [],
  cancelled: [],
  no_show: [],
};

export type ReservationRow = {
  id: string; restaurant_id: string; branch_id: string | null; table_id: string | null;
  user_id: string | null; guest_name: string; guest_phone: string; party_size: number;
  start_at: Date; duration_minutes: number; status: string; reference: string;
  notes: string; source: string; created_at: Date;
};

export function serializeReservation(r: ReservationRow) {
  return {
    id: r.id,
    restaurantId: r.restaurant_id,
    branchId: r.branch_id,
    tableId: r.table_id,
    userId: r.user_id,
    guestName: r.guest_name,
    guestPhone: r.guest_phone,
    partySize: r.party_size,
    startAt: r.start_at,
    durationMinutes: r.duration_minutes,
    endsAt: new Date(new Date(r.start_at).getTime() + r.duration_minutes * 60_000),
    status: r.status,
    reference: r.reference,
    notes: r.notes,
    source: r.source,
    createdAt: r.created_at,
  };
}

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Human-readable reservation reference, e.g. `TR-8F2KQ`. */
function makeReference(): string {
  let code = '';
  for (let i = 0; i < 5; i += 1) {
    code += ALPHABET[Math.floor(Math.random() * ALPHABET.length)] ?? 'X';
  }
  return `TR-${code}`;
}

const WEEKDAY_KEYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const;
const DEFAULT_WINDOWS = [{ open: '18:00', close: '23:00' }];

type HoursWindow = { open: string; close: string };
type DayHours = { closed?: boolean; windows?: HoursWindow[] };

/** Picks the service windows for one weekday out of a venue's hours jsonb. */
function windowsFor(hours: unknown, weekday: number): HoursWindow[] {
  if (hours === null || typeof hours !== 'object') return DEFAULT_WINDOWS;
  const map = hours as Record<string, DayHours>;
  // A venue that has published no weekday map at all — `{}`, or the legacy
  // `{"Mon-Sun": "17:00-24:00"}` shape — is *unconfigured*, not closed. This
  // mirrors the seat-capacity fallback further down: an empty field must never
  // strand a guest with zero bookable slots.
  const configured = WEEKDAY_KEYS.some((k) => map[k] !== undefined);
  if (!configured) return DEFAULT_WINDOWS;
  const key = WEEKDAY_KEYS[weekday];
  if (key === undefined) return DEFAULT_WINDOWS;
  const day = map[key];
  if (!day || day.closed === true) return [];
  const windows = Array.isArray(day.windows) ? day.windows : [];
  const valid = windows.filter(
    (w): w is HoursWindow =>
      typeof w?.open === 'string' && typeof w?.close === 'string' && w.open < w.close,
  );
  return valid.length > 0 ? valid : DEFAULT_WINDOWS;
}

export type SlotOption = {
  startAt: string;
  endAt: string;
  available: boolean;
  seatsLeft: number;
};

/**
 * Availability for one service day.
 *
 * `date` is a `YYYY-MM-DD` string interpreted in the venue's own timezone, so a
 * partner in Karachi and a diner travelling in London see the same service day
 * boundaries. Slots step every 30 minutes; a slot is bookable when the venue
 * still has `partySize` free covers and at least one table can seat the party.
 */
export async function availability(options: {
  restaurantId: string;
  date: string;
  partySize: number;
  branchId?: string | null;
}): Promise<{
  date: string;
  timeZone: string;
  slots: SlotOption[];
  capacity: number;
  configuredHours: boolean;
}> {
  const [venue] = await query<{
    id: string; seats: number; accepting_bookings: boolean;
    opening_hours: unknown; timezone: string | null;
  }>(
    `SELECT r.id, r.seats, r.accepting_bookings, r.opening_hours,
            (SELECT b.timezone FROM restaurant_branches b
              WHERE b.restaurant_id = r.id
              ORDER BY b.is_primary DESC LIMIT 1) AS timezone
       FROM restaurants r WHERE r.id = $1::UUID`,
    [options.restaurantId],
  );
  if (!venue) throw notFound('Restaurant');

  const timeZone = venue.timezone ?? 'UTC';
  const [hoursRow] = await query<{ opening_hours: unknown }>(
    `SELECT opening_hours FROM restaurant_branches
      WHERE restaurant_id = $1::UUID
        AND ($2::uuid IS NULL OR id = $2::UUID)
      ORDER BY is_primary DESC LIMIT 1`,
    [options.restaurantId, options.branchId ?? null],
  );
  const hours = hoursRow?.opening_hours ?? venue.opening_hours;

  const [calendar] = await query<{ weekday: number }>(
    `SELECT EXTRACT(DOW FROM ($1::date::timestamp AT TIME ZONE $2))::int AS weekday`,
    [options.date, timeZone],
  );
  const windows = windowsFor(hours, calendar?.weekday ?? 0);

  const [inventory] = await query<{ capacity: string | null; max_seats: number | null }>(
    `SELECT SUM(seats)::text AS capacity, MAX(seats)::int AS max_seats
       FROM restaurant_tables
      WHERE restaurant_id = $1::UUID AND is_active
        AND ($2::uuid IS NULL OR branch_id = $2::UUID OR branch_id IS NULL)`,
    [options.restaurantId, options.branchId ?? null],
  );
  // A venue that has not entered table inventory yet still accepts
  // reservations up to its published seat count; without that fallback every
  // new venue would show "no availability" until the desk filled in tables.
  const capacity = Number(inventory?.capacity ?? 0) > 0
    ? Number(inventory?.capacity)
    : venue.seats;
  const maxTableSeats = inventory?.max_seats ?? null;

  const slotLength = 90;
  const slotStarts: { start: Date; end: Date }[] = [];
  for (const window of windows) {
    const rows = await query<{ slot_start: Date; slot_end: Date }>(
      `SELECT gs AS slot_start,
              gs + make_interval(mins => $4::int) AS slot_end
         FROM generate_series(
                (($1::date::timestamp + $2::time) AT TIME ZONE $3),
                (($1::date::timestamp + $5::time) AT TIME ZONE $3)
                  - make_interval(mins => $4::int),
                interval '30 minutes') gs`,
      [options.date, window.open, timeZone, slotLength, window.close],
    );
    for (const row of rows) slotStarts.push({ start: row.slot_start, end: row.slot_end });
  }

  // One query for the day's held covers instead of one per slot.
  const held = slotStarts.length === 0
    ? []
    : await query<{ start_at: Date; duration_minutes: number; party_size: number }>(
        `SELECT start_at, duration_minutes, party_size
           FROM table_reservations
          WHERE restaurant_id = $1::UUID
            AND status = ANY($2::text[])
            AND start_at >= $3::timestamptz - interval '8 hours'
            AND start_at <= $4::timestamptz + interval '8 hours'`,
        [
          options.restaurantId,
          [...CAPACITY_HOLDING_STATUSES],
          slotStarts[0]!.start,
          slotStarts[slotStarts.length - 1]!.end,
        ],
      );

  const now = Date.now();
  const slots: SlotOption[] = slotStarts.map(({ start, end }) => {
    const heldSeats = held.reduce((total, reservation) => {
      const rStart = new Date(reservation.start_at).getTime();
      const rEnd = rStart + reservation.duration_minutes * 60_000;
      const overlaps = rStart < end.getTime() && rEnd > start.getTime();
      return overlaps ? total + reservation.party_size : total;
    }, 0);
    const seatsLeft = Math.max(0, capacity - heldSeats);
    const fitsTable = maxTableSeats === null ? true : maxTableSeats >= options.partySize;
    return {
      startAt: start.toISOString(),
      endAt: end.toISOString(),
      available:
        venue.accepting_bookings && seatsLeft >= options.partySize && fitsTable
        && start.getTime() > now,
      seatsLeft,
    };
  });

  return {
    date: options.date,
    timeZone,
    slots,
    capacity,
    configuredHours: windows !== DEFAULT_WINDOWS,
  };
}

export type CreateReservationInput = {
  restaurantId: string;
  branchId?: string | null;
  tableId?: string | null;
  userId: string | null;
  guestName: string;
  guestPhone?: string;
  partySize: number;
  startAt: Date;
  durationMinutes?: number;
  notes?: string;
  source: 'customer' | 'partner';
  /** Partners may create already-confirmed bookings for walk-ins/phone calls. */
  status?: 'pending' | 'confirmed';
};

/**
 * Creates one reservation, or throws 409 when the slot cannot hold the party.
 *
 * The venue row is locked first; inside that lock the table (or the whole
 * venue's cover count) is re-checked, then inserted. A rolled-back
 * transaction leaves no phantom hold, and a retry sees the committed row.
 */
export async function createReservation(
  input: CreateReservationInput,
): Promise<ReservationRow> {
  const duration = input.durationMinutes ?? 90;
  const end = new Date(input.startAt.getTime() + duration * 60_000);

  return withTransaction(async (client: pg.PoolClient) => {
    const { rows: venueRows } = await client.query<{
      id: string; seats: number; accepting_bookings: boolean;
    }>(
      `SELECT id, seats, accepting_bookings FROM restaurants
        WHERE id = $1::UUID FOR UPDATE`,
      [input.restaurantId],
    );
    const venue = venueRows[0];
    if (!venue) throw notFound('Restaurant');
    if (!venue.accepting_bookings) {
      throw new ApiError(409, 'This venue is not accepting bookings right now');
    }
    if (input.startAt.getTime() <= Date.now()) {
      throw new ApiError(422, 'Reservation time must be in the future');
    }

    // Duplicate guard: the same guest cannot hold two live reservations at the
    // same venue for the same slot (double-tap on a slow connection).
    if (input.userId !== null) {
      const { rows: duplicates } = await client.query<{ id: string }>(
        `SELECT id FROM table_reservations
          WHERE restaurant_id = $1::UUID AND user_id = $2::UUID
            AND status = ANY($3::text[]) AND start_at = $4::timestamptz`,
        [input.restaurantId, input.userId, [...CAPACITY_HOLDING_STATUSES], input.startAt],
      );
      if (duplicates.length > 0) {
        throw new ApiError(409, 'You already have a reservation at this time');
      }
    }

    let tableId: string | null = null;

    // Branch isolation: a branch id from another venue must not be attachable,
    // otherwise a partner could file its bookings into a competitor's location
    // (and skew that venue's day list).
    if (input.branchId !== undefined && input.branchId !== null) {
      const { rows: branches } = await client.query<{ id: string }>(
        `SELECT id FROM restaurant_branches
          WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
        [input.branchId, input.restaurantId],
      );
      if (branches.length === 0) {
        throw new ApiError(422, 'Unknown branch for this restaurant');
      }
    }
    if (input.tableId !== undefined && input.tableId !== null) {
      const { rows } = await client.query<{ id: string; seats: number }>(
        `SELECT id, seats FROM restaurant_tables
          WHERE id = $1::UUID AND restaurant_id = $2::UUID AND is_active
          FOR UPDATE`,
        [input.tableId, input.restaurantId],
      );
      const table = rows[0];
      if (!table) throw notFound('Table');
      if (table.seats < input.partySize) {
        throw new ApiError(
          409,
          `This table seats ${table.seats}; the party is ${input.partySize}`,
        );
      }
      const { rows: clashes } = await client.query<{ id: string }>(
        `SELECT id FROM table_reservations
          WHERE table_id = $1::UUID AND status = ANY($2::text[])
            AND start_at < $3::timestamptz
            AND start_at + make_interval(mins => duration_minutes) > $4::timestamptz`,
        [table.id, [...CAPACITY_HOLDING_STATUSES], end, input.startAt],
      );
      if (clashes.length > 0) {
        throw new ApiError(409, 'That table is already booked for this time');
      }
      tableId = table.id;
    }

    // Cover check across the whole venue (tables are not the only capacity
    // model — a venue may not publish table inventory at all).
    const { rows: inventoryRows } = await client.query<{ capacity: string | null }>(
      `SELECT SUM(seats)::text AS capacity FROM restaurant_tables
        WHERE restaurant_id = $1::UUID AND is_active`,
      [input.restaurantId],
    );
    const capacity = Number(inventoryRows[0]?.capacity ?? 0) > 0
      ? Number(inventoryRows[0]?.capacity)
      : venue.seats;

    const { rows: heldRows } = await client.query<{ held: string }>(
      `SELECT COALESCE(SUM(party_size), 0)::text AS held
         FROM table_reservations
        WHERE restaurant_id = $1::UUID AND status = ANY($2::text[])
          AND start_at < $3::timestamptz
          AND start_at + make_interval(mins => duration_minutes) > $4::timestamptz`,
      [input.restaurantId, [...CAPACITY_HOLDING_STATUSES], end, input.startAt],
    );
    const held = Number(heldRows[0]?.held ?? 0);
    if (capacity > 0 && held + input.partySize > capacity) {
      throw new ApiError(409, 'No availability for the requested party size and time');
    }

    // Insert with a reference retried on the (astronomically unlikely) clash.
    for (let attempt = 0; attempt < 5; attempt += 1) {
      try {
        const { rows } = await client.query<ReservationRow>(
          `INSERT INTO table_reservations
             (restaurant_id, branch_id, table_id, user_id, guest_name, guest_phone,
              party_size, start_at, duration_minutes, status, reference, notes, source)
           VALUES ($1::UUID,$2,$3,$4,$5,$6,$7,$8::timestamptz,$9,$10,$11,$12,$13)
           RETURNING *`,
          [
            input.restaurantId,
            input.branchId ?? null,
            tableId,
            input.userId,
            input.guestName,
            input.guestPhone ?? '',
            input.partySize,
            input.startAt,
            duration,
            input.status ?? 'pending',
            makeReference(),
            input.notes ?? '',
            input.source,
          ],
        );
        const created = rows[0];
        if (!created) throw new ApiError(500, 'Reservation creation failed');
        return created;
      } catch (error) {
        const code = (error as { code?: string }).code;
        if (code !== '23505' || attempt === 4) throw error;
      }
    }
    throw new ApiError(500, 'Reservation creation failed');
  });
}

/**
 * Moves a reservation through its lifecycle. Every transition is validated
 * server-side so a stale Partner App screen cannot seat a cancelled booking or
 * complete one that was never seated.
 */
export async function transitionReservation(options: {
  reservationId: string;
  restaurantId: string;
  to: 'confirmed' | 'seated' | 'completed' | 'cancelled' | 'no_show';
  notes?: string;
}): Promise<ReservationRow> {
  return withTransaction(async (client: pg.PoolClient) => {
    const { rows } = await client.query<ReservationRow>(
      `SELECT * FROM table_reservations
        WHERE id = $1::UUID AND restaurant_id = $2::UUID FOR UPDATE`,
      [options.reservationId, options.restaurantId],
    );
    const reservation = rows[0];
    if (!reservation) throw notFound('Reservation');

    const allowed = TRANSITIONS[reservation.status] ?? [];
    if (!allowed.includes(options.to)) {
      throw new ApiError(
        409,
        `Cannot move a ${reservation.status} reservation to ${options.to}`,
      );
    }

    const { rows: updatedRows } = await client.query<ReservationRow>(
      `UPDATE table_reservations
          SET status = $2, notes = CASE WHEN $3::text = '' THEN notes ELSE $3 END,
              updated_at = now()
        WHERE id = $1::UUID RETURNING *`,
      [reservation.id, options.to, options.notes ?? ''],
    );
    const updated = updatedRows[0];
    if (!updated) throw new ApiError(500, 'Reservation update failed');
    return updated;
  });
}

/** Cancels a reservation on behalf of the guest (owner check happens here). */
export async function cancelOwnReservation(
  reservationId: string,
  userId: string,
): Promise<ReservationRow> {
  return withTransaction(async (client: pg.PoolClient) => {
    const { rows } = await client.query<ReservationRow>(
      'SELECT * FROM table_reservations WHERE id = $1::UUID FOR UPDATE',
      [reservationId],
    );
    const reservation = rows[0];
    if (!reservation) throw notFound('Reservation');
    if (reservation.user_id !== userId) {
      throw new ApiError(403, 'This reservation belongs to another guest');
    }
    if (!['pending', 'confirmed'].includes(reservation.status)) {
      throw new ApiError(409, `A ${reservation.status} reservation cannot be cancelled`);
    }
    const { rows: updatedRows } = await client.query<ReservationRow>(
      `UPDATE table_reservations SET status = 'cancelled', updated_at = now()
        WHERE id = $1::UUID RETURNING *`,
      [reservation.id],
    );
    const updated = updatedRows[0];
    if (!updated) throw new ApiError(500, 'Reservation cancellation failed');
    return updated;
  });
}
