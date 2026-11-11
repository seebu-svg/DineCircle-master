import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound, patchKeys } from '../context.js';
import { requireVenueRole } from '../access.js';
import { list, one, parsePagination, optionalString, optionalDate } from '../api.js';
import {
  availability,
  createReservation,
  transitionReservation,
  serializeReservation,
} from '../reservations.js';

const router = Router();

// ── Table inventory ──────────────────────────────────────────────────────────

type TableRow = {
  id: string; restaurant_id: string; branch_id: string | null; label: string;
  seats: number; zone: string; is_active: boolean; created_at: Date;
};

function serializeTable(t: TableRow) {
  return {
    id: t.id,
    restaurantId: t.restaurant_id,
    branchId: t.branch_id,
    label: t.label,
    seats: t.seats,
    zone: t.zone,
    isActive: t.is_active,
    createdAt: t.created_at,
  };
}

// GET /api/partner/restaurants/:restaurantId/tables
router.get('/:restaurantId/tables', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const rows = await query<TableRow>(
    `SELECT id, restaurant_id, branch_id, label, seats, zone, is_active, created_at
       FROM restaurant_tables
      WHERE restaurant_id = $1::UUID
      ORDER BY is_active DESC, zone ASC, label ASC`,
    [req.params.restaurantId],
  );
  res.json({
    data: { tables: rows.map(serializeTable) },
    meta: { total: rows.length, seats: rows.reduce((s, t) => s + t.seats, 0) },
  });
});

const tableSchema = z.object({
  label: z.string().trim().min(1).max(40),
  seats: z.coerce.number().int().min(1).max(50),
  zone: z.string().trim().max(40).default(''),
  branchId: z.string().uuid().nullable().optional(),
  isActive: z.boolean().default(true),
});

// POST /api/partner/restaurants/:restaurantId/tables
router.post('/:restaurantId/tables', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = tableSchema.parse(req.body ?? {});

  if (input.branchId) {
    const [branch] = await query<{ id: string }>(
      'SELECT id FROM restaurant_branches WHERE id = $1::UUID AND restaurant_id = $2::UUID',
      [input.branchId, req.params.restaurantId],
    );
    if (!branch) throw new ApiError(422, 'Unknown branch for this restaurant');
  }

  const [created] = await query<TableRow>(
    `INSERT INTO restaurant_tables
       (restaurant_id, branch_id, label, seats, zone, is_active)
     VALUES ($1::UUID,$2,$3,$4,$5,$6)
     RETURNING id, restaurant_id, branch_id, label, seats, zone, is_active, created_at`,
    [
      req.params.restaurantId, input.branchId ?? null, input.label, input.seats,
      input.zone, input.isActive,
    ],
  ).catch((error: { code?: string }) => {
    if (error.code === '23505') {
      throw new ApiError(409, `Table label "${input.label}" already exists`);
    }
    throw error;
  });
  if (!created) throw new ApiError(500, 'Table creation failed');

  res.status(201).json({ data: { table: serializeTable(created) } });
});

const patchTableSchema = tableSchema.partial();

// PATCH /api/partner/restaurants/:restaurantId/tables/:tableId
router.patch('/:restaurantId/tables/:tableId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchTableSchema.parse(req.body ?? {});
  const provided = patchKeys(req.body);

  const sets: string[] = [];
  const params: unknown[] = [];
  const map: Record<string, string> = {
    label: 'label', seats: 'seats', zone: 'zone', branchId: 'branch_id',
    isActive: 'is_active',
  };
  for (const [key, column] of Object.entries(map)) {
    if (!provided.has(key)) continue;
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }
  params.push(req.params.tableId, req.params.restaurantId);
  const [updated] = await query<TableRow>(
    `UPDATE restaurant_tables SET ${sets.join(', ')}, updated_at = now()
      WHERE id = $${params.length - 1}::UUID AND restaurant_id = $${params.length}::UUID
      RETURNING id, restaurant_id, branch_id, label, seats, zone, is_active, created_at`,
    params,
  );
  if (!updated) throw notFound('Table');

  res.json({ data: { table: serializeTable(updated) } });
});

/**
 * DELETE /api/partner/restaurants/:restaurantId/tables/:tableId
 *
 * Soft-deletes by default: reservations reference the table, so a hard delete
 * would rewrite history. `?hard=true` removes the row and detaches its
 * reservations (`ON DELETE SET NULL`), which is only correct for a table that
 * was added by mistake.
 */
router.delete('/:restaurantId/tables/:tableId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const hard = req.query.hard === 'true';

  if (hard) {
    const [deleted] = await query<{ id: string }>(
      `DELETE FROM restaurant_tables
        WHERE id = $1::UUID AND restaurant_id = $2::UUID RETURNING id`,
      [req.params.tableId, req.params.restaurantId],
    );
    if (!deleted) throw notFound('Table');
    res.json({ data: { id: deleted.id, deleted: true } });
    return;
  }

  const [updated] = await query<{ id: string }>(
    `UPDATE restaurant_tables SET is_active = false, updated_at = now()
      WHERE id = $1::UUID AND restaurant_id = $2::UUID RETURNING id`,
    [req.params.tableId, req.params.restaurantId],
  );
  if (!updated) throw notFound('Table');
  res.json({ data: { id: updated.id, isActive: false } });
});

// ── Availability (partner view) ──────────────────────────────────────────────

