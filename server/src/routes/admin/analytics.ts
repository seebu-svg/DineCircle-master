import { Router } from 'express';
import { query } from '../../db.js';
import { requireAdminConsole } from '../../access.js';
import { one } from '../../api.js';
import { adminPage, monthBuckets, toSeries } from './_shared.js';

/**
 * Basic Analytics.
 *
 * Only numbers the platform actually records appear here: QR scans, event
 * page views, reservations, bookings, deal redemptions and account counts.
 * Anything else an operator might expect (session duration, push delivery,
 * churn, ad attribution) has no source table on this deployment, so it is
 * returned in `notMeasured` and the console shows it as unmeasured rather than
 * inventing a figure.
 */
const router = Router();

router.get('/', async (req, res) => {
  requireAdminConsole(req);

  const buckets = monthBuckets(6);
  const since = `date_trunc('month', now()) - interval '5 months'`;

  const [scanSeries, viewSeries, reservationSeries, bookingSeries, redemptionSeries] =
    await Promise.all([
      query<{ bucket: string; value: number }>(
        `SELECT to_char(date_trunc('month', scanned_at), 'YYYY-MM') AS bucket,
                count(*)::int AS value
           FROM qr_scans WHERE scanned_at >= ${since} GROUP BY 1`,
      ),
      query<{ bucket: string; value: number }>(
        `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS bucket,
                COALESCE(sum(views), 0)::int AS value
           FROM dinner_events WHERE created_at >= ${since} GROUP BY 1`,
      ),
      query<{ bucket: string; value: number }>(
        `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS bucket,
                count(*)::int AS value
           FROM table_reservations WHERE created_at >= ${since} GROUP BY 1`,
      ),
      query<{ bucket: string; value: number }>(
        `SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS bucket,
                count(*)::int AS value
           FROM bookings WHERE created_at >= ${since} GROUP BY 1`,
      ),
      query<{ bucket: string; value: number }>(
        `SELECT to_char(date_trunc('month', d.created_at), 'YYYY-MM') AS bucket,
                COALESCE(sum(d.redemptions), 0)::int AS value
           FROM restaurant_deals d WHERE d.created_at >= ${since} GROUP BY 1`,
      ),
    ]);

  const [headline] = await query<Record<string, unknown>>(
    `SELECT
       (SELECT count(*)::int FROM users WHERE NOT is_deleted)                  AS accounts,
       (SELECT count(*)::int FROM users
         WHERE role = 'user' AND created_at >= now() - interval '30 days')     AS newCustomers30d,
       (SELECT count(*)::int FROM users
         WHERE (account_type = 'professional' OR role IN ('host','influencer'))
           AND created_at >= now() - interval '30 days')                       AS newHosts30d,
       (SELECT count(*)::int FROM restaurants)                                 AS venues,
       (SELECT count(*)::int FROM restaurants WHERE is_partner)                AS partnerVenues,
       (SELECT count(*)::int FROM qr_scans)                                    AS qrScans,
       (SELECT count(*)::int FROM qr_scans WHERE scanned_at >= now() - interval '7 days')
                                                                              AS qrScans7d,
       (SELECT COALESCE(sum(views), 0)::int FROM dinner_events)                AS eventViews,
       (SELECT count(*)::int FROM table_reservations)                          AS reservations,
       (SELECT count(*)::int FROM table_reservations
         WHERE status IN ('completed','seated'))                               AS fulfilledReservations,
       (SELECT count(*)::int FROM table_reservations WHERE status = 'no_show')  AS noShows,
       (SELECT count(*)::int FROM bookings)                                    AS bookings,
       (SELECT COALESCE(round(sum(total_amount), 2), 0)::numeric FROM bookings)
                                                                              AS bookedValue,
       (SELECT COALESCE(sum(redemptions), 0)::int FROM restaurant_deals)        AS redemptions,
       (SELECT count(*)::int FROM reviews)                                     AS reviews,
       (SELECT count(*)::int FROM reports)                                     AS reports,
       (SELECT count(*)::int FROM partner_payment_receipts
         WHERE status = 'verified')                                            AS verifiedPayments,
       (SELECT COALESCE(sum(amount_pkr), 0)::int FROM partner_payment_receipts
         WHERE status = 'verified')                                            AS collectedPkr`,
  );

  const topVenues = await query<Record<string, unknown>>(
    `SELECT r.id, r.name, r.city,
            (SELECT count(*)::int FROM qr_scans q WHERE q.restaurant_id = r.id) AS scans,
            (SELECT count(*)::int FROM table_reservations t
              WHERE t.restaurant_id = r.id)                                     AS reservations,
            (SELECT count(*)::int FROM reviews rv
              WHERE rv.restaurant_id = r.id)                                    AS reviews
       FROM restaurants r
      ORDER BY (SELECT count(*)::int FROM qr_scans q WHERE q.restaurant_id = r.id) DESC
       LIMIT 10`,
  );

  const topEvents = await query<Record<string, unknown>>(
    `SELECT e.id, e.title, e.views, e.seats_total, e.seats_booked, r.name AS venue_name
       FROM dinner_events e JOIN restaurants r ON r.id = e.restaurant_id
      ORDER BY e.views DESC, e.seats_booked DESC LIMIT 10`,
  );

  res.json(
    one('analytics', {
      generatedAt: new Date().toISOString(),
      headline,
      series: {
        qrScans: toSeries(scanSeries, buckets),
        eventViews: toSeries(viewSeries, buckets),
        reservations: toSeries(reservationSeries, buckets),
        bookings: toSeries(bookingSeries, buckets),
        dealRedemptions: toSeries(redemptionSeries, buckets),
      },
      rangeMonths: 6,
      page: adminPage(req).page,
      topVenues: topVenues.map((v) => ({
        id: v.id,
        name: v.name,
        city: v.city,
        scans: v.scans,
        reservations: v.reservations,
        reviews: v.reviews,
      })),
      topEvents: topEvents.map((e) => ({
        id: e.id,
        title: e.title,
        venueName: e.venue_name,
        views: e.views,
        seatsTotal: e.seats_total,
        seatsBooked: e.seats_booked,
      })),
      // Stated explicitly so the console can say "not measured" instead of
      // rendering a zero that reads like a real result.
      notMeasured: [
        'Session duration',
        'Retention and churn',
        'Push notification delivery',
        'Marketing attribution',
        'Average order value per partner',
        'Refund rate',
      ],
    }),
  );
});

export default router;
