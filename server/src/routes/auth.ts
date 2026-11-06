import { Router } from 'express';
import type { Request } from 'express';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound, requireAuth, loadUser } from '../context.js';
import { hashToken } from '../security.js';
import { hashPassword, verifyPassword } from '../passwords.js';

const router = Router();

const TOKEN_TTL_DAYS = 30;

// Phone sign-in is the MVP demo shortcut and is gated to non-production.
// Production deployments must use email+password (/login) or OTP (/otp/*);
// the phone-only flow below would otherwise be an account-takeover primitive
// for any seeded account whose phone number is public.
const isProduction = process.env.NODE_ENV === 'production';

// OTP is enabled in development and test unconditionally. In production it
// is disabled by default because no SMS provider is wired up — an operator
// must set OTP_ENABLED=1 after connecting a provider (Twilio, etc.). When
// disabled, /otp/request returns 503 so the client can show an honest error
// instead of silently swallowing the code.
const otpEnabled = !isProduction || process.env.OTP_ENABLED === '1';

const phoneSchema = z
  .string()
  .trim()
  .regex(/^\+?[0-9][0-9\s-]{7,19}$/, 'Enter a valid phone number');

// POST /api/auth/signin — simple MVP sign-in (non-production only).
router.post('/signin', async (req, res) => {
  if (isProduction) {
    throw new ApiError(
      403,
      'Phone sign-in is disabled on this server. Use email and password.',
    );
  }
  const { phone } = z.object({ phone: phoneSchema }).parse(req.body ?? {});
  const normalized = phone.replace(/[\s-]/g, '');

  const [existing] = await query<{ id: string; role: string }>(
    'SELECT id, role FROM users WHERE phone = $1',
    [normalized],
  );

  let userId = existing?.id;
  if (!userId) {
    const digits = normalized.slice(-4);
    const [created] = await query<{ id: string }>(
      `INSERT INTO users (name, handle, phone, city, bio, joined_year, accent_hex)
       VALUES ($1, $2, $3, 'Karachi', '', $4, $5)
       RETURNING id`,
      [
        `Diner ${digits}`,
        `diner.${digits}${Math.random().toString(36).slice(2, 5)}`,
        normalized,
        new Date().getFullYear(),
        '#4A5A7A',
      ],
    );
    userId = created?.id;
  }
  if (!userId) {
    res.status(500).json({ error: 'Could not create the account' });
    return;
  }

  const token = `dc_${randomBytes(24).toString('hex')}`;
  const expiresAt = new Date(Date.now() + TOKEN_TTL_DAYS * 24 * 60 * 60_000);
  await query(
    'INSERT INTO auth_tokens (token, user_id, expires_at) VALUES ($1, $2, $3)',
    [hashToken(token), userId, expiresAt],
  );

  res.json({ token, expiresAt, user: await loadUser(userId) });
});

// ── Legacy OTP endpoints (kept for backward compatibility) ──────────────────

const OTP_TTL_MINUTES = 10;
const OTP_MAX_ATTEMPTS = 5;
const isDev = process.env.NODE_ENV !== 'production';

const requestSchema = z.object({ phone: phoneSchema });
const verifySchema = z.object({
  phone: phoneSchema,
  code: z.string().trim().regex(/^[0-9]{6}$/, 'Enter the 6-digit code'),
});

function generateOtp(): string {
  const buf = randomBytes(4);
  const num = buf.readUInt32BE(0) % 1_000_000;
  return num.toString().padStart(6, '0');
}

router.post('/otp/request', async (req, res) => {
  if (!otpEnabled) {
    throw new ApiError(
      503,
      'Phone OTP is not configured on this server. Use email and password.',
    );
  }
  const { phone } = requestSchema.parse(req.body ?? {});
  const normalized = phone.replace(/[\s-]/g, '');
  const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60_000);
  const code = generateOtp();
  // Store only the digest — the plaintext code is returned to dev clients
  // for convenience but never written to the database.
  const codeHash = hashToken(code);

  await query(
    `INSERT INTO otp_codes (phone, code_hash, expires_at, attempts)
     VALUES ($1, $2, $3, 0)
     ON CONFLICT (phone) DO UPDATE
       SET code_hash = EXCLUDED.code_hash, expires_at = EXCLUDED.expires_at,
           attempts = 0, created_at = now()`,
    [normalized, codeHash, expiresAt],
  );

  if (isDev) {
    // In dev/test the code is returned so integration tests and the Flutter
    // hot-reload workflow can verify without an SMS provider.
    res.json({ sent: true, phone: normalized, expiresAt, devCode: code });
  } else {
    // Production path: the code would be sent via SMS here. Until an SMS
    // provider is wired up, otpEnabled is false in production and the 503
    // above fires instead.
    console.log(`[SMS] Sending OTP to ${normalized}`);
    res.json({ sent: true, phone: normalized, expiresAt });
  }
});

