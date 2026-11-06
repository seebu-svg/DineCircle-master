import { Router } from 'express';
import { query } from '../db.js';

const router = Router();

// ── Offers (Deals & Offers discovery category) ──────────────────────────────
//
// Public read surface for the Deals & Offers category. `special_menus` and
// `promo_codes` already back the partner studio (see routes/partner.ts); this
// exposes the *active* subset to diners. Mounted after `requireAuth`, so
// `req.userId` is available even though the feed is not user-specific.

type OfferRow = {
  id: string;
  name: string;
  description: string;
  restaurant_id: string;
  restaurant_name: string;
  city: string;
  price_per_guest: string;
  min_guests: number;
  cover_image: string;
  tags: string[];
  bookings_count: number;
};

/**
 * Derive a coarse deal kind from the menu. Explicit tags win (a venue can
 * label a package "couple"/"group"/"tasting"); otherwise fall back to the
 * minimum party size the menu was built for.
 */
function deriveKind(tags: string[], minGuests: number): 'couple' | 'group' | 'tasting' {
  const lowered = tags.map((t) => t.toLowerCase());
  if (lowered.some((t) => t.includes('couple') || t.includes('date'))) return 'couple';
  if (lowered.some((t) => t.includes('group') || t.includes('party'))) return 'group';
  if (lowered.some((t) => t.includes('tast') || t.includes('flight'))) return 'tasting';
  if (minGuests <= 2) return 'couple';
  if (minGuests >= 6) return 'group';
  return 'tasting';
}

// GET /api/offers — active special menus + promo codes for the Deals feed.
router.get('/', async (req, res) => {
  const { city, kind = 'all', limit = '50' } = req.query;

  const conditions: string[] = ["sm.status = 'active'"];
  const params: unknown[] = [];

  if (typeof city === 'string' && city.trim() !== '') {
    params.push(`%${city.trim()}%`);
    conditions.push(`r.city ILIKE $${params.length}`);
  }

  const parsedLimit = Math.min(Number(limit) || 50, 200);
  const where = `WHERE ${conditions.join(' AND ')}`;

  const rows = await query<OfferRow>(
    `SELECT sm.id, sm.name, sm.description, sm.restaurant_id,
            r.name AS restaurant_name, r.city,
            sm.price_per_guest, sm.min_guests, sm.cover_image, sm.tags,
            sm.bookings_count
     FROM special_menus sm
     JOIN restaurants r ON r.id = sm.restaurant_id
     ${where}
     ORDER BY sm.bookings_count DESC, sm.created_at DESC
     LIMIT ${parsedLimit}`,
    params,
  );

  const normalizedKind = typeof kind === 'string' ? kind.trim().toLowerCase() : 'all';
  const offers = rows
    .map((row) => ({
      id: row.id,
      name: row.name,
      description: row.description,
      restaurantId: row.restaurant_id,
      restaurantName: row.restaurant_name,
      city: row.city,
      pricePerGuest: Number(row.price_per_guest),
      minGuests: row.min_guests,
      coverImage: row.cover_image,
      tags: row.tags,
      kind: deriveKind(row.tags, row.min_guests),
    }))
    .filter((offer) => normalizedKind === 'all' || normalizedKind === 'any' || offer.kind === normalizedKind);

  const promos = await query<{ code: string; discount_pct: string }>(
    `SELECT code, discount_pct FROM promo_codes WHERE active ORDER BY discount_pct DESC`,
  );

  res.json({
    offers,
    promos: promos.map((p) => ({ code: p.code, discountPct: Number(p.discount_pct) })),
    count: offers.length,
  });
});

export default router;
