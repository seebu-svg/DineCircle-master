import type { Response } from 'express';
import { z } from 'zod';
import type { Request } from 'express';
import { query } from '../../db.js';
import { notFound } from '../../context.js';
import { list, parsePagination, type Pagination } from '../../api.js';

/**
 * Conventions shared by every `/api/admin/*` router.
 *
 * The console is the only client of these routes, so they all answer with the
 * same envelope the Partner API already uses (`{ data: { key: rows }, meta }`),
 * all page with `?page=&limit=` capped at 100, and all accept `?q=` as a
 * case-insensitive search over the module's own text columns. Keeping that in
 * one place is what lets a new view module be added without re-deriving the
 * count-then-fetch dance each time.
 */

export const PAGE_OPTIONS = { defaultLimit: 20, maxLimit: 100 };

export function adminPage(req: Request): Pagination {
  return parsePagination(req.query as Record<string, unknown>, PAGE_OPTIONS);
}

/** Trims a search term to something safe to put inside an ILIKE pattern. */
export function searchTerm(req: Request): string {
  const raw = typeof req.query.q === 'string' ? req.query.q.trim() : '';
  return raw.slice(0, 80);
}

/**
 * Appends `(<col> ILIKE $n OR ...)` to `where` when a search term exists.
 * Returns nothing; callers mutate the arrays they passed in.
 */
export function pushSearch(
  where: string[],
  params: unknown[],
  term: string,
  columns: string[],
): void {
  if (term === '') return;
  params.push(`%${term.replace(/[%_]/g, (m) => `\\${m}`)}%`);
  const clause = columns.map((c) => `${c} ILIKE $${params.length}`).join(' OR ');
  where.push(`(${clause})`);
}

/** Adds an equality filter only when the query parameter is non-empty. */
export function pushEquals(
  where: string[],
  params: unknown[],
  value: string | undefined,
  column: string,
): void {
  const trimmed = (value ?? '').trim();
  if (trimmed === '' || trimmed === 'all') return;
  params.push(trimmed);
  where.push(`${column} = $${params.length}`);
}

export type ListSpec<T> = {
  /** Column list without the leading `SELECT`. */
  select: string;
  /** `FROM ...` including any joins. */
  from: string;
  where: string[];
  params: unknown[];
  order: string;
  page: Pagination;
  /**
   * Set when the list aggregates per row (partner accounts collect their venue
   * memberships, venues collect their staff). The count then has to count
   * groups rather than join-expanded rows, or `meta.total` would say 400 for
   * 60 accounts.
   */
  groupBy?: string;
};

/**
 * Runs the count and the page for one list endpoint and writes the envelope.
 * `where` may be empty, in which case no WHERE clause is emitted.
 */
export async function renderList<T extends Record<string, unknown>>(
  res: Response,
  key: string,
  spec: ListSpec<T>,
  map: (row: T) => Record<string, unknown>,
): Promise<void> {
  const where = spec.where.length > 0 ? `WHERE ${spec.where.join(' AND ')}` : '';
  const groupBy = spec.groupBy ? ` ${spec.groupBy}` : '';

  const countSql = groupBy
    ? `SELECT count(*)::int AS count FROM (SELECT 1 AS k ${spec.from} ${where}${groupBy}) grouped`
    : `SELECT count(*)::int AS count ${spec.from} ${where}`;
  const [totalRow] = await query<{ count: number }>(countSql, spec.params);

  const rows = await query<T & Record<string, unknown>>(
    `SELECT ${spec.select} ${spec.from} ${where}${groupBy}
      ORDER BY ${spec.order}
      LIMIT $${spec.params.length + 1} OFFSET $${spec.params.length + 2}`,
    [...spec.params, spec.page.limit, spec.page.offset],
  );

  res.json(list(key, rows.map(map), spec.page, totalRow?.count ?? 0));
}

/** `?status=`/`?kind=` style enum guard so a typo cannot reach the SQL. */

/** Loads one row or 404s, used by every detail endpoint. */
export async function requireRow<T>(
  text: string,
  params: unknown[],
  what: string,
): Promise<T> {
  const [row] = await query<T & Record<string, unknown>>(text, params);
  if (!row) throw notFound(what);
  return row;
}

/** Writes a manual audit row for console actions the middleware cannot infer. */
export async function recordAudit(input: {
  userId: string;
  action: string;
  resource: string;
  resourceId: string;
  changes: Record<string, unknown>;
}): Promise<void> {
  await query(
    `INSERT INTO audit_log (user_id, action, resource, resource_id, changes, status_code)
     VALUES ($1::UUID, $2, $3, $4, $5::jsonb, 200)`,
    [
      input.userId,
      input.action,
      input.resource,
      input.resourceId,
      JSON.stringify(input.changes),
    ],
  );
}

export const noteSchema = z.string().trim().max(1000).default('');

/** `YYYY-MM` bucket key for the last `months` calendar months, oldest first. */
export function monthBuckets(months: number): string[] {
  const out: string[] = [];
  const now = new Date();
  for (let back = months - 1; back >= 0; back -= 1) {
    const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - back, 1));
    out.push(`${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`);
  }
  return out;
}

/** Fills a `{month: value}` result set into a fixed-length monthly series. */
export function toSeries(
  rows: Array<{ bucket: string; value: number }>,
  buckets: string[],
): Array<{ month: string; value: number }> {
  const found = new Map(rows.map((r) => [r.bucket, Number(r.value)]));
  return buckets.map((month) => ({ month, value: found.get(month) ?? 0 }));
}
