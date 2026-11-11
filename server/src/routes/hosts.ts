import { Router } from 'express';
import { z } from 'zod';
import type pg from 'pg';
import { query, withTransaction } from '../db.js';
import { ApiError, forbidden, notFound, requireHostStudio } from '../context.js';
import type { UserRole } from '../context.js';
import { notifyVenue } from '../notify.js';

// Phase 2a: 0% commission, inlined so pricing.ts can be deleted.
const PLATFORM_COMMISSION_RATE = 0;

const router = Router();

// Host Studio is a Professional-account surface. Venue-side and admin roles are
// exempt inside the guard so the Partner app's `/hosts/:id/summary` reads keep
// working unchanged; a customer on a Personal account is refused here rather
// than being allowed to call the API behind a hidden screen.
router.use(requireHostStudio);

type PayoutRow = {
  id: string;
  event_id: string;
  event_title: string;
  payout_date: Date;
  seats_sold: number;
  gross: string;
  commission: string;
  status: string;
};

function serialize(p: PayoutRow) {
  const gross = Number(p.gross);
  const commission = Number(p.commission);
  return {
    id: p.id,
    eventId: p.event_id,
    eventTitle: p.event_title,
    date: p.payout_date,
    seatsSold: p.seats_sold,
    gross,
    commission,
    net: gross - commission,
    status: p.status,
  };
}

async function requireHost(id: string): Promise<void> {
  const [host] = await query<{ id: string }>(
    'SELECT id FROM users WHERE id = $1::UUID',
    [id],
  );
  if (!host) throw notFound('Host');
}

/**
 * Ensure the caller is either the host themselves, or a privileged role.
 * Prevents any random user from viewing another host's financial data.
 */
export function assertHostAccess(requesterId: string, requesterRole: UserRole, targetHostId: string): void {
  if (requesterId === targetHostId) return;
  if (requesterRole === 'super_admin') return;
  throw forbidden('You can only view your own collaborations');
}

// GET /api/hosts/:id/payouts, one earnings line per hosted event.
router.get('/:id/payouts', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<PayoutRow>(
    `SELECT p.*, e.title AS event_title
     FROM payouts p
     JOIN dinner_events e ON e.id = p.event_id
     WHERE e.host_id = $1::UUID
     ORDER BY p.payout_date DESC
     LIMIT 200`,
    [hostId],
  );
  res.json({ payouts: rows.map(serialize), count: rows.length });
});

type MoneyRow = {
  earned: number;
  in_transit: number;
  scheduled: number;
  lifetime_gross: number;
  commission_total: number;
  seats_sold: number;
};

type TablesRow = {
  hosted_count: number;
  upcoming_count: number;
  fill_rate: number;
  seats_reserved: number;
};

// GET /api/hosts/:id/summary, headline numbers for the earnings panel.
router.get('/:id/summary', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const [money] = await query<MoneyRow>(
    `SELECT
       COALESCE((SUM(gross - commission) FILTER (WHERE p.status = 'paid')), 0)::float8      AS earned,
       COALESCE((SUM(gross - commission) FILTER (WHERE p.status = 'processing')), 0)::float8 AS in_transit,
       COALESCE((SUM(gross - commission) FILTER (WHERE p.status = 'scheduled')), 0)::float8 AS scheduled,
       COALESCE(SUM(gross), 0)::float8                                                     AS lifetime_gross,
       COALESCE(SUM(commission), 0)::float8                                                AS commission_total,
       COALESCE(SUM(seats_sold), 0)::int                                                   AS seats_sold
     FROM payouts p
     JOIN dinner_events e ON e.id = p.event_id
     WHERE e.host_id = $1::UUID`,
    [hostId],
  );

  const [tables] = await query<TablesRow>(
    `SELECT count(*)::int AS hosted_count,
            (count(*) FILTER (WHERE start_at >= now()))::int AS upcoming_count,
            COALESCE(AVG(seats_booked::numeric / GREATEST(seats_total, 1)), 0)::float8 AS fill_rate,
            COALESCE(SUM(seats_booked), 0)::int AS seats_reserved
     FROM dinner_events
     WHERE host_id = $1::UUID`,
    [hostId],
  );

  // Ratings come from guest reviews of this host's experiences. `users.rating`
  // is a cached column nothing in the host workflow writes, so reading it
  // would report a stale (or seeded) number instead of the review average.
  const [ratings] = await query<{ avg: number | null; count: number }>(
    `SELECT AVG(r.rating)::float8 AS avg, count(*)::int AS count
     FROM reviews r
     JOIN dinner_events e ON e.id = r.event_id
     WHERE e.host_id = $1::UUID`,
    [hostId],
  );

  const earned = money?.earned ?? 0;
  const inTransit = money?.in_transit ?? 0;
  const scheduled = money?.scheduled ?? 0;
  const lifetimeGross = money?.lifetime_gross ?? 0;
  const seatsSold = money?.seats_sold ?? 0;

  const now = new Date();
  const nextPayout = new Date(now.getFullYear(), now.getMonth() + 1, 1);

  res.json({
    hostId,
    earned,
    inTransit,
    scheduled,
    lifetimeGross,
    commissionTotal: money?.commission_total ?? 0,
    netTotal: earned + inTransit + scheduled,
    // `seatsSold` is the payout ledger's count, kept for the partner app's
    // existing contract. Free RSVPs reserve a seat without selling one, so the
    // customer app reads `seatsReserved` (live `dinner_events.seats_booked`).
    seatsSold,
    seatsReserved: tables?.seats_reserved ?? 0,
    averageSeatPrice: seatsSold > 0 ? lifetimeGross / seatsSold : 0,
    hostedCount: tables?.hosted_count ?? 0,
    upcomingCount: tables?.upcoming_count ?? 0,
    averageFillRate: tables?.fill_rate ?? 0,
    averageRating: Number(ratings?.avg ?? 0),
    reviewCount: ratings?.count ?? 0,
    nextPayoutDate: nextPayout.toISOString(),
    platformCommissionRate: PLATFORM_COMMISSION_RATE,
    // Withdrawable now: net captured, less withdrawals still in flight.
    available: await availableBalance(hostId),
  });
});

