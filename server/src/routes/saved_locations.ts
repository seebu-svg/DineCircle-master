import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { notFound } from '../context.js';

const router = Router();

type LocationRow = {
  id: string;
  user_id: string;
  kind: string;
  name: string;
  city: string;
  area: string;
  address: string;
  latitude: string | number | null;
  longitude: string | number | null;
  created_at: string;
};

function serialize(row: LocationRow) {
  return {
    id: row.id,
    kind: row.kind,
    name: row.name,
    city: row.city,
    area: row.area,
    address: row.address,
    latitude: row.latitude === null ? null : Number(row.latitude),
    longitude: row.longitude === null ? null : Number(row.longitude),
    createdAt: row.created_at,
  };
}

const saveSchema = z.object({
  kind: z.enum(['home', 'work', 'favourite', 'custom']),
  name: z.string().min(1).max(120),
  city: z.string().min(1).max(80),
  area: z.string().max(120).default(''),
  address: z.string().max(240).default(''),
  latitude: z.number().min(-90).max(90).optional().nullable(),
  longitude: z.number().min(-180).max(180).optional().nullable(),
});

/**
 * GET /api/users/me/saved-locations — all saved places for the auth'd user.
 */
router.get('/', async (req, res) => {
  const rows = await query<LocationRow>(
    'SELECT * FROM saved_locations WHERE user_id = $1 ORDER BY created_at DESC',
    [req.userId],
  );
  res.json({ locations: rows.map(serialize) });
});

/**
 * POST /api/users/me/saved-locations — create or replace a saved location.
 *
 * For 'home' and 'work' kinds only one row is allowed per user; a second POST
 * with the same kind replaces the previous entry (upsert behaviour).
 */
router.post('/', async (req, res) => {
  const body = saveSchema.parse(req.body);

  // Enforce single home / work per user.
  if (body.kind === 'home' || body.kind === 'work') {
    await query(
      'DELETE FROM saved_locations WHERE user_id = $1 AND kind = $2',
      [req.userId, body.kind],
    );
  }

  const [row] = await query<LocationRow>(
    `INSERT INTO saved_locations (user_id, kind, name, city, area, address, latitude, longitude)
     VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8)
     RETURNING *`,
    [
      req.userId,
      body.kind,
      body.name,
      body.city,
      body.area,
      body.address || `${body.area ? body.area + ', ' : ''}${body.city}`,
      body.latitude ?? null,
      body.longitude ?? null,
    ],
  );
  if (!row) throw notFound('Location');
  res.status(201).json(serialize(row));
});

/**
 * DELETE /api/users/me/saved-locations/:id — remove a saved location.
 */
router.delete('/:id', async (req, res) => {
  const result = await query<{ id: string }>(
    'DELETE FROM saved_locations WHERE id = $1::uuid AND user_id = $2::uuid RETURNING id',
    [req.params.id, req.userId],
  );
  if (result.length === 0) throw notFound('Location');
  res.status(204).end();
});

export default router;
