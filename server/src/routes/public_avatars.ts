import { Router } from 'express';
import { query } from '../db.js';
import { isUuid } from '../avatars.js';

const router = Router();

/**
 * GET /api/public/avatars/:userId — the uploaded profile photo bytes.
 *
 * Mounted BEFORE requireAuth: `Image.network` cannot attach the bearer token
 * on every platform, and profile photos are public on every social surface
 * anyway. Deleted accounts lose their row (account deletion purges it), so
 * they 404 like any account without an upload.
 */
router.get('/:userId', async (req, res) => {
  const { userId } = req.params;
  if (!isUuid(userId)) {
    res.status(404).json({ error: 'Avatar not found' });
    return;
  }

  const [row] = await query<{
    content_type: string;
    byte_size: number;
    bytes: Buffer;
    updated_at: Date;
  }>(
    `SELECT a.content_type, a.byte_size, a.bytes, a.updated_at
       FROM user_avatars a
       JOIN users u ON u.id = a.user_id
      WHERE a.user_id = $1::UUID AND u.is_deleted = false`,
    [userId],
  );
  if (!row) {
    res.status(404).json({ error: 'Avatar not found' });
    return;
  }

  const etag = `"${row.updated_at.getTime().toString(36)}-${row.byte_size}"`;
  if (req.header('If-None-Match') === etag) {
    res.status(304).end();
    return;
  }

  // The URL is versioned (`?v=<epoch>`) on every replacement, so the bytes
  // behind it never change and may be cached hard. Cross-origin is allowed so
  // a web build on another origin can render the image (helmet defaults the
  // resource policy to same-origin).
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
