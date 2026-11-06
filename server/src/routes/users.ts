import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../db.js';
import { forbidden, notFound, loadUser } from '../context.js';
import { ApiError } from '../context.js';
import { isBlockedPair, notBlockedBetween } from '../blocks.js';
import { likeTerm } from '../search.js';
import { verifyPassword } from '../passwords.js';
import {
  MAX_AVATAR_BASE64_CHARS,
  decodeAvatarPayload,
  isUuid,
  uploadedAvatarPath,
} from '../avatars.js';

const router = Router();

export type UserRow = {
  id: string;
  name: string;
  handle: string;
  city: string;
  bio: string;
  followers_count: number;
  following_count: number;
  dinners_hosted: number;
  dinners_joined: number;
  rating: string;
  review_count: number;
  avatar_url: string | null;
  badges: string[];
  tastes: string[];
  accent_hex: string | null;
  joined_year: number;
  role: string;
  instagram: string;
  email: string | null;
  phone: string | null;
  is_deleted: boolean;
  // Account & Settings (P1) — privacy toggles, food preferences, home locale.
  home_area: string;
  dietary: string[];
  allergies: string[];
  show_follow_list: boolean;
  show_activity: boolean;
  dm_from_followers_only: boolean;
  allow_tagging: boolean;
  // Customer account mode: 'personal' (default, private) | 'professional'.
  account_type: string;
  professional_since: Date | null;
};

/**
 * The profile card any signed-in viewer may read (discovery, rosters,
 * `/users/:id`). Deliberately omits the owner-only settings: home area,
 * dietary/allergy labels (health data) and the DM/tagging preferences are
 * nobody else's business. `showFollowList`/`showActivity` stay because the
 * client uses them to explain why a list is hidden.
 */
export function serializePublic(u: UserRow) {
  return {
    id: u.id,
    name: u.name,
    handle: u.handle,
    city: u.city,
    bio: u.bio,
    followers: u.followers_count,
    following: u.following_count,
    dinnersHosted: u.dinners_hosted,
    dinnersJoined: u.dinners_joined,
    rating: Number(u.rating),
    reviewCount: u.review_count,
    avatarUrl: u.avatar_url,
    badges: u.badges,
    tastes: u.tastes,
    accentHex: u.accent_hex,
    joinedYear: u.joined_year,
    role: u.role,
    instagram: normalizeInstagram(u.instagram),
    showFollowList: u.show_follow_list,
    showActivity: u.show_activity,
    // Public account mode so a profile card can show the Private/Professional
    // badge. Nothing private rides along: contact details, home area and
    // dietary/allergy labels stay owner-only.
    accountType: u.account_type,
    isInfluencer: u.role === 'influencer',
    isVerified: u.badges.includes('verified') || u.role === 'influencer',
  };
}

/** Seed data stores `@name`; the API always speaks the bare username. */
function normalizeInstagram(value: string | null | undefined): string {
  return (value ?? '').trim().replace(/^@+/, '');
}

/**
 * The signed-in user's own profile: the public card plus every owner-only
 * setting and the contact fields, matching the `/auth/me` (`loadUser`) shape
 * so a PATCH response can replace the session user without losing the email.
 */
function serialize(u: UserRow) {
  return {
    id: u.id,
    name: u.name,
    handle: u.handle,
    city: u.city,
    bio: u.bio,
    followers: u.followers_count,
    following: u.following_count,
    dinnersHosted: u.dinners_hosted,
    dinnersJoined: u.dinners_joined,
    rating: Number(u.rating),
    reviewCount: u.review_count,
    avatarUrl: u.avatar_url,
    badges: u.badges,
    tastes: u.tastes,
    accentHex: u.accent_hex,
    joinedYear: u.joined_year,
    role: u.role,
    accountType: u.account_type,
    professionalSince: u.professional_since,
    instagram: normalizeInstagram(u.instagram),
    email: u.email,
    phone: u.phone,
    homeArea: u.home_area,
    dietary: u.dietary,
    allergies: u.allergies,
    showFollowList: u.show_follow_list,
    showActivity: u.show_activity,
    dmFromFollowersOnly: u.dm_from_followers_only,
    allowTagging: u.allow_tagging,
    isInfluencer: u.role === 'influencer',
    isVerified: u.badges.includes('verified') || u.role === 'influencer',
  };
}

// ── Growth ladder (one account: diner → host → influencer) ─────────────────
// Thresholds for a host to claim Food Influencer status. Tunable here only;
// both GET /me/tier and POST /me/influencer evaluate against the same rules.
export const INFLUENCER_THRESHOLDS = {
  minFollowers: 50,
  minEventsHosted: 3,
  minRating: 4.0,
  minRatingCount: 3,
} as const;

