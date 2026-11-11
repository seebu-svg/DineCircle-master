import type { Request, RequestHandler } from 'express';
import { query } from './db.js';
import { ApiError, forbidden, notFound } from './context.js';
import type { UserRole } from './context.js';

/** 402 Payment Required, subscription entitlement missing. */
export function paymentRequired(plan: string = 'monthly'): ApiError {
  return new ApiError(402, JSON.stringify({ error: 'plan_required', plan }));
}

/**
 * Venue-scoped authorization for the Partner App.
 *
 * Two clients share this API, so "is this token a partner?" is never enough,
 * every venue read/write must also be scoped to the venues the caller belongs
 * to. `restaurant_staff` is the single source of that membership; a venue's
 * `owner_id` counts as an implicit `owner` row so older partner accounts (which
 * still only carry `owner_id`) keep working unchanged.
 *
 * Ranks are ordered so a `minRole` check is a numeric comparison:
 *   staff (day-of operations) < manager (operations) < owner (full control)
 */
export type PartnerRole = 'staff' | 'manager' | 'owner';

const PARTNER_ROLE_RANK: Record<PartnerRole, number> = {
  staff: 1,
  manager: 2,
  owner: 3,
};

/** Roles that may use the Partner App at all. */
export const PARTNER_ROLES: readonly UserRole[] = [
  'partner_admin',
  'super_admin',
  'restaurant_owner',
  'restaurant_staff',
];

export function isPartnerRole(role: UserRole | undefined): boolean {
  return role !== undefined && PARTNER_ROLES.includes(role);
}

/**
 * Gate for every /api/partner route. Authentication already happened globally;
 * this rejects plain diners and hosts with a 403 instead of leaking venue data.
 *
 * A partner-role token is accepted outright *and* so is any account holding a
 * live venue membership, a host who registers a venue keeps the host role
 * (and its publishing rights) instead of being downgraded to `restaurant_owner`.
 */
export const requirePartner: RequestHandler = async (req, _res, next) => {
  try {
    if (isPartnerRole(req.userRole)) {
      next();
      return;
    }
    const [row] = await query<{ ok: boolean }>(
      `SELECT (EXISTS (SELECT 1 FROM restaurants WHERE owner_id = $1::UUID)
            OR EXISTS (SELECT 1 FROM restaurant_staff
                        WHERE user_id = $1::UUID AND status = 'active')) AS ok`,
      [req.userId],
    );
    if (row?.ok) {
      next();
      return;
    }
    next(forbidden('Partner access requires a restaurant account'));
  } catch (error) {
    next(error);
  }
};

/** super_admin sees every venue; everyone else sees their membership set. */
export function seesAllVenues(role: UserRole): boolean {
  return role === 'super_admin';
}

/**
 * Effective role for one venue, or null when the caller has no relationship to
 * it. Never throws, callers decide between 403 and 404.
 */
export async function effectivePartnerRole(
  userId: string,
  userRole: UserRole,
  restaurantId: string,
): Promise<PartnerRole | null> {
  if (seesAllVenues(userRole)) {
    const [venue] = await query<{ id: string }>(
      'SELECT id FROM restaurants WHERE id = $1::UUID',
      [restaurantId],
    );
    return venue ? 'owner' : null;
  }

  const [row] = await query<{ role: string | null; owns: boolean }>(
    `SELECT s.role, (r.owner_id = $2::UUID) AS owns
       FROM restaurants r
       LEFT JOIN restaurant_staff s
         ON s.restaurant_id = r.id AND s.user_id = $2::UUID AND s.status = 'active'
      WHERE r.id = $1::UUID`,
    [restaurantId, userId],
  );
  if (!row) return null;
  if (row.owns) return 'owner';
  if (row.role === null) return null;
  return row.role as PartnerRole;
}

/**
 * Assert the caller may act on a venue at `minRole` or above.
 *
 * Distinguishes the two failure modes on purpose: 404 when the venue does not
 * exist, 403 when it exists but belongs to someone else. Cross-venue probes
 * therefore cannot be used to enumerate other partners' venue ids.
 */
export async function requireVenueRole(
  req: Request,
  restaurantId: string,
  minRole: PartnerRole = 'staff',
): Promise<PartnerRole> {
  const role = await effectivePartnerRole(req.userId, req.userRole, restaurantId);
  if (role === null) {
    const [venue] = await query<{ id: string }>(
      'SELECT id FROM restaurants WHERE id = $1::UUID',
      [restaurantId],
    );
    if (!venue) throw notFound('Restaurant');
    throw forbidden('You do not have access to this restaurant');
  }
  if (PARTNER_ROLE_RANK[role] < PARTNER_ROLE_RANK[minRole]) {
    throw forbidden(`This action requires the ${minRole} role for this restaurant`);
  }
  return role;
}

/**
 * Venue ids the caller may see. `'all'` is returned for platform admins so
 * list queries can skip the id array entirely (and avoid an unbounded array
 * parameter on a large platform).
 */
export async function scopedRestaurantIds(
  userId: string,
  userRole: UserRole,
): Promise<string[] | 'all'> {
  if (seesAllVenues(userRole)) return 'all';
  const rows = await query<{ id: string }>(
    `SELECT r.id
       FROM restaurants r
       LEFT JOIN restaurant_staff s
         ON s.restaurant_id = r.id AND s.user_id = $1::UUID AND s.status = 'active'
      WHERE r.owner_id = $1::UUID OR s.user_id IS NOT NULL`,
    [userId],
  );
  return rows.map((r) => r.id);
}