// GET /api/partner/restaurants/:restaurantId/availability?date=YYYY-MM-DD
router.get('/:restaurantId/availability', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
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

// ── Reservations (partner view) ──────────────────────────────────────────────

// GET /api/partner/restaurants/:restaurantId/reservations
router.get('/:restaurantId/reservations', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const page = parsePagination(req.query as Record<string, unknown>, { defaultLimit: 100 });
  const date = optionalString(req.query.date);
  if (date !== null && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new ApiError(400, 'date must be YYYY-MM-DD');
  }
  const status = optionalString(req.query.status);
  const from = optionalDate(req.query.from);
  const to = optionalDate(req.query.to);

  const params: unknown[] = [req.params.restaurantId];
  const conditions = ['r.restaurant_id = $1::UUID'];

  if (status !== null) {
    params.push([status]);
    conditions.push(`r.status = ANY($${params.length}::text[])`);
  }
  if (date !== null) {
    params.push(date);
    conditions.push(
      `(r.start_at AT TIME ZONE COALESCE(br.timezone, 'UTC'))::date = $${params.length}::date`,
    );
  }
  if (from !== null) {
    params.push(from);
    conditions.push(`r.start_at >= $${params.length}::timestamptz`);
  }
  if (to !== null) {
    // Half-open window: callers (the Partner App Insights range chips) send
    // midnight *after* the last day they mean, so a booking at exactly that
    // instant belongs to the next day and must not be counted here.
    params.push(to);
    conditions.push(`r.start_at < $${params.length}::timestamptz`);
  }

  const where = conditions.join(' AND ');
  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM table_reservations r
       LEFT JOIN restaurant_branches br ON br.id = r.branch_id
      WHERE ${where}`,
    params,
  );

  params.push(page.limit, page.offset);
  const rows = await query<{
    id: string; restaurant_id: string; branch_id: string | null; table_id: string | null;
    user_id: string | null; guest_name: string; guest_phone: string; party_size: number;
    start_at: Date; duration_minutes: number; status: string; reference: string;
    notes: string; source: string; created_at: Date; table_label: string | null;
  }>(
    `SELECT r.*, t.label AS table_label
       FROM table_reservations r
       LEFT JOIN restaurant_branches br ON br.id = r.branch_id
       LEFT JOIN restaurant_tables t ON t.id = r.table_id
      WHERE ${where}
      ORDER BY r.start_at ASC
      LIMIT $${params.length - 1} OFFSET $${params.length}`,
    params,
  );

  res.json(
    list(
      'reservations',
      rows.map((r) => ({
        ...serializeReservation(r),
        tableLabel: r.table_label,
      })),
      page,
      totalRow?.count ?? 0,
    ),
  );
});

const createForGuestSchema = z.object({
  guestName: z.string().trim().min(1).max(120),
  guestPhone: z.string().trim().max(40).default(''),
  partySize: z.coerce.number().int().min(1).max(50),
  startAt: z.coerce.date(),
  durationMinutes: z.coerce.number().int().min(15).max(480).default(90),
  tableId: z.string().uuid().nullable().optional(),
  branchId: z.string().uuid().nullable().optional(),
  notes: z.string().trim().max(1000).default(''),
  status: z.enum(['pending', 'confirmed']).default('confirmed'),
});

/**
 * POST /api/partner/restaurants/:restaurantId/reservations
 * Phone-in / walk-in booking taken by the venue itself. Runs through the same
 * capacity check as the Customer App so the desk cannot oversell either.
 */
router.post('/:restaurantId/reservations', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'staff');
  const input = createForGuestSchema.parse(req.body ?? {});

  const created = await createReservation({
    restaurantId: req.params.restaurantId,
    branchId: input.branchId ?? null,
    tableId: input.tableId ?? null,
    userId: null,
    guestName: input.guestName,
    guestPhone: input.guestPhone,
    partySize: input.partySize,
    startAt: input.startAt,
    durationMinutes: input.durationMinutes,
    notes: input.notes,
    source: 'partner',
    status: input.status,
  });

  res.status(201).json({ data: { reservation: serializeReservation(created) } });
});

const TRANSITION_PATHS = {
  confirm: 'confirmed',
  seat: 'seated',
  complete: 'completed',
  cancel: 'cancelled',
  'no-show': 'no_show',
} as const;

/**
 * POST /api/partner/restaurants/:restaurantId/reservations/:reservationId/:action
 *
 * One endpoint per lifecycle action so the Partner App's buttons map 1:1 onto
 * routes, and the legal transitions stay in one table (src/reservations.ts).
 */
router.post('/:restaurantId/reservations/:reservationId/:action', async (req, res) => {
  const action = req.params.action as keyof typeof TRANSITION_PATHS;
  const to = TRANSITION_PATHS[action];
  if (!to) throw new ApiError(404, 'Unknown reservation action');

  await requireVenueRole(req, req.params.restaurantId, 'staff');
  const notes = typeof req.body?.notes === 'string' ? req.body.notes.slice(0, 1000) : undefined;

  const updated = await transitionReservation({
    reservationId: req.params.reservationId,
    restaurantId: req.params.restaurantId,
    to,
    notes,
  });

  res.json({
    data: { reservation: serializeReservation(updated) },
  });
});

// GET /api/partner/restaurants/:restaurantId/reservations/:reservationId
router.get('/:restaurantId/reservations/:reservationId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId);
  const [row] = await query<{
    id: string; restaurant_id: string; branch_id: string | null; table_id: string | null;
    user_id: string | null; guest_name: string; guest_phone: string; party_size: number;
    start_at: Date; duration_minutes: number; status: string; reference: string;
    notes: string; source: string; created_at: Date;
  }>(
    `SELECT * FROM table_reservations
      WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
    [req.params.reservationId, req.params.restaurantId],
  );
  if (!row) throw notFound('Reservation');
  res.json(one('reservation', serializeReservation(row)));
});

export default router;
