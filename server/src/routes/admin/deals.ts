import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { isModerationKind, setModeration, type ModerationKind } from '../../moderation.js';
import { adminPage, noteSchema, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Deals & Content.
 *
 * Deals have a real lifecycle (`draft/active/paused/expired`) owned by the
 * partner, so the console only approves, pauses and moderates; it never edits
 * offer terms, which are the partner's to write.
 *
 * There is no generic `content` table. Reviews, venue images and menu items are
 * each moderation targets in their own right, so the content queue unions them
 * on read and keys the write routes by `:kind`.
 */
export const dealsRouter = Router();

const DEAL_SELECT = `
  d.id, d.title, d.description, d.kind, d.value, d.code, d.status,
  d.moderation_status, d.moderation_note, d.starts_at, d.ends_at,
  d.max_redemptions, d.redemptions, d.terms, d.image_url, d.created_at,
  r.id AS restaurant_id, r.name AS venue_name, r.city, r.is_partner,
  u.name AS owner_name`;

const DEAL_FROM = `
  FROM restaurant_deals d
  JOIN restaurants r ON r.id = d.restaurant_id
  LEFT JOIN users u ON u.id = r.owner_id`;

function shapeDeal(row: Record<string, unknown>) {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    terms: row.terms,
    kind: row.kind,
    value: Number(row.value ?? 0),
    code: row.code,
    status: row.status,
    moderationStatus: row.moderation_status,
    moderationNote: row.moderation_note,
    flagged: row.moderation_status === 'flagged',
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    maxRedemptions: row.max_redemptions,
    redemptions: row.redemptions,
    imageUrl: row.image_url,
    createdAt: row.created_at,
    venueId: row.restaurant_id,
    venueName: row.venue_name,
    city: row.city,
    isPartner: row.is_partner,
    ownerName: row.owner_name,
    // The console's headline label: "20% off" or "Rs. 500 off".
    label:
      row.kind === 'percent'
        ? `${Number(row.value ?? 0)}% off`
        : `Rs. ${Number(row.value ?? 0).toLocaleString('en-GB')} off`,
  };
}

/**
 * GET /api/admin/deals?page&limit&status&flagged&q
 */
dealsRouter.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status !== '' && status !== 'all') {
    params.push(status);
    where.push(`d.status = $${params.length}`);
  }
  if (String(req.query.flagged ?? '').trim() === 'true') {
    where.push(`d.moderation_status = 'flagged'`);
  }
  pushSearch(where, params, searchTerm(req), ['d.title', 'r.name', 'd.code']);

  await renderList(res, 'deals', {
    select: DEAL_SELECT,
    from: DEAL_FROM,
    where,
    params,
    order: `CASE d.moderation_status WHEN 'flagged' THEN 0 ELSE 1 END, d.created_at DESC`,
    page: adminPage(req),
  }, shapeDeal);
});

