import { Router } from 'express';
import { z } from 'zod';
import { query, withTransaction } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { notifyUser } from '../../notify.js';
import {
  cancelExperience,
  restoreUser,
  setModeration,
  suspendUser,
  suspendVenue,
} from '../../moderation.js';
import { adminPage, pushEquals, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Reports & Safety.
 *
 * Resolving a case never re-implements a moderation effect: every action in the
 * picker calls the same function the direct admin routes use, so closing a
 * report with "venue suspended" and suspending that venue from the venue table
 * write identical rows. The chosen action and the operator's note are appended
 * to `reports.resolution`, which is what the drawer renders as history.
 */
const router = Router();

const ACTIONS = [
  'warning',
  'content_removed',
  'deal_removed',
  'experience_cancelled',
  'venue_suspended',
  'host_suspended',
  'customer_suspended',
  'no_action',
] as const;

const REPORT_SELECT = `
  rp.id, rp.reference, rp.target_type, rp.target_id, rp.reason, rp.description,
  rp.evidence, rp.status, rp.severity, rp.resolution, rp.created_at, rp.updated_at,
  rep.id AS reporter_id, rep.name AS reporter_name, rep.email AS reporter_email,
  assigned.name AS assigned_name, resolved.name AS resolved_by_name,
  tgt_user.name AS target_user_name, tgt_user.email AS target_user_email,
  tgt_event.title AS target_event_title, tgt_event.host_id AS target_host_id,
  tgt_event.restaurant_id AS target_restaurant_id,
  tgt_review.text AS target_review_text,
  tgt_event.moderation_status AS target_moderation_status`;

const REPORT_FROM = `
  FROM reports rp
  JOIN users rep ON rep.id = rp.reporter_id
  LEFT JOIN users assigned ON assigned.id = rp.assigned_to
  LEFT JOIN users resolved ON resolved.id = rp.resolved_by
  LEFT JOIN users tgt_user ON tgt_user.id = rp.target_id AND rp.target_type = 'user'
  LEFT JOIN dinner_events tgt_event ON tgt_event.id = rp.target_id AND rp.target_type = 'event'
  LEFT JOIN reviews tgt_review ON tgt_review.id = rp.target_id AND rp.target_type = 'review'
  LEFT JOIN restaurants r ON r.id = COALESCE(tgt_event.restaurant_id, tgt_review.restaurant_id)`;

function shape(row: Record<string, unknown>) {
  return {
    id: row.id,
    reference: row.reference,
    targetType: row.target_type,
    targetId: row.target_id,
    reason: row.reason,
    description: row.description,
    evidence: row.evidence,
    status: row.status,
    severity: row.severity,
    resolution: row.resolution,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    reporterId: row.reporter_id,
    reporterName: row.reporter_name,
    reporterEmail: row.reporter_email,
    assignedTo: row.assigned_name,
    resolvedBy: row.resolved_by_name,
    targetName:
      row.target_user_name ?? row.target_event_title ?? row.target_review_text ?? row.target_id,
    targetEmail: row.target_user_email,
    targetExcerpt: row.target_review_text,
    hostId: row.target_host_id,
    restaurantId: row.target_restaurant_id,
  };
}

/**
 * GET /api/admin/reports?page&limit&status&type&severity&q
 * Open cases first, then by severity, then newest.
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const where: string[] = [];
  const params: unknown[] = [];

  const status = String(req.query.status ?? '').trim();
  if (status === 'open') {
    where.push(`rp.status IN ('pending','reviewing')`);
  } else {
    pushEquals(where, params, status, 'rp.status');
  }
  pushEquals(where, params, req.query.type as string | undefined, 'rp.target_type');
  pushEquals(where, params, req.query.severity as string | undefined, 'rp.severity');
  pushSearch(where, params, searchTerm(req), [
    'rp.reference',
    'rp.reason',
    'rp.description',
    'rep.name',
  ]);

  await renderList(res, 'reports', {
    select: REPORT_SELECT,
    from: REPORT_FROM,
    where,
    params,
    order: `CASE rp.status WHEN 'reviewing' THEN 0 WHEN 'pending' THEN 1 ELSE 2 END,
            CASE rp.severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 ELSE 2 END,
            rp.created_at DESC`,
    page: adminPage(req),
  }, shape);
});

// GET /api/admin/reports/:id
router.get('/:id', async (req, res) => {
  requireAdminConsole(req);
  const [row] = await query<Record<string, unknown>>(
    `SELECT ${REPORT_SELECT}, r.name AS venue_name, r.city,
            rp.resolved_at, rp.assigned_to
       ${REPORT_FROM}
      WHERE rp.id = $1::UUID`,
    [req.params.id],
  );
  if (!row) throw notFound('Report');

  const others = await query<Record<string, unknown>>(
    `SELECT id, reference, reason, status, severity, created_at
       FROM reports
      WHERE target_type = $1 AND target_id = $2::UUID AND id <> $3::UUID
      ORDER BY created_at DESC LIMIT 10`,
    [row.target_type, row.target_id, req.params.id],
  );

  res.json(
    one('report', {
      ...shape(row),
      venueName: row.venue_name,
      city: row.city,
      resolvedAt: row.resolved_at,
      relatedReports: others.map((o) => ({
        id: o.id,
        reference: o.reference,
        reason: o.reason,
        status: o.status,
        severity: o.severity,
        createdAt: o.created_at,
      })),
    }),
  );
});

const assignSchema = z.object({
  severity: z.enum(['low', 'medium', 'high']).optional(),
});

/**
 * POST /api/admin/reports/:id/start-review
 * Claims the case for the acting operator and optionally raises its severity.
 */
router.post('/:id/start-review', async (req, res) => {
  requireAdminConsole(req);
  const input = assignSchema.parse(req.body ?? {});

  const params: unknown[] = [req.params.id, req.userId];
  const sets = [`status = 'reviewing'`, `assigned_to = $2::UUID`];
  if (input.severity) {
    params.push(input.severity);
    sets.push(`severity = $${params.length}`);
  }
  params.push(req.userId);
  sets.push(`resolved_by = $${params.length}::UUID`);

  const [updated] = await query<Record<string, unknown>>(
    `UPDATE reports SET ${sets.join(', ')}, updated_at = now()
      WHERE id = $1::UUID AND status IN ('pending','reviewing') RETURNING id, status, severity`,
    params,
  );
  if (!updated) throw notFound('Report');
  res.json(one('report', updated));
});

const resolveSchema = z.object({
  resolution: z.string().trim().min(3).max(1000),
  action: z.enum(ACTIONS),
  // Only `deal_removed` needs it: a report never targets a deal row directly,
  // so the operator names the deal from the case drawer.
  dealId: z.string().uuid().optional(),
});

/**
 * Runs the chosen effect through the shared moderation functions and returns a
 * human-readable summary of what actually changed.
 */
async function applyAction(
  report: Record<string, unknown>,
  action: (typeof ACTIONS)[number],
  input: { dealId?: string; resolution: string },
  actorId: string,
): Promise<string[]> {
  const notes: string[] = [];
  const targetType = String(report.target_type);
  const targetId = String(report.target_id);

  switch (action) {
    case 'warning': {
      const recipient =
        (report.target_user_id as string | undefined) ??
        (report.host_id as string | undefined) ??
        null;
      if (recipient) {
        await notifyUser(null, recipient, {
          title: 'A report was reviewed',
          body: `The platform team reviewed a report about your ${targetType}. ${input.resolution}`,
          kind: 'reminder',
        });
        notes.push('Warning sent to the account.');
      } else {
        notes.push('No account to warn was linked to this case.');
      }
      break;
    }
    case 'content_removed': {
      if (targetType !== 'review') {
        throw new ApiError(400, 'Content removal needs a review-targeted report');
      }
      await setModeration({
        kind: 'review',
        id: targetId,
        state: 'removed',
        note: input.resolution,
        actorId,
      });
      notes.push('Review removed from public listing.');
      break;
    }
    case 'deal_removed': {
      if (!input.dealId) throw new ApiError(400, 'Choose the deal to remove');
      await setModeration({
        kind: 'deal',
        id: input.dealId,
        state: 'removed',
        note: input.resolution,
        actorId,
      });
      notes.push('Deal removed and paused.');
      break;
    }
    case 'experience_cancelled': {
      if (targetType !== 'event') {
        throw new ApiError(400, 'Cancelling an experience needs an event-targeted report');
      }
      const result = await cancelExperience({
        eventId: targetId,
        reason: input.resolution,
        notifyGuests: true,
        actorId,
      });
      notes.push(`Experience cancelled, ${result.guestCount} guest(s) told.`);
      break;
    }
    case 'venue_suspended': {
      const restaurantId = (report.restaurant_id as string | undefined) ?? null;
      if (!restaurantId) throw new ApiError(400, 'This case is not linked to a venue');
      await suspendVenue({ restaurantId, note: input.resolution, actorId });
      notes.push('Venue suspended and pulled from discovery.');
      break;
    }
    case 'host_suspended':
    case 'customer_suspended': {
      if (targetType !== 'user') {
        throw new ApiError(400, 'Suspending an account needs a user-targeted report');
      }
      await suspendUser({ userId: targetId, reason: input.resolution });
      notes.push(
        action === 'host_suspended'
          ? 'Host account suspended.'
          : 'Customer account suspended.',
      );
      break;
    }
    case 'no_action': {
      notes.push('Case closed with no platform action.');
      break;
    }
  }
  return notes;
}

/**
 * POST /api/admin/reports/:id/resolve
 * The moderation write and the case write commit in one transaction, so a
 * resolved report always describes what really happened.
 */
router.post('/:id/resolve', async (req, res) => {
  requireAdminConsole(req);
  const input = resolveSchema.parse(req.body ?? {});

  const result = await withTransaction(async (client) => {
    const { rows } = await client.query<Record<string, unknown>>(
      `SELECT rp.id, rp.reference, rp.target_type, rp.target_id, rp.status,
              tgt_user.id AS target_user_id,
              tgt_event.host_id, tgt_event.restaurant_id,
              tgt_review.restaurant_id AS review_restaurant_id
         FROM reports rp
         LEFT JOIN users tgt_user ON tgt_user.id = rp.target_id AND rp.target_type = 'user'
         LEFT JOIN dinner_events tgt_event ON tgt_event.id = rp.target_id AND rp.target_type = 'event'
         LEFT JOIN reviews tgt_review ON tgt_review.id = rp.target_id AND rp.target_type = 'review'
        WHERE rp.id = $1::UUID
        FOR UPDATE OF rp`,
      [req.params.id],
    );
    const report = rows[0];
    if (!report) throw notFound('Report');
    if (report.status === 'resolved' || report.status === 'dismissed') {
      throw new ApiError(409, `This report was already ${report.status}`);
    }

    const restaurantId =
      (report.restaurant_id as string | undefined) ??
      (report.review_restaurant_id as string | undefined) ??
      null;

    const notes = await applyAction(
      { ...report, restaurant_id: restaurantId },
      input.action,
      input,
      req.userId,
    );

    const line = `${input.action}: ${input.resolution}`;
    const { rows: updated } = await client.query<Record<string, unknown>>(
      `UPDATE reports
          SET status = 'resolved', resolution = $2, resolved_by = $3::UUID,
              resolved_at = now(), updated_at = now()
        WHERE id = $1::UUID
        RETURNING id, reference, status, severity, resolution, resolved_at`,
      [report.id, line, req.userId],
    );

    await client.query(
      `INSERT INTO audit_log (user_id, action, resource, resource_id, changes, status_code)
       VALUES ($1::UUID, 'admin.report.resolve', 'reports', $2, $3::jsonb, 200)`,
      [
        req.userId,
        String(report.id),
        JSON.stringify({ action: input.action, resolution: input.resolution, effects: notes }),
      ],
    );

    return { report: updated[0]!, action: input.action, effects: notes };
  });

  res.json(one('resolution', result));
});

const dismissSchema = z.object({ resolution: z.string().trim().min(3).max(1000) });

// POST /api/admin/reports/:id/dismiss
router.post('/:id/dismiss', async (req, res) => {
  requireAdminConsole(req);
  const input = dismissSchema.parse(req.body ?? {});
  const [dismissed] = await query<Record<string, unknown>>(
    `UPDATE reports SET status = 'dismissed', resolution = $2, resolved_by = $3::UUID,
            resolved_at = now(), updated_at = now()
      WHERE id = $1::UUID AND status IN ('pending','reviewing')
      RETURNING id, reference, status, resolution`,
    [req.params.id, `dismissed: ${input.resolution}`, req.userId],
  );
  if (!dismissed) throw notFound('Report');
  res.json(one('report', dismissed));
});

/**
 * POST /api/admin/reports/:id/reopen
 * Clears the outcome but leaves any moderation state alone: reopening a case is
 * a review decision, not an undo of a suspension.
 */
router.post('/:id/reopen', async (req, res) => {
  requireAdminConsole(req);
  const [reopened] = await query<Record<string, unknown>>(
    `UPDATE reports SET status = 'reviewing', resolution = '', resolved_by = NULL,
            resolved_at = NULL, assigned_to = $2::UUID, updated_at = now()
      WHERE id = $1::UUID AND status IN ('resolved','dismissed')
      RETURNING id, reference, status`,
    [req.params.id, req.userId],
  );
  if (!reopened) throw notFound('Report');
  res.json(one('report', reopened));
});

// POST /api/admin/reports/:id/restore-user, undo a suspension from the case.
router.post('/:id/restore-user', async (req, res) => {
  requireAdminConsole(req);
  const [report] = await query<{ target_type: string; target_id: string }>(
    `SELECT target_type, target_id FROM reports WHERE id = $1::UUID`,
    [req.params.id],
  );
  if (!report) throw notFound('Report');
  if (report.target_type !== 'user') throw new ApiError(400, 'This case does not target a user');
  const result = await restoreUser({ userId: report.target_id });
  res.json(one('report', result));
});

export default router;
