import { Router } from 'express';
import type { Request } from 'express';
import type pg from 'pg';
import { z } from 'zod';

import { query, withTransaction } from '../db.js';
import { ApiError, forbidden, notFound, patchKeys } from '../context.js';
import { requireVenueRole } from '../access.js';
import { notifyUser } from '../notify.js';

/**
 * The venue half of the two-way collaboration inbox.
 *
 * Before this router existed a venue operator had no way to see, answer or send
 * a collaboration proposal: `collaboration_invites` was only ever read and
 * written by `/api/hosts/*`, which is the host's own surface. Every handler here
 * opens with `requireVenueRole`, so a partner can never read another venue's
 * inbox by guessing an id.
 *
 * Mounted at `/api/partner/restaurants`.
 */
const router = Router();

type ProposalRow = {
  id: string;
  host_id: string;
  restaurant_id: string;
  title: string;
  message: string;
  status: string;
  proposed_by: string;
  experience_id: string | null;
  created_at: Date;
  responded_at: Date | null;
  responded_by: string | null;
  decline_reason: string;
  restaurant_name: string;
  host_name: string | null;
  host_handle: string | null;
  host_avatar: string | null;
  host_account_type: string | null;
  experience_title: string | null;
  experience_cover: string | null;
  experience_start: Date | null;
  experience_status: string | null;
};

/**
 * One proposal, in the shape both apps render. `direction` is derived rather
 * than stored so the client never has to reason about `proposed_by`.
 */
function serializeProposal(row: ProposalRow) {
  return {
    id: row.id,
    title: row.title,
    message: row.message,
    status: row.status,
    proposedBy: row.proposed_by,
    direction: row.proposed_by === 'restaurant' ? 'outgoing' : 'incoming',
    experienceId: row.experience_id,
    createdAt: row.created_at,
    respondedAt: row.responded_at,
    respondedBy: row.responded_by,
    declineReason: row.decline_reason,
    // Direction B publishes on top of a draft experience, so the venue must see
    // exactly which experience the host is accepting on its behalf.
    experience: row.experience_id === null ? null : {
      id: row.experience_id,
      title: row.experience_title,
      coverImage: row.experience_cover,
      startAt: row.experience_start,
      status: row.experience_status,
    },
    host: {
      id: row.host_id,
      name: row.host_name,
      handle: row.host_handle,
      avatarUrl: row.host_avatar,
      accountType: row.host_account_type,
    },
    restaurant: {
      id: row.restaurant_id,
      name: row.restaurant_name,
    },
  };
}

const PROPOSAL_SELECT = `
  SELECT ci.id, ci.host_id, ci.restaurant_id, ci.title, ci.message, ci.status,
         ci.proposed_by, ci.experience_id, ci.created_at, ci.responded_at,
         ci.responded_by, ci.decline_reason,
         r.name AS restaurant_name,
         h.name AS host_name, h.handle AS host_handle,
         h.avatar_url AS host_avatar, h.account_type AS host_account_type,
         ex.title AS experience_title, ex.cover_image AS experience_cover,
         ex.start_at AS experience_start, ex.status AS experience_status
    FROM collaboration_invites ci
    JOIN restaurants r ON r.id = ci.restaurant_id
    LEFT JOIN users h ON h.id = ci.host_id
    LEFT JOIN dinner_events ex ON ex.id = ci.experience_id`;

const PROPOSAL_BY_ID = `${PROPOSAL_SELECT} WHERE ci.id = $1::UUID`;

async function readProposal(id: string): Promise<ProposalRow> {
  const [row] = await query<ProposalRow>(PROPOSAL_BY_ID, [id]);
  if (!row) throw notFound('Proposal');
  return row;
}

// ── Inbox ────────────────────────────────────────────────────────────────────

/**
 * GET /api/partner/restaurants/:restaurantId/collab-proposals
 *
 * `direction=incoming` returns proposals hosts sent the venue (the venue answers
 * those); `direction=outgoing` returns proposals the venue sent hosts (the venue
 * may cancel those). Omit it to get both, which is what the app's single
 * proposals tab renders.
 */