router.post('/otp/verify', async (req, res) => {
  const { phone, code } = verifySchema.parse(req.body ?? {});
  const normalized = phone.replace(/[\s-]/g, '');

  const [otp] = await query<{ code_hash: string; attempts: number; expires_at: Date }>(
    'SELECT code_hash, attempts, expires_at FROM otp_codes WHERE phone = $1',
    [normalized],
  );
  if (!otp) {
    res.status(401).json({ error: 'Request a code first.' });
    return;
  }
  if (new Date(otp.expires_at).getTime() <= Date.now()) {
    res.status(401).json({ error: 'That code expired. Request a new one.' });
    return;
  }
  // Constant-time compare: hash the supplied code and check against the
  // stored digest. timingSafeEqual requires equal-length buffers, so both
  // are SHA-256 hex strings (64 chars).
  const suppliedHash = hashToken(code);
  const a = Buffer.from(suppliedHash, 'utf8');
  const b = Buffer.from(otp.code_hash, 'utf8');
  if (a.length !== b.length || !timingSafeEqual(a, b)) {
    // Increment the attempt counter; at OTP_MAX_ATTEMPTS the row is deleted
    // so the attacker must request a fresh code (which is rate-limited).
    const rows = await query<{ attempts: number }>(
      `UPDATE otp_codes SET attempts = attempts + 1 WHERE phone = $1
       RETURNING attempts`,
      [normalized],
    );
    const attempts = rows[0]?.attempts ?? 0;
    if (attempts >= OTP_MAX_ATTEMPTS) {
      await query('DELETE FROM otp_codes WHERE phone = $1', [normalized]);
      res.status(429).json({ error: 'Too many failed attempts. Request a new code.' });
      return;
    }
    res.status(401).json({ error: 'That code is not right. Try again.' });
    return;
  }
  await query('DELETE FROM otp_codes WHERE phone = $1', [normalized]);

  const [existing] = await query<{ id: string }>(
    'SELECT id FROM users WHERE phone = $1',
    [normalized],
  );

  let userId = existing?.id;
  if (!userId) {
    const digits = normalized.slice(-4);
    const [created] = await query<{ id: string }>(
      `INSERT INTO users (name, handle, phone, city, bio, joined_year, accent_hex)
       VALUES ($1, $2, $3, 'Karachi', '', $4, $5)
       RETURNING id`,
      [
        `Diner ${digits}`,
        `diner.${digits}${Math.random().toString(36).slice(2, 5)}`,
        normalized,
        new Date().getFullYear(),
        '#4A5A7A',
      ],
    );
    userId = created?.id;
  }
  if (!userId) {
    res.status(500).json({ error: 'Could not create the account' });
    return;
  }

  const token = `dc_${randomBytes(24).toString('hex')}`;
  const expiresAt = new Date(Date.now() + TOKEN_TTL_DAYS * 24 * 60 * 60_000);
  await query(
    'INSERT INTO auth_tokens (token, user_id, expires_at) VALUES ($1, $2, $3)',
    [hashToken(token), userId, expiresAt],
  );

  res.json({ token, expiresAt, user: await loadUser(userId) });
});

// ── Email + password (primary first-launch auth) ─────────────────────────────
const emailSchema = z
  .string()
  .trim()
  .min(3)
  .max(320)
  .refine(
    (v) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v),
    'Enter a valid email address',
  )
  .transform((v) => v.toLowerCase());

const signupSchema = z.object({
  name: z.string().trim().min(2, 'Tell us your name').max(60),
  email: emailSchema,
  password: z.string().min(8, 'Use at least 8 characters').max(200),
  // City is captured during first-run preferences; default to the app's
  // home market rather than a stale placeholder so new accounts land in the
  // right world even if the client hasn't sent it yet.
  city: z.string().trim().min(2).max(60).default('Karachi'),
});