type TrendRow = {
  label: string;
  month: Date;
  seats: number;
  revenue: number;
};

// GET /api/hosts/:id/trend, net revenue and seats per month.
router.get('/:id/trend', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<TrendRow>(
    `SELECT to_char(m.month, 'Mon') AS label,
            m.month,
            COALESCE(SUM(p.seats_sold), 0)::int AS seats,
            COALESCE(SUM(p.gross - p.commission), 0)::float8 AS revenue
     FROM generate_series(
            date_trunc('month', now()) - interval '5 months',
            date_trunc('month', now()),
            interval '1 month') AS m(month)
     LEFT JOIN payouts p
       ON date_trunc('month', p.payout_date) = m.month
      AND p.event_id IN (SELECT id FROM dinner_events WHERE host_id = $1::UUID)
     GROUP BY m.month
     ORDER BY m.month DESC`,
    [hostId],
  );

  res.json({
    trend: rows
      .slice(0, 6)
      .reverse()
      .map((r) => ({ label: r.label, seats: r.seats, revenue: r.revenue })),
  });
});

type InviteRow = {
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
  restaurant_cover: string;
  restaurant_neighborhood: string;
  restaurant_rating: string;
  restaurant_cuisines: string[];
  host_name: string | null;
  host_handle: string | null;
  host_avatar: string | null;
  experience_title: string | null;
  experience_cover: string | null;
  experience_start: Date | null;
  experience_status: string | null;
};

function serializeInvite(row: InviteRow) {
  return {
    id: row.id,
    title: row.title,
    message: row.message,
    status: row.status,
    proposedBy: row.proposed_by,
    experienceId: row.experience_id,
    receivedAt: row.created_at,
    respondedAt: row.responded_at,
    declineReason: row.decline_reason,
    // Direction B: a venue proposes on top of a draft experience, so the host
    // has to see what they are being asked to accept without a second call.
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
    },
    restaurant: {
      id: row.restaurant_id,
      name: row.restaurant_name,
      coverImage: row.restaurant_cover,
      neighborhood: row.restaurant_neighborhood,
      rating: Number(row.restaurant_rating ?? 0),
      cuisines: row.restaurant_cuisines ?? [],
    },
  };
}

const INVITE_SELECT = `
  SELECT ci.*, r.name AS restaurant_name, r.cover_image AS restaurant_cover,
         r.neighborhood AS restaurant_neighborhood,
         r.rating AS restaurant_rating, r.cuisines AS restaurant_cuisines,
         h.name AS host_name, h.handle AS host_handle,
         h.avatar_url AS host_avatar,
         ex.title AS experience_title, ex.cover_image AS experience_cover,
         ex.start_at AS experience_start, ex.status AS experience_status
  FROM collaboration_invites ci
  JOIN restaurants r ON r.id = ci.restaurant_id
  LEFT JOIN users h ON h.id = ci.host_id
  LEFT JOIN dinner_events ex ON ex.id = ci.experience_id`;

const INVITE_BY_ID = `${INVITE_SELECT} WHERE ci.id = $1::UUID`;

// ── Per-event analytics ──────────────────────────────────────────────────────
type PerformanceRow = {
  event_id: string;
  title: string;
  cover_image: string;
  views: number;
  seats_booked: number;
  bookings: number;
  pending: number;
  checked_in: number;
};

// GET /api/hosts/:id/performance, views / bookings / attendance per event.
router.get('/:id/performance', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<PerformanceRow>(
    `SELECT e.id AS event_id, e.title, e.cover_image, e.views, e.seats_booked,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id
                AND b.status IN ('confirmed', 'pending'))::int  AS bookings,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id AND b.status = 'pending')::int AS pending,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id AND b.checked_in)::int     AS checked_in
     FROM dinner_events e
     WHERE e.host_id = $1::UUID
     ORDER BY e.start_at DESC
     LIMIT 200`,
    [hostId],
  );

  res.json({
    performance: rows.map((r) => ({
      eventId: r.event_id,
      title: r.title,
      coverImage: r.cover_image,
      views: r.views,
      seatsBooked: r.seats_booked,
      bookings: r.bookings,
      pending: r.pending,
      checkedIn: r.checked_in,
    })),
    count: rows.length,
  });
});

// ── Partner venues ───────────────────────────────────────────────────────────
type PartnerRow = {
  id: string;
  name: string;
  cover_image: string;
  neighborhood: string;
  events_together: number;
};