function tierInfo(u: UserRow) {
  const tier =
    u.role === 'influencer' ? 'influencer'
    : u.role === 'host' ? 'host'
    : u.role === 'partner_admin' || u.role === 'super_admin' ? 'partner'
    : 'diner';
  const progress = {
    followers: u.followers_count,
    eventsHosted: u.dinners_hosted,
    rating: Number(u.rating),
    ratingCount: u.review_count,
  };
  const thresholdsMet =
    progress.followers >= INFLUENCER_THRESHOLDS.minFollowers &&
    progress.eventsHosted >= INFLUENCER_THRESHOLDS.minEventsHosted &&
    progress.rating >= INFLUENCER_THRESHOLDS.minRating &&
    progress.ratingCount >= INFLUENCER_THRESHOLDS.minRatingCount;
  return {
    tier,
    thresholds: INFLUENCER_THRESHOLDS,
    progress,
    eligible: tier === 'host' && thresholdsMet,
  };
}

// A roster/discovery row is a full user plus the viewer's follow state.
type RosterRow = UserRow & { is_following: boolean };

/**
 * Profile + Account/Settings patch schema (P1-4 / P1-5 / P1-6).
 *
 * EVERY field is optional: the Edit Profile sheet keeps sending the original
 * full {name, city, bio, tastes} payload, while the new Settings sheets send
 * only the slice they own (a privacy toggle, a dietary list, the home area).
 * A partial object means one endpoint and one validation contract for both,
 * and a settings write can never accidentally blank an unrelated column.
 */
// Single-line fields reject every C0 control (incl. newlines); the bio keeps
// line breaks and tabs but nothing a renderer could trip over.
const SINGLE_LINE_CONTROL = /[\u0000-\u001F\u007F]/;
const MULTI_LINE_CONTROL = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]/;

const singleLine = (min: number, max: number) =>
  z
    .string()
    .trim()
    .min(min)
    .max(max)
    .refine((v) => !SINGLE_LINE_CONTROL.test(v), 'Remove unsupported characters');

/**
 * Usernames: 3–30 of a–z, 0–9, `_` and `.` (the seed data uses dots), not
 * starting or ending with a dot and no `..`. Lower-cased before validation so
 * `@Ayesha.Khan` and `ayesha.khan` are the same claim. The `deleted_` prefix
 * is reserved for anonymised accounts.
 */
export const HANDLE_PATTERN = /^(?!.*\.\.)[a-z0-9_][a-z0-9._]{1,28}[a-z0-9_]$/;
const handleSchema = z
  .string()
  .trim()
  .transform((v) => v.replace(/^@+/, '').toLowerCase())
  .pipe(
    z
      .string()
      .regex(
        HANDLE_PATTERN,
        'Usernames are 3–30 letters, numbers, _ or . (no leading/trailing dot)',
      )
      .refine((v) => !v.startsWith('deleted_'), 'That username is reserved'),
  );

