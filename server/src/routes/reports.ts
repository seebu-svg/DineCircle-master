import { Router } from 'express';
import { randomInt } from 'node:crypto';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound, requireRole } from '../context.js';
import { reportRateLimiter } from '../security.js';

const router = Router();

/**
 * P2-2 Reports, users may flag profiles, events, reviews and chat messages.
 *
 * Privacy model: a report is readable ONLY by its reporter (through
 * `/users/me/reports`) and by platform admins (`super_admin`, through the
 * `/reports` queue). Nothing in this file ever exposes a report, let alone
 * the reporter's identity, to the account that was reported.
 *
 * The DB is the enforcement layer for abuse: a partial unique index allows
 * exactly one OPEN ('pending' | 'reviewing') report per (reporter, target),
 * so re-submitting the same flag is a 409, not queue pollution. Reports never
 * auto-ban anyone, only the admin status transitions move a case.
 */

const TARGET_TYPES = ['user', 'event', 'review', 'message'] as const;
const REASONS = [
  'harassment',
  'spam',
  'inappropriate_content',
  'impersonation',
  'unsafe_experience',
  'misleading_event_info',
  'other',
] as const;
const REPORT_STATUSES = ['pending', 'reviewing', 'resolved', 'dismissed'] as const;

const REF_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** Human-readable report reference, e.g. `RP-7K3MQF` (crypto-random). */
function makeReportReference(): string {
  return (
    'RP-' +
    Array.from({ length: 6 }, () => REF_ALPHABET[randomInt(REF_ALPHABET.length)] ?? 'X').join('')
  );
}

type TargetInfo = {
  label: string;
  /** Short content snapshot stored as moderation `evidence`. */
  evidence: string;
  /** Owner of the reported content (self-report guard). */
  ownerId: string | null;
};

/**
 * Validate that the reported target exists (and is not an anonymised shell)
 * while snapshotting the evidence a moderator will need after the target is
 * edited or deleted. Returns null for unknown ids → caller 404s.
 */
async function resolveTarget(
  type: (typeof TARGET_TYPES)[number],
  id: string,
): Promise<TargetInfo | null> {
  switch (type) {
    case 'user': {
      const [row] = await query<{ name: string; handle: string }>(
        "SELECT name, handle FROM users WHERE id = $1::UUID AND is_deleted = false",
        [id],
      );
      if (!row) return null;
      return {
        label: 'User',
        evidence: `profile @${row.handle}: ${row.name}`,
        ownerId: id,
      };
    }
    case 'event': {
      const [row] = await query<{ title: string; host_id: string }>(
        'SELECT title, host_id FROM dinner_events WHERE id = $1::UUID',
        [id],
      );
      if (!row) return null;
      return { label: 'Event', evidence: `event "${row.title}"`, ownerId: row.host_id };
    }
    case 'review': {
      const [row] = await query<{ text: string; author_id: string; event_title: string }>(
        `SELECT left(rv.text, 200) AS text, rv.author_id, e.title AS event_title
         FROM reviews rv
         JOIN dinner_events e ON e.id = rv.event_id
         WHERE rv.id = $1::UUID`,
        [id],
      );
      if (!row) return null;
      return {
        label: 'Review',
        evidence: `review on "${row.event_title}": ${row.text}`,
        ownerId: row.author_id,
      };
    }
    case 'message': {
      const [row] = await query<{ text: string; author_id: string | null; event_title: string }>(
        `SELECT left(m.text, 200) AS text, m.author_id, e.title AS event_title
         FROM chat_messages m
         JOIN dinner_events e ON e.id = m.event_id
         WHERE m.id = $1::UUID`,
        [id],
      );
      if (!row) return null;
      return {
        label: 'Message',
        evidence: `message in "${row.event_title}": ${row.text}`,
        ownerId: row.author_id,
      };
    }
  }
}

const reportSchema = z.object({
  targetType: z.enum(TARGET_TYPES),
  targetId: z.string().uuid(),
  reason: z.enum(REASONS),
  description: z.string().trim().max(1000).default(''),
});

function serializeReport(r: {
  id: string;
  target_type: string;
  target_id: string;
  reason: string;
  description: string;
  status: string;
  reference: string;
  created_at: Date;
  updated_at: Date;
}) {
  return {
    id: r.id,
    targetType: r.target_type,
    targetId: r.target_id,
    reason: r.reason,
    description: r.description,
    status: r.status,
    reference: r.reference,
    createdAt: r.created_at,
    updatedAt: r.updated_at,
  };
}

type ReportRow = Parameters<typeof serializeReport>[0];