// GET /api/hosts/:id/partners, distinct venues the host has held tables at.
router.get('/:id/partners', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<PartnerRow>(
    `SELECT r.id, r.name, r.cover_image, r.neighborhood,
            count(e.id)::int AS events_together
     FROM dinner_events e
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE e.host_id = $1::UUID
     GROUP BY r.id, r.name, r.cover_image, r.neighborhood
     ORDER BY events_together DESC, r.name ASC`,
    [hostId],
  );

  res.json({
    partners: rows.map((r) => ({
      id: r.id,
      name: r.name,
      coverImage: r.cover_image,
      neighborhood: r.neighborhood,
      eventsTogether: r.events_together,
    })),
    count: rows.length,
  });
});

// ── Collaboration invites ────────────────────────────────────────────────────
// GET /api/hosts/:id/invites, partnership offers (incoming from restaurants).
router.get('/:id/invites', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<InviteRow>(
    `${INVITE_SELECT} WHERE ci.host_id = $1::UUID ORDER BY ci.created_at DESC`,
    [hostId],
  );
  res.json({ invites: rows.map(serializeInvite), count: rows.length });
});

// GET /api/hosts/:id/collabs: ALL collaborations (incoming + outgoing).
router.get('/:id/collabs', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<InviteRow>(
    `${INVITE_SELECT} WHERE ci.host_id = $1::UUID ORDER BY ci.created_at DESC`,
    [hostId],
  );
  res.json({ collaborations: rows.map(serializeInvite), count: rows.length });
});

// POST /api/hosts/:id/collabs/propose, host sends a collaboration proposal.
const proposeSchema = z.object({
  restaurantId: z.string().uuid(),
  title: z.string().trim().min(3).max(120),
  message: z.string().trim().min(1).max(1000),
  // Optional: attach the experience this proposal is about. Validated against
  // the caller and the target venue so a proposal cannot point at a stranger's
  // draft.
  experienceId: z.string().uuid().optional(),
});

router.post('/:id/collabs/propose', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  if (req.userId !== hostId) throw forbidden('You can only propose on your own behalf');

  const input = proposeSchema.parse(req.body ?? {});

  // Validate restaurant exists and is a verified partner.
  const [restaurant] = await query<{ id: string; owner_id: string | null }>(
    `SELECT id, owner_id FROM restaurants
     WHERE id = $1::UUID AND is_partner = true AND partnership_status = 'verified'`,
    [input.restaurantId],
  );
  if (!restaurant) throw notFound('Restaurant partner');

  if (input.experienceId) {
    const [linked] = await query<{ id: string }>(
      `SELECT id FROM dinner_events
       WHERE id = $1::UUID AND host_id = $2::UUID AND restaurant_id = $3::UUID`,
      [input.experienceId, hostId, input.restaurantId],
    );
    if (!linked) {
      throw new ApiError(422, 'That experience does not belong to you at this venue');
    }
  }

  // Friendly pre-check. The real guard against two concurrent sends is
  // `uq_collab_active`, because a read-then-write check cannot see the row the
  // other request is about to insert.
  const [existing] = await query<{ id: string }>(
    `SELECT id FROM collaboration_invites
     WHERE host_id = $1::UUID AND restaurant_id = $2::UUID
       AND status IN ('invited', 'accepted')
     LIMIT 1`,
    [hostId, input.restaurantId],
  );
  if (existing) {
    throw new ApiError(409, 'An active collaboration already exists with this restaurant');
  }

  const createdId = await withTransaction(async (client) => {
    let insertedId: string;
    try {
      const { rows } = await client.query<{ id: string }>(
        `INSERT INTO collaboration_invites
           (host_id, restaurant_id, title, message, proposed_by, experience_id)
         VALUES ($1::UUID, $2::UUID, $3, $4, 'host', $5::UUID)
         RETURNING id`,
        [
          hostId, input.restaurantId, input.title, input.message,
          input.experienceId ?? null,
        ],
      );
      insertedId = rows[0]!.id;
    } catch (error) {
      if ((error as { code?: string }).code === '23505') {
        throw new ApiError(409, 'An active collaboration already exists with this restaurant');
      }
      throw error;
    }

    await notifyVenue(client, input.restaurantId, {
      kind: 'collab',
      title: 'New collaboration proposal from host',
      body: `"${input.title}": ${input.message.slice(0, 80)}`,
      eventId: input.experienceId ?? null,
    });
    return insertedId;
  });

  // Re-read with the venue/host/experience JOINs for the full response.
  const [full] = await query<InviteRow>(INVITE_BY_ID, [createdId]);
  res.status(201).json({ collaboration: serializeInvite(full!) });
});

// POST /api/hosts/:id/collabs/:collabId/cancel, host cancels their own pending proposal.
router.post('/:id/collabs/:collabId/cancel', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  if (req.userId !== hostId) throw forbidden('You can only cancel your own proposals');

  const [collab] = await query<InviteRow>(INVITE_BY_ID, [req.params.collabId]);
  if (!collab || collab.host_id !== hostId) throw notFound('Collaboration');
  if (collab.status !== 'invited') {
    throw new ApiError(400, 'Only pending proposals can be cancelled');
  }
  if (collab.proposed_by !== 'host') {
    throw new ApiError(400, 'You can only cancel proposals you sent');
  }

  await query(
    `UPDATE collaboration_invites SET status = 'cancelled', updated_at = now()
     WHERE id = $1::UUID AND host_id = $2::UUID`,
    [req.params.collabId, hostId],
  );

  const [updated] = await query<InviteRow>(INVITE_BY_ID, [req.params.collabId]);
  res.json({ collaboration: serializeInvite(updated!), status: 'cancelled' });
});

