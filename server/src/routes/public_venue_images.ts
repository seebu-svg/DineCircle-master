import { Router } from 'express';
import { query } from '../db.js';
import { isUuid } from '../avatars.js';

const router = Router();

/**
 * GET /api/public/venue-images/:imageId, uploaded venue photo bytes.
 *
 * Mounted BEFORE requireAuth, for the same reason the avatar route is:
 * `Image.network` cannot attach the bearer token on every platform, and these
 * photos are what the customer app and the public QR menu already display.
 *
 * Unlike `/public/avatars/:userId`, the URL needs no `?v=` cache-buster. The id
 * belongs to one upload and its bytes are never rewritten, so a replaced photo
 * is simply a different URL, which is why this response can be cached hard.
 */
router.get('/:imageId', async (req, res) => {
  const { imageId } = req.params;
  if (!isUuid(imageId)) {
    res.status(404).json({ error: 'Image not found' });
    return;
  }

  // The join proves the owning venue still exists rather than trusting the FK
  // alone; a cascade already removes the row, this just refuses a stale cache.
  const [row] = await query<{
    content_type: string;
    byte_size: number;
    bytes: Buffer;
    created_at: Date;
  }>(
    `SELECT i.content_type, i.byte_size, i.bytes, i.created_at
       FROM venue_images i
       JOIN restaurants r ON r.id = i.restaurant_id
      WHERE i.id = $1::UUID`,
    [imageId],
  );
  if (!row) {
    res.status(404).json({ error: 'Image not found' });
    return;
  }

  const etag = `"${row.created_at.getTime().toString(36)}-${row.byte_size}"`;
  if (req.header('If-None-Match') === etag) {
    res.status(304).end();
    return;
  }

  // Cross-origin is allowed so a web build on another origin can render the
  // image (helmet defaults the resource policy to same-origin), and the CSP
  // stops anything stored here from being interpreted as active content.
  res.set({
    'Content-Type': row.content_type,
    'Content-Length': String(row.byte_size),
    'Cache-Control': 'public, max-age=31536000, immutable',
    ETag: etag,
    'Cross-Origin-Resource-Policy': 'cross-origin',
    'Content-Security-Policy': "default-src 'none'",
  });
  res.end(row.bytes);
});

export default router;
