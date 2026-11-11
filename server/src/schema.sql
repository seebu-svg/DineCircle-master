-- DineCircle API schema: SINGLE SOURCE OF TRUTH, re-runnable (idempotent).
--
-- This schema is derived from the actual route contract in src/routes/*.ts:
--   * Every primary key is `uuid` with a server-side default (the INSERTs in
--     the routes omit `id`, and scalar id params are cast `$n::UUID`).
--   * `dinner_events.attendee_ids` is `text[]` (ids are appended/compared as
--     text, e.g. `$3 = ANY(attendee_ids)` / `array_append(attendee_ids, $3)`).
--   * `restaurants` carries the full partner profile (owner_id, tagline,
--     accepting_bookings, profile_completion, amenities, opening_hours jsonb…).
--   * Enum-ish columns are `text` + CHECK so the API returns the same
--     identifiers the Flutter app already uses.
--   * Money is `numeric(10,2)`; ratings `numeric(3,2)`.

-- users ───────────────────────────────────────────────────────────────────────
-- Profile-photo bytes live in user_avatars (declared after the users block
-- below so the FK target exists on a fresh database).
-- Sign-in finds-or-creates by phone; INSERTs omit id/role/counts → all defaulted.
CREATE TABLE IF NOT EXISTS users (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name             text NOT NULL,
  handle           text NOT NULL UNIQUE,
  phone            text UNIQUE,
  city             text NOT NULL DEFAULT '',
  bio              text NOT NULL DEFAULT '',
  role             text NOT NULL DEFAULT 'user'
                   CHECK (role IN ('user','host','influencer','partner_admin','super_admin')),
  followers_count  integer NOT NULL DEFAULT 0,
  following_count  integer NOT NULL DEFAULT 0,
  dinners_hosted   integer NOT NULL DEFAULT 0,
  dinners_joined   integer NOT NULL DEFAULT 0,
  rating           numeric(3,2) NOT NULL DEFAULT 0,
  review_count     integer NOT NULL DEFAULT 0,
  avatar_url       text,
  badges           text[] NOT NULL DEFAULT '{}',
  tastes          text[] NOT NULL DEFAULT '{}',
  accent_hex       text,
  joined_year      integer NOT NULL DEFAULT 2024,
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Email + password auth (primary first-launch path). Idempotent so re-running
-- the schema on an existing database backfills the columns. Both are nullable:
-- phone-only accounts (legacy) have no email, and email accounts may skip OTP.
ALTER TABLE users ADD COLUMN IF NOT EXISTS email         text UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS password_hash text;

-- Growth ladder on ONE account: diner ('user') → host → influencer. The
-- influencer rung widens the role CHECK; re-running this schema on an existing
-- database swaps the constraint in place (no data migration, no rows use the
-- new value yet). partners/admins sit outside the ladder.
-- Partner app: 'restaurant_owner' / 'restaurant_staff' are venue-side roles.
-- They are NOT publish-capable (hasHostCapabilities leaves them out) and are
-- scoped to venues through restaurant_staff below, never to the whole platform.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users ADD CONSTRAINT users_role_check CHECK (
  role IN ('user','host','influencer','partner_admin','super_admin',
           'restaurant_owner','restaurant_staff'));

-- Karachi test environment (seed.ts): creators carry their public Instagram
-- handle for discovery testing and every seeded account is a test record
-- (`is_demo`). The matching `is_demo`/`partnership_status` columns on
-- restaurants and dinner_events live in those tables' own sections below,
-- they MUST be added after the tables exist so a fresh database applies
-- cleanly (an ALTER before its CREATE aborts the whole migration).
ALTER TABLE users ADD COLUMN IF NOT EXISTS instagram     text NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_demo       boolean NOT NULL DEFAULT false;

-- Account & Settings (P1): privacy toggles, food preferences, home locale and
-- a soft-delete marker. All defaulted so existing accounts keep current
-- behaviour; `is_deleted` is FALSE until an account is anonymised in place.
ALTER TABLE users ADD COLUMN IF NOT EXISTS show_follow_list        boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS show_activity           boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS dm_from_followers_only  boolean NOT NULL DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS allow_tagging           boolean NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN IF NOT EXISTS dietary                 text[]   NOT NULL DEFAULT '{}';
ALTER TABLE users ADD COLUMN IF NOT EXISTS allergies               text[]   NOT NULL DEFAULT '{}';
ALTER TABLE users ADD COLUMN IF NOT EXISTS home_area               text     NOT NULL DEFAULT '';
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_deleted              boolean  NOT NULL DEFAULT false;

-- Account types: ONE account, two modes (Instagram-style).
--   * 'personal'    , private diner. Default for every new signup; may
--                      discover, reserve and join, but has no Host Studio.
--   * 'professional', public host profile + Host Studio (publish experiences).
--
-- `role` keeps its own meaning (ladder rung + partner/admin privileges) and is
-- still what the Partner App and RBAC read. `account_type` is the ONLY gate for
-- the customer Host Studio, so switching back to Personal never destroys the
-- role, badges or follower history earned as a host.
--
-- `professional_since` is set the first time an account goes Professional and
-- deliberately survives a downgrade: it is both the "Professional since" line
-- and the marker that makes the backfill below a once-only operation.
ALTER TABLE users ADD COLUMN IF NOT EXISTS account_type         text    NOT NULL DEFAULT 'personal';
ALTER TABLE users ADD COLUMN IF NOT EXISTS professional_since   timestamptz;
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_account_type_check;
ALTER TABLE users ADD CONSTRAINT users_account_type_check
  CHECK (account_type IN ('personal','professional'));

-- Existing/seed hosts are already publishing through `role`, so they are
-- grandfathered into Professional. Accounts that have ever been promoted keep
-- their `professional_since`, so a deliberate switch back to Personal is never
-- silently reverted by a later run of this schema.
UPDATE users SET account_type = 'professional', professional_since = now()
 WHERE account_type = 'personal' AND professional_since IS NULL
   AND role IN ('host','influencer','partner_admin','super_admin');

-- user_avatars ──────────────────────────────────────────────────────────────
-- Profile photos are stored here rather than in an object store: the module
-- ships complete without depending on S3/GCS credentials. `users.avatar_url`
-- keeps pointing at whatever the client renders, a bundled asset path, an
-- external https URL, or the relative path `/public/avatars/<id>?v=<epoch>`
-- this table's public route serves (relative to the API base, so the app can
-- resolve it against API_BASE_URL).
--
-- One row per user: the newest upload replaces the previous photo, and the
-- cascade means an account row can never outlive its own avatar. The size and
-- type columns are the server's own record of what it accepted; the bytes are
-- always what was validated at upload time.
CREATE TABLE IF NOT EXISTS user_avatars (
  user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  content_type text NOT NULL
               CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
  byte_size    integer NOT NULL CHECK (byte_size > 0 AND byte_size <= 524288),
  bytes        bytea NOT NULL,
  updated_at   timestamptz NOT NULL DEFAULT now()
);

-- restaurants ─────────────────────────────────────────────────────────────────
-- owner_id is the partner_admin user who manages the venue (NULL = unowned).
CREATE TABLE IF NOT EXISTS restaurants (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id           uuid REFERENCES users(id) ON DELETE SET NULL,
  name               text NOT NULL,
  tagline            text NOT NULL DEFAULT '',
  about              text NOT NULL DEFAULT '',
  cuisines           text[] NOT NULL DEFAULT '{}',
  neighborhood       text NOT NULL DEFAULT '',
  address            text NOT NULL DEFAULT '',
  city               text NOT NULL DEFAULT '',
  phone              text NOT NULL DEFAULT '',
  email              text NOT NULL DEFAULT '',
  website            text NOT NULL DEFAULT '',
  instagram          text NOT NULL DEFAULT '',
  price_range        text NOT NULL DEFAULT '$$',
  rating             numeric(3,2) NOT NULL DEFAULT 0,
  review_count       integer NOT NULL DEFAULT 0,
  seats              integer NOT NULL DEFAULT 0,
  tables_count       integer NOT NULL DEFAULT 0,
  since              text NOT NULL DEFAULT '',
  owner_name         text NOT NULL DEFAULT '',
  amenities          text[] NOT NULL DEFAULT '{}',
  opening_hours      jsonb NOT NULL DEFAULT '{}'::jsonb,
  profile_completion integer NOT NULL DEFAULT 0,
  accepting_bookings boolean NOT NULL DEFAULT true,
  dine_circle_plus   boolean NOT NULL DEFAULT false,
  cover_image        text NOT NULL DEFAULT '',
  gallery            text[] NOT NULL DEFAULT '{}',
  tags               text[] NOT NULL DEFAULT '{}',
  is_partner         boolean NOT NULL DEFAULT false,
  partner_perk       text,
  created_at         timestamptz NOT NULL DEFAULT now()
);

-- Seeded venues enter the partner pipeline as `unverified` test records
-- (relocated from the users block above so a fresh DB creates the table
-- before these columns are added).
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS partnership_status text NOT NULL DEFAULT 'unverified';

-- Map support (WS-A): real venue coordinates for markers and `nearby`
-- queries. Nullable, a venue without coords simply stays off the map.
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS latitude  double precision;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS longitude double precision;

-- Restaurant branding and social media (P2): logo separate from cover image,
-- plus Facebook and Twitter profiles for partner venues.
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS logo     text NOT NULL DEFAULT '';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS facebook text NOT NULL DEFAULT '';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS twitter  text NOT NULL DEFAULT '';

-- venue_images ──────────────────────────────────────────────────────────────
-- Partner-uploaded venue photos (logo, cover, gallery, dish, deal banner). Same
-- reasoning as user_avatars above: the module ships without S3/GCS credentials,
-- and the deployment target's disk is ephemeral, so the database is the only
-- durable home for the bytes.
--
-- Unlike user_avatars this is one row per UPLOAD, not one per venue: a venue has
-- many photos. Each row owns an immutable URL, `/public/venue-images/<id>`, so
-- replacing a photo writes a new row and repoints whichever text column
-- references it (`restaurants.logo`, `gallery[]`, `restaurant_menu_items.
-- photo_url`, `restaurant_deals.image_url`). Superseded rows are orphaned but
-- harmless, and the delete route removes one explicitly.
CREATE TABLE IF NOT EXISTS venue_images (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  kind          text NOT NULL DEFAULT 'general'
                CHECK (kind IN ('general','logo','cover','gallery','menu_item','deal')),
  content_type  text NOT NULL
                CHECK (content_type IN ('image/jpeg','image/png','image/webp')),
  byte_size     integer NOT NULL CHECK (byte_size > 0 AND byte_size <= 524288),
  bytes         bytea NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS venue_images_restaurant_idx
  ON venue_images (restaurant_id, created_at DESC);

-- dinner_events ───────────────────────────────────────────────────────────────
-- Host publish (events.ts) omits id + status → defaults. Partner events
-- (partner.ts) supply end_at + an explicit lifecycle `status`.
CREATE TABLE IF NOT EXISTS dinner_events (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title            text NOT NULL,
  tagline          text NOT NULL DEFAULT '',
  description      text NOT NULL DEFAULT '',
  host_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id    uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  cover_image      text NOT NULL DEFAULT '',
  gallery          text[] NOT NULL DEFAULT '{}',
  start_at         timestamptz NOT NULL,
  end_at           timestamptz,
  duration_minutes integer NOT NULL DEFAULT 150,
  seats_total      integer NOT NULL CHECK (seats_total >= 0),
  seats_booked     integer NOT NULL DEFAULT 0 CHECK (seats_booked >= 0),
  price_per_seat   numeric(10,2) NOT NULL CHECK (price_per_seat >= 0),
  type             text NOT NULL DEFAULT 'dinner'
                   CHECK (type IN ('dinner','tasting','supperClub','brunch','workshop','festival')),
  audience         text NOT NULL DEFAULT 'public'
                   CHECK (audience IN ('public','followers','friends','inviteOnly')),
  menu_style       text NOT NULL DEFAULT 'familyStyle'
                   CHECK (menu_style IN ('setMenu','tastingMenu','familyStyle','sharing','buffet')),
  included         text[] NOT NULL DEFAULT '{}',
  tags             text[] NOT NULL DEFAULT '{}',
  is_featured      boolean NOT NULL DEFAULT false,
  host_note        text NOT NULL DEFAULT '',
  language         text NOT NULL DEFAULT 'English',
  dress_code       text NOT NULL DEFAULT 'Smart casual',
  cancellation     text NOT NULL DEFAULT 'Free cancellation up to 48 hours before',
  attendee_ids     text[] NOT NULL DEFAULT '{}',
  status           text NOT NULL DEFAULT 'confirmed'
                   CHECK (status IN ('draft','requested','confirmed','live','completed','declined','cancelled')),
  created_at       timestamptz NOT NULL DEFAULT now()
);

-- Host-studio analytics + approval gating (Phase 4). Idempotent so re-running
-- the schema on an existing database backfills the columns.
--   * `views` is bumped inside GET /events/:id for non-host viewers.
--   * `requires_approval` routes new bookings to a `pending` status for the
--     host to approve/decline instead of auto-confirming.
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS views integer NOT NULL DEFAULT 0;
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS requires_approval boolean NOT NULL DEFAULT false;
-- Seeded events are test records (relocated from the users block so a fresh DB
-- creates dinner_events before this column is added).
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS is_demo boolean NOT NULL DEFAULT false;
-- Phase 1e: collaborator_ids lets a venue-created experience tag host/influencer
-- collaborators. Empty array = no collaborators (venue owns it solo).
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS collaborator_ids uuid[] NOT NULL DEFAULT '{}';
-- Proposal-workflow repair: an experience is never destroyed any more, so the
-- row has to carry the cancellation and re-approval trail itself.
--   * `cancelled_at/by/reason` record a soft cancel (who ended it and why);
--     the row stays queryable for guests and for audit.
--   * `approval_stale_at` is stamped when a host edits an already-decided
--     experience, which reopens it as `requested`. The venue inbox uses it to
--     tell "first approval" apart from "re-approval after a change".
--   * `updated_at` keeps the last content change visible to both sides.
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS approval_stale_at timestamptz;
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS cancelled_by uuid REFERENCES users(id);
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS cancellation_reason text NOT NULL DEFAULT '';

-- menu_items ──────────────────────────────────────────────────────────────────
-- events.ts INSERT omits id → defaulted; column is `signature` (not is_signature).
CREATE TABLE IF NOT EXISTS menu_items (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid NOT NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  position    integer NOT NULL DEFAULT 0,
  name        text NOT NULL,
  description text NOT NULL DEFAULT '',
  pairing     text,
  signature   boolean NOT NULL DEFAULT false
);

-- bookings ────────────────────────────────────────────────────────────────────
-- `user_id` (the guest), `total_amount`, `payment_status` and `checked_in_at`
-- are all required by the booking + partner routes.
CREATE TABLE IF NOT EXISTS bookings (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id       uuid NOT NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  seats          integer NOT NULL CHECK (seats > 0),
  price_per_seat numeric(10,2) NOT NULL,
  total_amount   numeric(10,2) NOT NULL DEFAULT 0,
  reference      text NOT NULL UNIQUE,
  payment_label  text NOT NULL DEFAULT '',
  payment_status text NOT NULL DEFAULT 'paid'
                 CHECK (payment_status IN ('unpaid','pending_payment','authorized','paid','refunded','failed')),
  status         text NOT NULL DEFAULT 'confirmed'
                 CHECK (status IN ('confirmed','pending','completed','cancelled')),
  checked_in     boolean NOT NULL DEFAULT false,
  checked_in_at  timestamptz,
  -- Contact the guest actually typed at checkout, so the host has a real way to
  -- reach the diner and the confirmation screen never shows invented details.
  guest_name     text,
  guest_email    text,
  guest_phone    text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Added after the original table shipped; repeated here so existing databases
-- pick the columns up on the next `npm run db:schema`.
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS guest_name text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS guest_email text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS guest_phone text;

-- Stripe payments (Phase 4): the booking row now points at a real
-- PaymentIntent when the Stripe gateway is active. `pending_payment` joins
-- the payment ladder, the seat is held while the guest confirms the card;
-- the webhook flips it to `paid` (or releases it to `failed`). Re-running
-- the schema swaps the CHECK in place for pre-Stripe databases (no rows use
-- the new value yet, same pattern as users_role_check above).
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS stripe_payment_intent_id text UNIQUE;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS stripe_amount_cents integer;
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_payment_status_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_payment_status_check CHECK (
  payment_status IN ('unpaid','pending_payment','authorized','paid','refunded','failed'));

-- refunds (BUG-02 refund bookkeeping ledger) ────────────────────────────────
-- One immutable row per refund decision: guest cancellations record the full
-- captured amount as `refunded`; host declines only reverse an uncaptured
-- `authorized` hold, so they book $0 as `released` (nothing was ever charged).
-- `gateway_status = 'simulated'` is the honest marker that no payment provider
-- has confirmed any of these movements, a real gateway integration must write
-- `pending_gateway` here and only flip the row to `confirmed` on webhook.
CREATE TABLE IF NOT EXISTS refunds (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid NOT NULL REFERENCES bookings(id) ON DELETE CASCADE,
  event_id       uuid NOT NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  guest_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount         numeric(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  reason         text NOT NULL
                 CHECK (reason IN ('guest_cancel', 'host_decline', 'event_cancelled')),
  status         text NOT NULL DEFAULT 'refunded'
                 CHECK (status IN ('refunded', 'released')),
  gateway_status text NOT NULL DEFAULT 'simulated'
                 CHECK (gateway_status IN ('simulated', 'pending_gateway', 'confirmed')),
  policy         text NOT NULL DEFAULT '',
  stripe_refund_id text,
  created_at     timestamptz NOT NULL DEFAULT now()
);

-- Refunds predates the Stripe columns in already-created databases, so the
-- CREATE above is skipped there; re-add idempotently (mirrors the bookings
-- ALTERs) so existing dev/prod DBs converge to the gateway-aware shape.
ALTER TABLE refunds ADD COLUMN IF NOT EXISTS stripe_refund_id text;

-- stripe_events (webhook idempotency ledger) ─────────────────────────────────
-- Every delivered Stripe event id is inserted ON CONFLICT DO NOTHING; a
-- duplicate delivery (Stripe retries) inserts zero rows and is skipped, so a
-- retried `payment_intent.succeeded` can never double-settle a booking.
CREATE TABLE IF NOT EXISTS stripe_events (
  id          text PRIMARY KEY,
  type        text NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now()
);

-- payouts ─────────────────────────────────────────────────────────────────────
-- hosts.ts reads payout_date/seats_sold/gross/commission/status and derives
-- event_title via JOIN, so payouts has NO event_title column.
CREATE TABLE IF NOT EXISTS payouts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id    uuid NOT NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  payout_date timestamptz NOT NULL,
  seats_sold  integer NOT NULL DEFAULT 0,
  gross       numeric(10,2) NOT NULL DEFAULT 0,
  commission  numeric(10,2) NOT NULL DEFAULT 0,
  status      text NOT NULL DEFAULT 'scheduled'
              CHECK (status IN ('paid','processing','scheduled')),
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- withdrawals (host simulated wallet ledger) ────────────────────────────────
-- Money never leaves the server: a withdrawal is a real row that reduces the
-- host's available balance. `requested`/`processing` are terminal in this
-- phase (no external gateway executes the payout).
CREATE TABLE IF NOT EXISTS withdrawals (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount     numeric(10,2) NOT NULL CHECK (amount > 0),
  method     text NOT NULL,
  status     text NOT NULL DEFAULT 'requested'
             CHECK (status IN ('requested','processing','completed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- collaboration_invites (host ↔ restaurant partnership offers) ──────────────
CREATE TABLE IF NOT EXISTS collaboration_invites (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  title         text NOT NULL,
  message       text NOT NULL,
  status        text NOT NULL DEFAULT 'invited'
                CHECK (status IN ('invited','accepted','declined')),
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Host Studio Phase 5: bidirectional proposals, lifecycle tracking, and event
-- linkage. All additive so existing databases converge without data loss.
ALTER TABLE collaboration_invites DROP CONSTRAINT IF EXISTS collaboration_invites_status_check;
ALTER TABLE collaboration_invites ADD CONSTRAINT collaboration_invites_status_check
  CHECK (status IN ('invited','accepted','declined','cancelled','completed'));
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS proposed_by text NOT NULL DEFAULT 'restaurant'
  CHECK (proposed_by IN ('host','restaurant'));
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS experience_id uuid REFERENCES dinner_events(id);
CREATE INDEX IF NOT EXISTS idx_collab_invites_restaurant ON collaboration_invites(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_collab_invites_status ON collaboration_invites(host_id, status);
-- Proposal-workflow repair: who answered, when, and why. The recipient of a
-- proposal is whichever side did not propose it, so the responder columns are
-- filled by the accept/decline path on both directions.
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS responded_at timestamptz;
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS responded_by uuid REFERENCES users(id);
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS decline_reason text NOT NULL DEFAULT '';
ALTER TABLE collaboration_invites ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();
-- One live proposal per (host, venue) pair, enforced by the database instead of
-- a read-then-write check that two concurrent sends can both pass. Declined,
-- cancelled and completed rows are excluded so a pair can try again later.
-- Pre-flight on an existing database:
--   SELECT host_id, restaurant_id, count(*) FROM collaboration_invites
--    WHERE status IN ('invited','accepted') GROUP BY 1,2 HAVING count(*) > 1;
-- must return no rows before this index can be created.
CREATE UNIQUE INDEX IF NOT EXISTS uq_collab_active
  ON collaboration_invites(host_id, restaurant_id)
  WHERE status IN ('invited','accepted');

-- reviews ─────────────────────────────────────────────────────────────────────
-- reviews.ts INSERT omits id + event_title (title comes from JOIN).
CREATE TABLE IF NOT EXISTS reviews (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id           uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id            uuid NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  restaurant_id       uuid NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  rating              numeric(3,2) NOT NULL CHECK (rating BETWEEN 0 AND 5),
  text                text NOT NULL,
  partner_reply       text NULL,
  partner_replied_at  timestamptz NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT reviews_target_check CHECK (
    (event_id IS NOT NULL AND restaurant_id IS NULL) OR
    (event_id IS NULL AND restaurant_id IS NOT NULL)
  )
);

-- Unique constraint: one review per author per target (event or restaurant).
CREATE UNIQUE INDEX IF NOT EXISTS reviews_event_author_idx
  ON reviews(event_id, author_id) WHERE event_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS reviews_restaurant_author_idx
  ON reviews(restaurant_id, author_id) WHERE restaurant_id IS NOT NULL;

-- follows ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS follows (
  follower_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  followee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id),
  CHECK (follower_id <> followee_id)
);

-- venue_follows (user → restaurant) ───────────────────────────────────────────
-- A user following a venue (distinct from user→user `follows`). Upsert/ignore
-- keyed on the composite PK; restaurants.ts exposes it as `isFollowing`.
CREATE TABLE IF NOT EXISTS venue_follows (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, restaurant_id)
);

-- saved_events ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS saved_events (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  event_id   uuid NOT NULL REFERENCES dinner_events(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, event_id)
);

-- activity (notifications feed) ───────────────────────────────────────────────
-- actor_id is the RECIPIENT (feed is `WHERE a.actor_id = userId`); INSERTs
-- from bookings/events/social/reviews omit id → defaulted, and set no user_id.
CREATE TABLE IF NOT EXISTS activity (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id   uuid REFERENCES users(id) ON DELETE CASCADE,
  kind       text NOT NULL
             CHECK (kind IN ('newGuest','payment','reminder','follower','payout','invite','review')),
  title      text NOT NULL,
  body       text NOT NULL DEFAULT '',
  event_id   uuid REFERENCES dinner_events(id) ON DELETE CASCADE,
  amount     numeric(10,2),
  is_unread  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Venue decisions on host event requests surface in the host's activity feed.
-- Widening the CHECK in place keeps existing databases convergent (same
-- drop/re-add pattern as the bookings payment ladder).
ALTER TABLE activity DROP CONSTRAINT IF EXISTS activity_kind_check;
ALTER TABLE activity ADD CONSTRAINT activity_kind_check CHECK (
  kind IN ('newGuest','payment','reminder','follower','payout','invite','review','approval','collab','promotion'));

-- chat_messages ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS chat_messages (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id  uuid REFERENCES dinner_events(id) ON DELETE CASCADE,
  author_id uuid REFERENCES users(id) ON DELETE SET NULL,
  text      text NOT NULL,
  sent_at   timestamptz NOT NULL DEFAULT now(),
  is_system boolean NOT NULL DEFAULT false
);

-- Messaging system: conversations, participants, read receipts ──────────────
-- conversations: one row per chat context (event group, direct message, or
-- partner channel). event_id is nullable, direct messages are not tied to a
-- dinner event. The partial unique constraint ensures at most one conversation
-- per event while allowing many event-less DM conversations.
CREATE TABLE IF NOT EXISTS conversations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind       text NOT NULL
             CHECK (kind IN ('event_group','direct','partner')),
  event_id   uuid REFERENCES dinner_events(id) ON DELETE CASCADE,
  title      text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- conversation_participants: composite PK prevents duplicate membership.
-- last_read_at drives unread-count badges in the inbox.
CREATE TABLE IF NOT EXISTS conversation_participants (
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            text NOT NULL DEFAULT 'member'
                  CHECK (role IN ('member','host','admin')),
  joined_at       timestamptz NOT NULL DEFAULT now(),
  left_at         timestamptz,
  last_read_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (conversation_id, user_id)
);

-- Extend chat_messages for the conversations system. event_id becomes nullable
-- (direct messages have no event); conversation_id links every message to its
-- conversation. edited_at / deleted_at enable soft-delete and edit tracking;
-- parent_id supports threaded replies.
ALTER TABLE chat_messages ALTER COLUMN event_id DROP NOT NULL;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS conversation_id uuid REFERENCES conversations(id) ON DELETE CASCADE;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS edited_at timestamptz;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS deleted_at timestamptz;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS parent_id uuid REFERENCES chat_messages(id);

-- Partial unique: one conversation per event (NULL event_id rows are excluded
-- from the index and therefore not uniqueness-constrained).
CREATE UNIQUE INDEX IF NOT EXISTS idx_conversations_one_per_event
  ON conversations(event_id) WHERE event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_conv_parts_user ON conversation_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_conv_parts_conv  ON conversation_participants(conversation_id);

-- message_read_receipts: one row per (message, reader) pair. The composite PK
-- prevents duplicate receipts; ON DELETE CASCADE on both FKs keeps cleanup
-- automatic when a message or user is removed.
CREATE TABLE IF NOT EXISTS message_read_receipts (
  message_id  uuid NOT NULL REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  read_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id)
);

-- Backfill: create event_group conversations for existing dinner_events, add
-- the host and booked guests as participants, and link any existing chat
-- messages to their conversation. Every statement is idempotent so re-running
-- the schema on an existing database converges without data loss.
DO $$
BEGIN
  -- One conversation per dinner_event (skip those that already have one).
  INSERT INTO conversations (kind, event_id, title)
  SELECT 'event_group', e.id, e.title
  FROM dinner_events e
  WHERE NOT EXISTS (
    SELECT 1 FROM conversations c WHERE c.event_id = e.id
  );

  -- Add event hosts as conversation participants (role = 'host').
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  SELECT c.id, e.host_id, 'host'
  FROM conversations c
  JOIN dinner_events e ON e.id = c.event_id
  WHERE c.kind = 'event_group'
  AND NOT EXISTS (
    SELECT 1 FROM conversation_participants cp
    WHERE cp.conversation_id = c.id AND cp.user_id = e.host_id
  );

  -- Add booked guests as conversation participants (role = 'member').
  INSERT INTO conversation_participants (conversation_id, user_id, role)
  SELECT c.id, b.user_id, 'member'
  FROM conversations c
  JOIN bookings b ON b.event_id = c.event_id
  WHERE c.kind = 'event_group' AND b.status <> 'cancelled'
  AND NOT EXISTS (
    SELECT 1 FROM conversation_participants cp
    WHERE cp.conversation_id = c.id AND cp.user_id = b.user_id
  );

  -- Link existing chat_messages to their conversation.
  UPDATE chat_messages m
  SET conversation_id = c.id
  FROM conversations c
  WHERE c.event_id = m.event_id
    AND m.conversation_id IS NULL;
END $$;

-- special_menus (partner) ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS special_menus (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id   uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name            text NOT NULL,
  description     text NOT NULL DEFAULT '',
  price_per_guest numeric(10,2) NOT NULL DEFAULT 0,
  min_guests      integer NOT NULL DEFAULT 2,
  tags            text[] NOT NULL DEFAULT '{}',
  cover_image     text NOT NULL DEFAULT '',
  status          text NOT NULL DEFAULT 'active'
                  CHECK (status IN ('draft','active','paused','archived')),
  views_this_week integer NOT NULL DEFAULT 0,
  bookings_count  integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- notifications (partner) ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id     uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  title             text NOT NULL,
  body              text NOT NULL DEFAULT '',
  category          text NOT NULL DEFAULT 'general',
  read              boolean NOT NULL DEFAULT false,
  icon              text,
  tint              text,
  notification_time timestamptz NOT NULL DEFAULT now()
);

-- otp_codes (phone sign-in; MVP dev code is generated per request) ────────────
CREATE TABLE IF NOT EXISTS otp_codes (
  phone      text PRIMARY KEY,
  code       text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
-- M2 hardening: store only the digest, track failed attempts so brute-force
-- is capped. Both columns are additive so existing databases converge.
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS code_hash text;
ALTER TABLE otp_codes ADD COLUMN IF NOT EXISTS attempts integer NOT NULL DEFAULT 0;
ALTER TABLE otp_codes ALTER COLUMN code DROP NOT NULL;

-- email_change_challenges (P1-2: verified email changes) ──────────────────────
-- One live challenge per user: requesting a change replaces any pending one.
-- The 6-digit code is stored only as a SHA-256 digest (same digest used for
-- bearer tokens), so a leaked table cannot replay confirmations.
CREATE TABLE IF NOT EXISTS email_change_challenges (
  user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  new_email  text NOT NULL,
  code_hash  text NOT NULL,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- promo_codes (server-validated booking discounts) ──────────────────────────
CREATE TABLE IF NOT EXISTS promo_codes (
  code         text PRIMARY KEY,
  discount_pct numeric(5,2) NOT NULL CHECK (discount_pct BETWEEN 0 AND 100),
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- auth_tokens (opaque bearer tokens, 30-day expiry; token column stores the
-- SHA-256 hex digest of the secret, never the plaintext) ─────────────────────
CREATE TABLE IF NOT EXISTS auth_tokens (
  token      text PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);

-- user_blocks (P2-1 safety: blocking) ────────────────────────────────────────
-- One row per direction is NOT stored: a block is a single directed edge
-- (blocker → blocked), but every enforcement check treats the pair as
-- blocked in BOTH directions (see src/blocks.ts). Self-blocks are impossible
-- by CHECK; the composite PK makes duplicates impossible server-side.
-- Blocking deletes the mutual `follows` rows inside one transaction (social.ts).
CREATE TABLE IF NOT EXISTS user_blocks (
  blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

-- Reverse lookup ("who blocked me?") and pair existence checks.
CREATE INDEX IF NOT EXISTS idx_user_blocks_blocked ON user_blocks(blocked_id);

-- reports (P2-2 safety: user/content reports) ────────────────────────────────
-- Polymorphic target: `target_id` cannot carry a FK (four different tables),
-- so reports.ts validates existence at submission time and snapshots a short
-- `evidence` excerpt, the moderation record survives even if the target is
-- later deleted. Reporter identity is NEVER exposed through any non-admin
-- endpoint. The partial unique index is the anti-spam guard: one OPEN report
-- per (reporter, target); resolved/dismissed reports don't block a re-report.
CREATE TABLE IF NOT EXISTS reports (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  target_type text NOT NULL
              CHECK (target_type IN ('user','event','review','message')),
  target_id   uuid NOT NULL,
  reason      text NOT NULL
              CHECK (reason IN ('harassment','spam','inappropriate_content',
                                'impersonation','unsafe_experience',
                                'misleading_event_info','other')),
  description text NOT NULL DEFAULT '',
  evidence    text NOT NULL DEFAULT '',
  status      text NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending','reviewing','resolved','dismissed')),
  reference   text NOT NULL UNIQUE,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_reports_reporter ON reports(reporter_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_reports_target   ON reports(target_type, target_id);
CREATE INDEX IF NOT EXISTS idx_reports_status   ON reports(status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_reports_open_duplicate
  ON reports(reporter_id, target_type, target_id)
  WHERE status IN ('pending','reviewing');

-- feedback (P2-3 help & feedback) ────────────────────────────────────────────
-- Support tickets raised from Settings → Help & Feedback. `ticket` is the
-- user-facing confirmation reference (FB-XXXXXX). `related_ref` optionally
-- carries a booking/event reference the user is asking about.
CREATE TABLE IF NOT EXISTS feedback (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category     text NOT NULL
               CHECK (category IN ('bug','feature','booking','payment',
                                   'restaurant_experience','general')),
  subject      text NOT NULL,
  description  text NOT NULL,
  related_ref  text NOT NULL DEFAULT '',
  status       text NOT NULL DEFAULT 'open'
               CHECK (status IN ('open','in_progress','resolved','closed')),
  ticket       text NOT NULL UNIQUE,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feedback_user ON feedback(user_id, created_at DESC);

-- audit_log (security.ts auditLog middleware) ─────────────────────────────────
-- user_id/resource_id are uuid to match req.userId / req.params.id.
CREATE TABLE IF NOT EXISTS audit_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid,
  action      text NOT NULL,
  resource    text NOT NULL,
  resource_id text,
  changes     jsonb NOT NULL DEFAULT '{}'::jsonb,
  status_code integer,
  ip_address  text,
  user_agent  text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- supported_cities ────────────────────────────────────────────────────────────
-- DineCircle-operated cities with their neighbourhoods. The Flutter app reads
-- this on the location picker; the seed script populates the initial set.
CREATE TABLE IF NOT EXISTS supported_cities (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name     text NOT NULL UNIQUE,
  country  text NOT NULL DEFAULT 'Pakistan',
  areas    text[] NOT NULL DEFAULT '{}',
  lat      numeric(9,6),
  lng      numeric(9,6),
  active   boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- saved_locations ─────────────────────────────────────────────────────────────
-- User-saved places (Home, Work, favourites). kind is 'home' | 'work' |
-- 'favourite' | 'custom'. One row per saved place; a user may have at most one
-- 'home' and one 'work' (enforced by the route, not the schema).
CREATE TABLE IF NOT EXISTS saved_locations (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind      text NOT NULL CHECK (kind IN ('home','work','favourite','custom')),
  name      text NOT NULL,
  city      text NOT NULL,
  area      text NOT NULL DEFAULT '',
  address   text NOT NULL DEFAULT '',
  latitude  numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_saved_locations_user ON saved_locations(user_id);

-- ═══════════════════════════════════════════════════════════════════════════
-- PARTNER APP (shared venue operations surface)
--
-- One backend, one database, two clients: these tables are the write side of
-- the Partner App. Every one of them is additive, the Customer App keeps
-- reading restaurants/dinner_events/bookings/special_menus exactly as before.
-- ═══════════════════════════════════════════════════════════════════════════

-- restaurant_staff ────────────────────────────────────────────────────────────
-- Per-venue membership. This is the data-isolation backbone: a partner token
-- only reaches venues it appears in here (or owns via restaurants.owner_id).
--   role: owner  → full control incl. staff, payouts, profile
--         manager→ operations: menus, tables, reservations, bookings, events
--         staff  → day-of operations: reservations + check-in only
-- status 'invited' is inert until accepted; 'revoked' keeps the audit history.
CREATE TABLE IF NOT EXISTS restaurant_staff (
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  role          text NOT NULL DEFAULT 'staff'
                CHECK (role IN ('owner','manager','staff')),
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('invited','active','revoked')),
  invited_by    uuid REFERENCES users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, restaurant_id)
);

-- restaurant_branches ─────────────────────────────────────────────────────────
-- A venue may run several locations. Exactly one primary branch per venue; it
-- mirrors its `opening_hours` onto restaurants.opening_hours so the Customer
-- App (which has always read the restaurant row) keeps working unchanged.
CREATE TABLE IF NOT EXISTS restaurant_branches (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id          uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name                   text NOT NULL,
  address                text NOT NULL DEFAULT '',
  area                   text NOT NULL DEFAULT '',
  city                   text NOT NULL DEFAULT '',
  phone                  text NOT NULL DEFAULT '',
  latitude               double precision,
  longitude              double precision,
  is_primary             boolean NOT NULL DEFAULT false,
  accepting_reservations boolean NOT NULL DEFAULT true,
  opening_hours          jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now()
);

-- Service-day timezone (IANA name). Reservation slots are generated as
-- "local date + window" AT TIME ZONE this value, so a venue in Karachi and a
-- diner in London agree on when service starts. Defaulted to UTC so existing
-- databases converge without a data migration; the Partner App sets it.
ALTER TABLE restaurant_branches ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'UTC';

CREATE UNIQUE INDEX IF NOT EXISTS idx_branches_one_primary
  ON restaurant_branches(restaurant_id) WHERE is_primary;

-- restaurant_menu_sections / restaurant_menu_items ───────────────────────────
-- Venue menu (what the kitchen serves), distinct from `menu_items`, which is
-- the per-event tasting menu and stays event-scoped. Prices are numeric(10,2)
-- like every other money column; `is_available` is the partner's 86 switch.
CREATE TABLE IF NOT EXISTS restaurant_menu_sections (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  branch_id     uuid REFERENCES restaurant_branches(id) ON DELETE CASCADE,
  name          text NOT NULL,
  position      integer NOT NULL DEFAULT 0,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS restaurant_menu_items (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  section_id    uuid NOT NULL REFERENCES restaurant_menu_sections(id) ON DELETE CASCADE,
  name          text NOT NULL,
  description   text NOT NULL DEFAULT '',
  price         numeric(10,2) NOT NULL DEFAULT 0 CHECK (price >= 0),
  position      integer NOT NULL DEFAULT 0,
  is_available  boolean NOT NULL DEFAULT true,
  dietary_tags  text[] NOT NULL DEFAULT '{}',
  photo_url     text NOT NULL DEFAULT '',
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- restaurant_tables ───────────────────────────────────────────────────────────
-- Physical table inventory. Reservations that name a table are exclusive for
-- their time window; reservations without one are capacity-checked against the
-- sum of live covers holding a seat in the same window.
CREATE TABLE IF NOT EXISTS restaurant_tables (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  branch_id     uuid REFERENCES restaurant_branches(id) ON DELETE CASCADE,
  label         text NOT NULL,
  seats         integer NOT NULL CHECK (seats > 0 AND seats <= 50),
  zone          text NOT NULL DEFAULT '',
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, label)
);

-- table_reservations ──────────────────────────────────────────────────────────
-- The a-la-carte reservation lane, parallel to ticket-based event bookings.
-- `status` is the operational lifecycle the Partner App drives:
--   pending → confirmed → seated → completed, plus cancelled / no_show.
-- Only pending/confirmed/seated hold capacity.
CREATE TABLE IF NOT EXISTS table_reservations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id    uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  branch_id        uuid REFERENCES restaurant_branches(id) ON DELETE SET NULL,
  table_id         uuid REFERENCES restaurant_tables(id) ON DELETE SET NULL,
  user_id          uuid REFERENCES users(id) ON DELETE SET NULL,
  guest_name       text NOT NULL,
  guest_phone      text NOT NULL DEFAULT '',
  party_size       integer NOT NULL CHECK (party_size > 0 AND party_size <= 50),
  start_at         timestamptz NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 90 CHECK (duration_minutes BETWEEN 15 AND 480),
  status           text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','confirmed','seated','completed','cancelled','no_show')),
  reference        text NOT NULL UNIQUE,
  notes            text NOT NULL DEFAULT '',
  source           text NOT NULL DEFAULT 'customer'
                   CHECK (source IN ('customer','partner')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

-- partner_verification_requests ──────────────────────────────────────────────
-- Restaurant registration + verification queue. A venue is registered by its
-- owner and stays `pending_review` (no public events, no platform payouts)
-- until a super_admin approves it. Rejections keep the reviewer's reason.
CREATE TABLE IF NOT EXISTS partner_verification_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  requested_by  uuid REFERENCES users(id) ON DELETE SET NULL,
  status        text NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected')),
  note          text NOT NULL DEFAULT '',
  reviewer_note text NOT NULL DEFAULT '',
  reviewed_by   uuid REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- restaurant_deals ───────────────────────────────────────────────────────────
-- Time-boxed promotions owned by a venue (percent, fixed amount, or a package
-- price). `code` is optional: present means redeemable by code, absent means a
-- public listing deal. Redemptions are counted server-side, never client-side.
CREATE TABLE IF NOT EXISTS restaurant_deals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id   uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  title           text NOT NULL,
  description     text NOT NULL DEFAULT '',
  kind            text NOT NULL DEFAULT 'percent'
                  CHECK (kind IN ('percent','fixed','package')),
  value           numeric(10,2) NOT NULL CHECK (value >= 0),
  code            text,
  starts_at       timestamptz NOT NULL DEFAULT now(),
  ends_at         timestamptz NOT NULL,
  max_redemptions integer CHECK (max_redemptions IS NULL OR max_redemptions > 0),
  redemptions     integer NOT NULL DEFAULT 0,
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','active','paused','expired')),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at)
);

-- restaurant_payouts ─────────────────────────────────────────────────────────
-- Venue-side earnings ledger, separate from `payouts` (which is per event and
-- belongs to the host). One immutable row per settled payout period; the
-- earnings endpoints recompute the live balance from captured bookings and
-- only ever read this table for history.
CREATE TABLE IF NOT EXISTS restaurant_payouts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  period_start  timestamptz NOT NULL,
  period_end    timestamptz NOT NULL,
  gross         numeric(10,2) NOT NULL DEFAULT 0,
  commission    numeric(10,2) NOT NULL DEFAULT 0,
  net           numeric(10,2) NOT NULL DEFAULT 0,
  status        text NOT NULL DEFAULT 'scheduled'
                CHECK (status IN ('scheduled','processing','paid')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (period_end > period_start)
);

-- Partner-side columns: host event approval + verification bookkeeping.
-- `requires_host_approval` defaults to FALSE so every existing venue keeps
-- auto-confirming host events exactly as it does today; a venue opts in when
-- it wants the Partner App approval queue.
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS requires_host_approval boolean NOT NULL DEFAULT false;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS verified_at timestamptz;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS rejection_note text NOT NULL DEFAULT '';

ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS restaurant_approved_at timestamptz;
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS restaurant_approved_by uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE dinner_events ADD COLUMN IF NOT EXISTS decline_reason text NOT NULL DEFAULT '';

-- Deal copy shown to diners: `terms` holds the conditions plus the redemption
-- steps, `image_url` an optional per-deal banner (falls back to venue cover).
ALTER TABLE restaurant_deals ADD COLUMN IF NOT EXISTS terms text NOT NULL DEFAULT '';
ALTER TABLE restaurant_deals ADD COLUMN IF NOT EXISTS image_url text NOT NULL DEFAULT '';

-- Indexes ─────────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_events_start_at    ON dinner_events(start_at);
CREATE INDEX IF NOT EXISTS idx_events_host        ON dinner_events(host_id);
CREATE INDEX IF NOT EXISTS idx_events_restaurant  ON dinner_events(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_events_type        ON dinner_events(type);
CREATE INDEX IF NOT EXISTS idx_events_status      ON dinner_events(status);
CREATE INDEX IF NOT EXISTS idx_menu_items_event   ON menu_items(event_id);
CREATE INDEX IF NOT EXISTS idx_bookings_user      ON bookings(user_id);
CREATE INDEX IF NOT EXISTS idx_bookings_event     ON bookings(event_id);
CREATE INDEX IF NOT EXISTS idx_refunds_booking    ON refunds(booking_id);
CREATE INDEX IF NOT EXISTS idx_refunds_event      ON refunds(event_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payouts_event  ON payouts(event_id);
CREATE INDEX IF NOT EXISTS idx_withdrawals_host   ON withdrawals(host_id);
CREATE INDEX IF NOT EXISTS idx_collab_invites_host ON collaboration_invites(host_id);
CREATE INDEX IF NOT EXISTS idx_reviews_event      ON reviews(event_id);
CREATE INDEX IF NOT EXISTS idx_reviews_author     ON reviews(author_id);
CREATE INDEX IF NOT EXISTS idx_chat_event         ON chat_messages(event_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_chat_conversation   ON chat_messages(conversation_id, sent_at);
CREATE INDEX IF NOT EXISTS idx_activity_actor     ON activity(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_auth_tokens_user   ON auth_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_saved_events_user  ON saved_events(user_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_owner  ON restaurants(owner_id);
CREATE INDEX IF NOT EXISTS idx_restaurants_partnership ON restaurants(partnership_status);
CREATE INDEX IF NOT EXISTS idx_special_menus_rest ON special_menus(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_notifications_rest ON notifications(restaurant_id, notification_time DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_user     ON audit_log(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created  ON audit_log(created_at DESC);

-- Partner app indexes ─────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_restaurant_staff_rest  ON restaurant_staff(restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_restaurant_staff_user  ON restaurant_staff(user_id, status);
CREATE INDEX IF NOT EXISTS idx_branches_rest          ON restaurant_branches(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_sections_rest     ON restaurant_menu_sections(restaurant_id, position);
CREATE INDEX IF NOT EXISTS idx_menu_items_rest        ON restaurant_menu_items(restaurant_id, position);
CREATE INDEX IF NOT EXISTS idx_menu_items_section     ON restaurant_menu_items(section_id, position);
CREATE INDEX IF NOT EXISTS idx_rest_tables_rest       ON restaurant_tables(restaurant_id, is_active);
-- Reservation reads are always "this venue, this window", the composite index
-- serves both the availability probe and the partner day list.
CREATE INDEX IF NOT EXISTS idx_reservations_rest_time ON table_reservations(restaurant_id, start_at);
CREATE INDEX IF NOT EXISTS idx_reservations_user      ON table_reservations(user_id, start_at DESC);
CREATE INDEX IF NOT EXISTS idx_reservations_status    ON table_reservations(restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_verification_rest      ON partner_verification_requests(restaurant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_verification_status    ON partner_verification_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_deals_rest             ON restaurant_deals(restaurant_id, status, ends_at);
CREATE INDEX IF NOT EXISTS idx_rest_payouts_rest      ON restaurant_payouts(restaurant_id, period_end DESC);
CREATE INDEX IF NOT EXISTS idx_events_approval        ON dinner_events(restaurant_id, status)
  WHERE status IN ('requested','declined');

-- partner_subscriptions ──────────────────────────────────────────────────────
-- One row per venue: records the plan the partner chose and its billing
-- intent. The server sets the price from a constant (PLAN_PRICES in the route)
-- so the client can never send a custom amount. No card, no wallet, no payment
-- gateway, this table captures *intent* only; actual billing is arranged
-- offline with DineCircle.
CREATE TABLE IF NOT EXISTS partner_subscriptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL UNIQUE REFERENCES restaurants(id) ON DELETE CASCADE,
  plan          text CHECK (plan IN ('monthly','yearly')),
  status        text NOT NULL DEFAULT 'none'
                CHECK (status IN ('none','trialing','active','past_due','cancelled')),
  price_pkr     integer NOT NULL DEFAULT 0,
  period_start  timestamptz,
  period_end    timestamptz,
  auto_renew    boolean NOT NULL DEFAULT true,
  cancelled_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_partner_subs_restaurant ON partner_subscriptions(restaurant_id);

-- qr_scans ───────────────────────────────────────────────────────────────────
-- Tracks QR code scans for analytics. Partners can see how many times their
-- QR codes were scanned (menu, profile). No PII is stored, only a device hash
-- for rate limiting.
CREATE TABLE IF NOT EXISTS qr_scans (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  branch_id     uuid NULL REFERENCES restaurant_branches(id) ON DELETE SET NULL,
  kind          text NOT NULL DEFAULT 'menu'
                CHECK (kind IN ('menu', 'profile')),
  scanned_at    timestamptz NOT NULL DEFAULT now(),
  device_hash   text NULL
);

CREATE INDEX IF NOT EXISTS idx_qr_scans_restaurant ON qr_scans(restaurant_id, scanned_at DESC);
CREATE INDEX IF NOT EXISTS idx_qr_scans_device ON qr_scans(device_hash, scanned_at DESC);

-- Universal search (GET /api/search) ─────────────────────────────────────────
-- The aggregate endpoint matches with ILIKE '%term%' across five tables, which
-- no btree index can serve. Trigram GIN indexes keep those predicates from
-- degrading into sequential scans as the dataset grows. Every statement is
-- additive and idempotent, so re-running `npm run db:schema` stays safe.
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_trgm;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_trgm unavailable (%): search ILIKE predicates will use sequential scans', SQLERRM;
END $$;

DO $$
BEGIN
  CREATE INDEX IF NOT EXISTS idx_restaurants_name_trgm ON restaurants USING gin (name gin_trgm_ops);
  CREATE INDEX IF NOT EXISTS idx_events_title_trgm     ON dinner_events USING gin (title gin_trgm_ops);
  CREATE INDEX IF NOT EXISTS idx_deals_title_trgm      ON restaurant_deals USING gin (title gin_trgm_ops);
  CREATE INDEX IF NOT EXISTS idx_menu_items_name_trgm  ON restaurant_menu_items USING gin (name gin_trgm_ops);
  CREATE INDEX IF NOT EXISTS idx_users_name_trgm       ON users USING gin (name gin_trgm_ops);
  CREATE INDEX IF NOT EXISTS idx_users_handle_trgm     ON users USING gin (handle gin_trgm_ops);
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Trigram search indexes skipped (%): ILIKE still works, without the index', SQLERRM;
END $$;

-- Admin console ──────────────────────────────────────────────────────────────
-- The web admin panel needs a handful of admin-owned state that no mobile
-- surface writes. Everything below is additive, so existing app behaviour is
-- unchanged until an admin actually flips one of these values.

-- Admin personas. `role` still decides whether a session may reach
-- /api/admin/* at all; `admin_scope` only decides which sections the console
-- renders, so a finance admin never sees a safety queue by accident.
ALTER TABLE users ADD COLUMN IF NOT EXISTS admin_scope text NOT NULL DEFAULT 'full';
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_admin_scope_check;
ALTER TABLE users ADD CONSTRAINT users_admin_scope_check
  CHECK (admin_scope IN ('full','operations','trust_safety','finance','support'));

-- Account suspension for diners, hosts and partner logins. `is_deleted` means
-- anonymised in place, which is a different state, so it stays untouched.
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspended_at      timestamptz;
ALTER TABLE users ADD COLUMN IF NOT EXISTS suspension_reason text NOT NULL DEFAULT '';

-- Venue moderation. A suspended venue also gets `accepting_bookings = false`
-- because that is the column discovery already filters on, so removal from the
-- customer app needs no change to any mobile-facing query.
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'active';
ALTER TABLE restaurants DROP CONSTRAINT IF EXISTS restaurants_moderation_status_check;
ALTER TABLE restaurants ADD CONSTRAINT restaurants_moderation_status_check
  CHECK (moderation_status IN ('active','suspended'));
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS moderated_by uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS moderated_at timestamptz;

-- Content moderation shared shape for the reviewable record types. The public
-- feeds hide only 'removed', so a flagged deal or review stays visible while an
-- admin decision is pending, which matches how the apps behave today.
ALTER TABLE restaurant_deals      ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'clean';
ALTER TABLE dinner_events         ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'clean';
ALTER TABLE reviews               ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'clean';
ALTER TABLE venue_images          ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'clean';
ALTER TABLE restaurant_menu_items ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'clean';
ALTER TABLE restaurant_deals      ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE dinner_events         ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE reviews               ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE venue_images          ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE restaurant_menu_items ADD COLUMN IF NOT EXISTS moderation_note text NOT NULL DEFAULT '';
ALTER TABLE restaurant_deals      DROP CONSTRAINT IF EXISTS restaurant_deals_moderation_status_check;
ALTER TABLE restaurant_deals      ADD CONSTRAINT restaurant_deals_moderation_status_check
  CHECK (moderation_status IN ('clean','flagged','removed'));
ALTER TABLE dinner_events         DROP CONSTRAINT IF EXISTS dinner_events_moderation_status_check;
ALTER TABLE dinner_events         ADD CONSTRAINT dinner_events_moderation_status_check
  CHECK (moderation_status IN ('clean','flagged','removed'));
ALTER TABLE reviews               DROP CONSTRAINT IF EXISTS reviews_moderation_status_check;
ALTER TABLE reviews               ADD CONSTRAINT reviews_moderation_status_check
  CHECK (moderation_status IN ('clean','flagged','removed'));
ALTER TABLE venue_images          DROP CONSTRAINT IF EXISTS venue_images_moderation_status_check;
ALTER TABLE venue_images          ADD CONSTRAINT venue_images_moderation_status_check
  CHECK (moderation_status IN ('clean','flagged','removed'));
ALTER TABLE restaurant_menu_items DROP CONSTRAINT IF EXISTS restaurant_menu_items_moderation_status_check;
ALTER TABLE restaurant_menu_items ADD CONSTRAINT restaurant_menu_items_moderation_status_check
  CHECK (moderation_status IN ('clean','flagged','removed'));

-- Report triage fields. `severity` drives the queue order, and the resolution
-- text is what the case drawer shows as its final entry.
ALTER TABLE reports ADD COLUMN IF NOT EXISTS severity    text NOT NULL DEFAULT 'medium';
ALTER TABLE reports DROP CONSTRAINT IF EXISTS reports_severity_check;
ALTER TABLE reports ADD CONSTRAINT reports_severity_check
  CHECK (severity IN ('low','medium','high'));
ALTER TABLE reports ADD COLUMN IF NOT EXISTS assigned_to uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolution   text NOT NULL DEFAULT '';
ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolved_by  uuid REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE reports ADD COLUMN IF NOT EXISTS resolved_at  timestamptz;

-- partner_payment_receipts ───────────────────────────────────────────────────
-- Proof of a manual bank transfer, JazzCash or Easypaisa payment. There is no
-- gateway: a receipt row is what the finance queue verifies before a
-- subscription can activate, and it is the only place payment evidence lives.
CREATE TABLE IF NOT EXISTS partner_payment_receipts (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id    uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  amount_pkr       integer NOT NULL CHECK (amount_pkr >= 0),
  method           text NOT NULL DEFAULT 'bank_transfer'
                   CHECK (method IN ('bank_transfer','jazzcash','easypaisa')),
  reference        text NOT NULL DEFAULT '',
  proof_path       text NOT NULL DEFAULT '',
  status           text NOT NULL DEFAULT 'awaiting_verification'
                   CHECK (status IN ('awaiting_verification','verified','rejected')),
  uploaded_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  verified_by      uuid REFERENCES users(id) ON DELETE SET NULL,
  verified_at      timestamptz,
  rejection_reason text NOT NULL DEFAULT '',
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_receipts_status    ON partner_payment_receipts(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_receipts_restaurant ON partner_payment_receipts(restaurant_id);

-- subscription_plans ─────────────────────────────────────────────────────────
-- Plan pricing was previously a constant in code. Holding it here lets the
-- admin console show and edit the reference price a receipt is checked
-- against. It creates no charge: partners still pay outside the apps.
CREATE TABLE IF NOT EXISTS subscription_plans (
  id         text PRIMARY KEY,
  name       text NOT NULL,
  cycle      text NOT NULL CHECK (cycle IN ('month','year')),
  price_pkr  integer NOT NULL CHECK (price_pkr >= 0),
  is_active  boolean NOT NULL DEFAULT true,
  inclusions jsonb NOT NULL DEFAULT '[]'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO subscription_plans (id, name, cycle, price_pkr, inclusions) VALUES
  ('pro_monthly', 'Partner Pro Monthly', 'month', 5000,
   '["Digital menu with unlimited items","QR code menus and scan statistics","Deals, packages and reservations","Experience publishing with a host","0% commission on bookings"]'::jsonb),
  ('pro_yearly', 'Partner Pro Yearly', 'year', 50000,
   '["Digital menu with unlimited items","QR code menus and scan statistics","Deals, packages and reservations","Experience publishing with a host","0% commission on bookings","Two months free versus monthly"]'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- platform_settings ──────────────────────────────────────────────────────────
-- One row of simple key/value configuration for the console: identity fields,
-- the launch city and the behaviour switches. Read on demand, never cached by
-- the mobile apps, so a change cannot surprise a shipped build. The column is
-- named `config` because `values` is a reserved word in Postgres.
CREATE TABLE IF NOT EXISTS platform_settings (
  id         text PRIMARY KEY DEFAULT 'default',
  config     jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO platform_settings (id, config) VALUES
  ('default',
   '{"platformName":"DineCircle","supportEmail":"support@dinecircle.app","currency":"PKR","timezone":"Asia/Karachi","city":"Karachi","riskFlagThreshold":2,"autoApproveVenues":false,"requireReceipt":true,"emailOnNewApplication":true,"emailOnPaymentUpload":true,"weeklyDigest":true,"maintenanceMode":false}'::jsonb)
ON CONFLICT (id) DO NOTHING;

-- Existing admin accounts are full-scope, so the new column needs a backfill
-- to stay consistent with the personas already in use.
UPDATE users SET admin_scope = 'full'
 WHERE role IN ('super_admin','partner_admin') AND admin_scope IS DISTINCT FROM 'full';
