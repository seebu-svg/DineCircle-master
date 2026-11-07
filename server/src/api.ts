import type { Request } from 'express';

/**
 * Response/pagination conventions for the Partner API.
 *
 * The Customer App predates these helpers and keeps its existing envelopes
 * verbatim (changing them would break the shipped client). Every *new* partner
 * endpoint uses the shape below so the Partner App has one contract to code
 * against:
 *
 *   { data: <payload>, meta: { page, limit, total, hasMore } }   ← lists
 *   { data: <resource> }                                        ← single
 *   { error: string, issues?: [...] }                           ← errors (global handler)
 *
 * `data` is always an object (never a bare array) so fields can be added
 * without breaking clients; the resource name is the single key inside it.
 */
export type Pagination = {
  page: number;
  limit: number;
  offset: number;
};

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 200;

/**
 * Parses `?page=&limit=` (1-based page, bounded limit). Deliberately tolerant:
 * non-numeric input falls back to defaults rather than 400ing, because a
 * dashboard page that renders nothing is friendlier than a hard error, and the
 * numeric columns are parameterised either way.
 */
export function parsePagination(
  query: Record<string, unknown>,
  options: { defaultLimit?: number; maxLimit?: number } = {},
): Pagination {
  const maxLimit = options.maxLimit ?? MAX_LIMIT;
  const defaultLimit = options.defaultLimit ?? DEFAULT_LIMIT;

  const rawLimit = Number(query.limit);
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(Math.floor(rawLimit), maxLimit)
      : defaultLimit;

  const rawPage = Number(query.page);
  const page = Number.isFinite(rawPage) && rawPage > 0 ? Math.floor(rawPage) : 1;

  return { page, limit, offset: (page - 1) * limit };
}

export type Meta = {
  page: number;
  limit: number;
  total: number;
  hasMore: boolean;
};

export function meta(page: Pagination, total: number): Meta {
  return {
    page: page.page,
    limit: page.limit,
    total,
    hasMore: page.offset + page.limit < total,
  };
}

/** `GET /x` list response. */
export function list<T>(key: string, rows: T[], page: Pagination, total: number) {
  return { data: { [key]: rows }, meta: meta(page, total) };
}

/** `GET /x/:id` or mutation response. */
export function one<T>(key: string, resource: T) {
  return { data: { [key]: resource } };
}

/**
 * Reads an optional ISO date/datetime query parameter.
 * Returns null when absent or unparseable so callers can apply their default.
 */
export function optionalDate(value: unknown): Date | null {
  if (typeof value !== 'string' || value.trim() === '') return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/** Reads an optional non-empty string query parameter. */
export function optionalString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed === '' ? null : trimmed;
}

/** True when the request carries `?flag=true`/`1`/`yes`. */
export function flag(value: unknown): boolean {
  return value === true || value === 'true' || value === '1' || value === 'yes';
}

/**
 * The acting user id, asserted present. Every partner route is mounted behind
 * `requireAuth`, so a missing id means a wiring mistake, fail closed with 401
 * rather than issuing a query with `undefined`.
 */
export function actorId(req: Request): string {
  if (!req.userId) {
    throw new Error('actorId used on an unauthenticated route');
  }
  return req.userId;
}