// POST /api/hosts/:id/collabs/:collabId/complete, mark collaboration completed.
// Optionally records which experience the partnership actually shipped, so the
// venue can see the result of the proposal it approved.
const completeSchema = z.object({ experienceId: z.string().uuid().optional() });

router.post('/:id/collabs/:collabId/complete', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  if (req.userId !== hostId) throw forbidden('You can only complete your own collaborations');

  const input = completeSchema.parse(req.body ?? {});
  const [collab] = await query<InviteRow>(INVITE_BY_ID, [req.params.collabId]);
  if (!collab || collab.host_id !== hostId) throw notFound('Collaboration');
  if (collab.status !== 'accepted') {
    throw new ApiError(400, 'Only accepted collaborations can be marked complete');
  }

  if (input.experienceId) {
    const [linked] = await query<{ id: string }>(
      `SELECT id FROM dinner_events
        WHERE id = $1::UUID AND host_id = $2::UUID AND restaurant_id = $3::UUID`,
      [input.experienceId, hostId, collab.restaurant_id],
    );
    if (!linked) {
      throw new ApiError(422, 'That experience does not belong to you at this venue');
    }
  }

  const moved = await withTransaction(async (client) => {
    const result = await client.query(
      `UPDATE collaboration_invites
          SET status = 'completed', updated_at = now(),
              experience_id = COALESCE($3::UUID, experience_id)
        WHERE id = $1::UUID AND host_id = $2::UUID AND status = 'accepted'`,
      [req.params.collabId, hostId, input.experienceId ?? null],
    );
    if ((result.rowCount ?? 0) === 0) return false;

    await notifyVenue(client, collab.restaurant_id, {
      kind: 'collab',
      title: 'Collaboration completed',
      body: `"${collab.title}" has been marked as completed.`,
      eventId: input.experienceId ?? collab.experience_id,
    });
    return true;
  });
  if (!moved) throw new ApiError(409, 'This collaboration is no longer accepted');

  const [updated] = await query<InviteRow>(INVITE_BY_ID, [req.params.collabId]);
  res.json({ collaboration: serializeInvite(updated!), status: 'completed' });
});

// POST /api/hosts/:id/invites/:inviteId/accept, flip a venue-sent invite to
// accepted.
//
// Only the invite's own host may act on it: a foreign `:id` or caller reads as
// a 404 (no existence leak) rather than a 403 that would confirm it exists.
// The host may only answer an invite the *venue* sent: accepting one's own
// outgoing proposal (Direction A) used to succeed, which let a host grant
// themselves a collaboration the venue never approved.
const respondSchema = z.object({ reason: z.string().trim().max(500).optional() });

router.post('/:id/invites/:inviteId/accept', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  if (req.userId !== hostId) throw forbidden('You can only answer your own invites');

  const body = respondSchema.parse(req.body ?? {});
  const [invite] = await query<InviteRow>(INVITE_BY_ID, [req.params.inviteId]);
  if (!invite || invite.host_id !== hostId) throw notFound('Invite');
  if (invite.proposed_by !== 'restaurant') {
    throw new ApiError(409, 'Only a proposal the venue sent can be accepted here');
  }
  if (invite.status !== 'invited') {
    throw new ApiError(409, `This proposal is already ${invite.status}`);
  }

  // Conditional UPDATE: two taps racing each other can only move one row, so
  // the loser gets a 409 instead of a second "accepted" notification.
  const moved = await withTransaction(async (client) => {
    const result = await client.query(
      `UPDATE collaboration_invites
          SET status = 'accepted', responded_at = now(), responded_by = $2::UUID,
              decline_reason = $3, updated_at = now()
        WHERE id = $1::UUID AND host_id = $2::UUID AND status = 'invited'
          AND proposed_by = 'restaurant'`,
      [req.params.inviteId, hostId, body.reason ?? ''],
    );
    if ((result.rowCount ?? 0) === 0) return false;

    const { rows: venueRows } = await client.query<{ name: string }>(
      'SELECT name FROM restaurants WHERE id = $1::UUID',
      [invite.restaurant_id],
    );
    const venueName = venueRows[0]?.name ?? 'your venue';
    await notifyVenue(client, invite.restaurant_id, {
      kind: 'collab',
      title: 'Collaboration accepted',
      body: `"${invite.title}" with ${venueName} has been accepted.`,
      eventId: invite.experience_id,
    });
    return true;
  });
  if (!moved) throw new ApiError(409, 'This proposal is no longer pending');

  const [updated] = await query<InviteRow>(INVITE_BY_ID, [req.params.inviteId]);
  res.json({ invite: serializeInvite(updated!), status: 'accepted' });
});

