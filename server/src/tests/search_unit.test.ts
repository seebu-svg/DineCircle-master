import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  SUGGESTIONS_MAX,
  escapeLike,
  likeTerm,
  mergeSuggestions,
  parseSearchParams,
  parseTokens,
  prefixTerm,
  rankSql,
  SEARCH_CATEGORIES,
  suggestionRank,
  type Suggestion,
} from '../search.js';

test('LIKE metacharacters are escaped so user text matches literally', () => {
  assert.equal(escapeLike('50%'), '50\\%');
  assert.equal(escapeLike('a_b'), 'a\\_b');
  // The backslash itself must be escaped first, or its own escape is doubled.
  assert.equal(escapeLike('a\\b'), 'a\\\\b');
  assert.equal(escapeLike('sushi'), 'sushi');
  assert.equal(likeTerm('50%'), '%50\\%%');
  assert.equal(prefixTerm('kar'), 'kar%');
});

test('relevance ranking has four tiers in the documented order', () => {
  const sql = rankSql('r', '$3');
  assert.match(sql, /lower\(r\.name\) = lower\(\$3\) THEN 0/);
  assert.match(sql, /LIKE lower\(\$3\) \|\| '%' THEN 1/);
  assert.match(sql, /'% ' \|\| lower\(\$3\) \|\| '%' THEN 2/);
  assert.match(sql, /ELSE 3 END/);
  // Category searches rank on their own title column.
  assert.match(rankSql('e', '$2', 'title'), /lower\(e\.title\)/);
});

test('typeahead relevance distinguishes exact, prefix and contains', () => {
  assert.equal(suggestionRank('Sushi', 'sushi'), 0);
  assert.equal(suggestionRank('Sushi House', 'sushi'), 1);
  assert.equal(suggestionRank('Best Sushi Bar', 'sushi'), 2);
  assert.equal(suggestionRank('Pizza', 'sushi'), 3);
  assert.equal(suggestionRank('  ', 'sushi'), 3);
});

test('parseTokens keeps only whitelisted comma separated values', () => {
  assert.deepEqual(parseTokens('restaurants,hosts', SEARCH_CATEGORIES), [
    'restaurants',
    'hosts',
  ]);
  assert.deepEqual(parseTokens('restaurants,bogus', SEARCH_CATEGORIES), [
    'restaurants',
  ]);
  assert.deepEqual(parseTokens('', SEARCH_CATEGORIES), []);
  // Duplicates collapse so the route never runs the same query twice.
  assert.deepEqual(parseTokens('hosts,hosts', SEARCH_CATEGORIES), ['hosts']);
});

test('parseSearchParams bounds paging and drops unknown tokens', () => {
  const params = parseSearchParams({ q: '  sushi  ', limit: '500', page: '3' });
  assert.equal(params.query, 'sushi');
  assert.equal(params.valid, true);
  assert.equal(params.limit, 20);
  assert.equal(params.page, 3);
  assert.equal(params.offset, 40);
  assert.deepEqual(params.categories, [...SEARCH_CATEGORIES]);

  const defaults = parseSearchParams({ q: 'x' });
  assert.equal(defaults.limit, 10);
  assert.equal(defaults.page, 1);
  assert.equal(defaults.offset, 0);
  assert.equal(defaults.sort, 'relevant');
  assert.equal(defaults.dealKind, null);
});

test('parseSearchParams rejects a missing or overlong query', () => {
  assert.equal(parseSearchParams({}).valid, false);
  assert.equal(parseSearchParams({ q: '   ' }).valid, false);
  assert.equal(parseSearchParams({ q: 'a'.repeat(80) }).valid, true);
  assert.equal(parseSearchParams({ q: 'a'.repeat(81) }).valid, false);
});

test('parseSearchParams keeps valid ISO bounds and ignores junk ones', () => {
  const params = parseSearchParams({
    q: 'brunch',
    from: '2026-11-06T00:00:00.000Z',
    to: 'not-a-date',
    available: 'true',
    sort: 'soon',
    dealKind: 'percent',
    category: 'deals,experiences',
    city: ' Karachi ',
    cuisine: 'Sushi',
    type: 'rooftop',
  });
  assert.equal(params.from, '2026-11-06T00:00:00.000Z');
  assert.equal(params.to, null);
  assert.equal(params.availableOnly, true);
  assert.equal(params.sort, 'soon');
  assert.equal(params.dealKind, 'percent');
  assert.deepEqual(params.categories, ['deals', 'experiences']);
  assert.equal(params.city, 'Karachi');
  assert.equal(params.cuisine, 'Sushi');
  assert.equal(params.venueType, 'rooftop');
});

test('parseSearchParams survives a bad sort or deal kind', () => {
  const params = parseSearchParams({ q: 'x', sort: 'nope', dealKind: 'bogus' });
  assert.equal(params.sort, 'relevant');
  assert.equal(params.dealKind, null);
});

test('mergeSuggestions de-duplicates case-insensitively and caps the list', () => {
  const rows: Suggestion[] = [
    { text: 'Sushi House', kind: 'restaurant', refId: 'a', rank: 1 },
    { text: 'sushi house', kind: 'menu', refId: 'b', rank: 2 },
    { text: 'Pizza', kind: 'restaurant', refId: 'c', rank: 3 },
    { text: 'Sushi', kind: 'cuisine', refId: null, rank: 0 },
    { text: '   ', kind: 'host', refId: null, rank: 0 },
  ];
  const merged = mergeSuggestions(rows);
  assert.deepEqual(
    merged.map((row) => row.text),
    ['Sushi', 'Sushi House', 'Pizza'],
  );
  // The best-ranked duplicate wins, keeping its own kind and ref.
  assert.equal(merged[1]?.kind, 'restaurant');
  assert.equal(merged[1]?.refId, 'a');

  const many: Suggestion[] = Array.from({ length: SUGGESTIONS_MAX + 4 }, (_, i) => ({
    text: `venue ${i}`,
    kind: 'restaurant',
    refId: `${i}`,
    rank: 3,
  }));
  assert.equal(mergeSuggestions(many).length, SUGGESTIONS_MAX);
});