router.get('/:restaurantId/collab-proposals', async (req, res) => {
  const { restaurantId } = req.params;
  await requireVenueRole(req, restaurantId);

  const status = typeof req.query.status === 'string' ? req.query.status.trim() : '';
  const direction = typeof req.query.direction === 'string' ? req.query.direction.trim() : '';
  if (status && !['invited', 'accepted', 'declined', 'cancelled', 'completed'].includes(status)) {
    throw new ApiError(400, 'status must be invited, accepted, declined, cancelled or completed');
  }
  if (direction && !['incoming', 'outgoing'].includes(direction)) {
    throw new ApiError(400, 'direction must be incoming or outgoing');
  }

  const params: unknown[] = [restaurantId];
  const conditions = ['ci.restaurant_id = $1::UUID'];
  if (status) {
    params.push(status);
    conditions.push(`ci.status = $${params.length}`);
  }
  if (direction === 'incoming') conditions.push(`ci.proposed_by = 'host'`);
  if (direction === 'outgoing') conditions.push(`ci.proposed_by = 'restaurant'`);

  params.push(Math.min(Number(req.query.limit) || 100, 200));
  const rows = await query<ProposalRow>(
    `${PROPOSAL_SELECT}
      WHERE ${conditions.join(' AND ')}
      ORDER BY ci.created_at DESC
      LIMIT $${params.length}`,
    params,
  );

  // Every partner surface answers inside `{ data: ... }`; the Partner App's
  // single JSON reader assumes that envelope and finds nothing without it.
  res.json({
    data: {
      proposals: rows.map(serializeProposal),
      count: rows.length,
    },
  });
});

// ── Venue answers an incoming proposal ───────────────────────────────────────

const respondSchema = z.object({ reason: z.string().trim().max(500).optional() });

/**
 * Answer a proposal a *host* sent. The venue is the recipient here, so it may
 * only move `proposed_by='host'` rows out of `invited`; a venue that tries to
 * accept its own outgoing proposal would be approving itself, which is why the
 * UPDATE carries `proposed_by = 'host'` and a lost race becomes a 409.
 */
async function answerIncoming(
  req: Request,
  restaurantId: string,
  proposalId: string,
  decision: 'accepted' | 'declined',
): Promise<ProposalRow> {
  await requireVenueRole(req, restaurantId, 'manager');

  const reason = respondSchema.parse(req.body ?? {}).reason ?? '';
  const proposal = await readProposal(proposalId);
  if (proposal.restaurant_id !== restaurantId) throw notFound('Proposal');

  if (proposal.proposed_by !== 'host') {
    throw new ApiError(409, 'This proposal was sent by your venue, so the host has to answer it');
  }
  if (proposal.status !== 'invited') {
    throw new ApiError(409, `This proposal is already ${proposal.status}`);
  }

  const moved = await withTransaction(async (client) => {
    const result = await client.query(
      `UPDATE collaboration_invites
          SET status = $2, responded_at = now(), responded_by = $3::UUID,
              decline_reason = $4, updated_at = now()
        WHERE id = $1::UUID AND restaurant_id = $5::UUID
          AND status = 'invited' AND proposed_by = 'host'`,
      [proposalId, decision, req.userId, reason, restaurantId],
    );
    if ((result.rowCount ?? 0) === 0) return false;

    await notifyUser(client, proposal.host_id, {
      kind: 'collab',
      title: decision === 'accepted'
        ? 'Collaboration accepted'
        : 'Collaboration declined',
      body: decision === 'accepted'
        ? `${proposal.restaurant_name} accepted "${proposal.title}".`
        : (reason
          ? `${proposal.restaurant_name} declined "${proposal.title}": ${reason}`
          : `${proposal.restaurant_name} declined "${proposal.title}".`),
      eventId: proposal.experience_id,
    });
    return true;
  });
  if (!moved) throw new ApiError(409, 'This proposal is no longer pending');

  return readProposal(proposalId);
}

