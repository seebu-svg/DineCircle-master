import { Router } from 'express';
import { z } from 'zod';
import { query } from '../../db.js';
import { notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { reviewVerificationRequest } from '../../verification_review.js';
import {
  adminPage,
  noteSchema,
  pushEquals,
  pushSearch,
  renderList,
  searchTerm,
} from './_shared.js';

/**
 * Partner Applications.
 *
 * There is no `applications` table: a partner submits a venue for review and
 * `partner_verification_requests` records it, joined to the venue and its
 * owner. This module therefore *reads* that join and *writes* through the same
 * shared reviewer function the Partner App queue uses, so an approval made here
 * and one made there cannot behave differently.
 */
const router = Router();

const reviewSchema = z.object({
  decision: z.enum(['approved', 'rejected']),
  reviewerNote: noteSchema,
});

const batchSchema = reviewSchema.extend({
  ids: z.array(z.string().uuid()).min(1).max(100),
});

/** `decisions[]` for the drawer timeline: one row per application on the venue. */
async function decisionsFor(restaurantId: string) {
  return query<Record<string, unknown>>(
    `SELECT v.id, v.status, v.note, v.reviewer_note, v.created_at, v.reviewed_at,
            u.name AS reviewer_name
       FROM partner_verification_requests v
       LEFT JOIN users u ON u.id = v.reviewed_by
      WHERE v.restaurant_id = $1::UUID
      ORDER BY v.created_at DESC`,
    [restaurantId],
  );
}

function shape(row: Record<string, unknown>) {
  return {
    id: row.id,
    requestId: row.id,
    restaurantId: row.restaurant_id,
    name: row.restaurant_name,
    venueName: row.restaurant_name,
    city: row.city,
    area: row.neighborhood,
    status: row.status,
    note: row.note,
    reviewerNote: row.reviewer_note,
    createdAt: row.created_at,
    submittedAt: row.created_at,
    reviewedAt: row.reviewed_at,
    reviewer: row.reviewer_name,
    ownerName: row.owner_name,
    ownerEmail: row.owner_email,
    ownerPhone: row.owner_phone,
    seats: row.seats,
    cuisines: row.cuisines,
    profileCompletion: row.profile_completion,
  };
}

const LIST_SELECT = `
  v.id, v.status, v.note, v.reviewer_note, v.created_at, v.reviewed_at,
  r.id AS restaurant_id, r.name AS restaurant_name, r.city, r.neighborhood,
  r.seats, r.cuisines, r.profile_completion,
  o.name AS owner_name, o.email AS owner_email, o.phone AS owner_phone,
  rv.name AS reviewer_name`;

const LIST_FROM = `
  FROM partner_verification_requests v
  JOIN restaurants r ON r.id = v.restaurant_id
  LEFT JOIN users o ON o.id = r.owner_id
  LEFT JOIN users rv ON rv.id = v.reviewed_by`;

/**
 * GET /api/admin/applications?page&limit&status&q
 * Newest first; `status=pending` is the queue badge target.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  pushEquals(where, params, req.query.status as string | undefined, 'v.status');
  pushSearch(where, params, searchTerm(req), ['r.name', 'r.city', 'o.name', 'o.email']);

  await renderList(res, 'applications', {
    select: LIST_SELECT,
    from: LIST_FROM,
    where,
    params,
    order: `CASE v.status WHEN 'pending' THEN 0 ELSE 1 END, v.created_at DESC`,
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/applications/:id, the full drawer payload.
router.get('/:id', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${LIST_SELECT}, r.address, r.phone, r.email, r.website, r.about,
            r.partnership_status, r.accepting_bookings, r.created_at AS venue_created_at
       ${LIST_FROM}
      WHERE v.id = $1::UUID`,
    [req.params.id],
  );
  if (!row) throw notFound('Application');

  const decisions = await decisionsFor(String(row.restaurant_id));
  res.json(
    one('application', {
      ...shape(row),
      address: row.address,
      venuePhone: row.phone,
      venueEmail: row.email,
      website: row.website,
      about: row.about,
      partnershipStatus: row.partnership_status,
      acceptingBookings: row.accepting_bookings,
      decisions: decisions.map((d) => ({
        id: d.id,
        status: d.status,
        note: d.note,
        reviewerNote: d.reviewer_note,
        createdAt: d.created_at,
        reviewedAt: d.reviewed_at,
        reviewer: d.reviewer_name,
      })),
    }),
  );
});

/**
 * POST /api/admin/applications/:id/review
 * Delegates to `reviewVerificationRequest`, which 409s when the request has
 * already been decided and notifies the venue desk inside the same transaction.
 */
router.post('/:id/review', async (req, res) => {
  requireAdminConsole(req);
  const input = reviewSchema.parse(req.body ?? {});

  const result = await reviewVerificationRequest({
    requestId: req.params.id,
    decision: input.decision,
    reviewerNote: input.reviewerNote,
    actorId: req.userId,
  });

  res.json(one('review', { ...result, venueNotified: true }));
});

/**
 * POST /api/admin/applications/batch-review
 * Sequential on purpose: each decision runs in its own transaction so one
 * already-decided row reports a precise conflict instead of rolling the whole
 * batch back. `results[]` tells the console which ids it actually changed.
 */
router.post('/batch-review', async (req, res) => {
  requireAdminConsole(req);
  const input = batchSchema.parse(req.body ?? {});

  const results: Array<{
    id: string;
    ok: boolean;
    status?: string;
    restaurantId?: string;
    error?: string;
  }> = [];

  for (const id of input.ids) {
    try {
      const r = await reviewVerificationRequest({
        requestId: id,
        decision: input.decision,
        reviewerNote: input.reviewerNote,
        actorId: req.userId,
      });
      results.push({ id, ok: true, status: r.status, restaurantId: r.restaurantId });
    } catch (error) {
      results.push({
        id,
        ok: false,
        error: error instanceof Error ? error.message : 'Review failed',
      });
    }
  }

  const changed = results.filter((r) => r.ok).length;
  res.json({
    data: { batch: results, changed, skipped: results.length - changed },
  });
});

export default router;