// POST /api/hosts/:id/invites/:inviteId/decline, refuse a venue-sent invite.
router.post('/:id/invites/:inviteId/decline', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  if (req.userId !== hostId) throw forbidden('You can only answer your own invites');

  const body = respondSchema.parse(req.body ?? {});
  const [invite] = await query<InviteRow>(INVITE_BY_ID, [req.params.inviteId]);
  if (!invite || invite.host_id !== hostId) throw notFound('Invite');
  if (invite.proposed_by !== 'restaurant') {
    throw new ApiError(409, 'Only a proposal the venue sent can be declined here');
  }
  if (invite.status !== 'invited') {
    throw new ApiError(409, `This proposal is already ${invite.status}`);
  }

  const moved = await withTransaction(async (client) => {
    const result = await client.query(
      `UPDATE collaboration_invites
          SET status = 'declined', responded_at = now(), responded_by = $2::UUID,
              decline_reason = $3, updated_at = now()
        WHERE id = $1::UUID AND host_id = $2::UUID AND status = 'invited'
          AND proposed_by = 'restaurant'`,
      [req.params.inviteId, hostId, body.reason ?? ''],
    );
    if ((result.rowCount ?? 0) === 0) return false;

    const { rows: venueRows } = await client.query<{ name: string }>(
      'SELECT name FROM restaurants WHERE id = $1::UUID',
      [invite.restaurant_id],
    );
    const venueName = venueRows[0]?.name ?? 'your venue';
    await notifyVenue(client, invite.restaurant_id, {
      kind: 'collab',
      title: 'Collaboration declined',
      body: body.reason
        ? `"${invite.title}" was declined: ${body.reason}`
        : `"${invite.title}" with ${venueName} was declined.`,
      eventId: invite.experience_id,
    });
    return true;
  });
  if (!moved) throw new ApiError(409, 'This proposal is no longer pending');

  const [updated] = await query<InviteRow>(INVITE_BY_ID, [req.params.inviteId]);
  res.json({ invite: serializeInvite(updated!), status: 'declined' });
});

// ── Unified analytics ────────────────────────────────────────────────────────

/**
 * Parse ?period= into a Postgres interval literal, or null for 'all'.
 *
 * The interval is applied as a CLOSED window on `dinner_events.start_at`
 * (`>= now() - interval` AND `<= now()`), so `?period=7d` really means
 * "experiences that started in the last 7 days", which is the label the app
 * renders. Future events belong to the status snapshot, never to a past
 * window: previously the filter had no upper bound and every period returned
 * the same payload.
 */
function periodInterval(period: string): string | null {
  if (period === '7d') return '7 days';
  if (period === '30d') return '30 days';
  if (period === '90d') return '90 days';
  return null;
}

