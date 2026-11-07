import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { requireVenueRole, loadVenueGate, isVerifiedVenue } from '../access.js';

const router = Router();

/**
 * Venue menu management: what the kitchen actually serves, with prices and an
 * availability switch per dish. This is intentionally separate from the
 * per-event tasting menu (`menu_items`), which belongs to a single dinner and
 * is edited by the host.
 */

type SectionRow = {
  id: string; restaurant_id: string; branch_id: string | null; name: string;
  position: number; is_active: boolean;
};

type ItemRow = {
  id: string; restaurant_id: string; section_id: string; name: string;
  description: string; price: string; position: number; is_available: boolean;
  dietary_tags: string[]; photo_url: string;
};

function serializeItem(i: ItemRow) {
  return {
    id: i.id,
    restaurantId: i.restaurant_id,
    sectionId: i.section_id,
    name: i.name,
    description: i.description,
    price: Number(i.price),
    position: i.position,
    isAvailable: i.is_available,
    dietaryTags: i.dietary_tags,
    photoUrl: i.photo_url,
  };
}

function serializeSection(s: SectionRow, items: ItemRow[]) {
  return {
    id: s.id,
    restaurantId: s.restaurant_id,
    branchId: s.branch_id,
    name: s.name,
    position: s.position,
    isActive: s.is_active,
    items: items.filter((i) => i.section_id === s.id).map(serializeItem),
  };
}

// GET /api/partner/restaurants/:restaurantId/menu, full menu, ordered.
router.get('/:restaurantId/menu', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'staff');

  const sections = await query<SectionRow>(
    `SELECT id, restaurant_id, branch_id, name, position, is_active
       FROM restaurant_menu_sections
      WHERE restaurant_id = $1::UUID
      ORDER BY position ASC, name ASC`,
    [req.params.restaurantId],
  );
  const items = await query<ItemRow>(
    `SELECT id, restaurant_id, section_id, name, description, price, position,
            is_available, dietary_tags, photo_url
       FROM restaurant_menu_items
      WHERE restaurant_id = $1::UUID
      ORDER BY position ASC, name ASC`,
    [req.params.restaurantId],
  );

  res.json({
    data: { sections: sections.map((s) => serializeSection(s, items)) },
    meta: { sections: sections.length, items: items.length },
  });
});

const sectionSchema = z.object({
  name: z.string().trim().min(1).max(80),
  branchId: z.string().uuid().nullable().optional(),
  position: z.coerce.number().int().min(0).max(999).default(0),
  isActive: z.boolean().default(true),
});

// POST /api/partner/restaurants/:restaurantId/menu/sections
router.post('/:restaurantId/menu/sections', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = sectionSchema.parse(req.body ?? {});

  const [created] = await query<SectionRow>(
    `INSERT INTO restaurant_menu_sections (restaurant_id, branch_id, name, position, is_active)
     VALUES ($1::UUID, $2, $3, $4, $5)
     RETURNING id, restaurant_id, branch_id, name, position, is_active`,
    [
      req.params.restaurantId,
      input.branchId ?? null,
      input.name,
      input.position,
      input.isActive,
    ],
  );
  if (!created) throw new ApiError(500, 'Menu section creation failed');

  res.status(201).json({ data: { section: serializeSection(created, []) } });
});

const patchSectionSchema = sectionSchema.partial();

// PATCH /api/partner/restaurants/:restaurantId/menu/sections/:sectionId
router.patch('/:restaurantId/menu/sections/:sectionId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchSectionSchema.parse(req.body ?? {});

  const sets: string[] = [];
  const params: unknown[] = [];
  const map: Record<string, string> = {
    name: 'name', branchId: 'branch_id', position: 'position', isActive: 'is_active',
  };
  for (const [key, column] of Object.entries(map)) {
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }
  params.push(req.params.sectionId, req.params.restaurantId);
  const [updated] = await query<SectionRow>(
    `UPDATE restaurant_menu_sections SET ${sets.join(', ')}, updated_at = now()
      WHERE id = $${params.length - 1}::UUID AND restaurant_id = $${params.length}::UUID
      RETURNING id, restaurant_id, branch_id, name, position, is_active`,
    params,
  );
  if (!updated) throw notFound('Menu section');

  const items = await query<ItemRow>(
    `SELECT id, restaurant_id, section_id, name, description, price, position,
            is_available, dietary_tags, photo_url
       FROM restaurant_menu_items WHERE section_id = $1::UUID
      ORDER BY position ASC, name ASC`,
    [updated.id],
  );
  res.json({ data: { section: serializeSection(updated, items) } });
});

