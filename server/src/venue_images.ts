import { ApiError } from './context.js';
import { sniffImageType } from './avatars.js';

/**
 * Venue-photo rules shared by the partner upload route
 * (`POST /partner/restaurants/:id/images`) and the public byte route
 * (`GET /public/venue-images/:imageId`).
 *
 * Deliberately the same envelope, ceiling and magic-byte sniffing as
 * `avatars.ts` — the codebase keeps ONE upload convention rather than growing
 * a second. The 512 KiB cap keeps the base64 body (~700 KB) under the global
 * 1 MB `express.json` limit, and the client downsizes before upload, so the
 * ceiling is generous for a 1280px dish photo.
 */
export const MAX_VENUE_IMAGE_BYTES = 512 * 1024;

/** Upper bound on the base64 string the routes will even try to decode. */
export const MAX_VENUE_IMAGE_BASE64_CHARS =
  Math.ceil(MAX_VENUE_IMAGE_BYTES / 3) * 4 + 128;

/**
 * What a photo is *for*. Metadata only: the kind never decides where the URL
 * is stored, because repointing the referencing column is the caller's choice
 * (`restaurants.logo`, `gallery[]`, `restaurant_menu_items.photo_url`,
 * `restaurant_deals.image_url`). It exists so a later cleanup job can tell a
 * logo from a dish photo, and so the DB can reject nonsense values.
 */
export const VENUE_IMAGE_KINDS = [
  'general',
  'logo',
  'cover',
  'gallery',
  'menu_item',
  'deal',
] as const;

export type VenueImageKind = (typeof VENUE_IMAGE_KINDS)[number];

/** The real image type, per `sniffImageType`, never the client's claim. */
export type VenueImageContentType = 'image/jpeg' | 'image/png' | 'image/webp';

const BASE64_BODY = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * Decodes the upload payload: plain base64 or a `data:image/...;base64,` URL.
 * `Buffer.from(…, 'base64')` silently skips invalid characters, so the
 * alphabet is checked first — a corrupt upload is a 400, not a broken photo.
 *
 * Like the avatar route, the declared content type is discarded: whatever we
 * store is served back with the type sniffed from the bytes themselves, which
 * is what stops an HTML or SVG payload being re-served as an image.
 */
export function decodeVenueImagePayload(raw: string): {
  bytes: Buffer;
  contentType: VenueImageContentType;
} {
  const body = raw.replace(/^data:[^;,]*;base64,/, '').replace(/\s+/g, '');
  if (body.length === 0 || body.length % 4 !== 0 || !BASE64_BODY.test(body)) {
    throw new ApiError(400, 'The photo could not be read. Try another image.');
  }
  const bytes = Buffer.from(body, 'base64');
  if (bytes.length === 0) {
    throw new ApiError(400, 'The photo could not be read. Try another image.');
  }
  if (bytes.length > MAX_VENUE_IMAGE_BYTES) {
    throw new ApiError(413, 'That photo is too large — keep it under 512 KB.');
  }
  const contentType = sniffImageType(bytes);
  if (!contentType) {
    throw new ApiError(415, 'Use a JPEG, PNG or WebP photo.');
  }
  return { bytes, contentType };
}

/**
 * The value written into the referencing column: relative to the API root so it
 * survives a host change (the app resolves it against `API_BASE_URL`).
 *
 * The id is unique per upload and a row is never rewritten, so this URL never
 * changes meaning — which is what lets the public route mark it immutable and
 * skip cache-busting entirely.
 */
export function uploadedVenueImagePath(imageId: string): string {
  return `/public/venue-images/${imageId}`;
}