const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(200),
});

async function issueToken(
  userId: string,
): Promise<{ token: string; expiresAt: Date }> {
  const token = `dc_${randomBytes(24).toString('hex')}`;
  const expiresAt = new Date(Date.now() + TOKEN_TTL_DAYS * 24 * 60 * 60_000);
  await query(
    'INSERT INTO auth_tokens (token, user_id, expires_at) VALUES ($1, $2, $3)',
    [hashToken(token), userId, expiresAt],
  );
  return { token, expiresAt };
}

async function uniqueHandle(email: string): Promise<string> {
  const local = email.split('@')[0] ?? 'member';
  const base =
    local.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 18) || 'member';
  let candidate = base;
  for (let attempt = 1; attempt <= 50; attempt += 1) {
    const [clash] = await query<{ one: number }>(
      'SELECT 1 AS one FROM users WHERE handle = $1',
      [candidate],
    );
    if (!clash) return candidate;
    candidate = `${base}${attempt}`.slice(0, 30);
  }
  return `${base}${Date.now()}`.slice(0, 30);
}

const ACCENT_COLORS = ['#4A5A7A', '#7A4A5A', '#4A7A5A', '#7A6A4A', '#5A4A7A'];

// POST /api/auth/signup — create an email/password account and sign in.
router.post('/signup', async (req, res) => {
  const { name, email, password, city } = signupSchema.parse(req.body ?? {});

  const [taken] = await query<{ id: string }>(
    'SELECT id FROM users WHERE email = $1',
    [email],
  );
  if (taken) {
    res
      .status(409)
      .json({ error: 'An account with that email already exists.' });
    return;
  }

  const handle = await uniqueHandle(email);
  const accent = ACCENT_COLORS[email.length % ACCENT_COLORS.length];
  const passwordHash = await hashPassword(password);

  const [created] = await query<{ id: string }>(
    `INSERT INTO users (name, handle, email, password_hash, city, bio, joined_year, accent_hex)
     VALUES ($1, $2, $3, $4, $5, '', $6, $7)
     RETURNING id`,
    [
      name,
      handle,
      email,
      passwordHash,
      city,
      new Date().getFullYear(),
      accent,
    ],
  );
  if (!created) {
    res.status(500).json({ error: 'Could not create the account' });
    return;
  }

  const { token, expiresAt } = await issueToken(created.id);
  res
    .status(201)
    .json({ token, expiresAt, user: await loadUser(created.id) });
});

// POST /api/auth/login — email + password.
router.post('/login', async (req, res) => {
  const { email, password } = loginSchema.parse(req.body ?? {});

  const [row] = await query<{ id: string; password_hash: string | null }>(
    'SELECT id, password_hash FROM users WHERE email = $1',
    [email],
  );
  if (!row || !row.password_hash) {
    res.status(401).json({ error: 'Email or password is incorrect.' });
    return;
  }
  const ok = await verifyPassword(password, row.password_hash);
  if (!ok) {
    res.status(401).json({ error: 'Email or password is incorrect.' });
    return;
  }

  const { token, expiresAt } = await issueToken(row.id);
  res.json({ token, expiresAt, user: await loadUser(row.id) });
});

// GET /api/auth/me — the session's user (used on app start to restore state).
router.get('/me', requireAuth, async (req, res) => {
  res.json({ user: await loadUser(req.userId) });
});

// POST /api/auth/signout — deletes the token row.
router.post('/signout', requireAuth, async (req, res) => {
  const header = req.header('Authorization') ?? '';
  const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
  await query('DELETE FROM auth_tokens WHERE token = $1', [hashToken(token)]);
  res.json({ signedOut: true });
});

// ── Account & credential changes (P1-1 / P1-2 / P1-3 / P1-8) ───────────────
// Tokens here are opaque rows in `auth_tokens`, not JWTs, so there is no
// `token_version` claim to bump: revoking a session MEANS deleting its row.
// A credential change keeps the CURRENT device signed in (so the app does not
// have to re-login mid-flow) and revokes every other session; `logout-all`
// revokes all of them, including the caller's.

