import { query } from './db.js';

/**
 * P2-1 blocking, shared server-side enforcement primitives.
 *
 * A block is stored as ONE directed row (blocker → blocked) in `user_blocks`,
 * but every safety rule is symmetric: once either user has blocked the other,
 * the pair may not follow, discover, view profiles of, chat against, or book
 * each other. These helpers are the single place that question is asked, so
 * enforcement cannot drift route-by-route.
 */

/** True when either user has blocked the other (either direction). */
export async function isBlockedPair(a: string, b: string): Promise<boolean> {
  const [row] = await query<{ blocked: boolean }>(
    `SELECT EXISTS (
       SELECT 1 FROM user_blocks
       WHERE (blocker_id = $1::UUID AND blocked_id = $2::UUID)
          OR (blocker_id = $2::UUID AND blocked_id = $1::UUID)
     ) AS blocked`,
    [a, b],
  );
  return row?.blocked ?? false;
}

/**
 * SQL predicate that is FALSE for every row whose owner (`ownerColumn`, e.g.
 * `u.id` or `e.host_id`) forms a blocked pair with the viewer bound to
 * `viewerPlaceholder` (e.g. `$2`). Use it inside an existing WHERE so blocked
 * accounts vanish from discovery, search and feeds without a second query.
 */
export function notBlockedBetween(
  viewerPlaceholder: string,
  ownerColumn: string,
): string {
  return `(NOT EXISTS (
    SELECT 1 FROM user_blocks ub
    WHERE (ub.blocker_id = ${viewerPlaceholder}::UUID AND ub.blocked_id = ${ownerColumn})
       OR (ub.blocked_id = ${viewerPlaceholder}::UUID AND ub.blocker_id = ${ownerColumn})
  ))`;
}
