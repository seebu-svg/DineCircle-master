-- ─────────────────────────────────────────────────────────────────────────────
-- Promote 8 of the 11 existing Karachi demo venues to verified-partner status.
--
-- Verified (8): Kolachi, Kababjees, Cafe Aylanto, Xander's, Okra,
--               Espresso Shahbaz DHA, Bar B Q Tonight, Cafe Flo
-- Pending  (3): Butlers Chocolate Café, Café Zouk, Esquires Coffee
--
-- Idempotent: safe to re-run.  Does NOT delete any existing menu, deal,
-- table, event or branch data.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ── 1.  Mark the eight venues as verified partners ──────────────────────────

UPDATE restaurants
SET partnership_status = 'verified',
    is_partner         = true,
    verified_at        = NOW() - INTERVAL '30 days',
    partner_perk       = CASE name
      WHEN 'Kolachi Restaurant'   THEN 'Complimentary welcome chai for DineCircle guests'
      WHEN 'Kababjees'            THEN 'Reserved riverside table for DineCircle bookings'
      WHEN 'Cafe Aylanto'         THEN 'Complimentary dessert on DineCircle tables'
      WHEN 'Xander''s'            THEN 'Ten percent off the a-la-carte bill for DineCircle guests'
      WHEN 'Okra'                 THEN 'Kitchen tour with the head chef for DineCircle tables'
      WHEN 'Espresso Shahbaz DHA' THEN 'Free upgrade to large coffee for DineCircle guests'
      WHEN 'Bar B Q Tonight'      THEN 'Reserved family section held for DineCircle tables'
      WHEN 'Cafe Flo'             THEN 'Complimentary pastry with every DineCircle booking'
    END
WHERE name IN (
  'Kolachi Restaurant', 'Kababjees', 'Cafe Aylanto', 'Xander''s',
  'Okra', 'Espresso Shahbaz DHA', 'Bar B Q Tonight', 'Cafe Flo'
);

-- ── 2.  Bump profile_completion for verified venues (they are fully set up) ─

UPDATE restaurants
SET profile_completion = 100
WHERE partnership_status = 'verified' AND is_demo = true;

-- ── 3.  Partner verification requests — approved for the eight ──────────────

INSERT INTO partner_verification_requests
  (id, restaurant_id, requested_by, status, note, reviewer_note, reviewed_by, reviewed_at)
SELECT
  gen_random_uuid(),
  r.id,
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,   -- Karachi Partners Desk
  'approved',
  'Venue onboarded as a DineCircle demo partner. Verification approved by seed script.',
  'Approved as a verified demo partner by the platform admin.',
  '55555555-5555-5555-5555-555555555555'::uuid,    -- Dana Ops (super_admin)
  NOW() - INTERVAL '25 days'
FROM restaurants r
WHERE r.name IN (
  'Kolachi Restaurant', 'Kababjees', 'Cafe Aylanto', 'Xander''s',
  'Okra', 'Espresso Shahbaz DHA', 'Bar B Q Tonight', 'Cafe Flo'
)
AND NOT EXISTS (
  SELECT 1 FROM partner_verification_requests pvr WHERE pvr.restaurant_id = r.id
);

-- ── 4.  Pending verification requests for the three unverified candidates ───

INSERT INTO partner_verification_requests
  (id, restaurant_id, requested_by, status, note, reviewer_note, reviewed_by, reviewed_at)
SELECT
  gen_random_uuid(),
  r.id,
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
  'pending',
  'Desk enquiry: the venue has been contacted; partnership approval is pending.',
  '',
  NULL,
  NULL
FROM restaurants r
WHERE r.name IN (
  'Butlers Chocolate Café', 'Café Zouk', 'Esquires Coffee'
)
AND NOT EXISTS (
  SELECT 1 FROM partner_verification_requests pvr WHERE pvr.restaurant_id = r.id
);

-- ── 5.  Restaurant staff links — owner role for each verified venue ─────────

INSERT INTO restaurant_staff (user_id, restaurant_id, role, status)
SELECT
  'aaaaaaaa-0000-4000-8000-000000000001'::uuid,
  r.id,
  'owner',
  'active'
FROM restaurants r
WHERE r.partnership_status = 'verified'
  AND r.is_demo = true
  AND NOT EXISTS (
    SELECT 1 FROM restaurant_staff rs
    WHERE rs.restaurant_id = r.id AND rs.user_id = 'aaaaaaaa-0000-4000-8000-000000000001'::uuid
  );

-- ── 6.  Activate subscriptions for the three unverified venues too ──────────
--     (they already have rows from the karachi seed; just ensure status)

UPDATE partner_subscriptions
SET status = 'active', plan = 'monthly'
WHERE restaurant_id IN (
  SELECT id FROM restaurants
  WHERE name IN ('Butlers Chocolate Café', 'Café Zouk', 'Esquires Coffee')
);

COMMIT;

-- ── Summary query ───────────────────────────────────────────────────────────
SELECT name, neighborhood, partnership_status, is_partner, partner_perk,
       accepting_bookings, is_demo
FROM restaurants
ORDER BY partnership_status DESC, name;