// GET /api/hosts/:id/analytics, unified analytics payload with period filter.
router.get('/:id/analytics', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const period: string = typeof req.query.period === 'string' ? req.query.period.toLowerCase().trim() : 'all';
  const dateFilter = periodInterval(period);
  const dateCondition = dateFilter
    ? `AND e.start_at >= now() - interval '${dateFilter}' AND e.start_at <= now()`
    : '';
  const pastDateCondition = dateFilter
    ? `AND e2.start_at >= now() - interval '${dateFilter}'`
    : '';
  const payoutDateCondition = dateFilter
    ? `AND p.payout_date >= now() - interval '${dateFilter}'`
    : '';

  // Event-scoped metrics, kept in their own single-table aggregate. Joining
  // `payouts` here multiplied SUM(e.seats_booked) by the number of payout rows
  // for the same event, so a host with two payouts on one experience saw its
  // reservations counted twice.
  const [eventMetrics] = await query<{
    total_events: number;
    total_bookings: number;
    total_seats_reserved: number;
    avg_fill_rate: number;
    total_views: number;
  }>(
    `SELECT
       COUNT(*)::int AS total_events,
       COALESCE(SUM(e.seats_booked), 0)::int AS total_seats_reserved,
       COALESCE(AVG(e.seats_booked::numeric / GREATEST(e.seats_total, 1)), 0)::float8 AS avg_fill_rate,
       COALESCE(SUM(e.views), 0)::int AS total_views,
       COALESCE(SUM((
         SELECT count(*) FROM bookings b
          WHERE b.event_id = e.id
            AND b.status IN ('confirmed','pending','completed')
       )), 0)::int AS total_bookings
     FROM dinner_events e
     WHERE e.host_id = $1::UUID ${dateCondition}`,
    [hostId],
  );

  // Money is only ever the payouts ledger. `dinner_events.price_per_seat` is
  // the venue's dining estimate, not money the host collected, so multiplying
  // it by reserved seats reported revenue that never existed.
  const [moneyMetrics] = await query<{
    gross_revenue: number;
    net_earnings: number;
    seats_sold: number;
  }>(
    `SELECT COALESCE(SUM(p.gross), 0)::float8 AS gross_revenue,
            COALESCE(SUM(p.gross - p.commission), 0)::float8 AS net_earnings,
            COALESCE(SUM(p.seats_sold), 0)::int AS seats_sold
       FROM payouts p
       JOIN dinner_events e ON e.id = p.event_id
      WHERE e.host_id = $1::UUID ${payoutDateCondition}`,
    [hostId],
  );

  // Status snapshot, deliberately not scoped to the period: "Upcoming" answers
  // "what is still ahead of me", which a past window cannot express. "Done" is
  // derived from start_at because no backend path ever writes
  // `dinner_events.status = 'completed'`, so counting that status was always 0.
  const [counts] = await query<{
    upcoming_count: number;
    completed_count: number;
  }>(
    `SELECT
       (SELECT count(*)::int FROM dinner_events e2
         WHERE e2.host_id = $1::UUID AND e2.start_at >= now()
           AND e2.status IN ('confirmed','live')) AS upcoming_count,
       (SELECT count(*)::int FROM dinner_events e2
         WHERE e2.host_id = $1::UUID AND e2.start_at < now()
           AND e2.status NOT IN ('cancelled','draft')
           ${pastDateCondition}) AS completed_count`,
    [hostId],
  );

  // Average rating from guest reviews of this host's experiences. `users.rating`
  // is a cached column no host workflow updates, so it would report 0 (or a
  // seeded figure) no matter how many reviews exist.
  const [ratingRow] = await query<{ avg: number | null; count: number }>(
    `SELECT AVG(r.rating)::float8 AS avg, count(*)::int AS count
       FROM reviews r
       JOIN dinner_events e ON e.id = r.event_id
      WHERE e.host_id = $1::UUID`,
    [hostId],
  );

  // Top experiences by reserved seats. Ordering by `seats_booked *
  // price_per_seat` ranked hosts by a revenue figure nobody was paid.
  const topEvents = await query<{
    event_id: string; title: string; cover_image: string;
    views: number; seats_booked: number;
    bookings: number; checked_in: number;
  }>(
    `SELECT e.id AS event_id, e.title, e.cover_image, e.views, e.seats_booked,
            (SELECT count(*)::int FROM bookings b
              WHERE b.event_id = e.id AND b.status IN ('confirmed','pending')) AS bookings,
            (SELECT count(*)::int FROM bookings b
              WHERE b.event_id = e.id AND b.checked_in) AS checked_in
     FROM dinner_events e
     WHERE e.host_id = $1::UUID ${dateCondition}
     ORDER BY e.seats_booked DESC, e.start_at DESC
     LIMIT 5`,
    [hostId],
  );

  // Trend data (reuse existing logic with period)
  const trendInterval = period === '7d' ? '1 day' : period === '30d' ? '1 week' : '1 month';
  const trendMonths = period === '7d' ? 7 : period === '30d' ? 5 : period === '90d' ? 3 : 6;
  const trendLabel = period === '7d' ? 'Dy' : period === '30d' ? 'Wk' : 'Mon';
  const trendRows = await query<TrendRow>(
    `SELECT to_char(m.month, '${trendLabel}') AS label,
            m.month,
            COALESCE(SUM(p.seats_sold), 0)::int AS seats,
            COALESCE(SUM(p.gross - p.commission), 0)::float8 AS revenue
     FROM generate_series(
            date_trunc('month', now()) - (${trendMonths} || ' months')::interval,
            date_trunc('month', now()),
            '${trendInterval}'::interval) AS m(month)
     LEFT JOIN payouts p
       ON date_trunc('month', p.payout_date) = m.month
      AND p.event_id IN (SELECT id FROM dinner_events WHERE host_id = $1::UUID)
     GROUP BY m.month
     ORDER BY m.month DESC`,
    [hostId],
  );

  // Per-event performance
  const perfRows = await query<PerformanceRow>(
    `SELECT e.id AS event_id, e.title, e.cover_image, e.views, e.seats_booked,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id
                AND b.status IN ('confirmed', 'pending'))::int  AS bookings,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id AND b.status = 'pending')::int AS pending,
            (SELECT count(*) FROM bookings b
              WHERE b.event_id = e.id AND b.checked_in)::int     AS checked_in
     FROM dinner_events e
     WHERE e.host_id = $1::UUID ${dateCondition}
     ORDER BY e.start_at DESC
     LIMIT 200`,
    [hostId],
  );

  const totalBookings = eventMetrics?.total_bookings ?? 0;
  const totalViews = eventMetrics?.total_views ?? 0;

  res.json({
    analytics: {
      totalEventsHosted: eventMetrics?.total_events ?? 0,
      totalBookings,
      // Reserved seats, not sales: a free RSVP holds a seat without money
      // changing hands, so "sold" would be a claim the data cannot support.
      totalSeatsReserved: eventMetrics?.total_seats_reserved ?? 0,
      grossRevenue: moneyMetrics?.gross_revenue ?? 0,
      hostNetEarnings: moneyMetrics?.net_earnings ?? 0,
      seatsSold: moneyMetrics?.seats_sold ?? 0,
      averageSeatFillRate: eventMetrics?.avg_fill_rate ?? 0,
      averageRating: Number(ratingRow?.avg ?? 0),
      reviewCount: ratingRow?.count ?? 0,
      upcomingCount: counts?.upcoming_count ?? 0,
      completedCount: counts?.completed_count ?? 0,
      totalViews,
      conversionRate: totalViews > 0 ? (totalBookings / totalViews) * 100 : 0,
    },
    topPerformingEvents: topEvents.map((e) => ({
      eventId: e.event_id,
      title: e.title,
      coverImage: e.cover_image,
      views: e.views,
      seatsBooked: e.seats_booked,
      bookings: e.bookings,
      checkedIn: e.checked_in,
    })),
    trend: trendRows.slice(0, trendMonths + 1).reverse()
      .map((r) => ({ label: r.label, seats: r.seats, revenue: r.revenue })),
    performance: perfRows.map((r) => ({
      eventId: r.event_id,
      title: r.title,
      coverImage: r.cover_image,
      views: r.views,
      seatsBooked: r.seats_booked,
      bookings: r.bookings,
      pending: r.pending,
      checkedIn: r.checked_in,
    })),
  });
});

