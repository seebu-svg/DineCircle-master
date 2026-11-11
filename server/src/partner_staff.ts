import { query } from './db.js';
import { ApiError, notFound } from './context.js';
import { hashPassword } from './passwords.js';

/**
 * The single implementation of "put a person on a venue's staff list".
 *
 * Two callers need it: the Partner App owner inviting someone who already has
 * an account (`POST /api/partner/restaurants/:restaurantId/staff`) and the admin
 * console creating a partner account from scratch (`POST /api/admin/partner-accounts`).
 * The invite row, its `invited` status and the desk notification must be
 * identical, otherwise a console-created team member would appear in a
 * different state than one the partner added themselves.
 *
 * Account minting stays deliberately boring: the same `handle`/accent rules the
 * signup path uses (see `routes/auth.ts`), and no claim anywhere that an email
 * was sent, because no mail provider is configured on this deployment.
 */
export type StaffInviteRole = 'owner' | 'manager' | 'staff';

export type StaffInviteResult = {
  userId: string;
  name: string;
  email: string | null;
  role: StaffInviteRole;
  status: 'invited';
  created: boolean;
};

/** Mirrors `uniqueHandle` in routes/auth.ts so minted accounts look seeded. */
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

async function createPartnerAccount(input: {
  name: string;
  email: string;
  password: string;
  role: 'restaurant_owner';
}): Promise<{ id: string; name: string; email: string }> {
  const [taken] = await query<{ id: string }>(
    'SELECT id FROM users WHERE lower(email) = lower($1)',
    [input.email],
  );
  if (taken) {
    throw new ApiError(409, 'An account with that email already exists.');
  }

  const handle = await uniqueHandle(input.email);
  const accent = ACCENT_COLORS[input.email.length % ACCENT_COLORS.length];
  const passwordHash = await hashPassword(input.password);

  const [created] = await query<{ id: string }>(
    `INSERT INTO users (name, handle, email, password_hash, city, bio, joined_year,
                        accent_hex, role, account_type)
     VALUES ($1, $2, $3, $4, 'Karachi', '', $5, $6, $7, 'personal')
     RETURNING id`,
    [
      input.name,
      handle,
      input.email,
      passwordHash,
      new Date().getFullYear(),
      accent,
      input.role,
    ],
  );
  if (!created) throw new ApiError(500, 'Could not create the account');

  return { id: created.id, name: input.name, email: input.email };
}

/**
 * Invite a person into a venue. When `createIfMissing` is set and no account
 * matches `email`, one is minted with `partnerRole` (the admin-console path).
 * Without it, an unknown email/phone is a 404, which is what keeps the Partner
 * App on the single auth path for account creation.
 */
export async function inviteStaffToVenue(input: {
  restaurantId: string;
  role: StaffInviteRole;
  actorId: string;
  actorIsAdmin: boolean;
  email?: string;
  phone?: string;
  name?: string;
  password?: string;
  createIfMissing?: boolean;
}): Promise<StaffInviteResult> {
  let target: { id: string; name: string; email: string | null } | undefined;
  let created = false;

  if (input.createIfMissing && input.email) {
    const [existing] = await query<{ id: string; name: string; email: string | null }>(
      'SELECT id, name, email FROM users WHERE lower(email) = lower($1)',
      [input.email],
    );
    if (existing) {
      target = existing;
    } else {
      const account = await createPartnerAccount({
        name: (input.name ?? '').trim() || input.email.split('@')[0]!,
        email: input.email,
        password: input.password ?? 'dinecircle123',
        role: 'restaurant_owner',
      });
      target = { id: account.id, name: account.name, email: account.email };
      created = true;
    }
  } else {
    if (!input.email && !input.phone) {
      throw new ApiError(400, 'Provide the email or phone of an existing account');
    }
    const [found] = await query<{ id: string; name: string; email: string | null }>(
      `SELECT id, name, email FROM users
        WHERE ($1::text IS NOT NULL AND lower(email) = lower($1))
           OR ($2::text IS NOT NULL AND phone = $2)
        LIMIT 1`,
      [input.email ?? null, input.phone ?? null],
    );
    if (!found) throw notFound('Account for that email/phone');
    target = found;
  }

  await query(
    `INSERT INTO restaurant_staff (user_id, restaurant_id, role, status, invited_by)
     VALUES ($1::UUID, $2::UUID, $3, 'invited', $4::UUID)
     ON CONFLICT (user_id, restaurant_id)
     DO UPDATE SET role = EXCLUDED.role, status = 'invited',
                   invited_by = EXCLUDED.invited_by, updated_at = now()`,
    [target.id, input.restaurantId, input.role, input.actorId],
  );

  // The invitee gains access only on acceptance (see the accept endpoint), so a
  // mis-typed invite can never silently grant partner-role access.
  const actorLabel = input.actorIsAdmin ? 'An admin' : 'A venue owner';
  await query(
    `INSERT INTO notifications (restaurant_id, title, body, category, read)
     VALUES ($1::UUID, 'Staff invite', $2, 'staff', false)`,
    [input.restaurantId, `${actorLabel} invited ${target.name} as ${input.role}.`],
  );

  return {
    userId: target.id,
    name: target.name,
    email: target.email,
    role: input.role,
    status: 'invited',
    created,
  };
}
