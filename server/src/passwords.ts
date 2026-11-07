import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';

const scryptAsync = promisify(scrypt);

/**
 * Password hashing for the users table, shared by every route that creates or
 * verifies a credential (`auth.ts` signup/login/changes and `users.ts` account
 * deletion). Lives apart from the HTTP middleware in `security.ts` so both
 * route modules can depend on it without importing each other.
 *
 * Stored format is `scrypt:<salt-hex>:<hash-hex>`, the scheme and salt travel
 * with the digest, so parameters can be changed later without ambiguity.
 */
export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16).toString('hex');
  const derived = (await scryptAsync(password, salt, 64)) as Buffer;
  return `scrypt:${salt}:${derived.toString('hex')}`;
}

/**
 * Timing-safe verification. A malformed/unknown-scheme stored value simply
 * fails (returns false) rather than throwing, so legacy or hand-edited rows
 * cannot produce a 500 that leaks information.
 */
export async function verifyPassword(
  password: string,
  stored: string,
): Promise<boolean> {
  const parts = stored.split(':');
  const scheme = parts[0];
  const salt = parts[1];
  const hashHex = parts[2];
  if (parts.length !== 3 || scheme !== 'scrypt' || !salt || !hashHex) {
    return false;
  }
  const expected = Buffer.from(hashHex, 'hex');
  const derived = (await scryptAsync(password, salt, 64)) as Buffer;
  if (derived.length !== expected.length) return false;
  return timingSafeEqual(derived, expected);
}
