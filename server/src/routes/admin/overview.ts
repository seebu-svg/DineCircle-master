import { Router } from 'express';
import { query } from '../../db.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { adminPage, monthBuckets, toSeries } from './_shared.js';

/**
 * Dashboard feeds: headline numbers, the six sidebar counters, and one activity
 * stream. Everything here is a read over rows the platform already writes, so
 * no KPI on this screen is invented. Where a metric has no recorded source it is
 * left out rather than estimated, and the console says so.
 */
const router = Router();

router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const page = adminPage(req);

  const [totals] = await query<Record<string, number>>(
    `SELECT
       (SELECT count(*)::int FROM users WHERE role = 'user' AND NOT is_deleted)  AS customers,
       (SELECT count(*)::int FROM users
         WHERE account_type = 'professional' OR role IN ('host','influencer'))   AS hosts,
       (SELECT count(*)::int FROM restaurants)                                   AS venues,
       (SELECT count(*)::int FROM restaurants WHERE is_partner)                  AS partners,
       (SELECT count(*)::int FROM restaurants WHERE partnership_status = 'verified')
                                                                                 AS verifiedVenues,
       (SELECT count(*)::int FROM partner_subscriptions WHERE status = 'active') AS activeSubscriptions,
       (SELECT count(*)::int FROM dinner_events
         WHERE status IN ('confirmed','live'))                                   AS liveExperiences,
       (SELECT count(*)::int FROM table_reservations
         WHERE status IN ('pending','confirmed','seated'))                       AS openReservations,
       (SELECT count(*)::int FROM bookings WHERE status = 'confirmed')           AS eventBookings,
       (SELECT count(*)::int FROM qr_scans)                                      AS qrScans`,
  );

  const buckets = monthBuckets(6);
  const sinceSql = `date_trunc('month', now()) - interval '5 months'`;

  const [revenueRows, partnerRows, reservationRows, experienceRows] = await Promise.all([
    // Verified receipts are the only money the platform can actually point at:
    // payments arrive by bank transfer, JazzCash or Easypaisa and an admin
    // confirms them, so revenue is booked at verification time, not upload time.
    query<{ bucket: string; value: number }>(
      `SELECT to_char(date_trunc('month', verified_at), 'YYYY-MM') AS bucket,
              COALESCE(sum(amount_pkr), 0)::int                   AS value
         FROM partner_payment_receipts
        WHERE status = 'verified' AND verified_at >= ${sinceSql}
        GROUP BY 1`,
    ),
    query<{ bucket: string; value: number }>(
      `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS bucket,
              count(*)::int                                      AS value
         FROM restaurants
        WHERE created_at >= ${sinceSql}
        GROUP BY 1`,
    ),
    query<{ bucket: string; value: number }>(
      `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS bucket,
              count(*)::int                                      AS value
         FROM table_reservations
        WHERE created_at >= ${sinceSql}
        GROUP BY 1`,
    ),
    query<{ bucket: string; value: number }>(
      `SELECT to_char(date_trunc('month', b.created_at), 'YYYY-MM') AS bucket,
              COALESCE(sum(b.seats), 0)::int                        AS value
         FROM bookings b
         JOIN dinner_events e ON e.id = b.event_id
        WHERE b.created_at >= ${sinceSql}
        GROUP BY 1`,
    ),
  ]);

  res.json(
    one('overview', {
      generatedAt: new Date().toISOString(),
      totals: {
        customers: totals?.customers ?? 0,
        hosts: totals?.hosts ?? 0,
        venues: totals?.venues ?? 0,
        partners: totals?.partners ?? 0,
        verifiedVenues: totals?.verifiedVenues ?? 0,
        activeSubscriptions: totals?.activeSubscriptions ?? 0,
        liveExperiences: totals?.liveExperiences ?? 0,
        openReservations: totals?.openReservations ?? 0,
        eventBookings: totals?.eventBookings ?? 0,
        qrScans: totals?.qrScans ?? 0,
      },
      revenue: toSeries(revenueRows, buckets),
      partnerGrowth: toSeries(partnerRows, buckets),
      reservations: toSeries(reservationRows, buckets),
      experienceCovers: toSeries(experienceRows, buckets),
      // The console paginates nothing here, but the meta block keeps the shape
      // of every other admin response uniform for the client.
      rangeMonths: 6,
      page: page.page,
    }),
  );
});

/**
 * The six sidebar counters. Kept on their own endpoint because the console
 * refreshes them after every mutation, and one cheap query set beats refetching
 * six full lists.
 */
router.get('/badges', async (req, res) => {
  requireAdminConsole(req);
  const [counts] = await query<Record<string, number>>(
    `SELECT
       (SELECT count(*)::int FROM partner_verification_requests
         WHERE status = 'pending')                                  AS pendingApplications,
       (SELECT count(*)::int FROM partner_payment_receipts
         WHERE status = 'awaiting_verification')                    AS pendingReceipts,
       (SELECT count(*)::int FROM reports
         WHERE status IN ('pending','reviewing'))                   AS openReports,
       (SELECT count(*)::int FROM dinner_events
         WHERE status = 'requested')                                AS pendingExperiences,
       (SELECT count(*)::int FROM restaurant_deals
         WHERE moderation_status = 'flagged')                       AS flaggedDeals,
       (SELECT count(*)::int FROM users u
         WHERE (u.account_type = 'professional' OR u.role IN ('host','influencer'))
           AND EXISTS (SELECT 1 FROM reports r
                        WHERE r.target_type = 'user' AND r.target_id = u.id
                          AND r.status IN ('pending','reviewing'))) AS flaggedHosts,
       (SELECT count(*)::int FROM reviews
         WHERE moderation_status = 'flagged')                       AS flaggedContent,
       (SELECT count(*)::int FROM restaurants
         WHERE moderation_status = 'suspended')                     AS suspendedVenues`,
  );
  res.json({ data: { badges: counts ?? {} } });
});

/**
 * Latest operator-visible activity: the audit trail the middleware writes for
 * every mutating request, plus the two queues a human actually waits on
 * (applications submitted and receipts uploaded).
 */
router.get('/activity', async (req, res) => {
  requireAdminConsole(req);
  const page = adminPage(req);

  const rows = await query<Record<string, unknown>>(
    `SELECT * FROM (
       SELECT 'audit' AS source, a.id::text AS id, a.action AS title,
              COALESCE(a.resource, '') AS subtitle, a.created_at AS occurred_at,
              NULL::text AS status, u.name AS actor
         FROM audit_log a
         LEFT JOIN users u ON u.id = a.user_id
        UNION ALL
       SELECT 'application', v.id::text, r.name, 'partner application submitted',
              v.created_at, v.status, NULL
         FROM partner_verification_requests v
         JOIN restaurants r ON r.id = v.restaurant_id
        UNION ALL
       SELECT 'receipt', p.id::text, r.name,
              'payment receipt ' || replace(p.status, '_', ' '),
              p.created_at, p.status, NULL
         FROM partner_payment_receipts p
         JOIN restaurants r ON r.id = p.restaurant_id
     ) feed
     ORDER BY occurred_at DESC
     LIMIT $1 OFFSET $2`,
    [page.limit, page.offset],
  );

  res.json({
    data: {
      activity: rows.map((row) => ({
        source: row.source,
        id: row.id,
        title: row.title,
        subtitle: row.subtitle,
        occurredAt: row.occurred_at,
        status: row.status,
        actor: row.actor,
      })),
    },
    meta: { page: page.page, limit: page.limit, total: rows.length },
  });
});

export default router;