/** The raw bearer secret from the just-authenticated request. */
function bearerFrom(req: Request): string {
  const header = req.header('Authorization') ?? '';
  return header.startsWith('Bearer ') ? header.slice(7).trim() : '';
}

/** Revoke every session of this user except the current device's token. */
async function revokeOtherSessions(userId: string, currentToken: string): Promise<void> {
  await query(
    'DELETE FROM auth_tokens WHERE user_id = $1::UUID AND token <> $2',
    [userId, hashToken(currentToken)],
  );
}

/**
 * Load the acting user's credential row for a password-confirmed change.
 * Soft-deleted accounts are treated as gone (404) — their PII is already
 * erased and their tokens revoked, so no credential mutation may run on them.
 */
async function loadCredentialUser(userId: string) {
  const [user] = await query<{
    id: string;
    email: string | null;
    phone: string | null;
    password_hash: string | null;
    is_deleted: boolean;
  }>(
    'SELECT id, email, phone, password_hash, is_deleted FROM users WHERE id = $1::UUID',
    [userId],
  );
  if (!user || user.is_deleted) throw notFound('User');
  return user;
}

/**
 * Password confirmation for email/phone/account changes. scrypt compare is
 * timing-safe; failures get a generic 401 so the route is not a password
 * oracle. Accounts without a password (legacy phone-only) cannot confirm —
 * 409 states that instead of silently allowing an unverified change.
 */
async function requirePasswordMatch(
  user: { password_hash: string | null },
  password: string,
): Promise<void> {
  if (!user.password_hash) {
    throw new ApiError(
      409,
      'This account has no password yet — sign up with email first.',
    );
  }
  if (!(await verifyPassword(password, user.password_hash))) {
    throw new ApiError(401, 'Your password is incorrect.');
  }
}

const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Enter your current password').max(200),
  newPassword: z.string().min(8, 'Use at least 8 characters').max(200),
});
const confirmSchema = z.object({ password: z.string().min(1).max(200) });
const changeEmailSchema = confirmSchema.extend({ email: emailSchema });
const changePhoneSchema = confirmSchema.extend({ phone: phoneSchema });

// POST /api/auth/change-password — verify current, scrypt-rehash the new one,
// revoke other sessions. The current session survives so the app keeps
// working; other devices fall back to the login screen on their next call.
router.post('/change-password', requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = changePasswordSchema.parse(
    req.body ?? {},
  );
  const user = await loadCredentialUser(req.userId);
  await requirePasswordMatch(user, currentPassword);

  await query('UPDATE users SET password_hash = $2 WHERE id = $1::UUID', [
    user.id,
    await hashPassword(newPassword),
  ]);
  await revokeOtherSessions(user.id, bearerFrom(req));

  res.json({ changed: true, user: await loadUser(user.id) });
});

// POST /api/auth/change-email — START of a verified email change (P1-2).
// The address is never applied here: the password confirmation only mints a
// 6-digit challenge code (stored hashed, 15-minute TTL, one live challenge
// per user — a re-request replaces the old code). The new address becomes
// the login handle once /change-email/confirm validates the code. UNIQUE
// collisions surface as 409 BEFORE the challenge so the driver never raises
// a raw constraint error.
const EMAIL_CHANGE_TTL_MINUTES = 15;

router.post('/change-email', requireAuth, async (req, res) => {
  const { email, password } = changeEmailSchema.parse(req.body ?? {});
  const user = await loadCredentialUser(req.userId);
  await requirePasswordMatch(user, password);

  if (user.email === email) {
    res.status(400).json({ error: 'That is already your email address.' });
    return;
  }

  const [clash] = await query<{ id: string }>(
    'SELECT id FROM users WHERE email = $1 AND id <> $2::UUID',
    [email, user.id],
  );
  if (clash) {
    res.status(409).json({ error: 'An account with that email already exists.' });
    return;
  }

  const code = generateOtp();
  const expiresAt = new Date(Date.now() + EMAIL_CHANGE_TTL_MINUTES * 60_000);
  await query(
    `INSERT INTO email_change_challenges (user_id, new_email, code_hash, expires_at)
     VALUES ($1::UUID, $2, $3, $4)
     ON CONFLICT (user_id) DO UPDATE
       SET new_email = EXCLUDED.new_email, code_hash = EXCLUDED.code_hash,
           expires_at = EXCLUDED.expires_at, created_at = now()`,
    [user.id, email, hashToken(code), expiresAt],
  );

  // No mail provider is wired in this prototype, so dev builds return the
  // code to the client (same convention as /otp/request) and prod builds
  // log it for the operator. The response shape never differs otherwise.
  if (isDev) {
    console.log(`[Mail] Change-email code for ${email}: ${code}`);
    res.json({ sent: true, email, expiresAt, devCode: code });
  } else {
    console.log(`[Mail] Sending change-email code for ${email} to the account`);
    res.json({ sent: true, email, expiresAt });
  }
});

