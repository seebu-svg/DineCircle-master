import type { Request, Response, NextFunction, RequestHandler } from 'express';
import { query } from './db.js';
import { hashToken } from './security.js';

/** Recognised roles in the unified schema. */
export type UserRole =
  | 'user'
  | 'host'
  | 'influencer'
  | 'partner_admin'
  | 'super_admin'
  // Partner App (venue-side) roles. Deliberately outside the diner→host→
  // influencer ladder: a restaurant account operates venues, it does not
  // publish dinners as a host unless it also earns the host rung.
  | 'restaurant_owner'
  | 'restaurant_staff';

/**
 * The customer-facing account mode, orthogonal to [UserRole].
 *
 * One account has two modes: 'personal' (private diner, the default) and
 * 'professional' (public host profile + Host Studio). `role` still decides
 * admin/partner privileges and the influencer badge; `account_type` alone
 * decides whether the customer Host Studio is open.
 */
export type AccountType = 'personal' | 'professional';

/**
 * Which half of the admin console a persona is shown. Gates navigation in the
 * browser only; every `/api/admin` endpoint checks the role, not the scope, so
 * a hidden module cannot be reached by typing a URL.
 */
export type AdminScope = 'full' | 'operations' | 'trust_safety' | 'finance' | 'support';

/**
 * Single-account growth ladder: diner ('user') → host → influencer.
 * An influencer keeps every host capability (publishing, earnings, Host
 * Studio); partner/super admins also publish but sit outside the ladder.
 */
export function hasHostCapabilities(role: UserRole): boolean {
  return (
    role === 'host' ||
    role === 'influencer' ||
    role === 'partner_admin' ||
    role === 'super_admin'
  );
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      /** The acting user's UUID, resolved from the Bearer token. */
      userId: string;
      /** The acting user's role, loaded by requireAuth. */
      userRole: UserRole;
      /** The acting user's account mode ('personal' | 'professional'). */
      accountType: AccountType;
      /** Admin-console persona scope, read by the console UI only. */
      adminScope?: AdminScope;
    }
  }
}

export class ApiError extends Error {
  constructor(
    readonly status: number,
    message: string,
    /**
     * Extra machine-readable fields merged into the error body, so a client can
     * branch on `code` instead of parsing prose or re-parsing a stringified
     * JSON payload out of `error`.
     */
    readonly details?: Record<string, unknown>,
  ) {
    super(message);
  }
}

export const notFound = (what: string): ApiError =>
  new ApiError(404, `${what} not found`);

export const forbidden = (why: string): ApiError => new ApiError(403, why);

export const unauthorized = (): ApiError =>
  new ApiError(401, 'Sign in to continue');

/**
 * Resolves the acting user from the Authorization: Bearer <token> header.
 * Tokens live in auth_tokens with a 30-day expiry.
 */
export const requireAuth: RequestHandler = async (
  req: Request,
  _res: Response,
  next: NextFunction,
) => {
  try {
    const header = req.header('Authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7).trim() : '';
    if (token === '') throw unauthorized();

    const [session] = await query<{
      user_id: string;
      role: string;
      account_type: string;
      admin_scope: string;
      suspended_at: Date | null;
    }>(
      `SELECT at.user_id, u.role, u.account_type, u.admin_scope, u.suspended_at
       FROM auth_tokens at
       JOIN users u ON u.id = at.user_id
       WHERE at.token = $1 AND at.expires_at > now() AND NOT u.is_deleted`,
      [hashToken(token)],
    );
    if (!session) throw unauthorized();
    // An admin suspension freezes the account on every surface at once, the
    // same way a deleted one does. The console's suspend action and the report
    // resolver both write this column, so no client needs its own kill switch.
    if (session.suspended_at) {
      throw forbidden('This account has been suspended. Contact support.');
    }

    req.userId = session.user_id;
    req.userRole = session.role as UserRole;
    req.accountType = session.account_type as AccountType;
    req.adminScope = session.admin_scope as AdminScope;
    next();
  } catch (error) {
    next(error);
  }
};

/**
 * Middleware factory: restrict access to specific roles.
 * Usage: router.get('/', requireRole('partner_admin', 'super_admin'), handler)
 */
export function requireRole(...roles: UserRole[]): RequestHandler {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.userRole || !roles.includes(req.userRole)) {
      return next(forbidden('Insufficient permissions'));
    }
    next();
  };
}