// DELETE /api/partner/restaurants/:restaurantId/menu/sections/:sectionId
router.delete('/:restaurantId/menu/sections/:sectionId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const [deleted] = await query<{ id: string }>(
    `DELETE FROM restaurant_menu_sections
      WHERE id = $1::UUID AND restaurant_id = $2::UUID
      RETURNING id`,
    [req.params.sectionId, req.params.restaurantId],
  );
  if (!deleted) throw notFound('Menu section');
  // Items cascade with their section; the response says how many went with it
  // so the Partner App can warn before a destructive edit.
  res.json({ data: { id: deleted.id, deleted: true } });
});

const itemSchema = z.object({
  sectionId: z.string().uuid(),
  name: z.string().trim().min(1).max(120),
  description: z.string().trim().max(1000).default(''),
  price: z.coerce.number().min(0).max(100000),
  position: z.coerce.number().int().min(0).max(999).default(0),
  isAvailable: z.boolean().default(true),
  dietaryTags: z.array(z.string().trim().max(30)).max(10).default([]),
  photoUrl: z.string().trim().max(400).default(''),
});

// POST /api/partner/restaurants/:restaurantId/menu/items
router.post('/:restaurantId/menu/items', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = itemSchema.parse(req.body ?? {});

  const [section] = await query<{ id: string }>(
    `SELECT id FROM restaurant_menu_sections
      WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
    [input.sectionId, req.params.restaurantId],
  );
  if (!section) throw new ApiError(422, 'Unknown menu section for this restaurant');

  const [created] = await query<ItemRow>(
    `INSERT INTO restaurant_menu_items
       (restaurant_id, section_id, name, description, price, position,
        is_available, dietary_tags, photo_url)
     VALUES ($1::UUID,$2::UUID,$3,$4,$5,$6,$7,$8,$9)
     RETURNING id, restaurant_id, section_id, name, description, price, position,
               is_available, dietary_tags, photo_url`,
    [
      req.params.restaurantId, input.sectionId, input.name, input.description,
      input.price, input.position, input.isAvailable, input.dietaryTags,
      input.photoUrl,
    ],
  );
  if (!created) throw new ApiError(500, 'Menu item creation failed');

  res.status(201).json({ data: { item: serializeItem(created) } });
});

const patchItemSchema = itemSchema.partial();

// PATCH /api/partner/restaurants/:restaurantId/menu/items/:itemId
router.patch('/:restaurantId/menu/items/:itemId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = patchItemSchema.parse(req.body ?? {});

  // A move between sections must stay inside the same restaurant.
  if (input.sectionId !== undefined) {
    const [section] = await query<{ id: string }>(
      `SELECT id FROM restaurant_menu_sections
        WHERE id = $1::UUID AND restaurant_id = $2::UUID`,
      [input.sectionId, req.params.restaurantId],
    );
    if (!section) throw new ApiError(422, 'Unknown menu section for this restaurant');
  }

  const sets: string[] = [];
  const params: unknown[] = [];
  const map: Record<string, string> = {
    sectionId: 'section_id', name: 'name', description: 'description',
    price: 'price', position: 'position', isAvailable: 'is_available',
    dietaryTags: 'dietary_tags', photoUrl: 'photo_url',
  };
  for (const [key, column] of Object.entries(map)) {
    const value = (input as Record<string, unknown>)[key];
    if (value === undefined) continue;
    params.push(value);
    sets.push(`${column} = $${params.length}`);
  }
  if (sets.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }
  params.push(req.params.itemId, req.params.restaurantId);
  const [updated] = await query<ItemRow>(
    `UPDATE restaurant_menu_items SET ${sets.join(', ')}, updated_at = now()
      WHERE id = $${params.length - 1}::UUID AND restaurant_id = $${params.length}::UUID
      RETURNING id, restaurant_id, section_id, name, description, price, position,
                is_available, dietary_tags, photo_url`,
    params,
  );
  if (!updated) throw notFound('Menu item');

  res.json({ data: { item: serializeItem(updated) } });
});

// DELETE /api/partner/restaurants/:restaurantId/menu/items/:itemId
router.delete('/:restaurantId/menu/items/:itemId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const [deleted] = await query<{ id: string }>(
    `DELETE FROM restaurant_menu_items
      WHERE id = $1::UUID AND restaurant_id = $2::UUID RETURNING id`,
    [req.params.itemId, req.params.restaurantId],
  );
  if (!deleted) throw notFound('Menu item');
  res.json({ data: { id: deleted.id, deleted: true } });
});

const availabilitySchema = z.object({
  itemIds: z.array(z.string().uuid()).min(1).max(200),
  isAvailable: z.boolean(),
});

/**
 * POST /api/partner/restaurants/:restaurantId/menu/availability
 *
 * Bulk 86-list switch. Nightly service means "mark these eight dishes sold
 * out" in one action; doing it one PATCH per dish would be eight round trips
 * from a tablet at the pass. Scoped by restaurant_id so an item id from
 * another venue silently matches nothing instead of being writable.
 */
router.post('/:restaurantId/menu/availability', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const input = availabilitySchema.parse(req.body ?? {});

  const updated = await query<{ id: string }>(
    `UPDATE restaurant_menu_items
        SET is_available = $3, updated_at = now()
      WHERE restaurant_id = $1::UUID AND id = ANY($2::uuid[])
      RETURNING id`,
    [req.params.restaurantId, input.itemIds, input.isAvailable],
  );

  res.json({
    data: { updated: updated.map((r) => r.id), isAvailable: input.isAvailable },
  });
});

// ── Customer-visible menu (read surface) ─────────────────────────────────────

/**
 * GET /api/restaurants/:restaurantId/menu, public menu for the Customer App.
 *
 * Mounted separately (see server.ts) because it is a diner-facing read: only
 * verified, active venues expose a menu, and only available dishes come back.
 * Sold-out dishes stay in the response with `isAvailable: false` so the diner
 * sees "Sold out" instead of watching a dish silently disappear.
 */
export const publicMenuRouter = Router();

publicMenuRouter.get('/:restaurantId/menu', async (req, res) => {
  const venue = await loadVenueGate(req.params.restaurantId);
  if (!isVerifiedVenue(venue.partnership_status)) {
    throw notFound('Menu');
  }

  const sections = await query<SectionRow>(
    `SELECT id, restaurant_id, branch_id, name, position, is_active
       FROM restaurant_menu_sections
      WHERE restaurant_id = $1::UUID AND is_active
      ORDER BY position ASC, name ASC`,
    [venue.id],
  );
  const items = await query<ItemRow>(
    `SELECT id, restaurant_id, section_id, name, description, price, position,
            is_available, dietary_tags, photo_url
       FROM restaurant_menu_items
      WHERE restaurant_id = $1::UUID
      ORDER BY position ASC, name ASC`,
    [venue.id],
  );

  res.json({
    data: {
      restaurantId: venue.id,
      sections: sections.map((s) => ({
        id: s.id,
        name: s.name,
        items: items.filter((i) => i.section_id === s.id).map((i) => ({
          id: i.id,
          name: i.name,
          description: i.description,
          price: Number(i.price),
          isAvailable: i.is_available,
          dietaryTags: i.dietary_tags,
          photoUrl: i.photo_url,
        })),
      })),
    },
  });
});

/** Shared by the availability maths below: one connection per menu write. */
export default router;