// POST /api/auth/change-email/confirm — completes the verified change. Wrong
// or expired codes 401 (and the challenge survives for a corrected retry);
// the authRateLimiter caps guesses per minute. On success the challenge is
// consumed, the address applied, and every OTHER session is revoked so only
// this (verified) device keeps working with the new login handle.
router.post('/change-email/confirm', requireAuth, async (req, res) => {
  const { code } = z
    .object({ code: z.string().trim().regex(/^[0-9]{6}$/, 'Enter the 6-digit code') })
    .parse(req.body ?? {});
  const user = await loadCredentialUser(req.userId);

  const [challenge] = await query<{
    new_email: string;
    code_hash: string;
    expires_at: Date;
  }>(
    'SELECT new_email, code_hash, expires_at FROM email_change_challenges WHERE user_id = $1::UUID',
    [user.id],
  );
  if (!challenge) {
    res.status(400).json({ error: 'No email change is pending. Start again.' });
    return;
  }
  if (challenge.code_hash !== hashToken(code)) {
    res.status(401).json({ error: 'That code is not right. Try again.' });
    return;
  }
  if (new Date(challenge.expires_at).getTime() <= Date.now()) {
    res.status(401).json({ error: 'That code expired. Request a new one.' });
    return;
  }

  // The address may have been claimed while the code was in flight.
  const [clash] = await query<{ id: string }>(
    'SELECT id FROM users WHERE email = $1 AND id <> $2::UUID',
    [challenge.new_email, user.id],
  );
  if (clash) {
    await query('DELETE FROM email_change_challenges WHERE user_id = $1::UUID', [
      user.id,
    ]);
    res.status(409).json({ error: 'An account with that email already exists.' });
    return;
  }

  await query('DELETE FROM email_change_challenges WHERE user_id = $1::UUID', [
    user.id,
  ]);
  await query('UPDATE users SET email = $2 WHERE id = $1::UUID', [
    user.id,
    challenge.new_email,
  ]);
  await revokeOtherSessions(user.id, bearerFrom(req));

  res.json({ email: challenge.new_email, user: await loadUser(user.id) });
});

// POST /api/auth/change-phone — same confirmation contract as change-email.
// Numbers are normalised exactly like /signin does (strip spaces/dashes), so
// the stored value always matches what a phone sign-in would look up.
// No SMS delivery exists in this prototype, so the new number is recorded
// unverified — documented rather than hidden.
router.post('/change-phone', requireAuth, async (req, res) => {
  const { phone, password } = changePhoneSchema.parse(req.body ?? {});
  const normalized = phone.replace(/[\s-]/g, '');
  const user = await loadCredentialUser(req.userId);
  await requirePasswordMatch(user, password);

  const [clash] = await query<{ id: string }>(
    'SELECT id FROM users WHERE phone = $1 AND id <> $2::UUID',
    [normalized, user.id],
  );
  if (clash) {
    res.status(409).json({ error: 'That phone number already belongs to an account.' });
    return;
  }

  await query('UPDATE users SET phone = $2 WHERE id = $1::UUID', [user.id, normalized]);
  await revokeOtherSessions(user.id, bearerFrom(req));

  res.json({ phone: normalized, user: await loadUser(user.id) });
});

// POST /api/auth/logout-all — revoke EVERY session for the account, including
// the caller's own token. The client clears its local token on success; any
// other device's next authenticated call gets a 401 and lands on the login
// screen — immediate here (row delete), not after a cache TTL.
router.post('/logout-all', requireAuth, async (req, res) => {
  await query('DELETE FROM auth_tokens WHERE user_id = $1::UUID', [req.userId]);
  res.json({ signedOutEverywhere: true });
});

export default router;