/**
 * SQL fragment restricting `column` (a restaurant id column) to a venue scope,
 * appending the needed parameter. Returns a clause that is always safe to AND
 * into a WHERE: admins get `TRUE`, a partner with no venues gets `FALSE`.
 */
export function venueScopeClause(
  column: string,
  scope: string[] | 'all',
  params: unknown[],
): string {
  if (scope === 'all') return 'TRUE';
  if (scope.length === 0) return 'FALSE';
  params.push(scope);
  return `${column} = ANY($${params.length}::uuid[])`;
}

/** Throws 403 unless the caller is a platform operator (verification queue). */
export function requirePlatformAdmin(req: Request): void {
  if (req.userRole !== 'super_admin') {
    throw forbidden('Platform administration requires a super admin account');
  }
}

/** Roles allowed to sign in to the admin console. */
export const ADMIN_CONSOLE_ROLES: readonly UserRole[] = ['super_admin', 'partner_admin'];

export function isAdminConsoleRole(role: UserRole | undefined): boolean {
  return role !== undefined && ADMIN_CONSOLE_ROLES.includes(role);
}

/**
 * Gate for every /api/admin/* console endpoint.
 *
 * Wider than `requirePlatformAdmin` on purpose: the console ships a
 * partner-admin persona that works the operations queues, so both admin roles
 * pass. The narrower super-admin check stays on the endpoints that mint
 * accounts or change money, and the persona's `admin_scope` is a UI concern
 * (which nav items render) rather than an authorization boundary, so it is
 * never consulted here.
 */
export function requireAdminConsole(req: Request): void {
  if (!isAdminConsoleRole(req.userRole)) {
    throw forbidden('Admin console access requires an admin role');
  }
}

/** Throws 403 unless the caller is a super admin (money and account minting). */
export function requireSuperAdmin(req: Request): void {
  requireAdminConsole(req);
  if (req.userRole !== 'super_admin') {
    throw forbidden('This action requires a super admin account');
  }
}

/**
 * Whether a venue still has to be verified before it can sell anything.
 * `pending_review` / `unverified` / `rejected` are all non-selling states.
 */
export function isVerifiedVenue(status: string): boolean {
  return status === 'verified';
}

export type VenueGate = {
  id: string;
  is_partner: boolean;
  partnership_status: string;
  requires_host_approval: boolean;
};

/** Loads the columns every venue gate needs, 404ing on an unknown id. */
export async function loadVenueGate(restaurantId: string): Promise<VenueGate> {
  const [venue] = await query<VenueGate>(
    `SELECT id, is_partner, partnership_status, requires_host_approval
       FROM restaurants WHERE id = $1::UUID`,
    [restaurantId],
  );
  if (!venue) throw notFound('Restaurant');
  return venue;
}

/** 409 helper: state transition attempted from an invalid status. */
export function conflict(what: string, detail: string): ApiError {
  return new ApiError(409, `${what}: ${detail}`);
}

// ── Subscription entitlement middleware ──────────────────────────────────────

type SubscriptionStatus = 'none' | 'trialing' | 'active' | 'past_due' | 'cancelled';

interface SubscriptionCheck {
  status: SubscriptionStatus;
  created_at: Date;
  cancelled_at: Date | null;
  period_end: Date | null;
}

/**
 * Phase 3: require active subscription for partner modules.
 *
 * Grace periods:
 * - trialing: 14 days from creation
 * - past_due: read-only (GET requests allowed, mutations blocked)
 * - cancelled: 7 days from cancellation
 * - none/active: straightforward allow/block
 *
 * @param allowReadOnly - if true, GET requests are allowed even for past_due
 */
export function requireActiveSubscription(allowReadOnly = false): RequestHandler {
  return async (req, _res, next) => {
    try {
      const restaurantId = req.params.restaurantId;
      if (!restaurantId) {
        return next();
      }

      const [sub] = await query<SubscriptionCheck>(
        `SELECT status, created_at, cancelled_at, period_end
         FROM partner_subscriptions
         WHERE restaurant_id = $1::UUID`,
        [restaurantId],
      );

      const now = new Date();

      // No subscription record → block
      if (!sub) {
        return next(paymentRequired());
      }

      const status = sub.status as SubscriptionStatus;

      // Active → allow
      if (status === 'active') {
        return next();
      }

      // Trialing → allow if within 14 days
      if (status === 'trialing') {
        const trialEnd = new Date(sub.created_at);
        trialEnd.setDate(trialEnd.getDate() + 14);
        if (now <= trialEnd) {
          return next();
        }
        // Trial expired → treat as past_due
        return allowReadOnly && req.method === 'GET'
          ? next()
          : next(paymentRequired());
      }

      // Past due → read-only allowed if flag set
      if (status === 'past_due') {
        return allowReadOnly && req.method === 'GET'
          ? next()
          : next(paymentRequired());
      }

      // Cancelled → allow if within 7 days of cancellation
      if (status === 'cancelled') {
        if (sub.cancelled_at) {
          const graceEnd = new Date(sub.cancelled_at);
          graceEnd.setDate(graceEnd.getDate() + 7);
          if (now <= graceEnd) {
            return next();
          }
        }
        return next(paymentRequired());
      }

      // None or unknown → block
      next(paymentRequired());
    } catch (error) {
      next(error);
    }
  };
}
