import { ApiError } from './context.js';

/**
 * Profile-photo rules shared by the upload route (`PUT /users/me/avatar`) and
 * the public byte route (`GET /public/avatars/:userId`).
 *
 * The client resizes/compresses before upload (image_picker maxWidth +
 * imageQuality), so 512 KiB is generous for a 512px square while keeping the
 * base64 JSON envelope (~700 KB) under the global 1 MB express.json limit.
 * The same ceiling is enforced by the `user_avatars.byte_size` CHECK.
 */
export const MAX_AVATAR_BYTES = 512 * 1024;

/** Upper bound on the base64 string the schema will even try to decode. */
export const MAX_AVATAR_BASE64_CHARS = Math.ceil(MAX_AVATAR_BYTES / 3) * 4 + 128;

export type AvatarContentType = 'image/jpeg' | 'image/png' | 'image/webp';

/**
 * Detects the real image type from magic bytes. The client-declared type is
 * never trusted: whatever we store is served back with this content type, so
 * sniffing here is what stops an HTML/SVG payload being re-served as "image".
 */
export function sniffImageType(bytes: Buffer): AvatarContentType | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    bytes.length >= 8 &&
    bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
  ) {
    return 'image/png';
  }
  if (
    bytes.length >= 12 &&
    bytes.subarray(0, 4).toString('ascii') === 'RIFF' &&
    bytes.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

const BASE64_BODY = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * Decodes the upload payload: plain base64 or a `data:image/...;base64,` URL.
 * `Buffer.from(…, 'base64')` silently skips invalid characters, so the
 * alphabet is checked first — a corrupt upload is a 400, not a broken photo.
 */
export function decodeAvatarPayload(raw: string): {
  bytes: Buffer;
  contentType: AvatarContentType;
} {
  const body = raw.replace(/^data:[^;,]*;base64,/, '').replace(/\s+/g, '');
  if (body.length === 0 || body.length % 4 !== 0 || !BASE64_BODY.test(body)) {
    throw new ApiError(400, 'The photo could not be read. Try another image.');
  }
  const bytes = Buffer.from(body, 'base64');
  if (bytes.length === 0) {
    throw new ApiError(400, 'The photo could not be read. Try another image.');
  }
  if (bytes.length > MAX_AVATAR_BYTES) {
    throw new ApiError(413, 'That photo is too large — keep it under 512 KB.');
  }
  const contentType = sniffImageType(bytes);
  if (!contentType) {
    throw new ApiError(415, 'Use a JPEG, PNG or WebP photo.');
  }
  return { bytes, contentType };
}

/**
 * The `users.avatar_url` value for an uploaded photo. Relative to the API root
 * (`…/api`) so it survives host changes; the `v` query busts client and CDN
 * caches whenever a new photo replaces the old one.
 */
export function uploadedAvatarPath(userId: string, updatedAt: Date): string {
  return `/public/avatars/${userId}?v=${updatedAt.getTime()}`;
}

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True for a canonical UUID — lets routes 404 instead of a pg cast 500. */
export function isUuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}