// ── Partner discovery ─────────────────────────────────────────────────────────

// GET /api/hosts/:id/discover-partners, verified partner restaurants available
// for collaboration (excludes restaurants the host already has an active collab with).
router.get('/:id/discover-partners', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<{
    id: string; name: string; cover_image: string; neighborhood: string;
    city: string; rating: string; review_count: number; cuisines: string[];
  }>(
    `SELECT r.id, r.name, r.cover_image, r.neighborhood, r.city,
            r.rating, r.review_count, r.cuisines
     FROM restaurants r
     WHERE r.is_partner = true
       AND r.partnership_status = 'verified'
       AND r.id NOT IN (
         SELECT ci.restaurant_id FROM collaboration_invites ci
         WHERE ci.host_id = $1::UUID AND ci.status IN ('invited', 'accepted')
       )
     ORDER BY r.rating DESC, r.name ASC
     LIMIT 50`,
    [hostId],
  );

  res.json({
    partners: rows.map((r) => ({
      id: r.id,
      name: r.name,
      coverImage: r.cover_image,
      neighborhood: r.neighborhood,
      city: r.city,
      rating: Number(r.rating ?? 0),
      reviewCount: r.review_count ?? 0,
      cuisines: r.cuisines ?? [],
    })),
    count: rows.length,
  });
});

// ── Promotable events ─────────────────────────────────────────────────────────

// GET /api/hosts/:id/promotable-events, published upcoming events for promotion.
router.get('/:id/promotable-events', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  const rows = await query<{
    id: string; title: string; cover_image: string; start_at: Date;
    seats_total: number; seats_booked: number; price_per_seat: string;
    restaurant_name: string;
  }>(
    `SELECT e.id, e.title, e.cover_image, e.start_at,
            e.seats_total, e.seats_booked, e.price_per_seat,
            r.name AS restaurant_name
     FROM dinner_events e
     JOIN restaurants r ON r.id = e.restaurant_id
     WHERE e.host_id = $1::UUID
       AND e.status = 'confirmed'
       AND e.start_at > now()
     ORDER BY e.start_at ASC`,
    [hostId],
  );

  // Get the host's follower count from the follow graph itself. The cached
  // `users.followers_count` column was seeded with marketing-sized numbers
  // (128,400 against 20 real follow rows) and nothing refreshes it, so it
  // cannot back a "N followers will see this" promise.
  const [followerRow] = await query<{ followers: number }>(
    'SELECT count(*)::int AS followers FROM follows WHERE followee_id = $1::UUID',
    [hostId],
  );

  res.json({
    events: rows.map((e) => ({
      id: e.id,
      title: e.title,
      coverImage: e.cover_image,
      startAt: e.start_at,
      seatsTotal: e.seats_total,
      seatsBooked: e.seats_booked,
      seatsLeft: Math.max(0, e.seats_total - e.seats_booked),
      pricePerSeat: Number(e.price_per_seat),
      restaurantName: e.restaurant_name,
    })),
    followerCount: followerRow?.followers ?? 0,
    count: rows.length,
  });
});

// POST /api/hosts/events/:eventId/promote, record a promotion action.
router.post('/events/:eventId/promote', async (req, res) => {
  const eventId = req.params.eventId;
  const hostId = req.userId;

  const [event] = await query<{
    id: string; title: string; host_id: string; start_at: Date; status: string;
  }>(
    `SELECT id, title, host_id, start_at, status FROM dinner_events
     WHERE id = $1::UUID`,
    [eventId],
  );
  if (!event) throw notFound('Event');
  if (event.host_id !== hostId) throw forbidden('You can only promote your own events');
  if (event.status !== 'confirmed') throw new ApiError(400, 'Only confirmed events can be promoted');
  if (new Date(event.start_at) <= new Date()) throw new ApiError(400, 'Cannot promote past events');

  // Create activity entry visible in follower feeds.
  await query(
    `INSERT INTO activity (actor_id, kind, title, body, event_id, is_unread)
     VALUES ($1, 'promotion', $2, $3, $4, true)`,
    [
      hostId,
      `New experience: ${event.title}`,
      `Check out this upcoming dining experience!`,
      eventId,
    ],
  );

  res.status(201).json({ promoted: true, eventId });
});

// ── Simulated wallet ledger ──────────────────────────────────────────────────
type WalletSummaryRow = {
  earned: number;
  lifetime_net: number;
  pending_withdrawals: number;
  requested_total: number;
};

type WithdrawalRow = {
  id: string;
  amount: string;
  method: string;
  status: string;
  created_at: Date;
};

function serializeWithdrawal(w: WithdrawalRow) {
  return {
    id: w.id,
    amount: Number(w.amount),
    method: w.method,
    status: w.status,
    date: w.created_at,
  };
}

/**
 * Withdrawable balance for a host (the simulated ledger's one rule): lifetime
 * net earnings minus every withdrawal recorded to date. Because a withdrawal
 * row is the sole mechanism that moves money out of the wallet, its lifecycle
 * (`requested` → `completed`) never changes `available`, no double-counting.
 * `client` is optional: pass the transaction client when the read must be
 * locked and consistent with a write (withdrawal), otherwise the pool is used.
 */
