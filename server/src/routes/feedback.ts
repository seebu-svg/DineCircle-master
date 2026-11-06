import { Router } from 'express';
import { randomInt } from 'node:crypto';
import { z } from 'zod';
import { query } from '../db.js';
import { ApiError, notFound, requireRole } from '../context.js';
import { feedbackRateLimiter } from '../security.js';

const router = Router();

/**
 * P2-3 Help & Feedback — support tickets raised from the app.
 *
 * Every ticket is owned by the signed-in user and readable only by that user
 * (`/users/me/feedback`) or a platform admin. The `ticket` reference (FB-XXXXXX)
 * is what the confirmation screen shows and what support asks for.
 */

const CATEGORIES = [
  'bug',
  'feature',
  'booking',
  'payment',
  'restaurant_experience',
  'general',
] as const;
const STATUSES = ['open', 'in_progress', 'resolved', 'closed'] as const;

const TICKET_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function makeTicket(): string {
  return (
    'FB-' +
    Array.from({ length: 6 }, () => TICKET_ALPHABET[randomInt(TICKET_ALPHABET.length)] ?? 'X').join('')
  );
}

type FeedbackRow = {
  id: string;
  category: string;
  subject: string;
  description: string;
  related_ref: string;
  status: string;
  ticket: string;
  created_at: Date;
  updated_at: Date;
};

function serialize(f: FeedbackRow) {
  return {
    id: f.id,
    category: f.category,
    subject: f.subject,
    description: f.description,
    relatedRef: f.related_ref,
    status: f.status,
    ticket: f.ticket,
    createdAt: f.created_at,
    updatedAt: f.updated_at,
  };
}

const createSchema = z.object({
  category: z.enum(CATEGORIES),
  subject: z.string().trim().min(3).max(120),
  description: z.string().trim().min(10).max(2000),
  // Optional booking/event reference the user is asking about (e.g. DC-7K3MQ).
  relatedRef: z.string().trim().max(40).default(''),
});

// POST /api/feedback — file a ticket. Rate limited per IP (10/hour default).
router.post('/feedback', feedbackRateLimiter, async (req, res) => {
  const { category, subject, description, relatedRef } = createSchema.parse(
    req.body ?? {},
  );

  const [created] = await query<FeedbackRow>(
    `INSERT INTO feedback (user_id, category, subject, description, related_ref, ticket)
     VALUES ($1::UUID, $2, $3, $4, $5, $6)
     RETURNING id, category, subject, description, related_ref, status, ticket, created_at, updated_at`,
    [req.userId, category, subject, description, relatedRef, makeTicket()],
  );
  if (!created) throw new ApiError(500, 'Feedback could not be saved');

  res.status(201).json({ feedback: serialize(created) });
});

// GET /api/users/me/feedback — own ticket history with live statuses.
router.get('/users/me/feedback', async (req, res) => {
  const rows = await query<FeedbackRow>(
    `SELECT id, category, subject, description, related_ref, status, ticket, created_at, updated_at
     FROM feedback
     WHERE user_id = $1::UUID
     ORDER BY created_at DESC
     LIMIT 100`,
    [req.userId],
  );
  res.json({ feedback: rows.map(serialize), count: rows.length });
});

// ── Admin support queue (super_admin only) ──────────────────────────────────

// GET /api/feedback?status=open — admins triage the queue.
router.get(
  '/feedback',
  requireRole('super_admin'),
  async (req, res) => {
    const status =
      typeof req.query.status === 'string' &&
      (STATUSES as readonly string[]).includes(req.query.status)
        ? req.query.status
        : null;

    const rows = await query<FeedbackRow & { user_id: string }>(
      `SELECT id, category, subject, description, related_ref, status, ticket,
              created_at, updated_at, user_id
       FROM feedback
       ${status ? 'WHERE status = $1' : ''}
       ORDER BY created_at DESC
       LIMIT 100`,
      status ? [status] : [],
    );
    res.json({
      feedback: rows.map((f) => ({ ...serialize(f), userId: f.user_id })),
      count: rows.length,
    });
  },
);

const statusSchema = z.object({ status: z.enum(STATUSES) });

// PATCH /api/feedback/:id — advance a ticket's status (support workflow only;
// users never get to move their own ticket).
router.patch(
  '/feedback/:id',
  requireRole('super_admin'),
  async (req, res) => {
    const { status } = statusSchema.parse(req.body ?? {});
    const [updated] = await query<FeedbackRow>(
      `UPDATE feedback
       SET status = $2, updated_at = now()
       WHERE id = $1::UUID
       RETURNING id, category, subject, description, related_ref, status, ticket, created_at, updated_at`,
      [req.params.id, status],
    );
    if (!updated) throw notFound('Feedback');
    res.json({ feedback: serialize(updated) });
  },
);

export default router;