// POST /api/reports, submit a report. Rate limited (reportRateLimiter) and
// duplicate-guarded (one open report per reporter+target).
router.post('/reports', reportRateLimiter, async (req, res) => {
  const { targetType, targetId, reason, description } = reportSchema.parse(
    req.body ?? {},
  );

  const target = await resolveTarget(targetType, targetId);
  if (!target) {
    const noun: Record<(typeof TARGET_TYPES)[number], string> = {
      user: 'Profile',
      event: 'Event',
      review: 'Review',
      message: 'Message',
    };
    throw notFound(
      `${noun[targetType]} not found. It may have been removed already`,
    );
  }

  // You cannot flag yourself, and an already-open duplicate is refused before
  // it ever reaches the moderator queue.
  if (target.ownerId === req.userId) {
    throw new ApiError(400, 'You cannot report your own content');
  }
  const [open] = await query<{ id: string }>(
    `SELECT id FROM reports
     WHERE reporter_id = $1::UUID AND target_type = $2 AND target_id = $3::UUID
       AND status IN ('pending','reviewing')`,
    [req.userId, targetType, targetId],
  );
  if (open) {
    throw new ApiError(
      409,
      'You already have an open report for this. Our team is reviewing it.',
    );
  }

  const reference = makeReportReference();
  const [created] = await query<ReportRow>(
    `INSERT INTO reports (reporter_id, target_type, target_id, reason, description, evidence, reference)
     VALUES ($1::UUID, $2, $3::UUID, $4, $5, $6, $7)
     RETURNING id, target_type, target_id, reason, description, status, reference, created_at, updated_at`,
    [req.userId, targetType, targetId, reason, description, target.evidence, reference],
  );
  if (!created) throw new ApiError(500, 'Report could not be filed');

  res.status(201).json({ report: serializeReport(created) });
});

// GET /api/users/me/reports, the caller's own submissions with live status.
// Ownership is enforced by `reporter_id = req.userId`; there is no way to read
// anyone else's reports (the admin queue below is super_admin-only).
router.get('/users/me/reports', async (req, res) => {
  const rows = await query<ReportRow>(
    `SELECT id, target_type, target_id, reason, description, status, reference, created_at, updated_at
     FROM reports
     WHERE reporter_id = $1::UUID
     ORDER BY created_at DESC
     LIMIT 100`,
    [req.userId],
  );
  res.json({ reports: rows.map(serializeReport), count: rows.length });
});

// ── Admin moderation (super_admin only) ──────────────────────────────────────
// These are the ONLY endpoints where a reporter identity is visible, and they
// require the platform-admin role. Reports never ban anyone automatically,
// a human moves the status; enforcement lives in a later release.

// GET /api/reports?status=pending, the moderator queue (reporter included).
router.get(
  '/reports',
  requireRole('super_admin'),
  async (req, res) => {
    const status =
      typeof req.query.status === 'string' &&
      (REPORT_STATUSES as readonly string[]).includes(req.query.status)
        ? req.query.status
        : null;

    const rows = await query<
      ReportRow & {
        evidence: string;
        reporter_id: string;
        reporter_name: string | null;
      }
    >(
      `SELECT r.id, r.target_type, r.target_id, r.reason, r.description, r.status,
              r.reference, r.created_at, r.updated_at, r.evidence, r.reporter_id,
              u.name AS reporter_name
       FROM reports r
       LEFT JOIN users u ON u.id = r.reporter_id
       ${status ? `WHERE r.status = $1` : ''}
       ORDER BY r.created_at DESC
       LIMIT 100`,
      status ? [status] : [],
    );

    res.json({
      reports: rows.map((r) => ({
        ...serializeReport(r),
        evidence: r.evidence,
        reporterId: r.reporter_id,
        reporterName: r.reporter_name,
      })),
      count: rows.length,
    });
  },
);

const statusSchema = z.object({ status: z.enum(REPORT_STATUSES) });

// PATCH /api/reports/:id, a moderator advances the case. No user content is
// deleted or hidden here; this phase only tracks review state.
router.patch(
  '/reports/:id',
  requireRole('super_admin'),
  async (req, res) => {
    const { status } = statusSchema.parse(req.body ?? {});
    const [updated] = await query<ReportRow>(
      `UPDATE reports
       SET status = $2, updated_at = now()
       WHERE id = $1::UUID
       RETURNING id, target_type, target_id, reason, description, status, reference, created_at, updated_at`,
      [req.params.id, status],
    );
    if (!updated) throw notFound('Report');
    res.json({ report: serializeReport(updated) });
  },
);

export default router;
