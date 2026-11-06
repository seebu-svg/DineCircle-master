/**
 * DineCircle universal search primitives.
 *
 * Everything here is deliberately free of database access: the escaping,
 * ranking tiers, parameter parsing and suggestion merging are pure functions
 * so `tests/search_unit.test.ts` can pin them without a live Postgres. The
 * route (`routes/search.ts`) only assembles SQL around these helpers.
 */

export const SEARCH_CATEGORIES = [
  'restaurants',
  'menu',
  'deals',
  'experiences',
  'hosts',
] as const;

export type SearchCategory = (typeof SEARCH_CATEGORIES)[number];

/** Deal kinds accepted by `restaurant_deals.kind`. */
export const DEAL_KINDS = ['percent', 'fixed', 'package'] as const;
export type DealKind = (typeof DEAL_KINDS)[number];

/** Sort modes for the aggregate endpoint. */
export const SEARCH_SORTS = ['relevant', 'rating', 'soon', 'priceAsc'] as const;
export type SearchSort = (typeof SEARCH_SORTS)[number];

export const SEARCH_QUERY_MAX = 80;
export const SEARCH_LIMIT_DEFAULT = 10;
export const SEARCH_LIMIT_MAX = 20;
export const SUGGESTIONS_MAX = 8;

export type SuggestionKind =
  | 'restaurant'
  | 'cuisine'
  | 'menu'
  | 'deal'
  | 'experience'
  | 'host';

export type Suggestion = {
  text: string;
  kind: SuggestionKind;
  refId: string | null;
  rank: number;
};

/**
 * Neutralise the LIKE/ILIKE metacharacters so a query such as `50%` or
 * `a_b` matches those characters literally instead of turning into wildcards.
 * Backslash goes first so the escapes it introduces are not escaped again.
 */
export function escapeLike(term: string): string {
  return term.replace(/[\\%_]/g, (char) => `\\${char}`);
}

/** `%term%` pattern with every wildcard inside the term escaped. */
export function likeTerm(term: string): string {
  return `%${escapeLike(term)}%`;
}

/** `prefix%` pattern (used for typeahead ordering). */
export function prefixTerm(term: string): string {
  return `${escapeLike(term)}%`;
}

/**
 * Relevance tiers shared by every category: 0 exact name, 1 prefix, 2 word
 * prefix, 3 anything else. `placeholder` is the raw (unescaped) query
 * parameter, so `lower(x) = lower($n)` can use it directly.
 */
export function rankSql(alias: string, placeholder: string, column = 'name'): string {
  return `CASE
    WHEN lower(${alias}.${column}) = lower(${placeholder}) THEN 0
    WHEN lower(${alias}.${column}) LIKE lower(${placeholder}) || '%' THEN 1
    WHEN lower(${alias}.${column}) LIKE '% ' || lower(${placeholder}) || '%' THEN 2
    ELSE 3 END`;
}

/**
 * Relevance tier for one typeahead string: 0 exact, 1 prefix, 2 contains,
 * 3 no visible relationship. Computed in JS so the per-source queries stay
 * trivial (`ILIKE` + `LIMIT`) and the ordering rule lives in one testable place.
 */
export function suggestionRank(text: string, query: string): number {
  const value = text.trim().toLowerCase();
  const needle = query.trim().toLowerCase();
  if (needle === '' || value === '') return 3;
  if (value === needle) return 0;
  if (value.startsWith(needle)) return 1;
  if (value.includes(needle)) return 2;
  return 3;
}

function trimmed(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

/** Splits a comma separated filter and keeps only whitelisted tokens. */
export function parseTokens<T extends string>(
  raw: unknown,
  allowed: readonly T[],
): T[] {
  const value = trimmed(raw);
  if (value === '') return [];
  const seen = new Set<T>();
  for (const token of value.split(',')) {
    const candidate = token.trim() as T;
    if (allowed.includes(candidate)) seen.add(candidate);
  }
  return [...seen];
}

/** ISO timestamp that `Date.parse` accepts, otherwise null (never a 400). */
function isoTimestamp(raw: unknown): string | null {
  const value = trimmed(raw);
  if (value === '') return null;
  return Number.isNaN(Date.parse(value)) ? null : value;
}

export type SearchParams = {
  /** Trimmed free text. Empty when the caller sent nothing usable. */
  query: string;
  /** False when `q` is missing or outside 1..[SEARCH_QUERY_MAX] — the route 400s. */
  valid: boolean;
  categories: SearchCategory[];
  city: string | null;
  cuisine: string | null;
  venueType: string | null;
  dealKind: DealKind | null;
  from: string | null;
  to: string | null;
  availableOnly: boolean;
  sort: SearchSort;
  limit: number;
  page: number;
  offset: number;
};

/**
 * Parses and bounds `GET /api/search` input. Unknown category/sort/kind
 * tokens are dropped rather than rejected (a stale client keeps working),
 * and a missing or overlong `q` is reported through `valid` so the handler
 * can raise a single 400 instead of silently returning everything.
 */
export function parseSearchParams(
  query: Record<string, unknown>,
): SearchParams {
  const text = trimmed(query.q).slice(0, SEARCH_QUERY_MAX + 1);
  const categories = parseTokens(query.category, SEARCH_CATEGORIES);
  const rawLimit = Number(query.limit);
  const limit =
    Number.isFinite(rawLimit) && rawLimit > 0
      ? Math.min(Math.floor(rawLimit), SEARCH_LIMIT_MAX)
      : SEARCH_LIMIT_DEFAULT;
  const rawPage = Number(query.page);
  const page = Number.isFinite(rawPage) && rawPage > 0 ? Math.floor(rawPage) : 1;
  const sort = parseTokens(query.sort, SEARCH_SORTS)[0] ?? 'relevant';
  const dealKind = parseTokens(query.dealKind, DEAL_KINDS)[0] ?? null;

  return {
    query: text,
    valid: text.length >= 1 && text.length <= SEARCH_QUERY_MAX,
    categories: categories.length > 0 ? categories : [...SEARCH_CATEGORIES],
    city: trimmed(query.city) || null,
    cuisine: trimmed(query.cuisine) || null,
    venueType: trimmed(query.type) || null,
    dealKind,
    from: isoTimestamp(query.from),
    to: isoTimestamp(query.to),
    availableOnly: trimmed(query.available) === 'true',
    sort,
    limit,
    page,
    offset: (page - 1) * limit,
  };
}

/**
 * Merges the per-source suggestion rows into one ranked, de-duplicated list.
 * Exact and prefix matches float up, duplicates collapse case-insensitively,
 * and the longest list a caller can render is [SUGGESTIONS_MAX].
 */
export function mergeSuggestions(
  rows: ReadonlyArray<Suggestion>,
  max = SUGGESTIONS_MAX,
): Suggestion[] {
  const best = new Map<string, Suggestion>();
  for (const row of rows) {
    const text = row.text.trim();
    if (text === '') continue;
    const key = text.toLowerCase();
    const current = best.get(key);
    if (current === undefined || row.rank < current.rank) {
      best.set(key, { ...row, text });
    }
  }
  return [...best.values()]
    .sort((a, b) => a.rank - b.rank || a.text.localeCompare(b.text))
    .slice(0, max);
}