async function availableBalance(
  hostId: string,
  client?: pg.PoolClient,
): Promise<number> {
  // Only count payouts with status = 'paid'. A 'scheduled' payout means the
  // event has not happened yet, the host has not earned that money, so it
  // must not be withdrawable. The settleDuePayouts janitor flips scheduled →
  // paid once the event's starts_at is in the past.
  const sql = `SELECT GREATEST(
              COALESCE((SELECT SUM(p.gross - p.commission) FROM payouts p
                JOIN dinner_events e ON e.id = p.event_id
               WHERE e.host_id = $1::UUID AND p.status = 'paid'), 0)
              -
              COALESCE((SELECT SUM(w.amount) FROM withdrawals w
               WHERE w.host_id = $1::UUID), 0),
              0)::float8 AS available`;
  const rows = client
    ? (await client.query<{ available: number }>(sql, [hostId])).rows
    : await query<{ available: number }>(sql, [hostId]);
  return rows[0]?.available ?? 0;
}

// GET /api/hosts/:id/wallet, balances plus the withdrawal history.
router.get('/:id/wallet', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  assertHostAccess(req.userId, req.userRole, hostId);

  // Phase 2a: settleDuePayouts removed, payouts table deleted.

  const [summary] = await query<WalletSummaryRow>(
    `SELECT
       COALESCE((SELECT SUM(p.gross - p.commission) FROM payouts p
         JOIN dinner_events e ON e.id = p.event_id
        WHERE e.host_id = $1::UUID AND p.status = 'paid'), 0)::float8  AS earned,
       COALESCE((SELECT SUM(p.gross - p.commission) FROM payouts p
         JOIN dinner_events e ON e.id = p.event_id
        WHERE e.host_id = $1::UUID), 0)::float8                        AS lifetime_net,
       COALESCE((SELECT SUM(w.amount) FROM withdrawals w
        WHERE w.host_id = $1::UUID AND w.status <> 'completed'), 0)::float8 AS pending_withdrawals,
       COALESCE((SELECT SUM(w.amount) FROM withdrawals w
        WHERE w.host_id = $1::UUID), 0)::float8                        AS requested_total`,
    [hostId],
  );

  const withdrawals = await query<WithdrawalRow>(
    `SELECT id, amount, method, status, created_at
     FROM withdrawals WHERE host_id = $1::UUID ORDER BY created_at DESC`,
    [hostId],
  );

  // `available` is what the host can withdraw right now: earned (paid-out)
  // minus already-requested withdrawals. `lifetimeNet` includes scheduled
  // payouts for future events and is shown for information only.
  const earned = summary?.earned ?? 0;
  const withdrawn = summary?.requested_total ?? 0;
  const lifetimeNet = summary?.lifetime_net ?? 0;

  res.json({
    hostId,
    available: Math.max(0, earned - withdrawn),
    lifetimeNet,
    lifetimeWithdrawn: withdrawn,
    pendingWithdrawals: summary?.pending_withdrawals ?? 0,
    withdrawals: withdrawals.map(serializeWithdrawal),
  });
});

const withdrawSchema = z.object({
  amount: z.coerce.number().min(0.01),
  method: z.string().trim().min(1).max(60),
});

// POST /api/hosts/:id/withdrawals, record a (simulated) payout request.
// Balance check and insert run in ONE transaction. Two locks make it safe:
//  1. `FOR UPDATE` on the host's user row serialises concurrent withdrawals,
//     the second request blocks until the first commits, then re-reads the true
//     balance (no double-spend).
//  2. A transaction-scoped advisory lock on the host id (the SAME key syncPayout
//     takes) keeps the balance read consistent against a concurrent earnings
//     accrual, even when no payout row exists yet to row-lock. Advisory locks
//     are the correct primitive here: `SELECT … FOR UPDATE` only supports
//     UPDATE/NO KEY UPDATE/SHARE/KEY SHARE strengths, and cannot cover the
//     "row not inserted yet" case anyway.
router.post('/:id/withdrawals', async (req, res) => {
  const hostId = req.params.id;
  await requireHost(hostId);
  // Withdrawals are self-only, even a partner admin cannot move funds.
  if (req.userId !== hostId) throw forbidden('You can only withdraw your own earnings');

  const input = withdrawSchema.parse(req.body ?? {});

  const created = await withTransaction(async (client) => {
    await client.query('SELECT id FROM users WHERE id = $1::UUID FOR UPDATE', [hostId]);
    // Match syncPayout's key so accrual and withdrawal never interleave.
    await client.query(
      'SELECT pg_advisory_xact_lock(hashtextextended($1::text, 7))',
      [hostId],
    );
    const available = await availableBalance(hostId, client);
    if (input.amount > available) {
      throw new ApiError(
        400,
        `Amount exceeds available balance ($${available.toFixed(2)}). This "wallet" only accrues `
          + 'from simulated bookings; no real money is ever paid out.',
      );
    }

    const { rows } = await client.query<WithdrawalRow>(
      `INSERT INTO withdrawals (host_id, amount, method, status)
       VALUES ($1::UUID, $2, $3, 'requested')
       RETURNING id, amount, method, status, created_at`,
      [hostId, input.amount.toFixed(2), input.method],
    );
    const row = rows[0];
    if (!row) throw new ApiError(500, 'Withdrawal insert failed');
    return row;
  });

  res.status(201).json({
    withdrawal: serializeWithdrawal(created),
    available: await availableBalance(hostId),
  });
});

export default router;
