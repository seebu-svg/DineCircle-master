import { withTransaction } from './db.js';
import { ApiError, notFound } from './context.js';

/**
 * The single implementation of a platform-admin verification decision.
 *
 * Two callers reach the same rule from different surfaces: the Partner App
 * queue (`POST /api/partner/verification/requests/:id/review`) and the admin
 * console (`POST /api/admin/applications/:id/review`, plus batch review). Both
 * must flip the venue and tell the desk exactly the same way, so the
 * transaction body lives here and the routes stay thin.
 *
 * Approval is what sets `partnership_status='verified'` + `is_partner`, the two
 * flags every downstream gate (host publishing, deals, payouts) reads. A
 * rejection that only landed in an admin queue would leave the Partner App
 * showing a silent spinner, so the venue notification is part of the
 * transaction, not a follow-up call.
 */
export type ReviewDecision = 'approved' | 'rejected';

export type ReviewResult = {
  requestId: string;
  status: ReviewDecision;
  restaurantId: string;
  venueName: string;
};

export async function reviewVerificationRequest(input: {
  requestId: string;
  decision: ReviewDecision;
  reviewerNote?: string;
  actorId: string;
}): Promise<ReviewResult> {
  const note = (input.reviewerNote ?? '').slice(0, 1000);

  return withTransaction(async (client) => {
    // Row lock so two admins reviewing the same application at once cannot
    // both pass the `pending` check and double-write the venue flip.
    const { rows } = await client.query<{
      id: string;
      restaurant_id: string;
      status: string;
    }>(
      `SELECT id, restaurant_id, status FROM partner_verification_requests
        WHERE id = $1::UUID FOR UPDATE`,
      [input.requestId],
    );
    const request = rows[0];
    if (!request) throw notFound('Verification request');
    if (request.status !== 'pending') {
      throw new ApiError(409, `This request was already ${request.status}`);
    }

    await client.query(
      `UPDATE partner_verification_requests
          SET status = $2, reviewer_note = $3, reviewed_by = $4::UUID,
              reviewed_at = now()
        WHERE id = $1::UUID`,
      [request.id, input.decision, note, input.actorId],
    );

    const approved = input.decision === 'approved';
    const { rows: venues } = await client.query<{
      id: string;
      name: string;
      owner_id: string | null;
    }>(
      `UPDATE restaurants
          SET partnership_status = $2,
              is_partner = $3,
              verified_at = CASE WHEN $3 THEN now() ELSE verified_at END,
              rejection_note = CASE WHEN $3 THEN '' ELSE $4 END
        WHERE id = $1::UUID
        RETURNING id, name, owner_id`,
      [request.restaurant_id, approved ? 'verified' : 'rejected', approved, note],
    );

    const venue = venues[0];
    await client.query(
      `INSERT INTO notifications (restaurant_id, title, body, category, read)
       VALUES ($1::UUID, $2, $3, 'verification', false)`,
      [
        venue?.id ?? request.restaurant_id,
        approved ? 'Venue verified' : 'Verification needs work',
        approved
          ? 'Your venue is verified. You can now accept host event requests, publish deals and receive payouts.'
          : `Verification was declined. ${note}`.trim(),
      ],
    );

    return {
      requestId: request.id,
      status: input.decision,
      restaurantId: request.restaurant_id,
      venueName: venue?.name ?? '',
    };
  });
}
