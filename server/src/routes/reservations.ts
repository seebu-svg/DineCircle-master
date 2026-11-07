import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { list, one, parsePagination, optionalString } from '../api.js';
import {
  availability,
  cancelOwnReservation,
  createReservation,
  serializeReservation,
} from '../reservations.js';

const router = Router();

/**
 * Customer App side of the shared reservation engine.
 *
 * Everything the diner can do to a table booking lives here; the Partner App's
 * management surface is in routes/partner_tables.ts. Both call the same
 * service (src/reservations.ts), so availability, capacity and lifecycle rules
 * cannot drift between the two apps.
 */

// GET /api/restaurants/:restaurantId/availability?date=YYYY-MM-DD&partySize=2
router.get('/restaurants/:restaurantId/availability', async (req, res) => {
  const date = optionalString(req.query.date) ?? new Date().toISOString().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new ApiError(400, 'date must be YYYY-MM-DD');
  }
  const partySize = Number(req.query.partySize ?? 2);
  if (!Number.isInteger(partySize) || partySize < 1 || partySize > 50) {
    throw new ApiError(400, 'partySize must be an integer between 1 and 50');
  }

  const result = await availability({
    restaurantId: req.params.restaurantId,
    date,
    partySize,
    branchId: optionalString(req.query.branchId),
  });
  res.json({ data: result });
});

const createSchema = z.object({
  partySize: z.coerce.number().int().min(1).max(50).default(2),
  startAt: z.coerce.date(),
  durationMinutes: z.coerce.number().int().min(15).max(480).default(90),
  tableId: z.string().uuid().nullable().optional(),
  branchId: z.string().uuid().nullable().optional(),
  guestPhone: z.string().trim().max(40).default(''),
  notes: z.string().trim().max(1000).default(''),
});

/**
 * POST /api/restaurants/:restaurantId/reservations, diner books a table.
 * Always created `pending`; the venue confirms from the Partner App, and the
 * customer's app reflects the new status on its next read of /users/me/reservations.
 */
router.post('/restaurants/:restaurantId/reservations', async (req, res) => {
  const input = createSchema.parse(req.body ?? {});

  const [guest] = await query<{ name: string; phone: string | null }>(
    'SELECT name, phone FROM users WHERE id = $1::UUID',
    [req.userId],
  );
  if (!guest) throw notFound('Guest');

  const created = await createReservation({
    restaurantId: req.params.restaurantId,
    branchId: input.branchId ?? null,
    tableId: input.tableId ?? null,
    userId: req.userId,
    guestName: guest.name,
    guestPhone: input.guestPhone || guest.phone || '',
    partySize: input.partySize,
    startAt: input.startAt,
    durationMinutes: input.durationMinutes,
    notes: input.notes,
    source: 'customer',
    status: 'pending',
  });

  const [venue] = await query<{ name: string }>(
    'SELECT name FROM restaurants WHERE id = $1::UUID',
    [req.params.restaurantId],
  );

  // Tell the venue desk in the same request: a pending reservation nobody is
  // told about is how bookings silently rot.
  await query(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'New table reservation', $2, 'reservation', false)`,
    [
      req.params.restaurantId,
      `${guest.name} requested a table for ${input.partySize} (${
        new Date(input.startAt).toISOString()
      }).`,
    ],
  );

  res.status(201).json({
    data: {
      reservation: serializeReservation(created),
      restaurantName: venue?.name ?? null,
    },
  });
});

// GET /api/users/me/reservations, the diner's table bookings.
router.get('/users/me/reservations', async (req, res) => {
  const page = parsePagination(req.query as Record<string, unknown>, { defaultLimit: 50 });
  const status = optionalString(req.query.status);

  const params: unknown[] = [req.userId];
  const conditions = ['r.user_id = $1::UUID'];
  if (status !== null) {
    params.push([status]);
    conditions.push(`r.status = ANY($${params.length}::text[])`);
  }
  const where = conditions.join(' AND ');

  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM table_reservations r WHERE ${where}`,
    params,
  );

  params.push(page.limit, page.offset);
  const rows = await query<{
    id: string; restaurant_id: string; branch_id: string | null; table_id: string | null;
    user_id: string | null; guest_name: string; guest_phone: string; party_size: number;
    start_at: Date; duration_minutes: number; status: string; reference: string;
    notes: string; source: string; created_at: Date;
    restaurant_name: string; city: string; cover_image: string; table_label: string | null;
  }>(
    `SELECT r.*, v.name AS restaurant_name, v.city, v.cover_image,
            t.label AS table_label
       FROM table_reservations r
       JOIN restaurants v ON v.id = r.restaurant_id
       LEFT JOIN restaurant_tables t ON t.id = r.table_id
      WHERE ${where}
      ORDER BY r.start_at DESC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );

  res.json(
    list(
      'reservations',
      rows.map((r) => ({
        ...serializeReservation(r),
        restaurantName: r.restaurant_name,
        city: r.city,
        coverImage: r.cover_image,
        tableLabel: r.table_label,
      })),
      page,
      totalRow?.count ?? 0,
    ),
  );
});

// POST /api/reservations/:reservationId/cancel, the diner cancels.
router.post('/reservations/:reservationId/cancel', async (req, res) => {
  const cancelled = await cancelOwnReservation(req.params.reservationId, req.userId);

  await query(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'Reservation cancelled', $2, 'reservation', false)`,
    [
      cancelled.restaurant_id,
      `${cancelled.guest_name} cancelled table ${cancelled.reference}.`,
    ],
  );

  res.json(one('reservation', serializeReservation(cancelled)));
});

export default router;