router.post('/:restaurantId/collab-proposals/:proposalId/accept', async (req, res) => {
  const { restaurantId, proposalId } = req.params;
  const updated = await answerIncoming(
    req, String(restaurantId), String(proposalId), 'accepted',
  );
  res.json({ data: { proposal: serializeProposal(updated), status: 'accepted' } });
});

router.post('/:restaurantId/collab-proposals/:proposalId/decline', async (req, res) => {
  const { restaurantId, proposalId } = req.params;
  const updated = await answerIncoming(
    req, String(restaurantId), String(proposalId), 'declined',
  );
  res.json({ data: { proposal: serializeProposal(updated), status: 'declined' } });
});

/**
 * POST /api/partner/restaurants/:restaurantId/collab-proposals/:proposalId/cancel
 *
 * Withdraw a proposal the venue sent. A venue can only withdraw its own
 * outgoing proposal while it is still unanswered.
 */
router.post('/:restaurantId/collab-proposals/:proposalId/cancel', async (req, res) => {
  const { restaurantId, proposalId } = req.params;
  await requireVenueRole(req, restaurantId, 'manager');

  const proposal = await readProposal(proposalId);
  if (proposal.restaurant_id !== restaurantId) throw notFound('Proposal');
  if (proposal.proposed_by !== 'restaurant') {
    throw new ApiError(409, 'Only a proposal your venue sent can be cancelled');
  }
  if (proposal.status !== 'invited') {
    throw new ApiError(409, `This proposal is already ${proposal.status}`);
  }

  const moved = await withTransaction(async (client) => {
    const result = await client.query(
      `UPDATE collaboration_invites
          SET status = 'cancelled', updated_at = now(), responded_by = $2::UUID,
              responded_at = now()
        WHERE id = $1::UUID AND restaurant_id = $3::UUID
          AND status = 'invited' AND proposed_by = 'restaurant'`,
      [proposalId, req.userId, restaurantId],
    );
    if ((result.rowCount ?? 0) === 0) return false;

    await notifyUser(client, proposal.host_id, {
      kind: 'collab',
      title: 'Collaboration withdrawn',
      body: `${proposal.restaurant_name} withdrew "${proposal.title}".`,
      eventId: proposal.experience_id,
    });
    return true;
  });
  if (!moved) throw new ApiError(409, 'This proposal is no longer pending');

  res.json({
    data: { proposal: serializeProposal(await readProposal(proposalId)), status: 'cancelled' },
  });
});

// ── Direction B: the venue proposes to a host ────────────────────────────────

const proposeSchema = z.object({
  hostId: z.string().uuid(),
  title: z.string().trim().min(3).max(120),
  message: z.string().trim().min(1).max(1000),
  /**
   * Optional draft experience to attach. It must already belong to this venue
   * and to the host being asked, so a proposal can never be a back door to
   * publishing somebody else's draft.
   */
  experienceId: z.string().uuid().optional(),
});