// GET /api/admin/deals/:id
dealsRouter.get('/:id', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${DEAL_SELECT} ${DEAL_FROM} WHERE d.id = $1::UUID`,
    [req.params.id],
  );
  if (!row) throw notFound('Deal');
  res.json(one('deal', shapeDeal(row)));
});

const noteBody = z.object({ note: noteSchema });

/**
 * POST /api/admin/deals/:id/approve
 * Clears moderation and puts the deal live. A deal only reaches diners when
 * `status='active'`, so approving is exactly that write plus `clean`.
 */
dealsRouter.post('/:id/approve', async (req, res) => {
  requireAdminConsole(req);
  const input = noteBody.parse(req.body ?? {});
  await setModeration({
    kind: 'deal',
    id: req.params.id,
    state: 'clean',
    note: input.note,
    actorId: req.userId,
  });
  const [deal] = await query<Record<string, unknown>>(
    `UPDATE restaurant_deals SET status = 'active' WHERE id = $1::UUID RETURNING id`,
    [req.params.id],
  );
  if (!deal) throw notFound('Deal');
  res.json(one('deal', { id: deal.id, status: 'active', moderationStatus: 'clean' }));
});

// POST /api/admin/deals/:id/pause
dealsRouter.post('/:id/pause', async (req, res) => {
  requireAdminConsole(req);
  noteBody.parse(req.body ?? {});
  const [deal] = await query<Record<string, unknown>>(
    `UPDATE restaurant_deals SET status = 'paused'
      WHERE id = $1::UUID AND status <> 'expired' RETURNING id, status`,
    [req.params.id],
  );
  if (!deal) throw notFound('Deal');
  res.json(one('deal', deal));
});

// POST /api/admin/deals/:id/flag
dealsRouter.post('/:id/flag', async (req, res) => {
  requireAdminConsole(req);
  const input = noteBody.parse(req.body ?? {});
  const result = await setModeration({
    kind: 'deal',
    id: req.params.id,
    state: 'flagged',
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('deal', result));
});

/**
 * POST /api/admin/deals/:id/remove
 * Sets `moderation_status='removed'` and pauses the row, because the deal
 * visibility gate in `routes/deals.ts` is `status='active'` alone.
 */
dealsRouter.post('/:id/remove', async (req, res) => {
  requireAdminConsole(req);
  const input = noteBody.parse(req.body ?? {});
  const result = await setModeration({
    kind: 'deal',
    id: req.params.id,
    state: 'removed',
    note: input.note,
    actorId: req.userId,
  });
  res.json(one('deal', result));
});

/**
 * Content queue: three tables behind one list.
 *
 * `kind` is the discriminator the write routes need back, so it is part of every
 * row rather than something the client infers from the id. The three action
 * routes are literal sub-paths (`/keep`, `/flag`, `/remove`) on one router so
 * the union stays keyed by kind.
 */
export const contentRouter = Router();

const CONTENT_UNION = `
  SELECT 'review'::text AS kind, rv.id, rv.text AS title,
         coalesce(nullif(u.name, ''), 'A diner') AS actor,
         coalesce(r.name, e.title, '') AS target,
         rv.moderation_status, rv.moderation_note, rv.created_at,
         rv.rating AS weight,
         (SELECT count(*)::int FROM reports rp
           WHERE rp.target_type = 'review' AND rp.target_id = rv.id) AS report_count
     FROM reviews rv
     LEFT JOIN users u ON u.id = rv.author_id
     LEFT JOIN restaurants r ON r.id = rv.restaurant_id
     LEFT JOIN dinner_events e ON e.id = rv.event_id
  UNION ALL
  SELECT 'image', i.id, i.kind, coalesce(r.name, ''), i.kind,
         i.moderation_status, i.moderation_note, i.created_at, NULL, 0
     FROM venue_images i
     JOIN restaurants r ON r.id = i.restaurant_id
  UNION ALL
  SELECT 'menu_item', m.id, m.name, coalesce(r.name, ''), m.description,
         m.moderation_status, m.moderation_note, m.created_at, m.price, 0
     FROM restaurant_menu_items m
     JOIN restaurants r ON r.id = m.restaurant_id`;

function shapeContent(row: Record<string, unknown>) {
  return {
    id: row.id,
    kind: row.kind,
    title: row.title,
    excerpt: row.title,
    actor: row.actor,
    target: row.target,
    moderationStatus: row.moderation_status,
    moderationNote: row.moderation_note,
    createdAt: row.created_at,
    weight: row.weight === null ? null : Number(row.weight),
    reportCount: row.report_count,
    flagged: row.moderation_status === 'flagged',
  };
}

/**
 * GET /api/admin/content?page&limit&kind&flagged&q
 * Defaults to the moderation queue (flagged or removed) so the drawer opens on
 * work rather than on the whole corpus.
 */
contentRouter.get('/', async (req, res) => {
  requireAdminConsole(req);
  const filters: string[] = [];
  const params: unknown[] = [];

  const kind = String(req.query.kind ?? '').trim();
  if (kind !== '' && kind !== 'all') {
    params.push(kind);
    filters.push(`feed.kind = $${params.length}`);
  }
  if (String(req.query.flagged ?? '').trim() === 'true') {
    filters.push(`feed.moderation_status = 'flagged'`);
  }
  pushSearch(filters, params, searchTerm(req), ['feed.title', 'feed.target', 'feed.actor']);

  const where = filters.length > 0 ? `WHERE ${filters.join(' AND ')}` : '';
  const page = adminPage(req);

  const [totalRow] = await query<{ count: number }>(
    `SELECT count(*)::int AS count FROM (${CONTENT_UNION}) feed ${where}`,
    params,
  );
  const rows = await query<Record<string, unknown>>(
    `SELECT * FROM (${CONTENT_UNION}) feed ${where}
      ORDER BY CASE feed.moderation_status WHEN 'flagged' THEN 0 ELSE 1 END,
               feed.created_at DESC
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
    [...params, page.limit, page.offset],
  );

  res.json({
    data: { content: rows.map(shapeContent) },
    meta: {
      page: page.page,
      limit: page.limit,
      total: totalRow?.count ?? 0,
      hasMore: page.offset + page.limit < (totalRow?.count ?? 0),
    },
  });
});

const CONTENT_KINDS: ModerationKind[] = ['review', 'image', 'menu_item'];

/**
 * POST /api/admin/content/:kind/:id/(keep|flag|remove)
 * `:kind` is validated against the allowlist before any SQL is built, so the
 * table name interpolation in `setModeration` can only ever receive one of the
 * five moderation targets.
 */
for (const [path, state] of [
  ['keep', 'clean'],
  ['flag', 'flagged'],
  ['remove', 'removed'],
] as const) {
  contentRouter.post(`/:kind/:id/${path}`, async (req, res) => {
    requireAdminConsole(req);
    const kind = req.params.kind;
    if (!isModerationKind(kind) || !CONTENT_KINDS.includes(kind)) {
      throw notFound('Content kind');
    }
    const input = noteBody.parse(req.body ?? {});
    const result = await setModeration({
      kind,
      id: req.params.id,
      state,
      note: input.note,
      actorId: req.userId,
    });
    res.json(one('content', { ...result, kind }));
  });
}

export default dealsRouter;
