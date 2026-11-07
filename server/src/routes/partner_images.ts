import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound } from '../context.js';
import { requireVenueRole } from '../access.js';
import { isUuid } from '../avatars.js';
import {
  MAX_VENUE_IMAGE_BASE64_CHARS,
  VENUE_IMAGE_KINDS,
  decodeVenueImagePayload,
  uploadedVenueImagePath,
} from '../venue_images.js';

const router = Router();

/**
 * Venue photo upload for partners.
 *
 * The endpoint only STORES a photo and hands back a URL; it deliberately does
 * not know whether the result becomes a logo, a gallery tile, a dish photo or
 * a deal banner. Repointing the column is the caller's next request, through
 * the existing PATCH endpoints, which keeps this route free of per-module
 * rules and means "upload" never becomes a second way to edit a venue.
 *
 * Bytes live in `venue_images` (see schema.sql) rather than an object store,
 * matching the avatar route, so the module ships with no S3/GCS credentials.
 */

const uploadSchema = z.object({
  image: z
    .string()
    .min(1, 'Choose a photo to upload')
    .max(
      MAX_VENUE_IMAGE_BASE64_CHARS,
      'That photo is too large. Keep it under 512 KB.',
    ),
  kind: z.enum(VENUE_IMAGE_KINDS).default('general'),
});

/**
 * POST /api/partner/restaurants/:restaurantId/images
 * Body `{ image: <base64 | data URL>, kind? }` → `{ image: { id, url, … } }`.
 *
 * Manager, not staff: a photo is published content, and changing what a guest
 * sees needs the same role as editing the menu or the profile.
 */
router.post('/:restaurantId/images', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const { image, kind } = uploadSchema.parse(req.body ?? {});
  const { bytes, contentType } = decodeVenueImagePayload(image);

  const [stored] = await query<{ id: string }>(
    `INSERT INTO venue_images (restaurant_id, kind, content_type, byte_size, bytes)
     VALUES ($1::UUID, $2, $3, $4, $5)
     RETURNING id`,
    [req.params.restaurantId, kind, contentType, bytes.length, bytes],
  );
  if (!stored) throw new ApiError(500, 'The photo could not be saved');

  res.status(201).json({
    data: {
      image: {
        id: stored.id,
        kind,
        url: uploadedVenueImagePath(stored.id),
        byteSize: bytes.length,
        contentType,
      },
    },
  });
});

/**
 * DELETE /api/partner/restaurants/:restaurantId/images/:imageId
 *
 * Retires one upload. Scoped by `restaurant_id` as well as id, so a manager of
 * venue A can never delete a photo belonging to venue B by guessing a UUID.
 * The referencing column is the caller's to clear, this only frees the bytes.
 */
router.delete('/:restaurantId/images/:imageId', async (req, res) => {
  await requireVenueRole(req, req.params.restaurantId, 'manager');
  const { imageId } = req.params;
  if (!isUuid(imageId)) throw notFound('Image');

  const removed = await query<{ id: string }>(
    `DELETE FROM venue_images
      WHERE id = $1::UUID AND restaurant_id = $2::UUID
      RETURNING id`,
    [imageId, req.params.restaurantId],
  );
  if (removed.length === 0) throw notFound('Image');

  res.json({ data: { deleted: true } });
});

export default router;