/**
 * Venue-side and platform-admin roles that operate outside the customer
 * account-type switch. They keep their existing Host Studio-adjacent surfaces
 * (the Partner App reads `/hosts/:id/summary` for venue events), so excluding
 * them keeps that app working unchanged.
 */
const ACCOUNT_TYPE_EXEMPT_ROLES: readonly UserRole[] = [
  'super_admin',
  'partner_admin',
  'restaurant_owner',
  'restaurant_staff',
];

/**
 * Enforces the Host Studio gate server-side: personal accounts cannot publish
 * or manage experiences, whatever their historical `role` is. Mirrors the
 * client's `canHostProvider` so the UI can never be the only protection.
 */
export const requireHostStudio: RequestHandler = (
  req: Request,
  _res: Response,
  next: NextFunction,
) => {
  if (req.accountType === 'professional') return next();
  if (ACCOUNT_TYPE_EXEMPT_ROLES.includes(req.userRole)) return next();
  return next(
    forbidden('Switch to a Professional account to use Host Studio'),
  );
};

/**
 * Keys the caller actually sent, read from the raw body before Zod parses it.
 *
 * Zod's `.partial()` wraps each field in `ZodOptional` but *keeps* the inner
 * `.default()`, so an absent key still comes back populated. A PATCH handler
 * that trusts the parsed object therefore cannot tell "not sent" apart from
 * "sent as the default" and will overwrite columns the caller never touched.
 * Build the SET list off these keys instead.
 */
export function patchKeys(body: unknown): Set<string> {
  if (body === null || typeof body !== 'object') return new Set();
  return new Set(Object.keys(body as Record<string, unknown>));
}

/** Serializes the current user for auth endpoints (full profile shape). */
export async function loadUser(id: string) {
  const [user] = await query<{
    id: string; name: string; handle: string; phone: string | null;
    email: string | null; city: string; bio: string; followers_count: number;
    following_count: number; dinners_hosted: number; dinners_joined: number;
    rating: string; review_count: number; avatar_url: string | null;
    badges: string[]; tastes: string[]; accent_hex: string | null;
    joined_year: number; role: string; instagram: string | null;
    // Account & Settings (P1), the Settings screens read these straight off
    // the session bootstrap, so they must be part of the `/auth/me` shape.
    home_area: string; dietary: string[]; allergies: string[];
    show_follow_list: boolean; show_activity: boolean;
    dm_from_followers_only: boolean; allow_tagging: boolean;
    // Customer account mode, drives the Host Studio gate on both ends.
    account_type: string; professional_since: Date | null;
    // Admin console persona + state. Additive, the mobile clients ignore them.
    admin_scope: string; suspended_at: Date | null; suspension_reason: string;
  }>('SELECT * FROM users WHERE id = $1', [id]);
  if (!user) throw notFound('User');
  return {
    id: user.id,
    name: user.name,
    handle: user.handle,
    phone: user.phone,
    email: user.email,
    city: user.city,
    bio: user.bio,
    followers: user.followers_count,
    following: user.following_count,
    dinnersHosted: user.dinners_hosted,
    dinnersJoined: user.dinners_joined,
    rating: Number(user.rating),
    reviewCount: user.review_count,
    avatarUrl: user.avatar_url,
    badges: user.badges,
    tastes: user.tastes,
    accentHex: user.accent_hex,
    joinedYear: user.joined_year,
    role: user.role,
    accountType: user.account_type,
    professionalSince: user.professional_since,
    // Bare username (seed rows store `@name`), matching `PATCH /users/me`.
    instagram: (user.instagram ?? '').trim().replace(/^@+/, ''),
    homeArea: user.home_area,
    dietary: user.dietary,
    allergies: user.allergies,
    showFollowList: user.show_follow_list,
    showActivity: user.show_activity,
    dmFromFollowersOnly: user.dm_from_followers_only,
    allowTagging: user.allow_tagging,
    isInfluencer: user.role === 'influencer',
    isVerified: user.badges.includes('verified') || user.role === 'influencer',
    // Console-only: which nav sections the signed-in persona may see, and
    // whether the account is currently frozen by an admin suspension.
    adminScope: user.admin_scope,
    suspendedAt: user.suspended_at,
    suspensionReason: user.suspension_reason,
  };
}