/** Instagram username, stored bare. Empty string clears the link. */
const instagramSchema = z
  .string()
  .trim()
  .transform((v) =>
    v
      .replace(/^(https?:\/\/)?(www\.)?instagram\.com\//i, '')
      .replace(/^@+/, '')
      .replace(/\/+$/, ''),
  )
  .pipe(
    z
      .string()
      .regex(/^[A-Za-z0-9._]{0,30}$/, 'Enter a valid Instagram username'),
  );

const settingsSchema = z
  .object({
    name: singleLine(2, 80),
    handle: handleSchema,
    city: singleLine(2, 60),
    bio: z
      .string()
      .trim()
      .max(400)
      .refine((v) => !MULTI_LINE_CONTROL.test(v), 'Remove unsupported characters'),
    instagram: instagramSchema,
    tastes: z.array(z.string().trim().min(1).max(40)).max(8),
    // P1-6 home locale: a free-text neighbourhood/district within `city`.
    homeArea: z
      .string()
      .trim()
      .max(80)
      .refine((v) => !SINGLE_LINE_CONTROL.test(v), 'Remove unsupported characters'),
    // P1-4 privacy toggles.
    showFollowList: z.boolean(),
    showActivity: z.boolean(),
    dmFromFollowersOnly: z.boolean(),
    allowTagging: z.boolean(),
    // P1-5 food preferences (halal / vegetarian / … and allergy labels).
    dietary: z.array(z.string().trim().min(1).max(40)).max(12),
    allergies: z.array(z.string().trim().min(1).max(40)).max(12),
  })
  .partial();

/** Column name per incoming key — the whitelist the PATCH builder may touch. */
const SETTINGS_COLUMNS = {
  name: 'name',
  handle: 'handle',
  city: 'city',
  bio: 'bio',
  instagram: 'instagram',
  tastes: 'tastes',
  homeArea: 'home_area',
  showFollowList: 'show_follow_list',
  showActivity: 'show_activity',
  dmFromFollowersOnly: 'dm_from_followers_only',
  allowTagging: 'allow_tagging',
  dietary: 'dietary',
  allergies: 'allergies',
} as const satisfies Record<keyof z.infer<typeof settingsSchema>, string>;

// PATCH /api/users/me — edit the signed-in profile / settings.
router.patch('/me', async (req, res) => {
  const input = settingsSchema.parse(req.body ?? {});

  // Build the SET list only from keys the client actually sent, so a partial
  // settings write leaves every other column untouched.
  const assignments: string[] = [];
  const params: unknown[] = [req.userId];
  for (const [key, column] of Object.entries(SETTINGS_COLUMNS)) {
    const value = input[key as keyof typeof input];
    if (value === undefined) continue;
    params.push(value);
    assignments.push(`${column} = $${params.length}`);
  }

  if (input.handle !== undefined) {
    // Friendly pre-check (case-insensitive, excluding yourself); the UNIQUE
    // constraint below still settles a race between two simultaneous claims.
    const [clash] = await query<{ id: string }>(
      'SELECT id FROM users WHERE lower(handle) = $1 AND id <> $2::UUID LIMIT 1',
      [input.handle, req.userId],
    );
    if (clash) throw new ApiError(409, 'That username is taken');
  }

  // `is_deleted = false` guards the row: an anonymised account is not
  // editable, and a still-live token for it must not be able to revive it.
  // An empty patch still runs (`SET id = id`) so it 404s the same way.
  const [updated] = await query<UserRow>(
    `UPDATE users SET ${assignments.length ? assignments.join(', ') : 'id = id'}
     WHERE id = $1::UUID AND is_deleted = false
     RETURNING *`,
    params,
  ).catch((error: { code?: string; constraint?: string }) => {
    if (error.code === '23505' && error.constraint?.includes('handle')) {
      throw new ApiError(409, 'That username is taken');
    }
    throw error;
  });
  if (!updated) throw notFound('User');
  res.json({ user: serialize(updated) });
});

// ── Profile photo ────────────────────────────────────────────────────────────
// Bytes live in `user_avatars` (one row per user, ≤512 KiB, magic-byte
// sniffed); `users.avatar_url` points at the public, versioned byte route so
// every existing read surface (cards, rosters, reviews, chat) picks the new
// photo up without knowing uploads exist.
const avatarUploadSchema = z.object({
  image: z
    .string()
    .min(1, 'Choose a photo to upload')
    .max(MAX_AVATAR_BASE64_CHARS, 'That photo is too large — keep it under 512 KB.'),
});

// PUT /api/users/me/avatar — body `{ image: <base64 | data URL> }`.
router.put('/me/avatar', async (req, res) => {
  const { image } = avatarUploadSchema.parse(req.body ?? {});
  const { bytes, contentType } = decodeAvatarPayload(image);

  const user = await withTransaction(async (client) => {
    const { rows: locked } = await client.query<{ is_deleted: boolean }>(
      'SELECT is_deleted FROM users WHERE id = $1::UUID FOR UPDATE',
      [req.userId],
    );
    if (!locked[0] || locked[0].is_deleted) throw notFound('User');

    const { rows: stored } = await client.query<{ updated_at: Date }>(
      `INSERT INTO user_avatars (user_id, content_type, byte_size, bytes, updated_at)
       VALUES ($1::UUID, $2, $3, $4, clock_timestamp())
       ON CONFLICT (user_id) DO UPDATE
         SET content_type = EXCLUDED.content_type,
             byte_size = EXCLUDED.byte_size,
             bytes = EXCLUDED.bytes,
             updated_at = EXCLUDED.updated_at
       RETURNING updated_at`,
      [req.userId, contentType, bytes.length, bytes],
    );
    const { rows } = await client.query<UserRow>(
      'UPDATE users SET avatar_url = $2 WHERE id = $1::UUID RETURNING *',
      [req.userId, uploadedAvatarPath(req.userId, stored[0]!.updated_at)],
    );
    return rows[0]!;
  });

  res.json({ user: serialize(user) });
});

// DELETE /api/users/me/avatar — back to the initials avatar. Idempotent.
router.delete('/me/avatar', async (req, res) => {
  const user = await withTransaction(async (client) => {
    const { rows } = await client.query<UserRow>(
      `UPDATE users SET avatar_url = NULL
       WHERE id = $1::UUID AND is_deleted = false
       RETURNING *`,
      [req.userId],
    );
    if (!rows[0]) throw notFound('User');
    await client.query('DELETE FROM user_avatars WHERE user_id = $1::UUID', [
      req.userId,
    ]);
    return rows[0];
  });
  res.json({ user: serialize(user) });
});

// ── P1-7 Delete account ──────────────────────────────────────────────────────
// Anonymise-in-place rather than deleting the users row. Rationale:
//   * Records preserved — bookings, reviews and payouts keep their history and
//     their FKs stay valid, instead of `ON DELETE CASCADE` silently erasing the
//     earnings ledger a host may still owe money against.
//   * Login is destroyed: email/phone/password_hash are cleared and
//     `is_deleted` is set, so every read surface renders "Deleted user" and
//     the credential endpoints can no longer resolve the account.
//   * Money is settled: guests holding live seats at this host's events are
//     refunded, and the departing guest's own tickets release their seats and
//     roll back the affected events' accrued payouts — all in one transaction.
router.delete('/me', async (req, res) => {
  const { password } = z
    .object({ password: z.string().min(1, 'Confirm your password').max(200) })
    .parse(req.body ?? {});

  const outcome = await withTransaction(async (client) => {
    const { rows } = await client.query<{
      id: string;
      password_hash: string | null;
      is_deleted: boolean;
    }>(
      'SELECT id, password_hash, is_deleted FROM users WHERE id = $1::UUID FOR UPDATE',
      [req.userId],
    );
    const user = rows[0];
    if (!user || user.is_deleted) throw notFound('User');
    if (!user.password_hash) {
      throw new ApiError(
        409,
        'This account has no password yet — sign up with email first.',
      );
    }
    if (!(await verifyPassword(password, user.password_hash))) {
      throw new ApiError(401, 'Your password is incorrect.');
    }

    // Every event whose seat accounting can change: this user's own events and
    // events they still hold a live ticket at.
    const { rows: affected } = await client.query<{ id: string }>(
      `SELECT DISTINCT b.event_id AS id
         FROM bookings b
        WHERE b.user_id = $1::UUID AND b.status IN ('confirmed','pending')
       UNION
       SELECT e.id FROM dinner_events e
        WHERE e.host_id = $1::UUID
          AND e.status IN ('draft','requested','confirmed','live')`,
      [req.userId],
    );

    // 1. Cancel this host's still-open events, with a note guests can read.
    await client.query(
      `UPDATE dinner_events
         SET status = 'cancelled',
             host_note = CASE WHEN host_note = ''
                              THEN 'This host deleted their account.'
                              ELSE host_note END
       WHERE host_id = $1::UUID
         AND status IN ('draft','requested','confirmed','live')`,
      [req.userId],
    );

    // 1b. Cancel all live bookings for this host's events (no gateway needed).
    const gatewaySettlements: never[] = [];

    // 2. Refund guests still holding seats at those events.
    await client.query(
      `UPDATE bookings b
         SET status = 'cancelled',
             checked_in = false,
             payment_status = CASE WHEN b.payment_status IN ('paid','authorized')
                                   THEN 'refunded' ELSE b.payment_status END
        FROM dinner_events e
       WHERE e.id = b.event_id
         AND e.host_id = $1::UUID
         AND b.status IN ('confirmed','pending')`,
      [req.userId],
    );

    // 3. Release the departing guest's own seats at OTHER hosts' events and
    //    put those events' capacity back.
    const { rows: released } = await client.query<{
      event_id: string;
      seats: number;
      total: string;
    }>(
      `UPDATE bookings b
         SET status = 'cancelled',
             checked_in = false,
             payment_status = CASE WHEN b.payment_status IN ('paid','authorized')
                                   THEN 'refunded' ELSE b.payment_status END
       WHERE b.user_id = $1::UUID
         AND b.status IN ('confirmed','pending')
         AND b.event_id NOT IN (SELECT id FROM dinner_events WHERE host_id = $1::UUID)
       RETURNING b.event_id, b.seats, b.total_amount`,
      [req.userId],
    );
    if (released.length > 0) {
      await client.query(
        `UPDATE dinner_events e
           SET seats_booked = GREATEST(0, e.seats_booked - r.held)
          FROM (SELECT event_id, SUM(seats)::int AS held
                  FROM bookings
                 WHERE id = ANY($1::uuid[])
                 GROUP BY event_id) r
         WHERE r.event_id = e.id`,
        [released.map((r) => r.event_id)],
      );
    }

    // 4. Drop the guest from attendee lists they no longer actively hold.
    await client.query(
      `UPDATE dinner_events e
         SET attendee_ids = array_remove(e.attendee_ids, $1::text)
       WHERE $1::text = ANY(e.attendee_ids)
         AND NOT EXISTS (
           SELECT 1 FROM bookings b2
           WHERE b2.event_id = e.id AND b2.user_id = $1::UUID
             AND b2.status <> 'cancelled')`,
      [req.userId],
    );

    // 5. (syncPayout removed — payouts table deleted in Phase 2a)

    // 6. Anonymise the account in place, then revoke every session.
    await client.query(
      `UPDATE users
         SET name = 'Deleted user',
             handle = 'deleted_' || id::text,
             email = NULL,
             phone = NULL,
             password_hash = NULL,
             bio = '',
             city = '',
             home_area = '',
             instagram = '',
             avatar_url = NULL,
             tastes = '{}',
             dietary = '{}',
             allergies = '{}',
             is_deleted = true
       WHERE id = $1::UUID`,
      [req.userId],
    );
    // The photo is personal data too: purge the bytes, not just the pointer.
    await client.query('DELETE FROM user_avatars WHERE user_id = $1::UUID', [
      req.userId,
    ]);
    await client.query('DELETE FROM auth_tokens WHERE user_id = $1::UUID', [
      req.userId,
    ]);

    return {
      refundedSeats: released.reduce((sum, r) => sum + r.seats, 0),
      eventsTouched: affected.length,
      gatewaySettlements,
    };
  });

  // Execute the captured gateway movements outside the anonymisation
  // transaction: the ledger already tells the truth; failures here stay
  // honestly `pending_gateway` for ops follow-up rather than rolling back a
  // deletion the user confirmed with their password.
  const { gatewaySettlements, ...publicOutcome } = outcome;
  // Phase 2a: gateway settlement removed — no Stripe calls needed.

  res.json({ deleted: true, ...publicOutcome });
});

// GET /api/users — People-screen discovery list (P0-3). Registered before
// '/:id' so the literal path is not swallowed by the profile route.
router.get('/', async (req, res) => {
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  const hostsOnly = req.query.hosts === 'true';
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  const offset = Math.max(0, Number(req.query.offset) || 0);

  // Anonymised accounts are not people to discover.
  const conditions: string[] = ['u.is_deleted = false'];
  const params: unknown[] = [req.userId];
  // P2-1: blocked accounts vanish from discovery/search both ways — the
  // blocker never sees the person they blocked, and the blocked person never
  // sees them back. Pure SQL, so pagination stays consistent server-side.
  conditions.push(notBlockedBetween('$1', 'u.id'));
  if (q) {
    conditions.push(`(u.name ILIKE $${params.length + 1} OR u.handle ILIKE $${params.length + 1} OR u.bio ILIKE $${params.length + 1})`);
    params.push(likeTerm(q));
  }
  // `?hosts=true` narrows the roster to accounts that can publish dinners or
  // already have: the host ladder roles plus anyone with a hosted event. The
  // Explore People tab used to fetch 50 users and drop non-hosts client-side,
  // which made real hosts invisible past the first page.
  if (hostsOnly) {
    conditions.push(
      `(u.account_type = 'professional'
        AND (u.role IN ('host','influencer','partner_admin','super_admin')
             OR EXISTS (SELECT 1 FROM dinner_events de WHERE de.host_id = u.id)))`,
    );
  }

  const rows = await query<RosterRow>(
    `SELECT u.*, EXISTS (
       SELECT 1 FROM follows f WHERE f.follower_id = $1::UUID AND f.followee_id = u.id
     ) AS is_following
     FROM users u
     ${conditions.length ? `WHERE ${conditions.join(' AND ')}` : ''}
     ORDER BY u.followers_count DESC, u.name ASC
     LIMIT ${limit} OFFSET ${offset}`,
    params,
  );

  res.json({
    users: rows.map((u) => ({ ...serializePublic(u), isFollowing: u.is_following })),
    count: rows.length,
    offset,
  });
});

// ── Account type (one account, two modes) ────────────────────────────────────

/** Roles that may never be flipped to Personal: they own venues, not hosts. */
const ADMIN_ROLES = ['partner_admin', 'super_admin'];
/** Venue-side roles switch account type through the Partner App, not here. */
const VENUE_ROLES = ['restaurant_owner', 'restaurant_staff'];

const accountTypeSchema = z.object({
  accountType: z.enum(['personal', 'professional']),
});

/**
 * Experiences that block a switch back to Personal: anything guests can still
 * act on. Drafts are excluded on purpose — nobody has booked a draft, and it
 * is still there (unpublished) if the account goes Professional again.
 */
async function activeHostedExperiences(userId: string) {
  return query<{
    id: string;
    title: string;
    start_at: Date;
    status: string;
  }>(
    `SELECT id, title, start_at, status
       FROM dinner_events
      WHERE host_id = $1::UUID
        AND status IN ('requested','confirmed','live')
        AND start_at > now()
      ORDER BY start_at ASC`,
    [userId],
  );
}

/**
 * Applies an account-type change on the SAME account (same login, same id).
 *
 * Going Professional also promotes the role `user → host` so every pre-existing
 * role-based gate (event creation, host roster, earnings) keeps working. Going
 * Personal only flips `account_type`: the role, badges, followers and hosted
 * history all survive, so switching back and forth is lossless.
 */
async function setAccountType(userId: string, accountType: 'personal' | 'professional') {
  const [me] = await query<{ id: string; role: string; account_type: string }>(
    'SELECT id, role, account_type FROM users WHERE id = $1::UUID AND is_deleted = false',
    [userId],
  );
  if (!me) throw notFound('User');

  if (VENUE_ROLES.includes(me.role)) {
    throw forbidden('Venue accounts switch account type in the Partner app');
  }

  if (accountType === 'professional') {
    await query(
      `UPDATE users
          SET account_type = 'professional',
              professional_since = COALESCE(professional_since, now()),
              role = CASE WHEN role = 'user' THEN 'host' ELSE role END
        WHERE id = $1::UUID`,
      [userId],
    );
  } else {
    if (ADMIN_ROLES.includes(me.role)) {
      throw forbidden('Admin accounts cannot switch to a Personal account');
    }
    const blockers = await activeHostedExperiences(userId);
    if (blockers.length > 0) {
      // Blocking (rather than silently unpublishing) keeps every guest's
      // booking intact and gives the host a concrete list to resolve.
      throw new ApiError(
        409,
        `You have ${blockers.length} upcoming experience${blockers.length === 1 ? '' : 's'}. ` +
          'Cancel or complete them before switching to Personal.',
      );
    }
    await query(
      "UPDATE users SET account_type = 'personal' WHERE id = $1::UUID",
      [userId],
    );
  }

  return loadUser(userId);
}

// GET /api/users/me/account-type — current mode, when it was activated and the
// upcoming experiences that currently block a switch back to Personal.
router.get('/me/account-type', async (req, res) => {
  const [me] = await query<{
    account_type: string;
    professional_since: Date | null;
  }>(
    `SELECT account_type, professional_since FROM users
      WHERE id = $1::UUID AND is_deleted = false`,
    [req.userId],
  );
  if (!me) throw notFound('User');
  const blockers = await activeHostedExperiences(req.userId);
  res.json({
    accountType: me.account_type,
    professionalSince: me.professional_since,
    hostStudioEnabled: me.account_type === 'professional',
    blockers: blockers.map((e) => ({
      id: e.id,
      title: e.title,
      startAt: e.start_at,
      status: e.status,
    })),
  });
});

// POST /api/users/me/account-type — switch mode on the same account.
// Personal → Professional promotes the role to host; Professional → Personal
// is blocked while upcoming experiences exist (409) and never auto-cancels.
router.post('/me/account-type', async (req, res) => {
  const { accountType } = accountTypeSchema.parse(req.body ?? {});
  const user = await setAccountType(req.userId, accountType);
  res.json({ user });
});

// POST /api/users/me/host — legacy alias kept for already-installed builds.
// It is now exactly "switch this account to Professional"; the client's real
// entry point is /me/account-type.
router.post('/me/host', async (req, res) => {
  const user = await setAccountType(req.userId, 'professional');
  res.json({ role: user.role, user });
});

// GET /api/users/me/tier — current ladder rung plus progress toward the next.
// The client Profile card reads this to show met/unmet influencer criteria.
router.get('/me/tier', async (req, res) => {
  const [me] = await query<UserRow>(
    'SELECT * FROM users WHERE id = $1::UUID AND is_deleted = false',
    [req.userId],
  );
  if (!me) throw notFound('User');
  res.json(tierInfo(me));
});

// POST /api/users/me/influencer — claim Food Influencer status on the SAME
// account. Idempotent for existing influencers; 403s when the thresholds are
// not met yet (the structured body carries progress + thresholds so the UI can
// show what is missing). Success flips the role and grants the 'verified'
// badge atomically in one UPDATE.
router.post('/me/influencer', async (req, res) => {
  const [me] = await query<UserRow>(
    'SELECT * FROM users WHERE id = $1::UUID AND is_deleted = false',
    [req.userId],
  );
  if (!me) throw notFound('User');
  if (me.role === 'partner_admin' || me.role === 'super_admin') {
    throw forbidden('Your account already has a publishing role');
  }
  if (me.role === 'influencer') {
    res.json({ role: 'influencer', user: await loadUser(me.id) });
    return;
  }
  if (me.role !== 'host') {
    throw forbidden('Enable hosting before claiming influencer status');
  }
  const info = tierInfo(me);
  if (!info.eligible) {
    res.status(403).json({
      error: 'Not eligible yet',
      progress: info.progress,
      thresholds: info.thresholds,
    });
    return;
  }
  await query(
    `UPDATE users
     SET role = 'influencer',
         badges = CASE
           WHEN NOT ('verified' = ANY(badges))
           THEN array_append(badges, 'verified')
           ELSE badges
         END
     WHERE id = $1::UUID`,
    [me.id],
  );
  res.json({ role: 'influencer', user: await loadUser(me.id) });
});

// GET /api/users/me — the signed-in user's own profile.
router.get('/me', async (req, res) => {
  const [user] = await query<UserRow>(
    'SELECT * FROM users WHERE id = $1::UUID AND is_deleted = false',
    [req.userId],
  );
  if (!user) throw notFound('User');
  res.json({ user: serialize(user) });
});

// GET /api/users/handle-available?handle=… — advisory pre-check for the
// profile editor. Exposes exactly what the 409 on PATCH already does (is this
// username claimable?) and nothing else; an invalid value answers 200 with
// `reason: 'invalid'` so the field can render inline feedback instead of an
// error page. Must stay registered BEFORE `GET /:id` so `handle-available` is
// not parsed as a user id.
router.get('/handle-available', async (req, res) => {
  const parsed = handleSchema.safeParse(String(req.query.handle ?? ''));
  if (!parsed.success) {
    res.json({ handle: '', available: false, reason: 'invalid' });
    return;
  }

  const handle = parsed.data;
  if (handle.startsWith('deleted_')) {
    res.json({ handle, available: false, reason: 'reserved' });
    return;
  }

  const [clash] = await query<{ id: string }>(
    `SELECT id FROM users
      WHERE lower(handle) = $1 AND id <> $2::UUID AND is_deleted = false
      LIMIT 1`,
    [handle, req.userId],
  );
  res.json({ handle, available: !clash, reason: clash ? 'taken' : null });
});

// GET /api/users/:id/followers — accounts that follow :id, newest first.
// P1-4: the target can hide who they follow / who follows them. The owner
// always sees their own lists; everyone else gets 403 when the toggle is off.
router.get('/:id/followers', async (req, res) => {
  const target = await loadRosterTarget(req.params.id);
  assertFollowListVisible(target, req.userId);
  await assertProfileAccessible(target.id, req.userId);
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  const offset = Math.max(0, Number(req.query.offset) || 0);

  const rows = await query<RosterRow>(
    `SELECT u.*, EXISTS (
       SELECT 1 FROM follows f2 WHERE f2.follower_id = $1::UUID AND f2.followee_id = u.id
     ) AS is_following
     FROM follows f
     JOIN users u ON u.id = f.follower_id
     WHERE f.followee_id = $2::UUID AND u.is_deleted = false
       AND ${notBlockedBetween('$1', 'u.id')}
     ORDER BY f.created_at DESC
     LIMIT ${limit} OFFSET ${offset}`,
    [req.userId, target.id],
  );

  res.json({
    users: rows.map((u) => ({ ...serializePublic(u), isFollowing: u.is_following })),
    count: rows.length,
    offset,
  });
});

// GET /api/users/:id/following — accounts :id follows, newest first.
router.get('/:id/following', async (req, res) => {
  const target = await loadRosterTarget(req.params.id);
  assertFollowListVisible(target, req.userId);
  await assertProfileAccessible(target.id, req.userId);
  const limit = Math.min(50, Math.max(1, Number(req.query.limit) || 20));
  const offset = Math.max(0, Number(req.query.offset) || 0);

  const rows = await query<RosterRow>(
    `SELECT u.*, EXISTS (
       SELECT 1 FROM follows f2 WHERE f2.follower_id = $1::UUID AND f2.followee_id = u.id
     ) AS is_following
     FROM follows f
     JOIN users u ON u.id = f.followee_id
     WHERE f.follower_id = $2::UUID AND u.is_deleted = false
       AND ${notBlockedBetween('$1', 'u.id')}
     ORDER BY f.created_at DESC
     LIMIT ${limit} OFFSET ${offset}`,
    [req.userId, target.id],
  );

  res.json({
    users: rows.map((u) => ({ ...serializePublic(u), isFollowing: u.is_following })),
    count: rows.length,
    offset,
  });
});

/**
 * Resolves the owner of a follower/following roster. Malformed ids and
 * anonymised accounts 404 (rather than a pg cast 500, or an empty list that
 * implies the account still exists).
 */
async function loadRosterTarget(id: string) {
  if (!isUuid(id)) throw notFound('User');
  const [target] = await query<{ id: string; show_follow_list: boolean }>(
    'SELECT id, show_follow_list FROM users WHERE id = $1::UUID AND is_deleted = false',
    [id],
  );
  if (!target) throw notFound('User');
  return { id: target.id, showFollowList: target.show_follow_list };
}

/**
 * P2-1 block gate for direct profile access. Discovery already hides blocked
 * accounts, but a stale deep link (or a cached id) must not read a blocked
 * profile's data back out of `/users/:id` — either direction of a blocked
 * pair gets a 403 for the OTHER account; viewing your own profile is always
 * allowed. 403 rather than 404: the profile was publicly visible before the
 * block, so pretending it vanished would be the less honest signal.
 */
async function assertProfileAccessible(
  targetId: string,
  viewerId: string,
): Promise<void> {
  if (targetId === viewerId) return;
  if (await isBlockedPair(targetId, viewerId)) {
    throw forbidden('This profile is not available');
  }
}

/**
 * P1-4 privacy gate for the follower/following rosters. `loadUser` already
 * resolved the target, so this is a cheap in-memory check: the toggle hides
 * the list from everyone EXCEPT the owner (who must still be able to manage
 * their own graph). 404 rather than 403 would be the usual way to hide that
 * an account exists, but the profile is already public here, so a clear 403
 * is the honest signal.
 */
function assertFollowListVisible(
  target: { id: string; showFollowList?: boolean },
  viewerId: string,
): void {
  if (target.id === viewerId) return;
  if (target.showFollowList === false) {
    throw forbidden("This user's connections are private");
  }
}

/**
 * P1-4 privacy gate for the activity a profile broadcasts: with `showActivity`
 * off, other users no longer receive the host's upcoming-dinner list. Reviews
 * stay visible — they are the trust record of the platform, not user activity.
 */
function activityVisible(
  target: { id: string; showActivity?: boolean },
  viewerId: string,
): boolean {
  if (target.id === viewerId) return true;
  return target.showActivity !== false;
}

// GET /api/users/:id — profile card plus hosted upcoming events and reviews.
router.get('/:id', async (req, res) => {
  if (!isUuid(req.params.id)) throw notFound('User');
  // Anonymised accounts have no profile page; their reviews and bookings
  // still render elsewhere as "Deleted user".
  const [user] = await query<UserRow>(
    'SELECT * FROM users WHERE id = $1::UUID AND is_deleted = false',
    [req.params.id],
  );
  if (!user) throw notFound('User');
  await assertProfileAccessible(user.id, req.userId);

  const hosted = await query<{
    id: string;
    title: string;
    tagline: string;
    start_at: Date;
    cover_image: string;
    seats_total: number;
    seats_booked: number;
    price_per_seat: string;
    type: string;
  }>(
    `SELECT id, title, tagline, start_at, cover_image, seats_total, seats_booked,
            price_per_seat, type
     FROM dinner_events
     WHERE host_id = $1 AND start_at >= now()
     ORDER BY start_at ASC
     LIMIT 20`,
    [user.id],
  );

  const reviews = await query<{
    id: string;
    rating: string;
    text: string;
    created_at: Date;
    event_title: string;
    author_name: string | null;
    author_handle: string | null;
    author_avatar: string | null;
  }>(
    `SELECT rv.id, rv.rating, rv.text, rv.created_at, e.title AS event_title,
            u.name AS author_name, u.handle AS author_handle,
            u.avatar_url AS author_avatar
     FROM reviews rv
     JOIN dinner_events e ON e.id = rv.event_id
     LEFT JOIN users u ON u.id = rv.author_id
     WHERE e.host_id = $1
     ORDER BY rv.created_at DESC
     LIMIT 10`,
    [user.id],
  );

  const [follow] = await query<{ is_following: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM follows WHERE follower_id = $1 AND followee_id = $2
     ) AS is_following`,
    [req.userId, user.id],
  );

  res.json({
    // Your own profile via this route still gets the full self shape.
    user: user.id === req.userId ? serialize(user) : serializePublic(user),
    viewerFollows: follow?.is_following ?? false,
    // P1-4: the upcoming-dinners list is the profile's public activity feed.
    // Personal accounts are private: nothing they host is advertised publicly
    // (they have no Host Studio to manage it with either).
    hostedUpcoming:
      user.account_type === 'professional' && activityVisible(user, req.userId)
      ? hosted.map((e) => ({
          id: e.id,
          title: e.title,
          tagline: e.tagline,
          startAt: e.start_at,
          coverImage: e.cover_image,
          seatsTotal: e.seats_total,
          seatsBooked: e.seats_booked,
          seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
          pricePerSeat: Number(e.price_per_seat),
          type: e.type,
        }))
      : [],
    reviews: reviews.map((r) => ({
      id: r.id,
      rating: Number(r.rating),
      text: r.text,
      createdAt: r.created_at,
      eventTitle: r.event_title,
      author: {
        name: r.author_name,
        handle: r.author_handle,
        avatarUrl: r.author_avatar,
      },
    })),
  });
});

export default router;