router.post('/:restaurantId/collab-proposals', async (req, res) => {
  const { restaurantId } = req.params;
  await requireVenueRole(req, restaurantId, 'manager');

  const input = proposeSchema.parse(req.body ?? {});

  const [host] = await query<{ id: string; name: string; account_type: string }>(
    `SELECT id, name, account_type FROM users
      WHERE id = $1::UUID AND account_type = 'professional'`,
    [input.hostId],
  );
  if (!host) throw notFound('Host');

  if (input.experienceId) {
    const [linked] = await query<{ id: string; status: string }>(
      `SELECT id, status FROM dinner_events
        WHERE id = $1::UUID AND restaurant_id = $2::UUID AND host_id = $3::UUID`,
      [input.experienceId, restaurantId, input.hostId],
    );
    if (!linked) {
      throw new ApiError(422, 'That experience does not belong to this host at your venue');
    }
    if (linked.status !== 'draft') {
      throw new ApiError(422, 'Only a draft experience can be proposed for approval');
    }
  }

  const [venue] = await query<{ name: string }>(
    'SELECT name FROM restaurants WHERE id = $1::UUID',
    [restaurantId],
  );

  // Friendly pre-check; `uq_collab_active` is the real guard when two sends race.
  const [existing] = await query<{ id: string }>(
    `SELECT id FROM collaboration_invites
      WHERE host_id = $1::UUID AND restaurant_id = $2::UUID
        AND status IN ('invited', 'accepted')
      LIMIT 1`,
    [input.hostId, restaurantId],
  );
  if (existing) {
    throw new ApiError(409, 'An active collaboration already exists with this host');
  }

  // Offer the host an access chip that actually works: the host role, not the
  // venue-side role the caller happens to hold.
  if (input.hostId === req.userId) {
    throw forbidden('You cannot propose a collaboration to yourself');
  }

  let createdId: string;
  try {
    createdId = await withTransaction(async (client) => {
      const result = await client.query<{ id: string }>(
        `INSERT INTO collaboration_invites
           (host_id, restaurant_id, title, message, proposed_by, experience_id)
         VALUES ($1::UUID, $2::UUID, $3, $4, 'restaurant', $5::UUID)
         RETURNING id`,
        [input.hostId, restaurantId, input.title, input.message, input.experienceId ?? null],
      );
      const id = result.rows[0]!.id;

      await notifyUser(client, input.hostId, {
        kind: 'collab',
        title: 'New collaboration proposal from a venue',
        body: `${venue?.name ?? 'A venue'} invited you: "${input.title}". ${input.message.slice(0, 80)}`,
        eventId: input.experienceId ?? null,
      });
      return id;
    });
  } catch (error) {
    if ((error as { code?: string }).code === '23505') {
      throw new ApiError(409, 'An active collaboration already exists with this host');
    }
    throw error;
  }

  res.status(201).json({ data: { proposal: serializeProposal(await readProposal(createdId)) } });
});

// ── Host discovery ───────────────────────────────────────────────────────────

/**
 * GET /api/partner/restaurants/:restaurantId/discover-hosts?q=&limit=
 *
 * Professional hosts this venue is not already in an active collaboration with.
 * The predicate matches `users.ts`' `?hosts=true` roster so "who is a host"
 * means the same thing everywhere: professional accounts with a host-ladder
 * role, plus anyone who has already hosted an event.
 */
router.get('/:restaurantId/discover-hosts', async (req, res) => {
  const { restaurantId } = req.params;
  await requireVenueRole(req, restaurantId);

  const rawLimit = Number(req.query.limit);
  const limit = Math.min(Number.isFinite(rawLimit) && rawLimit > 0 ? rawLimit : 30, 100);
  const q = typeof req.query.q === 'string' ? req.query.q.trim() : '';

  const params: unknown[] = [restaurantId];
  const conditions = [
    `u.account_type = 'professional'`,
    `(u.role IN ('host','influencer','partner_admin','super_admin')
      OR EXISTS (SELECT 1 FROM dinner_events de WHERE de.host_id = u.id))`,
    `NOT EXISTS (
       SELECT 1 FROM collaboration_invites ci
        WHERE ci.host_id = u.id AND ci.restaurant_id = $1::UUID
          AND ci.status IN ('invited','accepted'))`,
  ];
  if (q) {
    params.push(`%${q}%`);
    conditions.push(`(u.name ILIKE $${params.length} OR u.handle ILIKE $${params.length})`);
  }
  params.push(limit);

  const rows = await query<{
    id: string; name: string; handle: string; avatar_url: string | null;
    bio: string; followers_count: number; events_together: number;
  }>(
    `SELECT u.id, u.name, u.handle, u.avatar_url, u.bio, u.followers_count,
            (SELECT count(*) FROM dinner_events e
              WHERE e.host_id = u.id AND e.restaurant_id = $1::UUID)::int AS events_together
       FROM users u
      WHERE ${conditions.join(' AND ')}
      ORDER BY events_together DESC, u.followers_count DESC, u.name ASC
      LIMIT $${params.length}`,
    params,
  );

  res.json({
    data: {
      hosts: rows.map((r) => ({
        id: r.id,
        name: r.name,
        handle: r.handle,
        avatarUrl: r.avatar_url,
        bio: r.bio,
        followersCount: r.followers_count,
        eventsTogether: r.events_together,
      })),
      count: rows.length,
    },
  });
});

export default router;
