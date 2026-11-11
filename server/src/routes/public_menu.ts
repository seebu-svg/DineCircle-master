import { Router } from 'express';
import { createHash } from 'node:crypto';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';

const router = Router();

/**
 * Public venue-menu surface, intentionally unauthenticated.
 *
 * A QR code printed on a restaurant table links here so a passer-by can scan
 * and read the menu without signing in. The payload is the same data the
 * partner dashboard edits (active sections, available items), minus any
 * internal fields. No reservation data, no pricing tiers, no partner-only
 * metadata leaks through this route.
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

type RestaurantRow = {
  id: string; name: string; city: string; neighborhood: string; address: string;
  cover_image: string; opening_hours: object; amenities: string[];
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
    items: items
      .filter((i) => i.section_id === s.id && i.is_available)
      .map(serializeItem),
  };
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// GET /api/public/menu/:restaurantId, unauthenticated diner-facing menu.
router.get('/:restaurantId', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  const [restaurant] = await query<RestaurantRow>(
    `SELECT id, name, city, neighborhood, address, cover_image,
            opening_hours, amenities
       FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant');

  const sections = await query<SectionRow>(
    `SELECT id, restaurant_id, branch_id, name, position, is_active
       FROM restaurant_menu_sections
      WHERE restaurant_id = $1::UUID AND is_active = true
      ORDER BY position ASC, name ASC`,
    [restaurantId],
  );
  const items = await query<ItemRow>(
    `SELECT id, restaurant_id, section_id, name, description, price, position,
            is_available, dietary_tags, photo_url
       FROM restaurant_menu_items
      WHERE restaurant_id = $1::UUID AND moderation_status <> 'removed'
      ORDER BY position ASC, name ASC`,
    [restaurantId],
  );

  res.json({
    restaurant: {
      id: restaurant.id,
      name: restaurant.name,
      city: restaurant.city,
      // Area/street let the diner confirm they scanned the right venue's
      // table without exposing contact or partner-only fields.
      neighborhood: restaurant.neighborhood,
      address: restaurant.address,
      coverImage: restaurant.cover_image,
      openingHours: restaurant.opening_hours,
      amenities: restaurant.amenities,
    },
    sections: sections.map((s) => serializeSection(s, items)),
  });
});

/**
 * POST /api/public/menu/:restaurantId/scan, record a QR scan for analytics.
 *
 * Fire-and-forget from the customer app. Rate-limited to 1 scan per device per
 * hour. No PII is stored, only a hash of the device identifier.
 */
router.post('/:restaurantId/scan', async (req, res) => {
  const { restaurantId } = req.params;
  if (!UUID_PATTERN.test(restaurantId)) {
    throw new ApiError(400, 'restaurantId must be a UUID');
  }

  // Verify the restaurant exists.
  const [restaurant] = await query<{ id: string }>(
    `SELECT id FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant');

  // Generate a device hash for rate limiting (no PII).
  const deviceFingerprint = req.ip || req.headers['user-agent'] || 'unknown';
  const deviceHash = createHash('sha256').update(deviceFingerprint).digest('hex');

  // Rate limit: 1 scan per device per hour.
  const [recentScan] = await query<{ id: string }>(
    `SELECT id FROM qr_scans
      WHERE device_hash = $1
        AND restaurant_id = $2::UUID
        AND scanned_at > now() - interval '1 hour'
      LIMIT 1`,
    [deviceHash, restaurantId],
  );

  if (recentScan) {
    // Already scanned within the last hour, silently accept but don't record.
    res.json({ recorded: false, reason: 'rate_limited' });
    return;
  }

  // Record the scan.
  await query(
    `INSERT INTO qr_scans (restaurant_id, kind, device_hash)
     VALUES ($1::UUID, 'menu', $2)`,
    [restaurantId, deviceHash],
  );

  res.json({ recorded: true });
});

export default router;
