--
-- PostgreSQL database dump
--

\restrict 19hE0hyD4yWqubsnMFaHniZndMyaTavXCxPEmB62IhxbnxPGztVKhnmQQB2c6lC

-- Dumped from database version 17.11 (Debian 17.11-0+deb13u1)
-- Dumped by pg_dump version 17.11 (Debian 17.11-0+deb13u1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: activity; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.activity (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    kind text NOT NULL,
    title text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    event_id uuid,
    amount numeric(10,2),
    is_unread boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT activity_kind_check CHECK ((kind = ANY (ARRAY['newGuest'::text, 'payment'::text, 'reminder'::text, 'follower'::text, 'payout'::text, 'invite'::text, 'review'::text, 'approval'::text, 'collab'::text, 'promotion'::text])))
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid,
    action text NOT NULL,
    resource text NOT NULL,
    resource_id text,
    changes jsonb DEFAULT '{}'::jsonb NOT NULL,
    status_code integer,
    ip_address text,
    user_agent text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: auth_tokens; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auth_tokens (
    token text NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    user_id uuid NOT NULL,
    seats integer NOT NULL,
    price_per_seat numeric(10,2) NOT NULL,
    total_amount numeric(10,2) DEFAULT 0 NOT NULL,
    reference text NOT NULL,
    payment_label text DEFAULT ''::text NOT NULL,
    payment_status text DEFAULT 'paid'::text NOT NULL,
    status text DEFAULT 'confirmed'::text NOT NULL,
    checked_in boolean DEFAULT false NOT NULL,
    checked_in_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    stripe_payment_intent_id text,
    stripe_amount_cents integer,
    CONSTRAINT bookings_payment_status_check CHECK ((payment_status = ANY (ARRAY['unpaid'::text, 'pending_payment'::text, 'authorized'::text, 'paid'::text, 'refunded'::text, 'failed'::text]))),
    CONSTRAINT bookings_seats_check CHECK ((seats > 0)),
    CONSTRAINT bookings_status_check CHECK ((status = ANY (ARRAY['confirmed'::text, 'pending'::text, 'completed'::text, 'cancelled'::text])))
);


--
-- Name: chat_messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid,
    author_id uuid,
    text text NOT NULL,
    sent_at timestamp with time zone DEFAULT now() NOT NULL,
    is_system boolean DEFAULT false NOT NULL,
    conversation_id uuid,
    edited_at timestamp with time zone,
    deleted_at timestamp with time zone,
    parent_id uuid
);


--
-- Name: collaboration_invites; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collaboration_invites (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    host_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    title text NOT NULL,
    message text NOT NULL,
    status text DEFAULT 'invited'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    proposed_by text DEFAULT 'restaurant'::text NOT NULL,
    experience_id uuid,
    CONSTRAINT collaboration_invites_proposed_by_check CHECK ((proposed_by = ANY (ARRAY['host'::text, 'restaurant'::text]))),
    CONSTRAINT collaboration_invites_status_check CHECK ((status = ANY (ARRAY['invited'::text, 'accepted'::text, 'declined'::text, 'cancelled'::text, 'completed'::text])))
);


--
-- Name: conversation_participants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversation_participants (
    conversation_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role text DEFAULT 'member'::text NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    left_at timestamp with time zone,
    last_read_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversation_participants_role_check CHECK ((role = ANY (ARRAY['member'::text, 'host'::text, 'admin'::text])))
);


--
-- Name: conversations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conversations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    kind text NOT NULL,
    event_id uuid,
    title text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT conversations_kind_check CHECK ((kind = ANY (ARRAY['event_group'::text, 'direct'::text, 'partner'::text])))
);


--
-- Name: dinner_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dinner_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    tagline text DEFAULT ''::text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    host_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    cover_image text DEFAULT ''::text NOT NULL,
    gallery text[] DEFAULT '{}'::text[] NOT NULL,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone,
    duration_minutes integer DEFAULT 150 NOT NULL,
    seats_total integer NOT NULL,
    seats_booked integer DEFAULT 0 NOT NULL,
    price_per_seat numeric(10,2) NOT NULL,
    type text DEFAULT 'dinner'::text NOT NULL,
    audience text DEFAULT 'public'::text NOT NULL,
    menu_style text DEFAULT 'familyStyle'::text NOT NULL,
    included text[] DEFAULT '{}'::text[] NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    is_featured boolean DEFAULT false NOT NULL,
    host_note text DEFAULT ''::text NOT NULL,
    language text DEFAULT 'English'::text NOT NULL,
    dress_code text DEFAULT 'Smart casual'::text NOT NULL,
    cancellation text DEFAULT 'Free cancellation up to 48 hours before'::text NOT NULL,
    attendee_ids text[] DEFAULT '{}'::text[] NOT NULL,
    status text DEFAULT 'confirmed'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    views integer DEFAULT 0 NOT NULL,
    requires_approval boolean DEFAULT false NOT NULL,
    is_demo boolean DEFAULT false NOT NULL,
    restaurant_approved_at timestamp with time zone,
    restaurant_approved_by uuid,
    decline_reason text DEFAULT ''::text NOT NULL,
    collaborator_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    CONSTRAINT dinner_events_audience_check CHECK ((audience = ANY (ARRAY['public'::text, 'followers'::text, 'friends'::text, 'inviteOnly'::text]))),
    CONSTRAINT dinner_events_menu_style_check CHECK ((menu_style = ANY (ARRAY['setMenu'::text, 'tastingMenu'::text, 'familyStyle'::text, 'sharing'::text, 'buffet'::text]))),
    CONSTRAINT dinner_events_price_per_seat_check CHECK ((price_per_seat >= (0)::numeric)),
    CONSTRAINT dinner_events_seats_booked_check CHECK ((seats_booked >= 0)),
    CONSTRAINT dinner_events_seats_total_check CHECK ((seats_total >= 0)),
    CONSTRAINT dinner_events_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'requested'::text, 'confirmed'::text, 'live'::text, 'completed'::text, 'declined'::text, 'cancelled'::text]))),
    CONSTRAINT dinner_events_type_check CHECK ((type = ANY (ARRAY['dinner'::text, 'tasting'::text, 'supperClub'::text, 'brunch'::text, 'workshop'::text, 'festival'::text])))
);


--
-- Name: email_change_challenges; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.email_change_challenges (
    user_id uuid NOT NULL,
    new_email text NOT NULL,
    code_hash text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: feedback; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.feedback (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    category text NOT NULL,
    subject text NOT NULL,
    description text NOT NULL,
    related_ref text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    ticket text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT feedback_category_check CHECK ((category = ANY (ARRAY['bug'::text, 'feature'::text, 'booking'::text, 'payment'::text, 'restaurant_experience'::text, 'general'::text]))),
    CONSTRAINT feedback_status_check CHECK ((status = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text, 'closed'::text])))
);


--
-- Name: follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.follows (
    follower_id uuid NOT NULL,
    followee_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT follows_check CHECK ((follower_id <> followee_id))
);


--
-- Name: menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.menu_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    pairing text,
    signature boolean DEFAULT false NOT NULL
);


--
-- Name: message_read_receipts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_read_receipts (
    message_id uuid NOT NULL,
    user_id uuid NOT NULL,
    read_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    title text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    category text DEFAULT 'general'::text NOT NULL,
    read boolean DEFAULT false NOT NULL,
    icon text,
    tint text,
    notification_time timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: otp_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.otp_codes (
    phone text NOT NULL,
    code text,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    code_hash text,
    attempts integer DEFAULT 0 NOT NULL
);


--
-- Name: partner_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partner_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    plan text,
    status text DEFAULT 'none'::text NOT NULL,
    price_pkr integer DEFAULT 0 NOT NULL,
    period_start timestamp with time zone,
    period_end timestamp with time zone,
    auto_renew boolean DEFAULT true NOT NULL,
    cancelled_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT partner_subscriptions_plan_check CHECK ((plan = ANY (ARRAY['monthly'::text, 'yearly'::text]))),
    CONSTRAINT partner_subscriptions_status_check CHECK ((status = ANY (ARRAY['none'::text, 'trialing'::text, 'active'::text, 'past_due'::text, 'cancelled'::text])))
);


--
-- Name: partner_verification_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partner_verification_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    requested_by uuid,
    status text DEFAULT 'pending'::text NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    reviewer_note text DEFAULT ''::text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT partner_verification_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payouts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id uuid NOT NULL,
    payout_date timestamp with time zone NOT NULL,
    seats_sold integer DEFAULT 0 NOT NULL,
    gross numeric(10,2) DEFAULT 0 NOT NULL,
    commission numeric(10,2) DEFAULT 0 NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payouts_status_check CHECK ((status = ANY (ARRAY['paid'::text, 'processing'::text, 'scheduled'::text])))
);


--
-- Name: promo_codes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.promo_codes (
    code text NOT NULL,
    discount_pct numeric(5,2) NOT NULL,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT promo_codes_discount_pct_check CHECK (((discount_pct >= (0)::numeric) AND (discount_pct <= (100)::numeric)))
);


--
-- Name: qr_scans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.qr_scans (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    branch_id uuid,
    kind text DEFAULT 'menu'::text NOT NULL,
    scanned_at timestamp with time zone DEFAULT now() NOT NULL,
    device_hash text,
    CONSTRAINT qr_scans_kind_check CHECK ((kind = ANY (ARRAY['menu'::text, 'profile'::text])))
);


--
-- Name: refunds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.refunds (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booking_id uuid NOT NULL,
    event_id uuid NOT NULL,
    guest_id uuid NOT NULL,
    amount numeric(10,2) DEFAULT 0 NOT NULL,
    reason text NOT NULL,
    status text DEFAULT 'refunded'::text NOT NULL,
    gateway_status text DEFAULT 'simulated'::text NOT NULL,
    policy text DEFAULT ''::text NOT NULL,
    stripe_refund_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT refunds_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT refunds_gateway_status_check CHECK ((gateway_status = ANY (ARRAY['simulated'::text, 'pending_gateway'::text, 'confirmed'::text]))),
    CONSTRAINT refunds_reason_check CHECK ((reason = ANY (ARRAY['guest_cancel'::text, 'host_decline'::text, 'event_cancelled'::text]))),
    CONSTRAINT refunds_status_check CHECK ((status = ANY (ARRAY['refunded'::text, 'released'::text])))
);


--
-- Name: reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    reporter_id uuid NOT NULL,
    target_type text NOT NULL,
    target_id uuid NOT NULL,
    reason text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    evidence text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reference text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT reports_reason_check CHECK ((reason = ANY (ARRAY['harassment'::text, 'spam'::text, 'inappropriate_content'::text, 'impersonation'::text, 'unsafe_experience'::text, 'misleading_event_info'::text, 'other'::text]))),
    CONSTRAINT reports_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'reviewing'::text, 'resolved'::text, 'dismissed'::text]))),
    CONSTRAINT reports_target_type_check CHECK ((target_type = ANY (ARRAY['user'::text, 'event'::text, 'review'::text, 'message'::text])))
);


--
-- Name: restaurant_branches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_branches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    name text NOT NULL,
    address text DEFAULT ''::text NOT NULL,
    area text DEFAULT ''::text NOT NULL,
    city text DEFAULT ''::text NOT NULL,
    phone text DEFAULT ''::text NOT NULL,
    latitude double precision,
    longitude double precision,
    is_primary boolean DEFAULT false NOT NULL,
    accepting_reservations boolean DEFAULT true NOT NULL,
    opening_hours jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    timezone text DEFAULT 'UTC'::text NOT NULL
);


--
-- Name: restaurant_deals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_deals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    title text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    kind text DEFAULT 'percent'::text NOT NULL,
    value numeric(10,2) NOT NULL,
    code text,
    starts_at timestamp with time zone DEFAULT now() NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    max_redemptions integer,
    redemptions integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_deals_check CHECK ((ends_at > starts_at)),
    CONSTRAINT restaurant_deals_kind_check CHECK ((kind = ANY (ARRAY['percent'::text, 'fixed'::text, 'package'::text]))),
    CONSTRAINT restaurant_deals_max_redemptions_check CHECK (((max_redemptions IS NULL) OR (max_redemptions > 0))),
    CONSTRAINT restaurant_deals_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'expired'::text]))),
    CONSTRAINT restaurant_deals_value_check CHECK ((value >= (0)::numeric))
);


--
-- Name: restaurant_menu_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_menu_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    section_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    price numeric(10,2) DEFAULT 0 NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    is_available boolean DEFAULT true NOT NULL,
    dietary_tags text[] DEFAULT '{}'::text[] NOT NULL,
    photo_url text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_menu_items_price_check CHECK ((price >= (0)::numeric))
);


--
-- Name: restaurant_menu_sections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_menu_sections (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    branch_id uuid,
    name text NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: restaurant_payouts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_payouts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    gross numeric(10,2) DEFAULT 0 NOT NULL,
    commission numeric(10,2) DEFAULT 0 NOT NULL,
    net numeric(10,2) DEFAULT 0 NOT NULL,
    status text DEFAULT 'scheduled'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_payouts_check CHECK ((period_end > period_start)),
    CONSTRAINT restaurant_payouts_status_check CHECK ((status = ANY (ARRAY['scheduled'::text, 'processing'::text, 'paid'::text])))
);


--
-- Name: restaurant_staff; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_staff (
    user_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    role text DEFAULT 'staff'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    invited_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_staff_role_check CHECK ((role = ANY (ARRAY['owner'::text, 'manager'::text, 'staff'::text]))),
    CONSTRAINT restaurant_staff_status_check CHECK ((status = ANY (ARRAY['invited'::text, 'active'::text, 'revoked'::text])))
);


--
-- Name: restaurant_tables; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurant_tables (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    branch_id uuid,
    label text NOT NULL,
    seats integer NOT NULL,
    zone text DEFAULT ''::text NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT restaurant_tables_seats_check CHECK (((seats > 0) AND (seats <= 50)))
);


--
-- Name: restaurants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.restaurants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid,
    name text NOT NULL,
    tagline text DEFAULT ''::text NOT NULL,
    about text DEFAULT ''::text NOT NULL,
    cuisines text[] DEFAULT '{}'::text[] NOT NULL,
    neighborhood text DEFAULT ''::text NOT NULL,
    address text DEFAULT ''::text NOT NULL,
    city text DEFAULT ''::text NOT NULL,
    phone text DEFAULT ''::text NOT NULL,
    email text DEFAULT ''::text NOT NULL,
    website text DEFAULT ''::text NOT NULL,
    instagram text DEFAULT ''::text NOT NULL,
    price_range text DEFAULT '$$'::text NOT NULL,
    rating numeric(3,2) DEFAULT 0 NOT NULL,
    review_count integer DEFAULT 0 NOT NULL,
    seats integer DEFAULT 0 NOT NULL,
    tables_count integer DEFAULT 0 NOT NULL,
    since text DEFAULT ''::text NOT NULL,
    owner_name text DEFAULT ''::text NOT NULL,
    amenities text[] DEFAULT '{}'::text[] NOT NULL,
    opening_hours jsonb DEFAULT '{}'::jsonb NOT NULL,
    profile_completion integer DEFAULT 0 NOT NULL,
    accepting_bookings boolean DEFAULT true NOT NULL,
    dine_circle_plus boolean DEFAULT false NOT NULL,
    cover_image text DEFAULT ''::text NOT NULL,
    gallery text[] DEFAULT '{}'::text[] NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    is_partner boolean DEFAULT false NOT NULL,
    partner_perk text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    is_demo boolean DEFAULT false NOT NULL,
    partnership_status text DEFAULT 'unverified'::text NOT NULL,
    latitude double precision,
    longitude double precision,
    requires_host_approval boolean DEFAULT false NOT NULL,
    verified_at timestamp with time zone,
    rejection_note text DEFAULT ''::text NOT NULL,
    logo text DEFAULT ''::text NOT NULL,
    facebook text DEFAULT ''::text NOT NULL,
    twitter text DEFAULT ''::text NOT NULL
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    author_id uuid NOT NULL,
    event_id uuid,
    rating numeric(3,2) NOT NULL,
    text text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    restaurant_id uuid,
    partner_reply text,
    partner_replied_at timestamp with time zone,
    CONSTRAINT reviews_rating_check CHECK (((rating >= (0)::numeric) AND (rating <= (5)::numeric))),
    CONSTRAINT reviews_target_check CHECK ((((event_id IS NOT NULL) AND (restaurant_id IS NULL)) OR ((event_id IS NULL) AND (restaurant_id IS NOT NULL))))
);


--
-- Name: saved_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_events (
    user_id uuid NOT NULL,
    event_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: saved_locations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.saved_locations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    kind text NOT NULL,
    name text NOT NULL,
    city text NOT NULL,
    area text DEFAULT ''::text NOT NULL,
    address text DEFAULT ''::text NOT NULL,
    latitude numeric(9,6),
    longitude numeric(9,6),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT saved_locations_kind_check CHECK ((kind = ANY (ARRAY['home'::text, 'work'::text, 'favourite'::text, 'custom'::text])))
);


--
-- Name: special_menus; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.special_menus (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    name text NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    price_per_guest numeric(10,2) DEFAULT 0 NOT NULL,
    min_guests integer DEFAULT 2 NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    cover_image text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    views_this_week integer DEFAULT 0 NOT NULL,
    bookings_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT special_menus_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'active'::text, 'paused'::text, 'archived'::text])))
);


--
-- Name: stripe_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stripe_events (
    id text NOT NULL,
    type text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: supported_cities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.supported_cities (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    country text DEFAULT 'Pakistan'::text NOT NULL,
    areas text[] DEFAULT '{}'::text[] NOT NULL,
    lat numeric(9,6),
    lng numeric(9,6),
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: table_reservations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.table_reservations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    restaurant_id uuid NOT NULL,
    branch_id uuid,
    table_id uuid,
    user_id uuid,
    guest_name text NOT NULL,
    guest_phone text DEFAULT ''::text NOT NULL,
    party_size integer NOT NULL,
    start_at timestamp with time zone NOT NULL,
    duration_minutes integer DEFAULT 90 NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reference text NOT NULL,
    notes text DEFAULT ''::text NOT NULL,
    source text DEFAULT 'customer'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT table_reservations_duration_minutes_check CHECK (((duration_minutes >= 15) AND (duration_minutes <= 480))),
    CONSTRAINT table_reservations_party_size_check CHECK (((party_size > 0) AND (party_size <= 50))),
    CONSTRAINT table_reservations_source_check CHECK ((source = ANY (ARRAY['customer'::text, 'partner'::text]))),
    CONSTRAINT table_reservations_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'confirmed'::text, 'seated'::text, 'completed'::text, 'cancelled'::text, 'no_show'::text])))
);


--
-- Name: user_avatars; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_avatars (
    user_id uuid NOT NULL,
    content_type text NOT NULL,
    byte_size integer NOT NULL,
    bytes bytea NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_avatars_byte_size_check CHECK (((byte_size > 0) AND (byte_size <= 524288))),
    CONSTRAINT user_avatars_content_type_check CHECK ((content_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text, 'image/webp'::text])))
);


--
-- Name: user_blocks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_blocks (
    blocker_id uuid NOT NULL,
    blocked_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT user_blocks_check CHECK ((blocker_id <> blocked_id))
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    handle text NOT NULL,
    phone text,
    city text DEFAULT ''::text NOT NULL,
    bio text DEFAULT ''::text NOT NULL,
    role text DEFAULT 'user'::text NOT NULL,
    followers_count integer DEFAULT 0 NOT NULL,
    following_count integer DEFAULT 0 NOT NULL,
    dinners_hosted integer DEFAULT 0 NOT NULL,
    dinners_joined integer DEFAULT 0 NOT NULL,
    rating numeric(3,2) DEFAULT 0 NOT NULL,
    review_count integer DEFAULT 0 NOT NULL,
    avatar_url text,
    badges text[] DEFAULT '{}'::text[] NOT NULL,
    tastes text[] DEFAULT '{}'::text[] NOT NULL,
    accent_hex text,
    joined_year integer DEFAULT 2024 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    email text,
    password_hash text,
    instagram text DEFAULT ''::text NOT NULL,
    is_demo boolean DEFAULT false NOT NULL,
    show_follow_list boolean DEFAULT true NOT NULL,
    show_activity boolean DEFAULT true NOT NULL,
    dm_from_followers_only boolean DEFAULT false NOT NULL,
    allow_tagging boolean DEFAULT true NOT NULL,
    dietary text[] DEFAULT '{}'::text[] NOT NULL,
    allergies text[] DEFAULT '{}'::text[] NOT NULL,
    home_area text DEFAULT ''::text NOT NULL,
    is_deleted boolean DEFAULT false NOT NULL,
    CONSTRAINT users_role_check CHECK ((role = ANY (ARRAY['user'::text, 'host'::text, 'influencer'::text, 'partner_admin'::text, 'super_admin'::text, 'restaurant_owner'::text, 'restaurant_staff'::text])))
);


--
-- Name: venue_follows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.venue_follows (
    user_id uuid NOT NULL,
    restaurant_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: withdrawals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.withdrawals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    host_id uuid NOT NULL,
    amount numeric(10,2) NOT NULL,
    method text NOT NULL,
    status text DEFAULT 'requested'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT withdrawals_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT withdrawals_status_check CHECK ((status = ANY (ARRAY['requested'::text, 'processing'::text, 'completed'::text])))
);


--
-- Data for Name: activity; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.activity (id, actor_id, kind, title, body, event_id, amount, is_unread, created_at) FROM stdin;
0318df81-e31c-4830-bd47-376527839dfe	22222222-2222-2222-2222-222222222222	newGuest	A new guest joined your event	The Omakase sold 2 more seats.	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	190.00	t	2026-11-02 01:46:02.999672+05
ce22a147-d195-48cb-94c8-be028e5fd97d	11111111-1111-1111-1111-111111111111	follower	Ava started following you	You now have 13 followers.	\N	\N	t	2026-11-02 01:46:02.999672+05
907d677b-b870-4c1d-bd04-5db627b9b49c	ffffffff-0000-4000-8000-000000000003	newGuest	A new guest booked demo seats	Kolachi Restaurant test listing picked up new bookings.	cccccccc-0000-4000-8000-000000000003	210000.00	t	2026-11-02 01:46:22.417965+05
7c42263b-b98b-4710-8574-c83be678f732	ffffffff-0000-4000-8000-000000000004	newGuest	A new guest booked demo seats	Xander's Clifton test listing picked up new bookings.	cccccccc-0000-4000-8000-000000000004	65000.00	t	2026-11-02 01:46:22.417965+05
5309c987-e9b1-4ac1-afd5-c299229f9992	ffffffff-0000-4000-8000-000000000005	newGuest	A new guest booked demo seats	Xander's Clifton test listing picked up new bookings.	cccccccc-0000-4000-8000-000000000005	112000.00	t	2026-11-02 01:46:22.417965+05
8f4d2af5-f580-4e09-94dd-7a4bf1bf3db6	ffffffff-0000-4000-8000-000000000008	newGuest	A new guest booked demo seats	Cafe Aylanto test listing picked up new bookings.	cccccccc-0000-4000-8000-000000000008	108000.00	t	2026-11-02 01:46:22.417965+05
8319d25d-6440-47a2-920f-9d4ee0dada22	ffffffff-0000-4000-8000-000000000009	newGuest	A new guest booked demo seats	Cafe Aylanto test listing picked up new bookings.	cccccccc-0000-4000-8000-000000000009	100000.00	t	2026-11-02 01:46:22.417965+05
837542cf-80e3-4e90-865e-c02a4a261e8b	ffffffff-0000-4000-8000-00000000000a	newGuest	A new guest booked demo seats	Bar BQ Tonight Clifton test listing picked up new bookings.	cccccccc-0000-4000-8000-00000000000a	54000.00	t	2026-11-02 01:46:22.417965+05
0c3a4f7a-cd03-4208-b415-04fde48a2ce6	ffffffff-0000-4000-8000-000000000003	newGuest	A new guest booked demo seats	Chef's Table Pakistan test listing picked up new bookings.	cccccccc-0000-4000-8000-00000000000d	75000.00	t	2026-11-02 01:46:22.417965+05
4dc64fad-f14f-4334-9d2c-1ef470308009	ffffffff-0000-4000-8000-000000000004	newGuest	A new guest booked demo seats	Chef's Table Pakistan test listing picked up new bookings.	cccccccc-0000-4000-8000-00000000000e	162000.00	t	2026-11-02 01:46:22.417965+05
86819b08-0b06-472e-8b9a-523e74c58265	ffffffff-0000-4000-8000-000000000001	payout	Mock payout scheduled	Fictional earnings for Seaside BBQ Dinner are queued in the host wallet.	cccccccc-0000-4000-8000-000000000001	69300.00	f	2026-11-02 01:46:22.417965+05
43cb696d-37f5-4fca-a7ce-36dd82530630	ffffffff-0000-4000-8000-000000000002	payout	Mock payout scheduled	Fictional earnings for Kolachi Supper Club Night are queued in the host wallet.	cccccccc-0000-4000-8000-000000000002	46800.00	f	2026-11-02 01:46:22.417965+05
e8d59b50-b090-458f-a16d-6f4f9463b7aa	ffffffff-0000-4000-8000-000000000006	payout	Mock payout scheduled	Fictional earnings for Xander's Long Table Session are queued in the host wallet.	cccccccc-0000-4000-8000-000000000006	67500.00	f	2026-11-02 01:46:22.417965+05
ada50f2c-c1ca-4055-bba2-e964a89d8c27	ffffffff-0000-4000-8000-000000000007	payout	Mock payout scheduled	Fictional earnings for Mediterranean Dining Night are queued in the host wallet.	cccccccc-0000-4000-8000-000000000007	163800.00	f	2026-11-02 01:46:22.417965+05
0cf6ad5a-4060-4eda-a69b-8326cdebfba7	ffffffff-0000-4000-8000-000000000001	payout	Mock payout scheduled	Fictional earnings for Bar Supper Club Night are queued in the host wallet.	cccccccc-0000-4000-8000-00000000000b	145800.00	f	2026-11-02 01:46:22.417965+05
4797ee54-ad42-4172-b61c-3a2efcba1752	ffffffff-0000-4000-8000-000000000002	payout	Mock payout scheduled	Fictional earnings for Bar Long Table Session are queued in the host wallet.	cccccccc-0000-4000-8000-00000000000c	54000.00	f	2026-11-02 01:46:22.417965+05
7dbe444d-a33b-4043-a10b-296b372127a9	ffffffff-0000-4000-8000-000000000001	follower	New followers this week	Simulated growth for the Food & lifestyle profile.	\N	\N	t	2026-11-02 01:46:22.417965+05
45d64262-cc9d-413d-beba-222f084c108c	ffffffff-0000-4000-8000-000000000002	follower	New followers this week	Simulated growth for the Local food discoveries profile.	\N	\N	f	2026-11-02 01:46:22.417965+05
82401bc6-ad87-4493-922f-ee824c365df9	ffffffff-0000-4000-8000-000000000003	follower	New followers this week	Simulated growth for the Food photography & reviews profile.	\N	\N	t	2026-11-02 01:46:22.417965+05
28b6e24e-164c-42a8-9756-66c93ee8e98e	ffffffff-0000-4000-8000-000000000004	follower	New followers this week	Simulated growth for the Food & lifestyle profile.	\N	\N	f	2026-11-02 01:46:22.417965+05
6e7d52e5-7fa6-4d56-8576-807718260b46	ffffffff-0000-4000-8000-000000000005	follower	New followers this week	Simulated growth for the Food & lifestyle profile.	\N	\N	t	2026-11-02 01:46:22.417965+05
07eedffb-e38d-4ffc-adda-b29aa75d7387	ffffffff-0000-4000-8000-000000000006	follower	New followers this week	Simulated growth for the Food & local businesses profile.	\N	\N	f	2026-11-02 01:46:22.417965+05
1031c8dc-f717-4a1c-ac48-fc02b4967183	ffffffff-0000-4000-8000-000000000007	follower	New followers this week	Simulated growth for the Premium dining profile.	\N	\N	t	2026-11-02 01:46:22.417965+05
a7755eca-f516-4a5f-806e-f4f43b7a5e51	ffffffff-0000-4000-8000-000000000008	follower	New followers this week	Simulated growth for the Food & entrepreneurship profile.	\N	\N	f	2026-11-02 01:46:22.417965+05
a9dba608-91ec-4e96-949a-70f617826c8a	ffffffff-0000-4000-8000-000000000009	follower	New followers this week	Simulated growth for the Café & restaurant reviews profile.	\N	\N	t	2026-11-02 01:46:22.417965+05
7f094dfd-5458-4e6c-abcd-b7ad52d4f279	ffffffff-0000-4000-8000-00000000000a	follower	New followers this week	Simulated growth for the Street food & breakfast profile.	\N	\N	f	2026-11-02 01:46:22.417965+05
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_log (id, user_id, action, resource, resource_id, changes, status_code, ip_address, user_agent, created_at) FROM stdin;
6263dd67-1704-4dbb-b117-49a41ada0eb2	aaaaaaaa-0000-4000-8000-000000000001	POST	/api/partner/notifications/:notificationId/read	\N	{}	200	::ffff:192.168.100.37	Dart/3.13 (dart:io)	2026-11-03 15:20:02.045611+05
fb5e57c9-5ba7-40b4-9b57-4a9535cb0818	27e49df8-1635-47a2-a5b7-94b2433adf73	POST	/api/restaurants/:restaurantId/reservations	\N	{"startAt": "2026-11-06T19:00:00.000Z", "partySize": 2}	201	::ffff:192.168.100.37	Dart/3.13 (dart:io)	2026-11-04 17:39:53.440633+05
a919ab07-000b-4099-b6e8-1517aba4d454	a665a235-ddd1-408a-a637-125441c5f6ac	POST	/api/restaurants/:restaurantId/reservations	\N	{"date": "2026-11-10", "startAt": "2026-11-10T19:00:00+05:00", "partySize": 2}	201	::1	curl/8.21.0	2026-11-04 17:46:49.243925+05
\.


--
-- Data for Name: auth_tokens; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.auth_tokens (token, user_id, created_at, expires_at) FROM stdin;
67f9c6b2f2963af50d4a78c83e52019303378bdf29fd8cb1b2c0f3dbf4a38429	aaaaaaaa-0000-4000-8000-000000000001	2026-11-02 02:03:26.111212+05	2026-12-02 02:03:26.107+05
7ffac9cfbfd766b0c4f101227456d5bf85ce6404b908ab83b00c108fccb33959	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:05:42.608477+05	2026-12-03 15:05:42.604+05
9c0e3c35bbf59637a19d618a2e15636537d2e8416a0016fd0e384ab2fc5f5c0d	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:42.034663+05	2026-12-03 15:21:42.033+05
e1daeb914e00adb992527cab24cdb4bd680d5f809ef315dd1a2613f8c818678c	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:42.414375+05	2026-12-03 15:21:42.413+05
1c49ddf916fb32dfcea3222e08dc0e47d6a67e274363c9a7133cbc942e354c5f	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:42.702809+05	2026-12-03 15:21:42.701+05
bbea456cd39e36e4074edde6250ff890c353a8475a6cf457f6fdf38f3ebd1a10	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:43.075796+05	2026-12-03 15:21:43.074+05
a6400520ef771987fafb6dca338fe3cd98d27b1cc105e75d2a8d3c0223aed4f9	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:43.423816+05	2026-12-03 15:21:43.423+05
f8ca93eea6eebb0b17555a480e8f9b513c4353840147aa34f268ffed001babab	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:43.723932+05	2026-12-03 15:21:43.722+05
d722398ada1eb9bb4a0d0657256f8a850aff768d6c364663b1c1ac8a31ef4860	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:44.154459+05	2026-12-03 15:21:44.153+05
e11088aa0ea839d17ab38d40b6b029ecdc48f3314064e20a7f0ae1f9a41b3b30	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:21:44.430419+05	2026-12-03 15:21:44.428+05
90ee3b110c2178fcceaf29184eaa6a3c154eeca3afe649b60e84b26b2b9ee64f	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 15:24:05.074926+05	2026-12-03 15:24:05.073+05
9eb9cda5e1efd1bad2983b3707be2a9ad2dc6e4899a34f4c0f73f00521519ee5	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:28.061613+05	2026-12-03 16:49:28.058+05
8dade59f56faf86a887041977ca465d444b6f071ec74051575fc7e824fdb7d28	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:28.597658+05	2026-12-03 16:49:28.596+05
1e20770e7fa44ad7c88e943fbd00dff2508dd6b77896ba83884893d3825d0369	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:28.904051+05	2026-12-03 16:49:28.903+05
64c65186e558b4be2d409f08f82654ed287d3715d9bff7ce3c2be51e7a5e3699	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:29.282813+05	2026-12-03 16:49:29.281+05
bfea55e0cc9c92f89257e4c33536fbc1a18fc069fd07fcc0e148cb4d8dd7f7c4	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:29.652155+05	2026-12-03 16:49:29.651+05
80a1ec0d7ffa621b3e9e7d073c5f41281a027f040a1e7ca22521f5975e1626cc	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:29.954163+05	2026-12-03 16:49:29.953+05
e6c1c71b99cd314bcae46a59b1a133a13dcfad4c6fca75bc30427afc74369498	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:30.266618+05	2026-12-03 16:49:30.265+05
93d96ad5ab973f49268b4b5182224fd4c35b9078033430172539cb36d1f5b038	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 16:49:30.527133+05	2026-12-03 16:49:30.526+05
1123dadddce970c5c6149c2dc0a73129a6fc310638b213a9004d26d4fc019bc4	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 17:51:33.322782+05	2026-12-03 17:51:33.316+05
b0e14ab0108d42ad9171df7c2abcc65d3925bff0005acf2aa342a18720bf5246	aaaaaaaa-0000-4000-8000-000000000001	2026-11-03 17:52:43.115028+05	2026-12-03 17:52:43.112+05
030c8a1a95d15f1124652b570ea4867b866b1141a18642dd2bc41c977456c0ae	dddddddd-0000-4000-8000-000000000001	2026-11-03 17:53:50.617881+05	2026-12-03 17:53:50.615+05
1f5f3a1187881f84ec236b6d86357bee7df21fc0017cc179f4e0cf4f0b35eeb1	aaaaaaaa-0000-4000-8000-000000000001	2026-11-04 11:59:57.017905+05	2026-12-04 11:59:57.015+05
5524f71bb753cd2a69d5dc4e38d0b73f03cc4dfe0ed66c7bc409e5339c6ef5aa	aaaaaaaa-0000-4000-8000-000000000001	2026-11-04 12:45:06.551719+05	2026-12-04 12:45:06.549+05
186f1bc318be3980e29528de575e8ee97be9b3980cf728331531b716fb5790ca	aaaaaaaa-0000-4000-8000-000000000001	2026-11-04 16:51:19.106629+05	2026-12-04 16:51:19.104+05
e132aa5527137db1b2d047041b5e8e75b80207fdd50d9807979e2abf15e6c1c8	aaaaaaaa-0000-4000-8000-000000000001	2026-11-04 17:01:41.608226+05	2026-12-04 17:01:41.607+05
9e2574f69b19c9d7ce8ef5c5fc45906ca8d99a6e26373bdac30892aa9bc2ff95	99427fa6-6c79-43c1-9b24-95292ad23640	2026-11-04 17:23:46.239125+05	2026-12-04 17:23:46.238+05
278a252e5ce7b022e4d2da3cddcd5ee99d68cc2ef804f6e5114a9aee5bae4a78	99427fa6-6c79-43c1-9b24-95292ad23640	2026-11-04 17:23:46.554808+05	2026-12-04 17:23:46.554+05
dbcd30a86408347c22c02b5e09fd26ddc8f894cc8fe3901b79c7be4a5afacef5	27e49df8-1635-47a2-a5b7-94b2433adf73	2026-11-04 17:28:27.567522+05	2026-12-04 17:28:27.565+05
7af09a2696363bbc54b154d165eec31dbb6e714c0cac7742bb84ec1b26138749	a665a235-ddd1-408a-a637-125441c5f6ac	2026-11-04 17:46:49.050384+05	2026-12-04 17:46:49.049+05
7d324225f700f64375d5d1d9864fc167b42866edc2c066203bd66185b0c53bcf	e8ef63b7-155f-4593-98f5-7573e7e35d5b	2026-11-04 17:48:07.579661+05	2026-12-04 17:48:07.578+05
\.


--
-- Data for Name: bookings; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.bookings (id, event_id, user_id, seats, price_per_seat, total_amount, reference, payment_label, payment_status, status, checked_in, checked_in_at, created_at, stripe_payment_intent_id, stripe_amount_cents) FROM stdin;
875e66a2-e03f-41e8-be4b-f34740e1400f	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	11111111-1111-1111-1111-111111111111	2	95.00	190.00	DC-7K3MQ	Visa 4242	paid	confirmed	f	\N	2026-11-02 01:46:02.945394+05	\N	\N
fef786de-483d-4899-8c8c-0110cb4604a7	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	11111111-1111-1111-1111-111111111111	1	38.00	38.00	DC-2P9XW	Visa 4242	paid	confirmed	f	\N	2026-11-02 01:46:02.945394+05	\N	\N
0ade7483-c146-4411-8d4a-4750cc3d6235	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	11111111-1111-1111-1111-111111111111	2	72.00	144.00	DC-9LZ4R	Visa 4242	paid	completed	t	\N	2026-11-02 01:46:02.945394+05	\N	\N
7af96953-2d47-4013-8a03-279597414951	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee4	33333333-3333-3333-3333-333333333333	1	45.00	45.00	DC-4TRNB	Visa 4242	pending_payment	pending	f	\N	2026-11-02 01:46:02.945394+05	\N	\N
1d1b71b8-2db1-4b33-ac2a-b476df2cb9ab	cccccccc-0000-4000-8000-000000000001	dddddddd-0000-4000-8000-000000000001	2	5500.00	11000.00	DC-K100001	Mock wallet PKR	failed	cancelled	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
a06deb8f-d576-4e2c-adb0-96b5bc5b5a3a	cccccccc-0000-4000-8000-000000000001	dddddddd-0000-4000-8000-000000000002	2	5500.00	11000.00	DC-K100002	Mock wallet PKR	paid	completed	t	2026-10-20 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
c842f660-fbee-4865-afc0-65bad0f0b517	cccccccc-0000-4000-8000-000000000001	dddddddd-0000-4000-8000-000000000003	4	5500.00	22000.00	DC-K100003	Mock wallet PKR	paid	completed	t	2026-10-20 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
ce2c435c-18a8-450a-a479-6df80a32dd22	cccccccc-0000-4000-8000-000000000001	dddddddd-0000-4000-8000-000000000004	4	5500.00	22000.00	DC-K100004	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
dbe25f29-4a5d-4895-b4fb-213f688f5713	cccccccc-0000-4000-8000-000000000001	dddddddd-0000-4000-8000-000000000005	4	5500.00	22000.00	DC-K100005	Mock wallet PKR	paid	completed	t	2026-10-20 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
d769a69b-031f-400e-b428-e664a584aabb	cccccccc-0000-4000-8000-000000000002	dddddddd-0000-4000-8000-000000000006	1	6500.00	6500.00	DC-K100006	Mock wallet PKR	paid	completed	t	2026-10-19 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
9ddeb1eb-fa92-4510-9345-28fb3d8a8202	cccccccc-0000-4000-8000-000000000002	dddddddd-0000-4000-8000-000000000007	2	6500.00	13000.00	DC-K100007	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
bdc0d536-e535-4927-8a17-f43a1c480bfa	cccccccc-0000-4000-8000-000000000002	dddddddd-0000-4000-8000-000000000008	1	6500.00	6500.00	DC-K100008	Mock wallet PKR	paid	completed	t	2026-10-19 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
a60f4614-7592-4321-91e7-224435c6fd97	cccccccc-0000-4000-8000-000000000002	dddddddd-0000-4000-8000-000000000009	1	6500.00	6500.00	DC-K100009	Mock wallet PKR	paid	completed	t	2026-10-19 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
47894293-1a3a-4fcb-9c01-88f9a86acab9	cccccccc-0000-4000-8000-000000000002	dddddddd-0000-4000-8000-00000000000a	3	6500.00	19500.00	DC-K100010	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1e2bb8b2-5e65-4e59-bed5-85d059f8a0d9	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-00000000000b	2	14000.00	28000.00	DC-K100011	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
dac29957-68c4-4171-8c96-c62bd926e42c	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-00000000000c	4	14000.00	56000.00	DC-K100012	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
58294d68-8410-4870-978b-f1966126a38d	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-00000000000d	3	14000.00	42000.00	DC-K100013	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4cde752f-a0c3-475a-aab7-d8e3722b6ae2	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-00000000000e	2	14000.00	28000.00	DC-K100014	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
8aecda3b-a173-4a71-ae8e-6cd364179fca	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-00000000000f	4	14000.00	56000.00	DC-K100015	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
d09a06db-fa33-41d9-b16c-1db129479ef0	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000010	2	6500.00	13000.00	DC-K100016	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
432281bd-4684-4e43-bdbc-7291c37bc37a	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000011	1	6500.00	6500.00	DC-K100017	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
40eb9425-23ba-4c49-9bfd-a789b8172601	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000012	1	6500.00	6500.00	DC-K100018	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
7c5cdf81-8dbc-478c-8a6f-42a98f084b34	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000013	2	6500.00	13000.00	DC-K100019	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
a1dfda9d-8de1-4c9e-a583-11bbd2cd2eed	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000014	4	6500.00	26000.00	DC-K100020	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1ae378ce-32e1-4a8c-9848-369794f50a25	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000015	4	8000.00	32000.00	DC-K100021	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
ceeffdfc-ad72-4cca-995a-0d0daeb0e552	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000016	4	8000.00	32000.00	DC-K100022	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
5d3ac91d-80f7-4ded-85f8-4c2170e5b69c	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000017	1	8000.00	8000.00	DC-K100023	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
8dbf2115-b645-4b04-a856-e90d7fa0c90c	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000018	1	8000.00	8000.00	DC-K100024	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
6b33ab81-08ac-4153-9a2c-ecf8e3e2144e	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000019	4	8000.00	32000.00	DC-K100025	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
5458bf87-a66b-46b6-9e01-4e190d461a04	cccccccc-0000-4000-8000-000000000006	dddddddd-0000-4000-8000-00000000001a	2	7500.00	15000.00	DC-K100026	Mock wallet PKR	paid	completed	t	2026-10-15 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
307e3dc5-baff-4b04-8372-0d0f00e80bc6	cccccccc-0000-4000-8000-000000000006	dddddddd-0000-4000-8000-00000000001b	4	7500.00	30000.00	DC-K100027	Mock wallet PKR	paid	completed	t	2026-10-15 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
d195c0ca-2b96-48ba-b1ff-f64e2dc78847	cccccccc-0000-4000-8000-000000000006	dddddddd-0000-4000-8000-00000000001c	2	7500.00	15000.00	DC-K100028	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
47a1c1f3-99aa-4efe-af97-d0fea595fd1d	cccccccc-0000-4000-8000-000000000006	dddddddd-0000-4000-8000-00000000001d	1	7500.00	7500.00	DC-K100029	Mock wallet PKR	paid	completed	t	2026-10-15 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
25c16391-7bfe-440a-9f51-17df0aaca92e	cccccccc-0000-4000-8000-000000000006	dddddddd-0000-4000-8000-00000000001e	1	7500.00	7500.00	DC-K100030	Mock wallet PKR	paid	completed	t	2026-10-15 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
01c986e7-5a1b-4763-83e7-28322ae5da0f	cccccccc-0000-4000-8000-000000000007	dddddddd-0000-4000-8000-00000000001f	3	13000.00	39000.00	DC-K100031	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
6a39103c-70ed-4d82-bd4a-1744f2cb75bc	cccccccc-0000-4000-8000-000000000007	dddddddd-0000-4000-8000-000000000020	2	13000.00	26000.00	DC-K100032	Mock wallet PKR	paid	completed	t	2026-10-14 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
b8de3d39-c175-4315-92fb-4386c32ce879	cccccccc-0000-4000-8000-000000000007	dddddddd-0000-4000-8000-000000000021	4	13000.00	52000.00	DC-K100033	Mock wallet PKR	paid	completed	t	2026-10-14 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
dbb2ebf3-4efe-47f8-92d2-8e4f049ccdac	cccccccc-0000-4000-8000-000000000007	dddddddd-0000-4000-8000-000000000022	2	13000.00	26000.00	DC-K100034	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
700f954e-c4b3-462f-b738-0f9c3925474a	cccccccc-0000-4000-8000-000000000007	dddddddd-0000-4000-8000-000000000023	3	13000.00	39000.00	DC-K100035	Mock wallet PKR	paid	completed	t	2026-10-14 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
31ac560a-be42-4454-be70-4427a037e322	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-000000000024	1	12000.00	12000.00	DC-K100036	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
3c18a1d0-db03-4206-99c9-6de3349806f7	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-000000000025	4	12000.00	48000.00	DC-K100037	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
603b5be6-16b6-4e33-bad5-32a7f89e76bb	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-000000000026	4	12000.00	48000.00	DC-K100038	Mock wallet PKR	failed	cancelled	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1db8e275-1edc-4f42-8d3a-054a586331f7	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-000000000027	1	12000.00	12000.00	DC-K100039	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
88bb37df-965a-4e48-82ba-0af041a6da33	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-000000000028	3	12000.00	36000.00	DC-K100040	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
355714e9-a9b1-4509-b880-e0293658a536	cccccccc-0000-4000-8000-000000000009	dddddddd-0000-4000-8000-000000000029	3	10000.00	30000.00	DC-K100041	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
0a1411c6-7ca6-4712-94d4-f955422a3400	cccccccc-0000-4000-8000-000000000009	dddddddd-0000-4000-8000-00000000002a	1	10000.00	10000.00	DC-K100042	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
3fc6e4e4-4517-4441-9eb6-52de7f83cdd4	cccccccc-0000-4000-8000-000000000009	dddddddd-0000-4000-8000-00000000002b	1	10000.00	10000.00	DC-K100043	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
994d1296-671b-41c0-b47a-0948110fe7ab	cccccccc-0000-4000-8000-000000000009	dddddddd-0000-4000-8000-00000000002c	4	10000.00	40000.00	DC-K100044	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
79703065-270d-4a63-bb68-2188c557ab6c	cccccccc-0000-4000-8000-000000000009	dddddddd-0000-4000-8000-00000000002d	1	10000.00	10000.00	DC-K100045	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
903912ec-0636-4e7e-81b3-5e8034dee919	cccccccc-0000-4000-8000-00000000000a	dddddddd-0000-4000-8000-00000000002e	1	4500.00	4500.00	DC-K100046	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
56251857-875c-4e6c-b76f-d22d7d5d8503	cccccccc-0000-4000-8000-00000000000a	dddddddd-0000-4000-8000-00000000002f	4	4500.00	18000.00	DC-K100047	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
a522de05-b91f-425f-83d8-7febc76c13e2	cccccccc-0000-4000-8000-00000000000a	dddddddd-0000-4000-8000-000000000030	1	4500.00	4500.00	DC-K100048	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1746d37e-3fe2-4f51-aadf-3489f1e24f06	cccccccc-0000-4000-8000-00000000000a	dddddddd-0000-4000-8000-000000000031	2	4500.00	9000.00	DC-K100049	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1cb4dd34-d92f-4f05-8790-1883cb30d3ab	cccccccc-0000-4000-8000-00000000000a	dddddddd-0000-4000-8000-000000000032	4	4500.00	18000.00	DC-K100050	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
885ca29f-d953-42ed-ba3a-5ccc895cddf1	cccccccc-0000-4000-8000-00000000000b	dddddddd-0000-4000-8000-000000000033	1	13500.00	13500.00	DC-K100051	Mock wallet PKR	paid	completed	t	2026-10-10 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
97284eee-abdc-42f4-8f26-371d27c7c64f	cccccccc-0000-4000-8000-00000000000b	dddddddd-0000-4000-8000-000000000034	4	13500.00	54000.00	DC-K100052	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
08adc3b6-2a66-4966-8304-1bf232b48a75	cccccccc-0000-4000-8000-00000000000b	dddddddd-0000-4000-8000-000000000035	1	13500.00	13500.00	DC-K100053	Mock wallet PKR	paid	completed	t	2026-10-10 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
f8333b38-1b5d-4721-a5de-b87e78756e8d	cccccccc-0000-4000-8000-00000000000b	dddddddd-0000-4000-8000-000000000036	3	13500.00	40500.00	DC-K100054	Mock wallet PKR	paid	completed	t	2026-10-10 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
daf71512-9523-44be-bb5f-5d2d8332f6cc	cccccccc-0000-4000-8000-00000000000b	dddddddd-0000-4000-8000-000000000037	3	13500.00	40500.00	DC-K100055	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
ea7e37ba-1ae6-4f5a-abae-8abae3c1c06c	cccccccc-0000-4000-8000-00000000000c	dddddddd-0000-4000-8000-000000000038	4	4000.00	16000.00	DC-K100056	Mock wallet PKR	paid	completed	t	2026-10-09 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
5989abab-31c3-42f5-a2d5-33e97f35fa2a	cccccccc-0000-4000-8000-00000000000c	dddddddd-0000-4000-8000-000000000039	3	4000.00	12000.00	DC-K100057	Mock wallet PKR	paid	completed	t	2026-10-09 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
4fae5e20-295c-4c48-95ac-552711ac2144	cccccccc-0000-4000-8000-00000000000c	dddddddd-0000-4000-8000-00000000003a	3	4000.00	12000.00	DC-K100058	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
21858580-4253-4f98-bdd4-976c9775f82e	cccccccc-0000-4000-8000-00000000000c	dddddddd-0000-4000-8000-00000000003b	4	4000.00	16000.00	DC-K100059	Mock wallet PKR	paid	completed	t	2026-10-09 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
05f353f6-3e0c-40b7-942d-bf4cc0d7fabc	cccccccc-0000-4000-8000-00000000000c	dddddddd-0000-4000-8000-00000000003c	1	4000.00	4000.00	DC-K100060	Mock wallet PKR	paid	completed	t	2026-10-09 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
6b67c4a2-2a23-4353-b4e6-0a3178fc72e9	cccccccc-0000-4000-8000-00000000000d	dddddddd-0000-4000-8000-00000000003d	1	7500.00	7500.00	DC-K100061	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
95703e34-c34f-45f9-948f-223f0c5740be	cccccccc-0000-4000-8000-00000000000d	dddddddd-0000-4000-8000-00000000003e	1	7500.00	7500.00	DC-K100062	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
cf921278-be88-45a4-953f-92f8151777e4	cccccccc-0000-4000-8000-00000000000d	dddddddd-0000-4000-8000-00000000003f	2	7500.00	15000.00	DC-K100063	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
31da3ca0-0cc9-4f01-bc0d-21874a9dfa64	cccccccc-0000-4000-8000-00000000000d	dddddddd-0000-4000-8000-000000000040	4	7500.00	30000.00	DC-K100064	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
a348757d-4e0b-4826-9eef-9c222b8fda30	cccccccc-0000-4000-8000-00000000000d	dddddddd-0000-4000-8000-000000000041	2	7500.00	15000.00	DC-K100065	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
dba928e3-d414-4a50-b6d5-e4d6b8627131	cccccccc-0000-4000-8000-00000000000e	dddddddd-0000-4000-8000-000000000042	2	13500.00	27000.00	DC-K100066	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
0c9da2e3-ae25-49f3-a4c5-463c4ab19714	cccccccc-0000-4000-8000-00000000000e	dddddddd-0000-4000-8000-000000000043	1	13500.00	13500.00	DC-K100067	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
00d82c22-e1de-4436-a522-cb287709db79	cccccccc-0000-4000-8000-00000000000e	dddddddd-0000-4000-8000-000000000044	3	13500.00	40500.00	DC-K100068	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4e33c451-ed1a-45f0-98d1-53c0ffbd102b	cccccccc-0000-4000-8000-00000000000e	dddddddd-0000-4000-8000-000000000045	3	13500.00	40500.00	DC-K100069	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
949a58f7-bbba-4433-b648-0869f8aa5919	cccccccc-0000-4000-8000-00000000000e	dddddddd-0000-4000-8000-000000000046	3	13500.00	40500.00	DC-K100070	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
c75d9567-6c20-4d15-b174-173b0585d526	cccccccc-0000-4000-8000-00000000000f	dddddddd-0000-4000-8000-000000000047	2	5000.00	10000.00	DC-K100071	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
be23f954-b944-4ad9-b316-e6c3daf1119c	cccccccc-0000-4000-8000-00000000000f	dddddddd-0000-4000-8000-000000000048	4	5000.00	20000.00	DC-K100072	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
699c019a-c487-4d96-9af9-ea983464a5f5	cccccccc-0000-4000-8000-00000000000f	dddddddd-0000-4000-8000-000000000049	3	5000.00	15000.00	DC-K100073	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
cd09d97e-f4b0-40aa-8bd2-f9af783ecdbc	cccccccc-0000-4000-8000-00000000000f	dddddddd-0000-4000-8000-00000000004a	1	5000.00	5000.00	DC-K100074	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
2dedf605-76c3-4160-9684-1a04f5a2ccc4	cccccccc-0000-4000-8000-00000000000f	dddddddd-0000-4000-8000-00000000004b	2	5000.00	10000.00	DC-K100075	Mock wallet PKR	failed	cancelled	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
75f221f6-fd5b-4242-8ba3-dfdf9ee9deae	cccccccc-0000-4000-8000-000000000010	dddddddd-0000-4000-8000-00000000004c	4	10500.00	42000.00	DC-K100076	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
f2ef0900-2057-4425-b820-ebbbb6a31e27	cccccccc-0000-4000-8000-000000000010	dddddddd-0000-4000-8000-00000000004d	1	10500.00	10500.00	DC-K100077	Mock wallet PKR	paid	completed	t	2026-10-05 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
cd31a4d2-5fd7-4ff8-a4b8-32e69b9244ab	cccccccc-0000-4000-8000-000000000010	dddddddd-0000-4000-8000-00000000004e	2	10500.00	21000.00	DC-K100078	Mock wallet PKR	paid	completed	t	2026-10-05 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
436675ac-1bd2-4033-86bf-a0117611c36b	cccccccc-0000-4000-8000-000000000010	dddddddd-0000-4000-8000-00000000004f	1	10500.00	10500.00	DC-K100079	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
7f42aa3e-c2de-42b7-8c6c-0b77e114ad29	cccccccc-0000-4000-8000-000000000010	dddddddd-0000-4000-8000-000000000050	2	10500.00	21000.00	DC-K100080	Mock wallet PKR	paid	completed	t	2026-10-05 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
5796086d-355c-4b97-9da2-3cec0a0d1a5c	cccccccc-0000-4000-8000-000000000011	dddddddd-0000-4000-8000-000000000051	1	6000.00	6000.00	DC-K100081	Mock wallet PKR	paid	completed	t	2026-10-04 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
3f1ea8c5-f9ef-4b74-aaa3-2f98d3318ea4	cccccccc-0000-4000-8000-000000000011	dddddddd-0000-4000-8000-000000000052	3	6000.00	18000.00	DC-K100082	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
1c19c4d5-9763-4bfd-85d8-2683037f2d33	cccccccc-0000-4000-8000-000000000011	dddddddd-0000-4000-8000-000000000053	3	6000.00	18000.00	DC-K100083	Mock wallet PKR	paid	completed	t	2026-10-04 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
d82e5a02-8a23-4a3f-8b66-c2541c6c79fd	cccccccc-0000-4000-8000-000000000011	dddddddd-0000-4000-8000-000000000054	1	6000.00	6000.00	DC-K100084	Mock wallet PKR	paid	completed	t	2026-10-04 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
9149b726-d698-4838-b638-e5ad3ce446c3	cccccccc-0000-4000-8000-000000000011	dddddddd-0000-4000-8000-000000000055	3	6000.00	18000.00	DC-K100085	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
abd61e3a-e055-4bfa-8ae2-005f4cfb8658	cccccccc-0000-4000-8000-000000000012	dddddddd-0000-4000-8000-000000000056	2	7500.00	15000.00	DC-K100086	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
afa78a8f-f465-43c5-8fd4-de598be85238	cccccccc-0000-4000-8000-000000000012	dddddddd-0000-4000-8000-000000000057	1	7500.00	7500.00	DC-K100087	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
05b5b86c-a219-4d60-b8cb-a900ad69b6d1	cccccccc-0000-4000-8000-000000000012	dddddddd-0000-4000-8000-000000000058	1	7500.00	7500.00	DC-K100088	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
9df603dd-199e-49b6-ab2f-7abbce2eb43f	cccccccc-0000-4000-8000-000000000012	dddddddd-0000-4000-8000-000000000059	2	7500.00	15000.00	DC-K100089	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
fe881fdd-6777-483a-851a-7f9ffbeb0353	cccccccc-0000-4000-8000-000000000012	dddddddd-0000-4000-8000-00000000005a	3	7500.00	22500.00	DC-K100090	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
d1a8cd11-95d7-49f3-97de-408e62b6c871	cccccccc-0000-4000-8000-000000000013	dddddddd-0000-4000-8000-00000000005b	1	12500.00	12500.00	DC-K100091	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
2a27a45f-7a8c-49b6-a4c9-f4dbef329314	cccccccc-0000-4000-8000-000000000013	dddddddd-0000-4000-8000-00000000005c	1	12500.00	12500.00	DC-K100092	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
891e1590-80bd-4d71-a244-177b84e20079	cccccccc-0000-4000-8000-000000000013	dddddddd-0000-4000-8000-00000000005d	3	12500.00	37500.00	DC-K100093	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
950998ae-1846-4fbe-af5a-1ead2cd5d61d	cccccccc-0000-4000-8000-000000000013	dddddddd-0000-4000-8000-00000000005e	2	12500.00	25000.00	DC-K100094	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
76f9ac5e-d74b-460b-86ba-e6256b01f5e0	cccccccc-0000-4000-8000-000000000013	dddddddd-0000-4000-8000-00000000005f	2	12500.00	25000.00	DC-K100095	Mock wallet PKR	authorized	pending	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
56ec9997-4530-489d-bea5-31da7882e48f	cccccccc-0000-4000-8000-000000000014	dddddddd-0000-4000-8000-000000000060	1	13000.00	13000.00	DC-K100096	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
cd6f0563-1a5a-4081-a7f2-edd054d9cc4d	cccccccc-0000-4000-8000-000000000014	dddddddd-0000-4000-8000-000000000061	3	13000.00	39000.00	DC-K100097	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
042a3925-0cda-47db-8280-632a250df789	cccccccc-0000-4000-8000-000000000014	dddddddd-0000-4000-8000-000000000062	1	13000.00	13000.00	DC-K100098	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
44a65a84-eb46-400e-964e-0eaf3900e446	cccccccc-0000-4000-8000-000000000014	dddddddd-0000-4000-8000-000000000063	3	13000.00	39000.00	DC-K100099	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4521f5d2-d455-46a0-8c70-5fdf8b3ef866	cccccccc-0000-4000-8000-000000000014	dddddddd-0000-4000-8000-000000000064	2	13000.00	26000.00	DC-K100100	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
f9341d0b-439a-4aba-a889-bbfd7bfb2d00	cccccccc-0000-4000-8000-000000000015	dddddddd-0000-4000-8000-000000000001	2	11000.00	22000.00	DC-K100101	Mock wallet PKR	paid	completed	t	2026-09-30 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
8a728818-692c-48fc-a6cb-ece6b40ef239	cccccccc-0000-4000-8000-000000000015	dddddddd-0000-4000-8000-000000000002	3	11000.00	33000.00	DC-K100102	Mock wallet PKR	paid	completed	t	2026-09-30 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
91ac4a79-1c94-4448-bc82-80e048c01b5b	cccccccc-0000-4000-8000-000000000015	dddddddd-0000-4000-8000-000000000003	4	11000.00	44000.00	DC-K100103	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
cbef875d-a977-47b1-9300-f076bb2f662f	cccccccc-0000-4000-8000-000000000015	dddddddd-0000-4000-8000-000000000004	4	11000.00	44000.00	DC-K100104	Mock wallet PKR	paid	completed	t	2026-09-30 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
5f11f7fd-d463-4bda-b1eb-a626f24256a3	cccccccc-0000-4000-8000-000000000015	dddddddd-0000-4000-8000-000000000005	3	11000.00	33000.00	DC-K100105	Mock wallet PKR	paid	completed	t	2026-09-30 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
2f1f8798-723d-408d-8917-976944b0f7b6	cccccccc-0000-4000-8000-000000000016	dddddddd-0000-4000-8000-000000000006	4	6000.00	24000.00	DC-K100106	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
d2b1ee53-14d7-461e-8cec-158c84eda430	cccccccc-0000-4000-8000-000000000016	dddddddd-0000-4000-8000-000000000007	3	6000.00	18000.00	DC-K100107	Mock wallet PKR	paid	completed	t	2026-09-29 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
fe2bc066-d982-4711-bbd5-f27ba2a21096	cccccccc-0000-4000-8000-000000000016	dddddddd-0000-4000-8000-000000000008	4	6000.00	24000.00	DC-K100108	Mock wallet PKR	paid	completed	t	2026-09-29 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
25777356-b767-4833-9eb3-499f6e628fd3	cccccccc-0000-4000-8000-000000000016	dddddddd-0000-4000-8000-000000000009	1	6000.00	6000.00	DC-K100109	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
6e004835-e4ed-40e5-9eaa-e6e0cee4806c	cccccccc-0000-4000-8000-000000000016	dddddddd-0000-4000-8000-00000000000a	2	6000.00	12000.00	DC-K100110	Mock wallet PKR	paid	completed	t	2026-09-29 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
cda13176-ac4f-44be-9393-ecf8df029036	cccccccc-0000-4000-8000-000000000017	dddddddd-0000-4000-8000-00000000000b	1	13000.00	13000.00	DC-K100111	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
85a93de0-476a-46fe-84e1-ac03ab4cca62	cccccccc-0000-4000-8000-000000000017	dddddddd-0000-4000-8000-00000000000c	4	13000.00	52000.00	DC-K100112	Mock wallet PKR	failed	cancelled	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
66c8a30c-d9cf-4b5a-bf5d-b65661c7f0be	cccccccc-0000-4000-8000-000000000017	dddddddd-0000-4000-8000-00000000000d	1	13000.00	13000.00	DC-K100113	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
bf3c1ab7-103c-42cd-9c6d-b8ec329a6300	cccccccc-0000-4000-8000-000000000017	dddddddd-0000-4000-8000-00000000000e	1	13000.00	13000.00	DC-K100114	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
0c40e3b0-f0e6-460c-b14c-6e794b6acdfd	cccccccc-0000-4000-8000-000000000017	dddddddd-0000-4000-8000-00000000000f	3	13000.00	39000.00	DC-K100115	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
eecaba1f-be29-4513-b525-1b90e7cc694f	cccccccc-0000-4000-8000-000000000018	dddddddd-0000-4000-8000-000000000010	4	10500.00	42000.00	DC-K100116	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
8c7cd9e2-5192-4871-bcfb-cca817a54f5e	cccccccc-0000-4000-8000-000000000018	dddddddd-0000-4000-8000-000000000011	2	10500.00	21000.00	DC-K100117	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
9bd0829c-4d7d-427b-a4c4-aa0785ad9631	cccccccc-0000-4000-8000-000000000018	dddddddd-0000-4000-8000-000000000012	2	10500.00	21000.00	DC-K100118	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
b902ed9a-dd37-4beb-a41b-fa613b2533a3	cccccccc-0000-4000-8000-000000000018	dddddddd-0000-4000-8000-000000000013	1	10500.00	10500.00	DC-K100119	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
8cf5148a-4e08-4e63-9534-b80aa253d0ba	cccccccc-0000-4000-8000-000000000018	dddddddd-0000-4000-8000-000000000014	4	10500.00	42000.00	DC-K100120	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
9028340b-8257-4c87-9c36-53f19dcd48a1	cccccccc-0000-4000-8000-000000000019	dddddddd-0000-4000-8000-000000000015	4	7500.00	30000.00	DC-K100121	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4bcb9653-d331-49ca-83c1-3b0face4deba	cccccccc-0000-4000-8000-000000000019	dddddddd-0000-4000-8000-000000000016	2	7500.00	15000.00	DC-K100122	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
35f356b2-5a7a-41aa-92fa-62b9eee54f4b	cccccccc-0000-4000-8000-000000000019	dddddddd-0000-4000-8000-000000000017	4	7500.00	30000.00	DC-K100123	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
469d91f1-65f9-45fb-b50c-9bb464784ba1	cccccccc-0000-4000-8000-000000000019	dddddddd-0000-4000-8000-000000000018	1	7500.00	7500.00	DC-K100124	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
7448963d-7416-4c55-88fc-6185235d70b7	cccccccc-0000-4000-8000-000000000019	dddddddd-0000-4000-8000-000000000019	2	7500.00	15000.00	DC-K100125	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
e99cb874-b6cb-44f6-b100-f753168f7b5e	cccccccc-0000-4000-8000-00000000001a	dddddddd-0000-4000-8000-00000000001a	1	4500.00	4500.00	DC-K100126	Mock wallet PKR	paid	completed	t	2026-09-25 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
4ca2d3b6-e4ca-4eb8-b690-601728550063	cccccccc-0000-4000-8000-00000000001a	dddddddd-0000-4000-8000-00000000001b	2	4500.00	9000.00	DC-K100127	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
3fb4238e-a989-4de5-b6c6-2667008d3aa9	cccccccc-0000-4000-8000-00000000001a	dddddddd-0000-4000-8000-00000000001c	1	4500.00	4500.00	DC-K100128	Mock wallet PKR	paid	completed	t	2026-09-25 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
598820af-b17d-42fb-bf91-254f2a002dd1	cccccccc-0000-4000-8000-00000000001a	dddddddd-0000-4000-8000-00000000001d	4	4500.00	18000.00	DC-K100129	Mock wallet PKR	paid	completed	t	2026-09-25 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
23d3f9c9-118c-44bc-84bd-4853dd369e5c	cccccccc-0000-4000-8000-00000000001a	dddddddd-0000-4000-8000-00000000001e	4	4500.00	18000.00	DC-K100130	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4ed11029-6874-481e-9a84-36b82c4eec03	cccccccc-0000-4000-8000-00000000001b	dddddddd-0000-4000-8000-00000000001f	3	8000.00	24000.00	DC-K100131	Mock wallet PKR	paid	completed	t	2026-09-24 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
5bdc1635-1294-4972-a660-d788f3f17e2b	cccccccc-0000-4000-8000-00000000001b	dddddddd-0000-4000-8000-000000000020	3	8000.00	24000.00	DC-K100132	Mock wallet PKR	paid	completed	t	2026-09-24 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
30fc8527-190f-427f-b424-63ed1fa96ea9	cccccccc-0000-4000-8000-00000000001b	dddddddd-0000-4000-8000-000000000021	2	8000.00	16000.00	DC-K100133	Mock wallet PKR	paid	completed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
d061b687-27d7-4198-9804-add40d67767d	cccccccc-0000-4000-8000-00000000001b	dddddddd-0000-4000-8000-000000000022	3	8000.00	24000.00	DC-K100134	Mock wallet PKR	paid	completed	t	2026-09-24 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
0cbe70df-e23e-476e-b0ac-3764697704b7	cccccccc-0000-4000-8000-00000000001b	dddddddd-0000-4000-8000-000000000023	2	8000.00	16000.00	DC-K100135	Mock wallet PKR	paid	completed	t	2026-09-24 19:15:00+05	2026-11-02 01:46:22.171011+05	\N	\N
33df604a-3a4a-4ac2-ac6d-004fc0da0e51	cccccccc-0000-4000-8000-00000000001c	dddddddd-0000-4000-8000-000000000024	3	10000.00	30000.00	DC-K100136	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
beccdad6-c638-4f7e-9ff0-8aa67c410778	cccccccc-0000-4000-8000-00000000001c	dddddddd-0000-4000-8000-000000000025	3	10000.00	30000.00	DC-K100137	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
54ece97e-78e7-401a-ad80-f6d7c30eaab7	cccccccc-0000-4000-8000-00000000001c	dddddddd-0000-4000-8000-000000000026	1	10000.00	10000.00	DC-K100138	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
2ce64494-2334-47d2-ab12-50ae6f2c61a7	cccccccc-0000-4000-8000-00000000001c	dddddddd-0000-4000-8000-000000000027	1	10000.00	10000.00	DC-K100139	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
389ca33b-b8d6-4a49-90f4-a5abb8189861	cccccccc-0000-4000-8000-00000000001c	dddddddd-0000-4000-8000-000000000028	4	10000.00	40000.00	DC-K100140	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
6e3816c0-8bfc-47ca-a9f2-8930cdd982b8	cccccccc-0000-4000-8000-00000000001d	dddddddd-0000-4000-8000-000000000029	4	13000.00	52000.00	DC-K100141	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
0c7335f0-7039-4056-9ecb-65e143288a59	cccccccc-0000-4000-8000-00000000001d	dddddddd-0000-4000-8000-00000000002a	2	13000.00	26000.00	DC-K100142	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
86265cf9-e211-4952-9f22-237a62129ed6	cccccccc-0000-4000-8000-00000000001d	dddddddd-0000-4000-8000-00000000002b	4	13000.00	52000.00	DC-K100143	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
4eaf6774-c969-44e7-b95a-1310b9ea079c	cccccccc-0000-4000-8000-00000000001d	dddddddd-0000-4000-8000-00000000002c	2	13000.00	26000.00	DC-K100144	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
f603367c-0b2d-4b15-a80f-43600fa8e63e	cccccccc-0000-4000-8000-00000000001d	dddddddd-0000-4000-8000-00000000002d	2	13000.00	26000.00	DC-K100145	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
45bdd5d1-412b-4f9d-ae37-2aa3d5999c25	cccccccc-0000-4000-8000-00000000001e	dddddddd-0000-4000-8000-00000000002e	1	12000.00	12000.00	DC-K100146	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
bad627f4-d3db-4ee7-aaea-c789e7827005	cccccccc-0000-4000-8000-00000000001e	dddddddd-0000-4000-8000-00000000002f	1	12000.00	12000.00	DC-K100147	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
6722a65e-2e48-438c-91f6-3b36b26ad5d4	cccccccc-0000-4000-8000-00000000001e	dddddddd-0000-4000-8000-000000000030	4	12000.00	48000.00	DC-K100148	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
f9196a6a-a95a-4be1-bd3c-4a5aaceefb00	cccccccc-0000-4000-8000-00000000001e	dddddddd-0000-4000-8000-000000000031	2	12000.00	24000.00	DC-K100149	Mock wallet PKR	failed	cancelled	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
bafe4a98-20f2-4c84-b4d6-2c103c47cafa	cccccccc-0000-4000-8000-00000000001e	dddddddd-0000-4000-8000-000000000032	2	12000.00	24000.00	DC-K100150	Mock wallet PKR	paid	confirmed	f	\N	2026-11-02 01:46:22.171011+05	\N	\N
\.


--
-- Data for Name: chat_messages; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.chat_messages (id, event_id, author_id, text, sent_at, is_system, conversation_id, edited_at, deleted_at, parent_id) FROM stdin;
b09c441a-3298-4d3f-b1ce-715669485934	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	\N	Welcome to the event chat. Introduce yourself!	2026-11-05 12:00:00+05	t	01b00cd4-035d-459a-9ef2-11b7069acf67	\N	\N	\N
2f7f07bd-c0e6-43f6-81d3-2087ccafb585	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	11111111-1111-1111-1111-111111111111	Excited for this, first omakase!	2026-11-05 12:30:00+05	f	01b00cd4-035d-459a-9ef2-11b7069acf67	\N	\N	\N
4b005ced-7ef0-4e96-895a-2ac44deab6c6	cccccccc-0000-4000-8000-000000000003	\N	Welcome to the event chat. This is a demo thread for a test listing.	2026-11-03 12:00:00+05	t	cdf3283d-b0bf-4885-be62-24c350871238	\N	\N	\N
ce77b0f9-271c-4c72-8941-a83e402224d9	cccccccc-0000-4000-8000-000000000003	dddddddd-0000-4000-8000-000000000001	Saved my seat for the meetup — see you there!	2026-11-03 13:20:00+05	f	cdf3283d-b0bf-4885-be62-24c350871238	\N	\N	\N
49f2bbe0-cc6b-4266-9f1d-3674f6c6bdb6	cccccccc-0000-4000-8000-000000000003	ffffffff-0000-4000-8000-000000000003	Host here. The check-in QR goes out the morning of the event (mock).	2026-11-03 14:05:00+05	f	cdf3283d-b0bf-4885-be62-24c350871238	\N	\N	\N
a1df2cf9-e5cb-4737-823c-59aa3dcb2721	cccccccc-0000-4000-8000-000000000004	\N	Welcome to the event chat. This is a demo thread for a test listing.	2026-11-03 12:00:00+05	t	276703ca-7e87-4287-ad77-7fc11c075629	\N	\N	\N
66aa8f3a-87eb-4432-90df-332817c5dba2	cccccccc-0000-4000-8000-000000000004	dddddddd-0000-4000-8000-000000000004	Saved my seat for the meetup — see you there!	2026-11-03 13:21:00+05	f	276703ca-7e87-4287-ad77-7fc11c075629	\N	\N	\N
cf6935e4-37b9-4e5f-8108-8c6b86739194	cccccccc-0000-4000-8000-000000000004	ffffffff-0000-4000-8000-000000000004	Host here. The check-in QR goes out the morning of the event (mock).	2026-11-03 14:06:00+05	f	276703ca-7e87-4287-ad77-7fc11c075629	\N	\N	\N
dacd870a-82d3-4ac1-8c56-d915a64ec793	cccccccc-0000-4000-8000-000000000005	\N	Welcome to the event chat. This is a demo thread for a test listing.	2026-11-03 12:00:00+05	t	5004c50a-7e34-41b6-9008-5ce49fba0fa9	\N	\N	\N
56ddc706-cfed-4b95-b762-b261f2089b99	cccccccc-0000-4000-8000-000000000005	dddddddd-0000-4000-8000-000000000007	Saved my seat for the meetup — see you there!	2026-11-03 13:22:00+05	f	5004c50a-7e34-41b6-9008-5ce49fba0fa9	\N	\N	\N
969a7f59-faf4-46b4-8120-f24d4a805592	cccccccc-0000-4000-8000-000000000005	ffffffff-0000-4000-8000-000000000005	Host here. The check-in QR goes out the morning of the event (mock).	2026-11-03 14:07:00+05	f	5004c50a-7e34-41b6-9008-5ce49fba0fa9	\N	\N	\N
4b2c676f-f48f-4e6c-972d-773bfe4ba487	cccccccc-0000-4000-8000-000000000008	\N	Welcome to the event chat. This is a demo thread for a test listing.	2026-11-03 12:00:00+05	t	863a8489-c556-4f8f-93dd-414124ccffe1	\N	\N	\N
ae91b8f3-d02f-4b27-a75f-edd72966d6f1	cccccccc-0000-4000-8000-000000000008	dddddddd-0000-4000-8000-00000000000a	Saved my seat for the meetup — see you there!	2026-11-03 13:23:00+05	f	863a8489-c556-4f8f-93dd-414124ccffe1	\N	\N	\N
52991ded-f238-4da2-98a9-bfe4b5cd91c3	cccccccc-0000-4000-8000-000000000008	ffffffff-0000-4000-8000-000000000008	Host here. The check-in QR goes out the morning of the event (mock).	2026-11-03 14:08:00+05	f	863a8489-c556-4f8f-93dd-414124ccffe1	\N	\N	\N
\.


--
-- Data for Name: collaboration_invites; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.collaboration_invites (id, host_id, restaurant_id, title, message, status, created_at, proposed_by, experience_id) FROM stdin;
31313131-3131-3131-3131-313131313131	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Rooftop Sunset Series	The sunset series is confirmed for monthly editions. Your September edition sold out in 48 hours — the October slot is yours whenever you are ready.	accepted	2026-10-24 10:00:00+05	restaurant	\N
31313131-3131-3131-3131-313131313132	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Omakase Collaboration Night	Our head chef loved your last tasting night. We would like to co-host a 4-night omakase series this season — chef’s counter, full creative control on the menu.	invited	2026-11-01 08:00:00+05	restaurant	\N
31313131-3131-3131-3131-313131313133	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	Brand-Sponsored Pasta Evening	A wine brand partner wants to sponsor a steak & pasta tasting evening hosted by you. We cover the venue, product and a guaranteed honorarium. 20 seats, invite-only.	invited	2026-10-30 15:00:00+05	restaurant	\N
99999999-0000-4000-8000-000000000001	ffffffff-0000-4000-8000-000000000001	bbbbbbbb-0000-4000-8000-000000000001	Seaside BBQ — candidate collab	Mock invite: we would love to test a Seaside BBQ Dinner with you once the venue confirms. Nothing is signed yet.	invited	2026-10-29 10:00:00+05	restaurant	\N
99999999-0000-4000-8000-000000000002	ffffffff-0000-4000-8000-000000000007	bbbbbbbb-0000-4000-8000-000000000005	Chef's Table pilot night	Mock invite for a counter-side tasting pilot. Pending venue verification — treat as a test record.	accepted	2026-10-24 12:00:00+05	restaurant	\N
99999999-0000-4000-8000-000000000003	ffffffff-0000-4000-8000-00000000000a	bbbbbbbb-0000-4000-8000-000000000008	Desi meetup co-host	Mock invite to co-host the Tipu Sultan Desi Food Meetup test event.	invited	2026-10-31 16:00:00+05	restaurant	\N
\.


--
-- Data for Name: conversation_participants; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.conversation_participants (conversation_id, user_id, role, joined_at, left_at, last_read_at) FROM stdin;
01b00cd4-035d-459a-9ef2-11b7069acf67	22222222-2222-2222-2222-222222222222	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	ffffffff-0000-4000-8000-000000000001	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
55b9ffb4-8d2e-42c2-baf5-8420e92c6f89	22222222-2222-2222-2222-222222222222	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7fc22c36-a70e-4268-ae7b-cd05922aff8f	22222222-2222-2222-2222-222222222222	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
6402aa1f-c9d1-4080-a564-36a33e3b2f5e	22222222-2222-2222-2222-222222222222	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	ffffffff-0000-4000-8000-000000000002	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	ffffffff-0000-4000-8000-000000000003	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	ffffffff-0000-4000-8000-000000000005	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	ffffffff-0000-4000-8000-000000000006	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	ffffffff-0000-4000-8000-000000000007	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	ffffffff-0000-4000-8000-000000000009	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	ffffffff-0000-4000-8000-000000000001	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	ffffffff-0000-4000-8000-000000000002	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	ffffffff-0000-4000-8000-000000000003	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	ffffffff-0000-4000-8000-000000000005	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	ffffffff-0000-4000-8000-000000000006	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	ffffffff-0000-4000-8000-000000000007	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	ffffffff-0000-4000-8000-000000000008	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	ffffffff-0000-4000-8000-00000000000a	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	ffffffff-0000-4000-8000-000000000001	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	ffffffff-0000-4000-8000-000000000003	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	ffffffff-0000-4000-8000-000000000004	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	ffffffff-0000-4000-8000-000000000005	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	ffffffff-0000-4000-8000-000000000007	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	ffffffff-0000-4000-8000-000000000008	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	ffffffff-0000-4000-8000-000000000009	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	ffffffff-0000-4000-8000-000000000004	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	ffffffff-0000-4000-8000-000000000008	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	ffffffff-0000-4000-8000-00000000000a	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	ffffffff-0000-4000-8000-000000000004	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	ffffffff-0000-4000-8000-000000000009	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	ffffffff-0000-4000-8000-000000000002	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	ffffffff-0000-4000-8000-000000000006	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	ffffffff-0000-4000-8000-00000000000a	host	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b00cd4-035d-459a-9ef2-11b7069acf67	11111111-1111-1111-1111-111111111111	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
55b9ffb4-8d2e-42c2-baf5-8420e92c6f89	11111111-1111-1111-1111-111111111111	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
6402aa1f-c9d1-4080-a564-36a33e3b2f5e	11111111-1111-1111-1111-111111111111	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7fc22c36-a70e-4268-ae7b-cd05922aff8f	33333333-3333-3333-3333-333333333333	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	dddddddd-0000-4000-8000-000000000002	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	dddddddd-0000-4000-8000-000000000003	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	dddddddd-0000-4000-8000-000000000004	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	dddddddd-0000-4000-8000-000000000005	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	dddddddd-0000-4000-8000-000000000006	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	dddddddd-0000-4000-8000-000000000007	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	dddddddd-0000-4000-8000-000000000008	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	dddddddd-0000-4000-8000-000000000009	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	dddddddd-0000-4000-8000-00000000000a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	dddddddd-0000-4000-8000-00000000000b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	dddddddd-0000-4000-8000-00000000000c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	dddddddd-0000-4000-8000-00000000000d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	dddddddd-0000-4000-8000-00000000000e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	dddddddd-0000-4000-8000-00000000000f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	dddddddd-0000-4000-8000-000000000010	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	dddddddd-0000-4000-8000-000000000011	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	dddddddd-0000-4000-8000-000000000012	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	dddddddd-0000-4000-8000-000000000013	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	dddddddd-0000-4000-8000-000000000014	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	dddddddd-0000-4000-8000-000000000015	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	dddddddd-0000-4000-8000-000000000016	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	dddddddd-0000-4000-8000-000000000017	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	dddddddd-0000-4000-8000-000000000018	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	dddddddd-0000-4000-8000-000000000019	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	dddddddd-0000-4000-8000-00000000001a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	dddddddd-0000-4000-8000-00000000001b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	dddddddd-0000-4000-8000-00000000001c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	dddddddd-0000-4000-8000-00000000001d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	dddddddd-0000-4000-8000-00000000001e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	dddddddd-0000-4000-8000-00000000001f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	dddddddd-0000-4000-8000-000000000020	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	dddddddd-0000-4000-8000-000000000021	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	dddddddd-0000-4000-8000-000000000022	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	dddddddd-0000-4000-8000-000000000023	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	dddddddd-0000-4000-8000-000000000024	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	dddddddd-0000-4000-8000-000000000025	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	dddddddd-0000-4000-8000-000000000027	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	dddddddd-0000-4000-8000-000000000028	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	dddddddd-0000-4000-8000-000000000029	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	dddddddd-0000-4000-8000-00000000002a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	dddddddd-0000-4000-8000-00000000002b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	dddddddd-0000-4000-8000-00000000002c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	dddddddd-0000-4000-8000-00000000002d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	dddddddd-0000-4000-8000-00000000002e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	dddddddd-0000-4000-8000-00000000002f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	dddddddd-0000-4000-8000-000000000030	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	dddddddd-0000-4000-8000-000000000031	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	dddddddd-0000-4000-8000-000000000032	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	dddddddd-0000-4000-8000-000000000033	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	dddddddd-0000-4000-8000-000000000034	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	dddddddd-0000-4000-8000-000000000035	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	dddddddd-0000-4000-8000-000000000036	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	dddddddd-0000-4000-8000-000000000037	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	dddddddd-0000-4000-8000-000000000038	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	dddddddd-0000-4000-8000-000000000039	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	dddddddd-0000-4000-8000-00000000003a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	dddddddd-0000-4000-8000-00000000003b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	dddddddd-0000-4000-8000-00000000003c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	dddddddd-0000-4000-8000-00000000003d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	dddddddd-0000-4000-8000-00000000003e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	dddddddd-0000-4000-8000-00000000003f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	dddddddd-0000-4000-8000-000000000040	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	dddddddd-0000-4000-8000-000000000041	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	dddddddd-0000-4000-8000-000000000042	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	dddddddd-0000-4000-8000-000000000043	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	dddddddd-0000-4000-8000-000000000044	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	dddddddd-0000-4000-8000-000000000045	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	dddddddd-0000-4000-8000-000000000046	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	dddddddd-0000-4000-8000-000000000047	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	dddddddd-0000-4000-8000-000000000048	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	dddddddd-0000-4000-8000-000000000049	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	dddddddd-0000-4000-8000-00000000004a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	dddddddd-0000-4000-8000-00000000004c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	dddddddd-0000-4000-8000-00000000004d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	dddddddd-0000-4000-8000-00000000004e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	dddddddd-0000-4000-8000-00000000004f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	dddddddd-0000-4000-8000-000000000050	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	dddddddd-0000-4000-8000-000000000051	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	dddddddd-0000-4000-8000-000000000052	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	dddddddd-0000-4000-8000-000000000053	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	dddddddd-0000-4000-8000-000000000054	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	dddddddd-0000-4000-8000-000000000055	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	dddddddd-0000-4000-8000-000000000056	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	dddddddd-0000-4000-8000-000000000057	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	dddddddd-0000-4000-8000-000000000058	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	dddddddd-0000-4000-8000-000000000059	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	dddddddd-0000-4000-8000-00000000005a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	dddddddd-0000-4000-8000-00000000005b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	dddddddd-0000-4000-8000-00000000005c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	dddddddd-0000-4000-8000-00000000005d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	dddddddd-0000-4000-8000-00000000005e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	dddddddd-0000-4000-8000-00000000005f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	dddddddd-0000-4000-8000-000000000060	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	dddddddd-0000-4000-8000-000000000061	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	dddddddd-0000-4000-8000-000000000062	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	dddddddd-0000-4000-8000-000000000063	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	dddddddd-0000-4000-8000-000000000064	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	dddddddd-0000-4000-8000-000000000001	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	dddddddd-0000-4000-8000-000000000002	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	dddddddd-0000-4000-8000-000000000003	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	dddddddd-0000-4000-8000-000000000004	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	dddddddd-0000-4000-8000-000000000005	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	dddddddd-0000-4000-8000-000000000006	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	dddddddd-0000-4000-8000-000000000007	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	dddddddd-0000-4000-8000-000000000008	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	dddddddd-0000-4000-8000-000000000009	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	dddddddd-0000-4000-8000-00000000000a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	dddddddd-0000-4000-8000-00000000000b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	dddddddd-0000-4000-8000-00000000000d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	dddddddd-0000-4000-8000-00000000000e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	dddddddd-0000-4000-8000-00000000000f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	dddddddd-0000-4000-8000-000000000010	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	dddddddd-0000-4000-8000-000000000011	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	dddddddd-0000-4000-8000-000000000012	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	dddddddd-0000-4000-8000-000000000013	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	dddddddd-0000-4000-8000-000000000014	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	dddddddd-0000-4000-8000-000000000015	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	dddddddd-0000-4000-8000-000000000016	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	dddddddd-0000-4000-8000-000000000017	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	dddddddd-0000-4000-8000-000000000018	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	dddddddd-0000-4000-8000-000000000019	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	dddddddd-0000-4000-8000-00000000001a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	dddddddd-0000-4000-8000-00000000001b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	dddddddd-0000-4000-8000-00000000001c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	dddddddd-0000-4000-8000-00000000001d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	dddddddd-0000-4000-8000-00000000001e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	dddddddd-0000-4000-8000-00000000001f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	dddddddd-0000-4000-8000-000000000020	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	dddddddd-0000-4000-8000-000000000021	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	dddddddd-0000-4000-8000-000000000022	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	dddddddd-0000-4000-8000-000000000023	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	dddddddd-0000-4000-8000-000000000024	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	dddddddd-0000-4000-8000-000000000025	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	dddddddd-0000-4000-8000-000000000026	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	dddddddd-0000-4000-8000-000000000027	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	dddddddd-0000-4000-8000-000000000028	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	dddddddd-0000-4000-8000-000000000029	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	dddddddd-0000-4000-8000-00000000002a	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	dddddddd-0000-4000-8000-00000000002b	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	dddddddd-0000-4000-8000-00000000002c	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	dddddddd-0000-4000-8000-00000000002d	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	dddddddd-0000-4000-8000-00000000002e	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	dddddddd-0000-4000-8000-00000000002f	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	dddddddd-0000-4000-8000-000000000030	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	dddddddd-0000-4000-8000-000000000032	member	2026-11-03 16:36:44.127345+05	\N	2026-11-03 16:36:44.127345+05
\.


--
-- Data for Name: conversations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.conversations (id, kind, event_id, title, created_at, updated_at) FROM stdin;
01b00cd4-035d-459a-9ef2-11b7069acf67	event_group	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	Omakase Under the Stars	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
687061ae-2ff9-4ebf-8628-ca4dca5b05bf	event_group	cccccccc-0000-4000-8000-000000000001	Seaside BBQ Dinner	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
55b9ffb4-8d2e-42c2-baf5-8420e92c6f89	event_group	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	Sunday Slow Brunch	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
7fc22c36-a70e-4268-ae7b-cd05922aff8f	event_group	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee4	Tasting Menu Tryout	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
6402aa1f-c9d1-4080-a564-36a33e3b2f5e	event_group	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	Cellar Supper	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
82af8757-bbcd-4584-af5a-80edc9d6932b	event_group	cccccccc-0000-4000-8000-000000000002	Kolachi Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
cdf3283d-b0bf-4885-be62-24c350871238	event_group	cccccccc-0000-4000-8000-000000000003	Kolachi Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
5004c50a-7e34-41b6-9008-5ce49fba0fa9	event_group	cccccccc-0000-4000-8000-000000000005	Xander's Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
4773738a-b70d-4103-9cbd-396a6c574e80	event_group	cccccccc-0000-4000-8000-000000000006	Xander's Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
31f4f799-7a6e-4fb9-bc14-45dacec28490	event_group	cccccccc-0000-4000-8000-000000000007	Mediterranean Dining Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
7c8e6e90-6c8d-4bfb-a301-d86a05119c01	event_group	cccccccc-0000-4000-8000-000000000009	Cafe Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
3d7e414b-4bf5-4364-8dc3-d22f787a02c7	event_group	cccccccc-0000-4000-8000-00000000000b	Bar Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
2a75f5de-adc0-4169-89da-c1aaf1b630b2	event_group	cccccccc-0000-4000-8000-00000000000c	Bar Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
c0b4396a-12db-447b-95cc-8d9828fc6226	event_group	cccccccc-0000-4000-8000-00000000000d	Chef's Tasting Experience	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
cdabf2ec-d5a2-4e6b-b5b1-167e3397468a	event_group	cccccccc-0000-4000-8000-00000000000f	Chef's Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
591d080b-f6ff-43b8-945c-6f407665cebf	event_group	cccccccc-0000-4000-8000-000000000010	Premium Meat Tasting	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
400b119b-f1cd-4311-8761-bd2dd2f4e268	event_group	cccccccc-0000-4000-8000-000000000011	The Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
e6c9b67f-5809-4c3e-bdd4-ecb19535004c	event_group	cccccccc-0000-4000-8000-000000000012	The Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
ab9d077a-5a3e-4d64-872d-2929e0390e49	event_group	cccccccc-0000-4000-8000-000000000014	Dynasty Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
3d0e943a-8de4-40f2-88dc-495011c64088	event_group	cccccccc-0000-4000-8000-000000000015	Dynasty Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
a9445517-15bb-4515-b865-696bf137aba0	event_group	cccccccc-0000-4000-8000-000000000017	Kanteen Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
606ed73d-e95f-4d67-ae7a-0b10985e72a7	event_group	cccccccc-0000-4000-8000-000000000018	Kanteen Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
01b25cf2-4ea4-49a8-8eed-f15b6dd997ff	event_group	cccccccc-0000-4000-8000-000000000019	Family Food Festival	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
162fd63d-3fc7-47b3-a647-a4ac27b60ba4	event_group	cccccccc-0000-4000-8000-00000000001b	Foods Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
a83530d5-d331-4401-b32c-d9995af998a0	event_group	cccccccc-0000-4000-8000-00000000001c	Karachi Heritage Tasting	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
5086dba7-aeea-43f6-9efa-94c1213ff084	event_group	cccccccc-0000-4000-8000-00000000001d	The Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
276703ca-7e87-4287-ad77-7fc11c075629	event_group	cccccccc-0000-4000-8000-000000000004	Weekend Brunch Meetup	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
863a8489-c556-4f8f-93dd-414124ccffe1	event_group	cccccccc-0000-4000-8000-000000000008	Cafe Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
c9950347-68ec-4a2e-a11a-5686c8a8c809	event_group	cccccccc-0000-4000-8000-00000000000a	Pakistani BBQ Experience	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
2e1dc465-0f1d-4911-a6da-53547ed95154	event_group	cccccccc-0000-4000-8000-00000000000e	Chef's Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
9a90dbc2-7ac5-4dd8-bd7f-74315ec84696	event_group	cccccccc-0000-4000-8000-000000000013	Chinese Fine Dining	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
3785643b-4dc9-4f42-8a3b-683d0cef7cce	event_group	cccccccc-0000-4000-8000-000000000016	Desi Food Meetup	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
0a9b783d-86f6-4f7f-ad9a-1bdabc3d063d	event_group	cccccccc-0000-4000-8000-00000000001a	Foods Supper Club Night	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
67661c73-8f16-4c14-9db5-e1762a9dd9df	event_group	cccccccc-0000-4000-8000-00000000001e	The Long Table Session	2026-11-03 16:36:44.127345+05	2026-11-03 16:36:44.127345+05
\.


--
-- Data for Name: dinner_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dinner_events (id, title, tagline, description, host_id, restaurant_id, cover_image, gallery, start_at, end_at, duration_minutes, seats_total, seats_booked, price_per_seat, type, audience, menu_style, included, tags, is_featured, host_note, language, dress_code, cancellation, attendee_ids, status, created_at, views, requires_approval, is_demo, restaurant_approved_at, restaurant_approved_by, decline_reason, collaborator_ids) FROM stdin;
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	Omakase Under the Stars	A seven-course chef counter at dusk	A long-table tasting built around whatever the market gave us this morning. Wine pairing optional.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/dish_sushi.png	{assets/images/dish_sushi.png,assets/images/hero_tasting.png}	2026-11-05 19:00:00+05	2026-11-05 22:00:00+05	180	12	3	95.00	tasting	public	tastingMenu	{"7 courses","welcome drink"}	{pasta,seasonal,date-night}	t	Meet at the rooftop door; lifts until 23:00.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	2840	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000001	Seaside BBQ Dinner	Sea-facing dining since 1989 — demo edition	Mock long-table dinner at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000001	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-10-19 19:00:00+05	2026-10-19 22:00:00+05	180	21	14	5500.00	dinner	inviteOnly	setMenu	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000002,dddddddd-0000-4000-8000-000000000003,dddddddd-0000-4000-8000-000000000004,dddddddd-0000-4000-8000-000000000005}	completed	2026-11-02 01:46:22.134907+05	2424	f	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	Sunday Slow Brunch	Lazy plates, bottomless coffee	A family-style brunch with fresh-baked bread and a long coffee tail.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	assets/images/dish_brunch.png	{}	2026-11-11 11:00:00+05	2026-11-11 13:00:00+05	120	16	5	38.00	brunch	public	familyStyle	{"Bottomless coffee",pastries}	{pasta,seasonal,date-night}	f	Kid-friendly.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	1930	f	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee4	Tasting Menu Tryout	Seats held until the host approves	A small preview supper where every seat needs a nod from Nora before it is confirmed.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/hero_tasting.png	{}	2026-11-08 18:00:00+05	2026-11-08 20:30:00+05	150	10	1	45.00	tasting	public	setMenu	{"5 courses"}	{tasting,seasonal}	f	I approve each seat personally — ping me if unsure.	English	Smart casual	Free cancellation up to 48 hours before	{33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	1120	t	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	Cellar Supper	Candles and old vintages	A completed supper club in the wine cellar.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/hero_tasting.png	{}	2026-10-23 20:00:00+05	2026-10-23 22:30:00+05	150	10	10	72.00	supperClub	public	setMenu	{"5 courses",flight}	{pasta,seasonal,date-night}	f	Thank you all.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	completed	2026-11-02 01:46:02.927338+05	2410	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000002	Kolachi Supper Club Night	Sea-facing dining since 1989 — demo edition	Mock chef tasting at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000002	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-10-18 19:00:00+05	2026-10-18 22:00:00+05	180	31	8	6500.00	tasting	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000006,dddddddd-0000-4000-8000-000000000007,dddddddd-0000-4000-8000-000000000008,dddddddd-0000-4000-8000-000000000009,dddddddd-0000-4000-8000-00000000000a}	completed	2026-11-02 01:46:22.134907+05	2366	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000003	Kolachi Long Table Session	Sea-facing dining since 1989 — demo edition	Mock supper club at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000003	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-11-06 19:00:00+05	2026-11-06 22:00:00+05	180	36	15	14000.00	supperClub	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000000b,dddddddd-0000-4000-8000-00000000000c,dddddddd-0000-4000-8000-00000000000d,dddddddd-0000-4000-8000-00000000000e,dddddddd-0000-4000-8000-00000000000f}	confirmed	2026-11-02 01:46:22.134907+05	2525	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000005	Xander's Supper Club Night	Coffee-house classics, all day — demo edition	Mock kitchen workshop at Xander's Clifton (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000005	bbbbbbbb-0000-4000-8000-000000000002	assets/images/venue_interior.png	{}	2026-11-08 19:00:00+05	2026-11-08 22:00:00+05	180	27	14	8000.00	workshop	public	buffet	{"Welcome drink","Shared plates",Dessert}	{brunch,cafe,meetup}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000015,dddddddd-0000-4000-8000-000000000016,dddddddd-0000-4000-8000-000000000017,dddddddd-0000-4000-8000-000000000018,dddddddd-0000-4000-8000-000000000019}	confirmed	2026-11-02 01:46:22.134907+05	852	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000006	Xander's Long Table Session	Coffee-house classics, all day — demo edition	Mock food festival at Xander's Clifton (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000006	bbbbbbbb-0000-4000-8000-000000000002	assets/images/venue_interior.png	{}	2026-10-14 19:00:00+05	2026-10-14 22:00:00+05	180	24	10	7500.00	festival	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{brunch,cafe,meetup}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001a,dddddddd-0000-4000-8000-00000000001b,dddddddd-0000-4000-8000-00000000001c,dddddddd-0000-4000-8000-00000000001d,dddddddd-0000-4000-8000-00000000001e}	completed	2026-11-02 01:46:22.134907+05	2840	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000007	Mediterranean Dining Night	Levantine courtyard dining — demo edition	Mock long-table dinner at Cafe Aylanto (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000007	bbbbbbbb-0000-4000-8000-000000000003	assets/images/venue_bar.png	{}	2026-10-13 19:00:00+05	2026-10-13 22:00:00+05	180	18	14	13000.00	dinner	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{mediterranean,courtyard,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001f,dddddddd-0000-4000-8000-000000000020,dddddddd-0000-4000-8000-000000000021,dddddddd-0000-4000-8000-000000000022,dddddddd-0000-4000-8000-000000000023}	completed	2026-11-02 01:46:22.134907+05	2820	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000009	Cafe Long Table Session	Levantine courtyard dining — demo edition	Mock supper club at Cafe Aylanto (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000009	bbbbbbbb-0000-4000-8000-000000000003	assets/images/venue_bar.png	{}	2026-11-12 19:00:00+05	2026-11-12 22:00:00+05	180	29	10	10000.00	supperClub	public	sharing	{"Welcome drink","Shared plates",Dessert}	{mediterranean,courtyard,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000029,dddddddd-0000-4000-8000-00000000002a,dddddddd-0000-4000-8000-00000000002b,dddddddd-0000-4000-8000-00000000002c,dddddddd-0000-4000-8000-00000000002d}	confirmed	2026-11-02 01:46:22.134907+05	2264	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000b	Bar Supper Club Night	Flip-shop grill, late into the night — demo edition	Mock kitchen workshop at Bar BQ Tonight Clifton (Boat Basin). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000001	bbbbbbbb-0000-4000-8000-000000000004	assets/images/dish_steak.png	{}	2026-10-09 19:00:00+05	2026-10-09 22:00:00+05	180	26	12	13500.00	workshop	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{bbq,late-night,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000033,dddddddd-0000-4000-8000-000000000034,dddddddd-0000-4000-8000-000000000035,dddddddd-0000-4000-8000-000000000036,dddddddd-0000-4000-8000-000000000037}	completed	2026-11-02 01:46:22.134907+05	2530	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000c	Bar Long Table Session	Flip-shop grill, late into the night — demo edition	Mock food festival at Bar BQ Tonight Clifton (Boat Basin). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000002	bbbbbbbb-0000-4000-8000-000000000004	assets/images/dish_steak.png	{}	2026-10-08 19:00:00+05	2026-10-08 22:00:00+05	180	27	15	4000.00	festival	inviteOnly	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{bbq,late-night,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000038,dddddddd-0000-4000-8000-000000000039,dddddddd-0000-4000-8000-00000000003a,dddddddd-0000-4000-8000-00000000003b,dddddddd-0000-4000-8000-00000000003c}	completed	2026-11-02 01:46:22.134907+05	2699	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000d	Chef's Tasting Experience	Counter-side tasting by resident chefs — demo edition	Mock long-table dinner at Chef's Table Pakistan (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000003	bbbbbbbb-0000-4000-8000-000000000005	assets/images/hero_tasting.png	{}	2026-11-16 19:00:00+05	2026-11-16 22:00:00+05	180	22	10	7500.00	dinner	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{tasting,chef-counter,premium}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000003d,dddddddd-0000-4000-8000-00000000003e,dddddddd-0000-4000-8000-00000000003f,dddddddd-0000-4000-8000-000000000040,dddddddd-0000-4000-8000-000000000041}	confirmed	2026-11-02 01:46:22.134907+05	2522	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000f	Chef's Long Table Session	Counter-side tasting by resident chefs — demo edition	Mock supper club at Chef's Table Pakistan (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000005	bbbbbbbb-0000-4000-8000-000000000005	assets/images/hero_tasting.png	{}	2026-11-18 19:00:00+05	2026-11-18 22:00:00+05	180	38	10	5000.00	supperClub	public	buffet	{"Welcome drink","Shared plates",Dessert}	{tasting,chef-counter,premium}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000047,dddddddd-0000-4000-8000-000000000048,dddddddd-0000-4000-8000-000000000049,dddddddd-0000-4000-8000-00000000004a}	confirmed	2026-11-02 01:46:22.134907+05	3018	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000010	Premium Meat Tasting	Fire-grilled premium cuts — demo edition	Mock slow brunch at The Carnivore Karachi (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000006	bbbbbbbb-0000-4000-8000-000000000006	assets/images/dish_steak.png	{}	2026-10-04 19:00:00+05	2026-10-04 22:00:00+05	180	40	10	10500.00	brunch	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{grill,steak,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000004c,dddddddd-0000-4000-8000-00000000004d,dddddddd-0000-4000-8000-00000000004e,dddddddd-0000-4000-8000-00000000004f,dddddddd-0000-4000-8000-000000000050}	completed	2026-11-02 01:46:22.134907+05	3116	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000011	The Supper Club Night	Fire-grilled premium cuts — demo edition	Mock kitchen workshop at The Carnivore Karachi (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000007	bbbbbbbb-0000-4000-8000-000000000006	assets/images/dish_steak.png	{}	2026-10-03 19:00:00+05	2026-10-03 22:00:00+05	180	35	11	6000.00	workshop	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{grill,steak,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000051,dddddddd-0000-4000-8000-000000000052,dddddddd-0000-4000-8000-000000000053,dddddddd-0000-4000-8000-000000000054,dddddddd-0000-4000-8000-000000000055}	completed	2026-11-02 01:46:22.134907+05	2686	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000012	The Long Table Session	Fire-grilled premium cuts — demo edition	Mock food festival at The Carnivore Karachi (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000008	bbbbbbbb-0000-4000-8000-000000000006	assets/images/dish_steak.png	{}	2026-11-21 19:00:00+05	2026-11-21 22:00:00+05	180	23	9	7500.00	festival	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{grill,steak,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000056,dddddddd-0000-4000-8000-000000000057,dddddddd-0000-4000-8000-000000000058,dddddddd-0000-4000-8000-000000000059,dddddddd-0000-4000-8000-00000000005a}	confirmed	2026-11-02 01:46:22.134907+05	2578	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000014	Dynasty Supper Club Night	Saddar institution for Chinese-Karachi classics — demo edition	Mock chef tasting at Dynasty (Saddar). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-00000000000a	bbbbbbbb-0000-4000-8000-000000000007	assets/images/dish_sushi.png	{}	2026-11-23 19:00:00+05	2026-11-23 22:00:00+05	180	40	10	13000.00	tasting	public	buffet	{"Welcome drink","Shared plates",Dessert}	{chinese,family,heritage}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000060,dddddddd-0000-4000-8000-000000000061,dddddddd-0000-4000-8000-000000000062,dddddddd-0000-4000-8000-000000000063,dddddddd-0000-4000-8000-000000000064}	confirmed	2026-11-02 01:46:22.134907+05	1692	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000015	Dynasty Long Table Session	Saddar institution for Chinese-Karachi classics — demo edition	Mock supper club at Dynasty (Saddar). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000001	bbbbbbbb-0000-4000-8000-000000000007	assets/images/dish_sushi.png	{}	2026-09-29 19:00:00+05	2026-09-29 22:00:00+05	180	31	16	11000.00	supperClub	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{chinese,family,heritage}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000001,dddddddd-0000-4000-8000-000000000002,dddddddd-0000-4000-8000-000000000003,dddddddd-0000-4000-8000-000000000004,dddddddd-0000-4000-8000-000000000005}	completed	2026-11-02 01:46:22.134907+05	887	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000017	Kanteen Supper Club Night	Desi plates in a cantonment-heritage setting — demo edition	Mock kitchen workshop at Kanteen (Tipu Sultan). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000003	bbbbbbbb-0000-4000-8000-000000000008	assets/images/dish_pasta.png	{}	2026-11-26 19:00:00+05	2026-11-26 22:00:00+05	180	21	6	13000.00	workshop	inviteOnly	familyStyle	{"Welcome drink","Shared plates",Dessert}	{desi,meetup,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000000b,dddddddd-0000-4000-8000-00000000000d,dddddddd-0000-4000-8000-00000000000e,dddddddd-0000-4000-8000-00000000000f}	confirmed	2026-11-02 01:46:22.134907+05	3014	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000018	Kanteen Long Table Session	Desi plates in a cantonment-heritage setting — demo edition	Mock food festival at Kanteen (Tipu Sultan). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000004	bbbbbbbb-0000-4000-8000-000000000008	assets/images/dish_pasta.png	{}	2026-11-27 19:00:00+05	2026-11-27 22:00:00+05	180	23	13	10500.00	festival	public	sharing	{"Welcome drink","Shared plates",Dessert}	{desi,meetup,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000010,dddddddd-0000-4000-8000-000000000011,dddddddd-0000-4000-8000-000000000012,dddddddd-0000-4000-8000-000000000013,dddddddd-0000-4000-8000-000000000014}	confirmed	2026-11-02 01:46:22.134907+05	1519	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000019	Family Food Festival	Family buffet and karahi corner — demo edition	Mock long-table dinner at Foods Inn (SMCHS). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000005	bbbbbbbb-0000-4000-8000-000000000009	assets/images/dish_brunch.png	{}	2026-11-28 19:00:00+05	2026-11-28 22:00:00+05	180	40	13	7500.00	dinner	public	buffet	{"Welcome drink","Shared plates",Dessert}	{buffet,family,festival}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000015,dddddddd-0000-4000-8000-000000000016,dddddddd-0000-4000-8000-000000000017,dddddddd-0000-4000-8000-000000000018,dddddddd-0000-4000-8000-000000000019}	confirmed	2026-11-02 01:46:22.134907+05	1880	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001b	Foods Long Table Session	Family buffet and karahi corner — demo edition	Mock supper club at Foods Inn (SMCHS). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000007	bbbbbbbb-0000-4000-8000-000000000009	assets/images/dish_brunch.png	{}	2026-09-23 19:00:00+05	2026-09-23 22:00:00+05	180	21	13	8000.00	supperClub	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{buffet,family,festival}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001f,dddddddd-0000-4000-8000-000000000020,dddddddd-0000-4000-8000-000000000021,dddddddd-0000-4000-8000-000000000022,dddddddd-0000-4000-8000-000000000023}	completed	2026-11-02 01:46:22.134907+05	2529	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001c	Karachi Heritage Tasting	Garden dining with old-city charm — demo edition	Mock slow brunch at The East End (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000008	bbbbbbbb-0000-4000-8000-00000000000a	assets/images/venue_interior.png	{}	2026-12-01 19:00:00+05	2026-12-01 22:00:00+05	180	40	12	10000.00	brunch	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{heritage,garden,date-night}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000024,dddddddd-0000-4000-8000-000000000025,dddddddd-0000-4000-8000-000000000026,dddddddd-0000-4000-8000-000000000027,dddddddd-0000-4000-8000-000000000028}	confirmed	2026-11-02 01:46:22.134907+05	2736	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001d	The Supper Club Night	Garden dining with old-city charm — demo edition	Mock kitchen workshop at The East End (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000009	bbbbbbbb-0000-4000-8000-00000000000a	assets/images/venue_interior.png	{}	2026-12-02 19:00:00+05	2026-12-02 22:00:00+05	180	23	14	13000.00	workshop	public	sharing	{"Welcome drink","Shared plates",Dessert}	{heritage,garden,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000029,dddddddd-0000-4000-8000-00000000002a,dddddddd-0000-4000-8000-00000000002b,dddddddd-0000-4000-8000-00000000002c,dddddddd-0000-4000-8000-00000000002d}	confirmed	2026-11-02 01:46:22.134907+05	2663	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000004	Weekend Brunch Meetup	Coffee-house classics, all day — demo edition	Mock slow brunch at Xander's Clifton (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000004	bbbbbbbb-0000-4000-8000-000000000002	assets/images/venue_interior.png	{}	2026-11-07 19:00:00+05	2026-11-07 22:00:00+05	180	38	10	6500.00	brunch	followers	sharing	{"Welcome drink","Shared plates",Dessert}	{brunch,cafe,meetup}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000010,dddddddd-0000-4000-8000-000000000011,dddddddd-0000-4000-8000-000000000012,dddddddd-0000-4000-8000-000000000013,dddddddd-0000-4000-8000-000000000014}	confirmed	2026-11-02 01:46:22.134907+05	1252	t	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000008	Cafe Supper Club Night	Levantine courtyard dining — demo edition	Mock chef tasting at Cafe Aylanto (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000008	bbbbbbbb-0000-4000-8000-000000000003	assets/images/venue_bar.png	{}	2026-11-11 19:00:00+05	2026-11-11 22:00:00+05	180	39	9	12000.00	tasting	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{mediterranean,courtyard,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000024,dddddddd-0000-4000-8000-000000000025,dddddddd-0000-4000-8000-000000000027,dddddddd-0000-4000-8000-000000000028}	confirmed	2026-11-02 01:46:22.134907+05	895	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000a	Pakistani BBQ Experience	Flip-shop grill, late into the night — demo edition	Mock slow brunch at Bar BQ Tonight Clifton (Boat Basin). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-00000000000a	bbbbbbbb-0000-4000-8000-000000000004	assets/images/dish_steak.png	{}	2026-11-13 19:00:00+05	2026-11-13 22:00:00+05	180	34	12	4500.00	brunch	public	buffet	{"Welcome drink","Shared plates",Dessert}	{bbq,late-night,casual}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000002e,dddddddd-0000-4000-8000-00000000002f,dddddddd-0000-4000-8000-000000000030,dddddddd-0000-4000-8000-000000000031,dddddddd-0000-4000-8000-000000000032}	confirmed	2026-11-02 01:46:22.134907+05	3193	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000e	Chef's Supper Club Night	Counter-side tasting by resident chefs — demo edition	Mock chef tasting at Chef's Table Pakistan (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000004	bbbbbbbb-0000-4000-8000-000000000005	assets/images/hero_tasting.png	{}	2026-11-17 19:00:00+05	2026-11-17 22:00:00+05	180	18	12	13500.00	tasting	public	sharing	{"Welcome drink","Shared plates",Dessert}	{tasting,chef-counter,premium}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000042,dddddddd-0000-4000-8000-000000000043,dddddddd-0000-4000-8000-000000000044,dddddddd-0000-4000-8000-000000000045,dddddddd-0000-4000-8000-000000000046}	confirmed	2026-11-02 01:46:22.134907+05	933	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000013	Chinese Fine Dining	Saddar institution for Chinese-Karachi classics — demo edition	Mock long-table dinner at Dynasty (Saddar). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000009	bbbbbbbb-0000-4000-8000-000000000007	assets/images/dish_sushi.png	{}	2026-11-22 19:00:00+05	2026-11-22 22:00:00+05	180	36	9	12500.00	dinner	followers	sharing	{"Welcome drink","Shared plates",Dessert}	{chinese,family,heritage}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000005b,dddddddd-0000-4000-8000-00000000005c,dddddddd-0000-4000-8000-00000000005d,dddddddd-0000-4000-8000-00000000005e,dddddddd-0000-4000-8000-00000000005f}	confirmed	2026-11-02 01:46:22.134907+05	1996	t	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000016	Desi Food Meetup	Desi plates in a cantonment-heritage setting — demo edition	Mock slow brunch at Kanteen (Tipu Sultan). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000002	bbbbbbbb-0000-4000-8000-000000000008	assets/images/dish_pasta.png	{}	2026-09-28 19:00:00+05	2026-09-28 22:00:00+05	180	32	14	6000.00	brunch	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{desi,meetup,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000006,dddddddd-0000-4000-8000-000000000007,dddddddd-0000-4000-8000-000000000008,dddddddd-0000-4000-8000-000000000009,dddddddd-0000-4000-8000-00000000000a}	completed	2026-11-02 01:46:22.134907+05	1287	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001a	Foods Supper Club Night	Family buffet and karahi corner — demo edition	Mock chef tasting at Foods Inn (SMCHS). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000006	bbbbbbbb-0000-4000-8000-000000000009	assets/images/dish_brunch.png	{}	2026-09-24 19:00:00+05	2026-09-24 22:00:00+05	180	27	12	4500.00	tasting	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{buffet,family,festival}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001a,dddddddd-0000-4000-8000-00000000001b,dddddddd-0000-4000-8000-00000000001c,dddddddd-0000-4000-8000-00000000001d,dddddddd-0000-4000-8000-00000000001e}	completed	2026-11-02 01:46:22.134907+05	1592	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001e	The Long Table Session	Garden dining with old-city charm — demo edition	Mock food festival at The East End (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-00000000000a	bbbbbbbb-0000-4000-8000-00000000000a	assets/images/venue_interior.png	{}	2026-12-03 19:00:00+05	2026-12-03 22:00:00+05	180	26	8	12000.00	festival	public	buffet	{"Welcome drink","Shared plates",Dessert}	{heritage,garden,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000002e,dddddddd-0000-4000-8000-00000000002f,dddddddd-0000-4000-8000-000000000030,dddddddd-0000-4000-8000-000000000032}	confirmed	2026-11-02 01:46:22.134907+05	798	f	t	\N	\N		{}
\.


--
-- Data for Name: email_change_challenges; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.email_change_challenges (user_id, new_email, code_hash, expires_at, created_at) FROM stdin;
\.


--
-- Data for Name: feedback; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.feedback (id, user_id, category, subject, description, related_ref, status, ticket, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: follows; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.follows (follower_id, followee_id, created_at) FROM stdin;
11111111-1111-1111-1111-111111111111	22222222-2222-2222-2222-222222222222	2026-11-02 01:46:02.982356+05
dddddddd-0000-4000-8000-000000000001	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000001	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000002	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000002	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000003	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000003	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000004	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000004	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000005	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000005	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000006	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000006	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000007	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000007	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000008	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000008	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000009	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000009	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000a	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000a	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000b	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000b	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000c	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000c	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000d	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000d	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000e	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000e	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000f	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000000f	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000010	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000010	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000011	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000011	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000012	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000012	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000013	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000013	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000014	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000014	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000015	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000015	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000016	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000016	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000017	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000017	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000018	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000018	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000019	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000019	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001a	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001a	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001b	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001b	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001c	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001c	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001d	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001d	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001e	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001e	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001f	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000001f	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000020	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000020	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000021	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000021	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000022	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000022	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000023	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000023	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000024	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000024	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000025	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000025	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000026	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000026	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000027	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000027	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000028	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000028	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000029	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000029	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002a	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002a	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002b	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002b	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002c	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002c	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002d	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002d	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002e	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002e	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002f	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000002f	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000030	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000030	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000031	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000031	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000032	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000032	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000033	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000033	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000034	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000034	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000035	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000035	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000036	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000036	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000037	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000037	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000038	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000038	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000039	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000039	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003a	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003a	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003b	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003b	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003c	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003c	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003d	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003d	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003e	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003e	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003f	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000003f	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000040	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000040	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000041	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000041	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000042	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000042	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000043	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000043	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000044	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000044	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000045	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000045	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000046	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000046	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000047	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000047	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000048	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000048	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000049	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000049	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004a	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004a	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004b	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004b	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004c	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004c	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004d	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004d	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004e	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004e	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004f	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000004f	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000050	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000050	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000051	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000051	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000052	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000052	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000053	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000053	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000054	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000054	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000055	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000055	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000056	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000056	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000057	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000057	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000058	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000058	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000059	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000059	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005a	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005a	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005b	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005b	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005c	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005c	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005d	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005d	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005e	ffffffff-0000-4000-8000-000000000004	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005e	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005f	ffffffff-0000-4000-8000-000000000005	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-00000000005f	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000060	ffffffff-0000-4000-8000-000000000006	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000060	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000061	ffffffff-0000-4000-8000-000000000007	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000061	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000062	ffffffff-0000-4000-8000-000000000008	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000062	ffffffff-0000-4000-8000-000000000001	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000063	ffffffff-0000-4000-8000-000000000009	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000063	ffffffff-0000-4000-8000-000000000002	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000064	ffffffff-0000-4000-8000-00000000000a	2026-11-02 01:46:22.381134+05
dddddddd-0000-4000-8000-000000000064	ffffffff-0000-4000-8000-000000000003	2026-11-02 01:46:22.381134+05
\.


--
-- Data for Name: menu_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.menu_items (id, event_id, "position", name, description, pairing, signature) FROM stdin;
3dd1c952-dfec-4890-b13a-bdb0aa5d3365	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	0	Chilled dashi	Spring vegetables, yuzu	\N	f
050610eb-44df-4f85-9205-02eb289ca410	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	1	Tuna and bottarga	House soy	Junmai daiginjo	t
0f51774c-1c2a-40f3-8594-0ea7435f4492	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	2	Aged rice, butter	Cured yolk	Junmai	f
9fb4bbed-51ac-4379-a291-87c488b087e6	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	0	Focaccia	Rosemary, olive oil	\N	f
55daab6f-6a2f-45ad-8bc6-9d561a57aeab	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	1	Carbonara	Guanciale, pecorino	Albana	t
02410342-d98d-491d-9116-ba8b8b863aa2	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	0	Beef tartare	Capers, egg yolk	Beaujolais	f
e8533988-c779-4e13-90e4-fa4049eb9708	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	1	Ravioli du jour	Brown butter, sage	Cote du Rhone	t
865798ae-ed83-4df5-9cea-9c495ff119f6	cccccccc-0000-4000-8000-000000000001	0	Chicken tikka platter	Mock menu line for the test edition	Soft drink	t
a618bc90-223c-4622-a8fb-49b260d86fad	cccccccc-0000-4000-8000-000000000001	1	Seekh kebab basket	Mock menu line for the test edition	\N	f
c2ffd7a7-c7ac-4e33-85e6-5cb9de15cdba	cccccccc-0000-4000-8000-000000000002	0	Mutton karahi	Mock menu line for the test edition	Mint lemonade	t
d1ee8cfe-bd20-4ca5-8338-8a10bb2bf700	cccccccc-0000-4000-8000-000000000002	1	Sindhi biryani	Mock menu line for the test edition	Soft drink	f
b92847c2-7257-4526-9456-8f42718ac626	cccccccc-0000-4000-8000-000000000003	0	Kheem palak	Mock menu line for the test edition	Mint lemonade	t
dce34f45-4025-45b0-9152-f82a7278478e	cccccccc-0000-4000-8000-000000000003	1	Naan & dips basket	Mock menu line for the test edition	Soft drink	f
82c2f81a-239d-4c70-99e9-ac522e831175	cccccccc-0000-4000-8000-000000000004	0	Bun kebab	Mock menu line for the test edition	\N	t
5166709b-c04c-4666-9dd0-72513fb8e373	cccccccc-0000-4000-8000-000000000004	1	Dumba pullao	Mock menu line for the test edition	Masala chai	f
bbc2faa8-5de8-45b9-bdf2-5964f91794e1	cccccccc-0000-4000-8000-000000000005	0	Gulab jamun	Mock menu line for the test edition	\N	t
c270c74c-d5dc-4212-8afb-ef696e6589fc	cccccccc-0000-4000-8000-000000000005	1	Kheer	Mock menu line for the test edition	Soft drink	f
ba720c74-cf2c-43d2-acd1-84b7f5dfae23	cccccccc-0000-4000-8000-000000000006	0	Grilled prawns	Mock menu line for the test edition	Masala chai	t
6bb8c033-72e4-418c-bf95-5bcfb874b921	cccccccc-0000-4000-8000-000000000006	1	Chapli kebab	Mock menu line for the test edition	Lassi	f
8411a640-a765-4451-b839-4c4361168c8a	cccccccc-0000-4000-8000-000000000007	0	Paneer butter masala	Mock menu line for the test edition	Lassi	t
c8bb0156-7e27-44e2-a19e-4ec7d5ef4d2e	cccccccc-0000-4000-8000-000000000007	1	Slow-cooked nihari	Mock menu line for the test edition	Masala chai	f
01f34937-291e-4025-ac7a-65471fbd747d	cccccccc-0000-4000-8000-000000000008	0	Chocolate fondant	Mock menu line for the test edition	Masala chai	t
7d897361-cd4e-437e-9b52-d94b9643a570	cccccccc-0000-4000-8000-000000000008	1	Masala chai & mithai	Mock menu line for the test edition	\N	f
e00ce0fa-d24c-48e7-b047-b124a1a04baa	cccccccc-0000-4000-8000-000000000009	0	Chicken tikka platter	Mock menu line for the test edition	\N	t
5bb5c2b3-6499-4774-b579-ffe2f5d814cb	cccccccc-0000-4000-8000-000000000009	1	Seekh kebab basket	Mock menu line for the test edition	Soft drink	f
9451ca45-0861-4343-b8a7-edf88647b0a4	cccccccc-0000-4000-8000-00000000000a	0	Mutton karahi	Mock menu line for the test edition	Soft drink	t
de17d4db-f21d-434c-b84a-7b7906b6285c	cccccccc-0000-4000-8000-00000000000a	1	Sindhi biryani	Mock menu line for the test edition	Lassi	f
db0866d8-6306-4ace-bcda-168c06dac871	cccccccc-0000-4000-8000-00000000000b	0	Kheem palak	Mock menu line for the test edition	Mint lemonade	t
4b2f5d20-16a3-464e-b832-c59ca7f18cd3	cccccccc-0000-4000-8000-00000000000b	1	Naan & dips basket	Mock menu line for the test edition	\N	f
2bf5efff-0d50-4796-bc8f-cc9923263343	cccccccc-0000-4000-8000-00000000000c	0	Bun kebab	Mock menu line for the test edition	Masala chai	t
262fcdc2-7343-4a91-8164-89c678d9e15a	cccccccc-0000-4000-8000-00000000000c	1	Dumba pullao	Mock menu line for the test edition	Mint lemonade	f
7b21594f-b167-42d9-901f-9d9f5a499da8	cccccccc-0000-4000-8000-00000000000d	0	Gulab jamun	Mock menu line for the test edition	Lassi	t
c3c49913-a557-453b-9edd-008595094220	cccccccc-0000-4000-8000-00000000000d	1	Kheer	Mock menu line for the test edition	Lassi	f
942b5059-d9b1-4b77-b5fd-d75d2edc7c8a	cccccccc-0000-4000-8000-00000000000e	0	Grilled prawns	Mock menu line for the test edition	Lassi	t
082f386c-1226-4825-bffd-4879196c4c91	cccccccc-0000-4000-8000-00000000000e	1	Chapli kebab	Mock menu line for the test edition	Mint lemonade	f
317c965b-2e5f-438e-8030-98572b30f2bf	cccccccc-0000-4000-8000-00000000000f	0	Paneer butter masala	Mock menu line for the test edition	Soft drink	t
f07cd080-a061-4b91-9cc1-62073c9290f8	cccccccc-0000-4000-8000-00000000000f	1	Slow-cooked nihari	Mock menu line for the test edition	Soft drink	f
03743c65-d9b8-4366-a859-dc29dade946a	cccccccc-0000-4000-8000-000000000010	0	Chocolate fondant	Mock menu line for the test edition	Soft drink	t
cafcaf3b-8f34-4af7-b80b-2dbeda389ced	cccccccc-0000-4000-8000-000000000010	1	Masala chai & mithai	Mock menu line for the test edition	Lassi	f
239a9d64-73d0-4a61-96f3-ee2f6ce95130	cccccccc-0000-4000-8000-000000000011	0	Chicken tikka platter	Mock menu line for the test edition	\N	t
e0ed9ba6-a0c3-4336-affd-f38310af5dff	cccccccc-0000-4000-8000-000000000011	1	Seekh kebab basket	Mock menu line for the test edition	Soft drink	f
c08fac66-3073-4185-bed6-14ca64afb906	cccccccc-0000-4000-8000-000000000012	0	Mutton karahi	Mock menu line for the test edition	\N	t
712d0c35-6d39-4ea7-aef4-872b8f39fe17	cccccccc-0000-4000-8000-000000000012	1	Sindhi biryani	Mock menu line for the test edition	Masala chai	f
6d531d3d-4d29-45c6-a076-344f568f200c	cccccccc-0000-4000-8000-000000000013	0	Kheem palak	Mock menu line for the test edition	Soft drink	t
eb3387de-f0e7-4026-9bb3-1b6c7a15225e	cccccccc-0000-4000-8000-000000000013	1	Naan & dips basket	Mock menu line for the test edition	Soft drink	f
ea56acda-7d14-4655-983e-15a34fbe7471	cccccccc-0000-4000-8000-000000000014	0	Bun kebab	Mock menu line for the test edition	Lassi	t
1934859a-afa6-4c4b-8850-abe636c59db0	cccccccc-0000-4000-8000-000000000014	1	Dumba pullao	Mock menu line for the test edition	Soft drink	f
af678a6c-2143-46f3-aace-58e185ba02c3	cccccccc-0000-4000-8000-000000000015	0	Gulab jamun	Mock menu line for the test edition	Soft drink	t
c493c080-eba9-4186-bf5a-a48e11205c99	cccccccc-0000-4000-8000-000000000015	1	Kheer	Mock menu line for the test edition	Masala chai	f
fe342617-9c2b-4a1d-adf9-820505fd0955	cccccccc-0000-4000-8000-000000000016	0	Grilled prawns	Mock menu line for the test edition	Lassi	t
f2857812-3e99-43d3-bc26-95fa34789bcf	cccccccc-0000-4000-8000-000000000016	1	Chapli kebab	Mock menu line for the test edition	\N	f
5bb0f267-c773-4253-98d1-bbc65b645a9d	cccccccc-0000-4000-8000-000000000017	0	Paneer butter masala	Mock menu line for the test edition	Masala chai	t
f5043419-9494-4200-9139-c8174bffaf55	cccccccc-0000-4000-8000-000000000017	1	Slow-cooked nihari	Mock menu line for the test edition	Masala chai	f
e72f527d-c69a-4cf3-89a3-221a96530ab1	cccccccc-0000-4000-8000-000000000018	0	Chocolate fondant	Mock menu line for the test edition	\N	t
ce396828-5279-4428-93ce-c65033256b2d	cccccccc-0000-4000-8000-000000000018	1	Masala chai & mithai	Mock menu line for the test edition	Lassi	f
db4592c4-d0f6-4081-99d1-6f0304ed02cb	cccccccc-0000-4000-8000-000000000019	0	Chicken tikka platter	Mock menu line for the test edition	\N	t
5cc1e989-9d82-4a57-b45a-e6c3ff5a25c2	cccccccc-0000-4000-8000-000000000019	1	Seekh kebab basket	Mock menu line for the test edition	Soft drink	f
55ace9c0-1af9-4e63-8631-f945d565eb54	cccccccc-0000-4000-8000-00000000001a	0	Mutton karahi	Mock menu line for the test edition	Mint lemonade	t
267e6952-7901-4c77-8c57-500e091b8003	cccccccc-0000-4000-8000-00000000001a	1	Sindhi biryani	Mock menu line for the test edition	\N	f
011d8387-578a-4080-beb1-32ba6edd44fa	cccccccc-0000-4000-8000-00000000001b	0	Kheem palak	Mock menu line for the test edition	\N	t
7c947042-e6a3-4e0d-a43d-7f8a05fbdf21	cccccccc-0000-4000-8000-00000000001b	1	Naan & dips basket	Mock menu line for the test edition	Mint lemonade	f
27390fa6-e102-4fca-bdf3-86e87f3ca6b7	cccccccc-0000-4000-8000-00000000001c	0	Bun kebab	Mock menu line for the test edition	\N	t
c87307bd-86bc-428b-bdd3-98fdd4125e55	cccccccc-0000-4000-8000-00000000001c	1	Dumba pullao	Mock menu line for the test edition	\N	f
f004ae8f-d3d3-46e5-b474-042a6d6edd40	cccccccc-0000-4000-8000-00000000001d	0	Gulab jamun	Mock menu line for the test edition	\N	t
62ed2c3f-0a37-4ce6-98d1-371c808567e0	cccccccc-0000-4000-8000-00000000001d	1	Kheer	Mock menu line for the test edition	Lassi	f
3cab9e45-ba12-4b6d-a417-3ef37eda1f76	cccccccc-0000-4000-8000-00000000001e	0	Grilled prawns	Mock menu line for the test edition	Lassi	t
04333ed8-b173-4402-8e78-828a8f972af4	cccccccc-0000-4000-8000-00000000001e	1	Chapli kebab	Mock menu line for the test edition	Mint lemonade	f
\.


--
-- Data for Name: message_read_receipts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.message_read_receipts (message_id, user_id, read_at) FROM stdin;
\.


--
-- Data for Name: notifications; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.notifications (id, restaurant_id, title, body, category, read, icon, tint, notification_time) FROM stdin;
a8ab7c1f-bfd0-4230-ac52-e1707d3ae8ed	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	New booking	2 seats booked for Omakase Under the Stars	booking	f	calendar	C26B4E	2026-11-01 09:30:00+05
df648625-ad6c-483c-8294-b4c1f365c578	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Payout scheduled	A 720 EUR payout for Cellar Supper is processing	payout	t	wallet	4A7A5A	2026-11-01 09:00:00+05
b8002e97-65cb-489b-9378-06dd387dd9d1	bbbbbbbb-0000-4000-8000-000000000001	New demo booking	2 seats on Seaside BBQ Dinner (mock payment).	booking	f	calendar	C26B4E	2026-11-01 09:30:00+05
3df4cc13-5796-480e-858e-144151038b07	bbbbbbbb-0000-4000-8000-00000000000a	Heritage night preview	Test event views are climbing for Karachi Heritage Tasting.	general	t	eye	4A5A7A	2026-10-30 18:00:00+05
ca472b00-e8aa-4ad0-af34-1452bdc6cdb6	bbbbbbbb-0000-4000-8000-000000000005	Candidate partnership	This listing is flagged unverified — awaiting venue contact.	partner	t	handshake	4A7A5A	2026-10-31 10:00:00+05
e428e6af-51c6-411f-9fd1-7f2928d3fcc5	bbbbbbbb-0000-4000-8000-000000000001	New table reservation	QA Mobile requested a table for 2 (2026-11-06T19:00:00.000Z).	reservation	f	\N	\N	2026-11-04 17:39:53.430146+05
c5075580-953b-4875-a72b-fd1b43c95876	bbbbbbbb-0000-4000-8000-000000000001	New table reservation	QA Api requested a table for 2 (2026-11-10T14:00:00.000Z).	reservation	f	\N	\N	2026-11-04 17:46:49.236217+05
\.


--
-- Data for Name: otp_codes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.otp_codes (phone, code, expires_at, created_at, code_hash, attempts) FROM stdin;
\.


--
-- Data for Name: partner_subscriptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partner_subscriptions (id, restaurant_id, plan, status, price_pkr, period_start, period_end, auto_renew, cancelled_at, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: partner_verification_requests; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partner_verification_requests (id, restaurant_id, requested_by, status, note, reviewer_note, reviewed_by, reviewed_at, created_at) FROM stdin;
\.


--
-- Data for Name: payouts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payouts (id, event_id, payout_date, seats_sold, gross, commission, status, created_at) FROM stdin;
f667525e-ab8a-4a4b-9a2c-eaa22f1111a4	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	2026-10-25 10:00:00+05	10	720.00	72.00	paid	2026-11-02 01:46:02.954409+05
a282b9ea-335a-466a-8061-f30141a29a33	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	2026-11-04 10:00:00+05	3	285.00	28.50	scheduled	2026-11-02 01:46:02.954409+05
4f568006-1d71-45be-996e-3de11d165954	cccccccc-0000-4000-8000-000000000001	2026-10-22 10:00:00+05	14	77000.00	7700.00	paid	2026-11-02 01:46:22.368067+05
21b357b8-319f-457a-9a8f-35d5bde94424	cccccccc-0000-4000-8000-000000000002	2026-10-21 10:00:00+05	8	52000.00	5200.00	processing	2026-11-02 01:46:22.368067+05
3d4b529e-8443-43e6-bbed-90cfbf565b88	cccccccc-0000-4000-8000-000000000006	2026-10-17 10:00:00+05	10	75000.00	7500.00	processing	2026-11-02 01:46:22.368067+05
dd8c022a-6290-42f2-8919-5b34df30deb5	cccccccc-0000-4000-8000-000000000007	2026-10-16 10:00:00+05	14	182000.00	18200.00	paid	2026-11-02 01:46:22.368067+05
fe292454-dbf3-4490-a882-23272b5b148e	cccccccc-0000-4000-8000-00000000000b	2026-10-12 10:00:00+05	12	162000.00	16200.00	paid	2026-11-02 01:46:22.368067+05
118dd6ea-c7bb-4c0d-b3f1-9ef1354bff1a	cccccccc-0000-4000-8000-00000000000c	2026-10-11 10:00:00+05	15	60000.00	6000.00	processing	2026-11-02 01:46:22.368067+05
3dd48711-de0d-4f89-9886-38977a032c6a	cccccccc-0000-4000-8000-000000000010	2026-10-07 10:00:00+05	10	105000.00	10500.00	processing	2026-11-02 01:46:22.368067+05
4ff73f66-e6aa-4ef8-a499-c1dcd189f189	cccccccc-0000-4000-8000-000000000011	2026-10-06 10:00:00+05	11	66000.00	6600.00	paid	2026-11-02 01:46:22.368067+05
2f6239c4-573c-404c-862a-62575a143198	cccccccc-0000-4000-8000-000000000015	2026-10-02 10:00:00+05	16	176000.00	17600.00	paid	2026-11-02 01:46:22.368067+05
67355967-13d7-4dfc-8346-00c2136b89ba	cccccccc-0000-4000-8000-000000000016	2026-10-01 10:00:00+05	14	84000.00	8400.00	processing	2026-11-02 01:46:22.368067+05
793b3bb0-65ac-4537-bf7e-a89efa66deed	cccccccc-0000-4000-8000-00000000001a	2026-09-27 10:00:00+05	12	54000.00	5400.00	processing	2026-11-02 01:46:22.368067+05
6c17dfdf-fb79-4d47-93fc-6c172ed328e8	cccccccc-0000-4000-8000-00000000001b	2026-09-26 10:00:00+05	13	104000.00	10400.00	paid	2026-11-02 01:46:22.368067+05
\.


--
-- Data for Name: promo_codes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.promo_codes (code, discount_pct, active, created_at) FROM stdin;
FOODIE5	5.00	t	2026-11-02 01:46:02.993107+05
WELCOME10	10.00	t	2026-11-02 01:46:02.993107+05
DINE20	20.00	t	2026-11-02 01:46:02.993107+05
VIP15	15.00	t	2026-11-02 01:46:02.993107+05
EXPIRED0	50.00	f	2026-11-02 01:46:02.993107+05
\.


--
-- Data for Name: qr_scans; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.qr_scans (id, restaurant_id, branch_id, kind, scanned_at, device_hash) FROM stdin;
12f516cf-a68e-4cc3-961c-25b301662355	bbbbbbbb-0000-4000-8000-000000000001	\N	menu	2026-11-04 17:32:45.141535+05	eff8e7ca506627fe15dda5e0e512fcaad70b6d520f37cc76597fdb4f2d83a1a3
\.


--
-- Data for Name: refunds; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.refunds (id, booking_id, event_id, guest_id, amount, reason, status, gateway_status, policy, stripe_refund_id, created_at) FROM stdin;
\.


--
-- Data for Name: reports; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reports (id, reporter_id, target_type, target_id, reason, description, evidence, status, reference, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: restaurant_branches; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_branches (id, restaurant_id, name, address, area, city, phone, latitude, longitude, is_primary, accepting_reservations, opening_hours, created_at, updated_at, timezone) FROM stdin;
00000000-0000-4000-8000-000000000001	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Skyline Rooftop	12 Quai Saint-Antoine	5th Arr.	Lyon	+15552220001	45.764	4.835	t	t	{"fri": {"windows": [{"open": "17:00", "close": "23:30"}]}, "mon": {"windows": [{"open": "18:00", "close": "23:00"}]}, "sat": {"windows": [{"open": "12:00", "close": "23:30"}]}, "sun": {"windows": [{"open": "12:00", "close": "22:00"}]}, "thu": {"windows": [{"open": "18:00", "close": "23:00"}]}, "tue": {"windows": [{"open": "18:00", "close": "23:00"}]}, "wed": {"windows": [{"open": "18:00", "close": "23:00"}]}}	2026-11-02 01:46:03.042867+05	2026-11-02 01:46:03.042867+05	Europe/Paris
00000000-0000-4000-8000-000000000002	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	Trattoria Nord	4 Place des Cordeliers	2nd Arr.	Lyon	+15552220002	45.762	4.832	t	t	{"fri": {"windows": [{"open": "12:00", "close": "22:00"}]}, "mon": {"closed": true}, "sat": {"windows": [{"open": "12:00", "close": "22:00"}]}, "sun": {"windows": [{"open": "12:00", "close": "21:00"}]}, "thu": {"windows": [{"open": "12:00", "close": "22:00"}]}, "tue": {"windows": [{"open": "12:00", "close": "22:00"}]}, "wed": {"windows": [{"open": "12:00", "close": "22:00"}]}}	2026-11-02 01:46:03.042867+05	2026-11-02 01:46:03.042867+05	Europe/Paris
\.


--
-- Data for Name: restaurant_deals; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_deals (id, restaurant_id, title, description, kind, value, code, starts_at, ends_at, max_redemptions, redemptions, status, created_at, updated_at) FROM stdin;
33333333-0000-4000-8000-000000000001	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Sunset hour -20%	Twenty percent off all starters between 18:00 and 19:00.	percent	20.00	SUNSET20	2026-11-01 18:00:00+05	2026-12-02 23:00:00+05	200	12	active	2026-11-02 01:46:03.079497+05	2026-11-02 01:46:03.079497+05
9e5cf40b-76ef-4b1b-8548-576d5fa16908	bbbbbbbb-0000-4000-8000-000000000001	Weekend Family Platter -15%	Fifteen percent off sharing platters every weekend.	percent	15.00	KOLACHI15	2026-11-04 17:30:12.453237+05	2026-12-04 17:30:12.453237+05	\N	0	active	2026-11-04 17:30:12.453237+05	2026-11-04 17:30:12.453237+05
9a66381f-1501-409b-9bb7-dc82f4e676ec	bbbbbbbb-0000-4000-8000-000000000002	Lunch Fixed Deal	Two mains + drinks for a fixed price at lunch.	fixed	500.00	XANDER500	2026-11-04 17:30:12.453237+05	2026-12-04 17:30:12.453237+05	\N	0	active	2026-11-04 17:30:12.453237+05	2026-11-04 17:30:12.453237+05
\.


--
-- Data for Name: restaurant_menu_items; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_menu_items (id, restaurant_id, section_id, name, description, price, "position", is_available, dietary_tags, photo_url, created_at, updated_at) FROM stdin;
72d77711-04e2-4c2b-bde5-6b3fed157249	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	22222222-0000-4000-8000-000000000001	Burrata & heirloom tomato	Basil oil, sourdough crumb	14.00	0	t	{vegetarian}	assets/images/dish_brunch.png	2026-11-02 01:46:03.071328+05	2026-11-02 01:46:03.071328+05
53c8b598-2b2a-4235-875d-86b93516e47c	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	22222222-0000-4000-8000-000000000001	Charred octopus	Smoked paprika, salsa verde	19.00	1	t	{gluten-free}	assets/images/dish_tacos.png	2026-11-02 01:46:03.071328+05	2026-11-02 01:46:03.071328+05
5c02c3d1-fbd0-4924-8eba-ce977fbd15e2	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	22222222-0000-4000-8000-000000000002	Dry-aged ribeye	Bone marrow butter, confit garlic	42.00	0	t	{}	assets/images/dish_steak.png	2026-11-02 01:46:03.071328+05	2026-11-02 01:46:03.071328+05
b6d9d94d-9b3a-4802-9668-2c7f455d1785	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	22222222-0000-4000-8000-000000000002	Wild mushroom risotto	Aged parmesan, truffle oil	26.00	1	t	{vegetarian}	assets/images/dish_pasta.png	2026-11-02 01:46:03.071328+05	2026-11-02 01:46:03.071328+05
\.


--
-- Data for Name: restaurant_menu_sections; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_menu_sections (id, restaurant_id, branch_id, name, "position", is_active, created_at, updated_at) FROM stdin;
22222222-0000-4000-8000-000000000001	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	Starters	0	t	2026-11-02 01:46:03.064979+05	2026-11-02 01:46:03.064979+05
22222222-0000-4000-8000-000000000002	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	Mains	1	t	2026-11-02 01:46:03.064979+05	2026-11-02 01:46:03.064979+05
\.


--
-- Data for Name: restaurant_payouts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_payouts (id, restaurant_id, period_start, period_end, gross, commission, net, status, created_at) FROM stdin;
e4638aa1-db90-48bf-865e-3a50f1fe5118	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	2026-10-02 00:00:00+05	2026-11-01 00:00:00+05	1980.00	198.00	1782.00	paid	2026-11-02 01:46:03.085743+05
\.


--
-- Data for Name: restaurant_staff; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_staff (user_id, restaurant_id, role, status, invited_by, created_at, updated_at) FROM stdin;
44444444-4444-4444-4444-444444444444	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	owner	active	\N	2026-11-02 01:46:03.036516+05	2026-11-02 01:46:03.036516+05
44444444-4444-4444-4444-444444444444	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	owner	active	\N	2026-11-02 01:46:03.036516+05	2026-11-02 01:46:03.036516+05
\.


--
-- Data for Name: restaurant_tables; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurant_tables (id, restaurant_id, branch_id, label, seats, zone, is_active, created_at, updated_at) FROM stdin;
11111111-0000-4000-8000-000000000001	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-01	8	Terrace	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000002	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-02	8	Terrace	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000003	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-03	8	Terrace	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000004	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-04	8	Terrace	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000005	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-05	8	Main	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000006	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-06	8	Main	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000007	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-07	6	Main	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000008	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	00000000-0000-4000-8000-000000000001	T-08	6	Main	t	2026-11-02 01:46:03.051069+05	2026-11-02 01:46:03.051069+05
11111111-0000-4000-8000-000000000015	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	00000000-0000-4000-8000-000000000002	T-01	6	Main	t	2026-11-02 01:46:03.060348+05	2026-11-02 01:46:03.060348+05
11111111-0000-4000-8000-000000000016	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	00000000-0000-4000-8000-000000000002	T-02	4	Main	t	2026-11-02 01:46:03.060348+05	2026-11-02 01:46:03.060348+05
4659894f-1264-48f8-a4cf-5ef2fd9d6eae	bbbbbbbb-0000-4000-8000-000000000001	\N	T1	2	Indoor	t	2026-11-04 17:34:02.576825+05	2026-11-04 17:34:02.576825+05
8d2ca2ca-0282-455a-86cb-3256c1908e52	bbbbbbbb-0000-4000-8000-000000000001	\N	T2	4	Indoor	t	2026-11-04 17:34:02.576825+05	2026-11-04 17:34:02.576825+05
bc5a4259-10f6-48db-815c-141de8454db2	bbbbbbbb-0000-4000-8000-000000000001	\N	S1	4	Seaside	t	2026-11-04 17:34:02.576825+05	2026-11-04 17:34:02.576825+05
655f555e-a708-4466-b418-5f70e5eaeb84	bbbbbbbb-0000-4000-8000-000000000001	\N	B1	6	BBQ Lawn	t	2026-11-04 17:34:02.576825+05	2026-11-04 17:34:02.576825+05
\.


--
-- Data for Name: restaurants; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.restaurants (id, owner_id, name, tagline, about, cuisines, neighborhood, address, city, phone, email, website, instagram, price_range, rating, review_count, seats, tables_count, since, owner_name, amenities, opening_hours, profile_completion, accepting_bookings, dine_circle_plus, cover_image, gallery, tags, is_partner, partner_perk, created_at, is_demo, partnership_status, latitude, longitude, requires_host_approval, verified_at, rejection_note, logo, facebook, twitter) FROM stdin;
aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	44444444-4444-4444-4444-444444444444	Skyline Rooftop	Golden-hour dining above the city	A plant-forward rooftop with panoramic views.	{Mediterranean,"Natural wine"}	5th Arr.	12 Quai Saint-Antoine	Lyon	+15552220001	hello@skyline.example	skyline.example	@skylinerooftop	$$$	4.70	214	60	18	2019	Marco Rossi	{Terrace,Bar,"Wheelchair access"}	{"Mon-Sun": "17:00-24:00"}	90	t	t	assets/images/venue_rooftop.png	{assets/images/venue_bar.png,assets/images/venue_interior.png}	{rooftop,views,dating}	t	Free welcome drink for DineCircle guests	2026-11-02 01:46:02.917891+05	t	verified	45.764	4.835	f	2026-11-02 01:46:03.026176+05				
aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	44444444-4444-4444-4444-444444444444	Trattoria Nord	Hand-rolled pasta, low candles	A family-run trattoria hidden off the market square.	{Italian,Pasta}	2nd Arr.	4 Place des Cordeliers	Lyon	+15552220002	ciao@trattoria.example	trattoria.example	@trattorianord	$$	4.55	96	40	14	2015	Marco Rossi	{Indoor,"Outdoor seating"}	{"Tue-Sun": "12:00-22:00"}	80	t	f	assets/images/venue_interior.png	{assets/images/venue_bar.png}	{italian,pasta,cozy}	t	\N	2026-11-02 01:46:02.917891+05	t	unverified	45.762	4.832	t	\N				
bbbbbbbb-0000-4000-8000-000000000002	aaaaaaaa-0000-4000-8000-000000000001	Xander's Clifton	Coffee-house classics, all day	Test listing: Xander's Clifton in Clifton is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Continental,Cafe,Brunch}	Clifton	Xander's Clifton, Clifton	Karachi	+922133500002	rest2.demo@example.test			$$	3.90	2140	119	15	2011	Xander's Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/venue_interior.png	{}	{brunch,cafe,meetup}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.8122	67.0332	f	\N				
bbbbbbbb-0000-4000-8000-000000000003	aaaaaaaa-0000-4000-8000-000000000001	Cafe Aylanto	Levantine courtyard dining	Test listing: Cafe Aylanto in Clifton is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Lebanese,Mediterranean}	Clifton	Cafe Aylanto, Clifton	Karachi	+922133500003	rest3.demo@example.test			$$$	4.10	1670	93	16	2002	Cafe Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/venue_bar.png	{}	{mediterranean,courtyard,date-night}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.816	67.028	f	\N				
bbbbbbbb-0000-4000-8000-000000000004	aaaaaaaa-0000-4000-8000-000000000001	Bar BQ Tonight Clifton	Flip-shop grill, late into the night	Test listing: Bar BQ Tonight Clifton in Boat Basin is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{BBQ,Pakistani}	Boat Basin	Bar BQ Tonight Clifton, Boat Basin	Karachi	+922133500004	rest4.demo@example.test			$$	4.30	2980	87	28	1996	Bar Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/dish_steak.png	{}	{bbq,late-night,casual}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.81	67.0255	f	\N				
bbbbbbbb-0000-4000-8000-000000000005	aaaaaaaa-0000-4000-8000-000000000001	Chef's Table Pakistan	Counter-side tasting by resident chefs	Test listing: Chef's Table Pakistan in DHA Phase 6 is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Fusion,Tasting}	DHA Phase 6	Chef's Table Pakistan, DHA Phase 6	Karachi	+922133500005	rest5.demo@example.test			$$$$	4.90	1120	88	18	2015	Chef's Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/hero_tasting.png	{}	{tasting,chef-counter,premium}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.798	67.055	f	\N				
bbbbbbbb-0000-4000-8000-000000000006	aaaaaaaa-0000-4000-8000-000000000001	The Carnivore Karachi	Fire-grilled premium cuts	Test listing: The Carnivore Karachi in DHA Phase 6 is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Grill,Steakhouse}	DHA Phase 6	The Carnivore Karachi, DHA Phase 6	Karachi	+922133500006	rest6.demo@example.test			$$$	4.70	1890	115	12	1992	The Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/dish_steak.png	{}	{grill,steak,date-night}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.7995	67.057	f	\N				
bbbbbbbb-0000-4000-8000-000000000007	aaaaaaaa-0000-4000-8000-000000000001	Dynasty	Saddar institution for Chinese-Karachi classics	Test listing: Dynasty in Saddar is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Chinese,"Dim Sum"}	Saddar	Dynasty, Saddar	Karachi	+922133500007	rest7.demo@example.test			$$	4.50	3410	143	12	2010	Dynasty Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/dish_sushi.png	{}	{chinese,family,heritage}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.8965	67.0245	f	\N				
bbbbbbbb-0000-4000-8000-000000000008	aaaaaaaa-0000-4000-8000-000000000001	Kanteen	Desi plates in a cantonment-heritage setting	Test listing: Kanteen in Tipu Sultan is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Pakistani,Desi}	Tipu Sultan	Kanteen, Tipu Sultan	Karachi	+922133500008	rest8.demo@example.test			$$	4.60	1450	158	17	2009	Kanteen Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/dish_pasta.png	{}	{desi,meetup,casual}	f	\N	2026-11-02 01:46:03.400412+05	t	unverified	24.8525	67.042	f	\N				
bbbbbbbb-0000-4000-8000-000000000009	aaaaaaaa-0000-4000-8000-000000000001	Foods Inn	Family buffet and karahi corner	Test listing: Foods Inn in SMCHS is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Pakistani,Buffet}	SMCHS	Foods Inn, SMCHS	Karachi	+922133500009	rest9.demo@example.test			$$	4.30	2260	92	22	2014	Foods Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/dish_brunch.png	{}	{buffet,family,festival}	f	\N	2026-11-02 01:46:03.400412+05	t	unverified	24.851	67.001	f	\N				
bbbbbbbb-0000-4000-8000-00000000000a	aaaaaaaa-0000-4000-8000-000000000001	The East End	Garden dining with old-city charm	Test listing: The East End in Clifton is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Continental,Heritage}	Clifton	The East End, Clifton	Karachi	+922133500010	rest10.demo@example.test			$$$	4.70	1980	41	20	2009	The Management	{"Indoor seating","Family section","VA parking"}	{}	65	t	f	assets/images/venue_interior.png	{}	{heritage,garden,date-night}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.8135	67.0195	f	\N				
bbbbbbbb-0000-4000-8000-000000000001	aaaaaaaa-0000-4000-8000-000000000001	Kolachi Restaurant	Sea-facing dining since 1989	Test listing: Kolachi Restaurant in DHA Phase 8 is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership — basics are public, everything else is mock data.	{Pakistani,Seafood,BBQ}	DHA Phase 8	Kolachi Restaurant, DHA Phase 8	Karachi	+922133500001	rest1.demo@example.test			$$$	4.50	3821	43	18	1994	Kolachi Management	{"Indoor seating","Family section","VA parking"}	{"fri": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "mon": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "sat": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "sun": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "thu": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "tue": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}, "wed": {"windows": [{"open": "12:00", "close": "15:00"}, {"open": "18:00", "close": "23:00"}]}}	65	t	f	assets/images/venue_rooftop.png	{}	{seaside,bbq,family}	t	\N	2026-11-02 01:46:03.400412+05	t	verified	24.8055	67.0305	f	\N				
\.


--
-- Data for Name: reviews; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.reviews (id, author_id, event_id, rating, text, created_at, restaurant_id, partner_reply, partner_replied_at) FROM stdin;
b708d0a6-7875-4681-8149-9bf46f4d0e04	11111111-1111-1111-1111-111111111111	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	5.00	Nora is a magician — best table I have sat at all year.	2026-10-26 15:00:00+05	\N	\N	\N
8de5be50-a4c6-4eda-a90f-dd444f2a6271	dddddddd-0000-4000-8000-000000000002	cccccccc-0000-4000-8000-000000000001	5.00	Long table, warm hosts, and the seekh kebab sold out early — already asking for a second edition.	2026-10-21 15:00:00+05	\N	\N	\N
68ae3f13-6f37-41c8-a1f7-4e48141ffc61	dddddddd-0000-4000-8000-000000000003	cccccccc-0000-4000-8000-000000000001	4.80	Smooth check-in at the door and the QR ticket worked first try.	2026-10-21 15:00:00+05	\N	\N	\N
35c47f94-3158-42c7-8c2c-a082398defa7	dddddddd-0000-4000-8000-000000000004	cccccccc-0000-4000-8000-000000000001	4.50	Great value for a demo ticket; portions were generous.	2026-10-21 15:00:00+05	\N	\N	\N
ef1ccbea-d015-4e3f-9644-89cddf4bcfa6	dddddddd-0000-4000-8000-000000000005	cccccccc-0000-4000-8000-000000000001	4.00	The hosting flow was flawless, though the dessert service ran late.	2026-10-21 15:00:00+05	\N	\N	\N
072c48b7-0462-4fa9-8583-79882eb8171b	dddddddd-0000-4000-8000-000000000006	cccccccc-0000-4000-8000-000000000002	4.90	Loved the crowd — half the table were followers, and everyone got along.	2026-10-20 15:00:00+05	\N	\N	\N
8312c40d-bf1f-4f93-8b11-39a1a3136401	dddddddd-0000-4000-8000-000000000007	cccccccc-0000-4000-8000-000000000002	3.80	Mock payment cleared instantly and the payout report matched to the rupee.	2026-10-20 15:00:00+05	\N	\N	\N
0d629f11-e5ca-41a3-8242-972f771a33fe	dddddddd-0000-4000-8000-000000000008	cccccccc-0000-4000-8000-000000000002	5.00	Seaside seating sold out fast; book earlier next time.	2026-10-20 15:00:00+05	\N	\N	\N
b7ba4e50-c7a9-4821-9e84-4ab1447b031c	dddddddd-0000-4000-8000-000000000009	cccccccc-0000-4000-8000-000000000002	4.80	The tasting course pacing was the best of the night.	2026-10-20 15:00:00+05	\N	\N	\N
831096c7-1639-417d-99d6-197379d9cb9c	dddddddd-0000-4000-8000-00000000000a	cccccccc-0000-4000-8000-000000000002	4.50	Family-friendly, high chairs available, booking took two taps.	2026-10-20 15:00:00+05	\N	\N	\N
402296ab-f036-4a83-9dc1-ebefe96e920c	dddddddd-0000-4000-8000-00000000001a	cccccccc-0000-4000-8000-000000000006	4.00	Heritage room was atmospheric; the photos practically took themselves.	2026-10-16 15:00:00+05	\N	\N	\N
866f47ee-80f8-465b-bc45-beec4ac2e668	dddddddd-0000-4000-8000-00000000001b	cccccccc-0000-4000-8000-000000000006	4.90	Brunch coffee refills kept coming. Solid meetup format.	2026-10-16 15:00:00+05	\N	\N	\N
5f4c6922-582d-432c-9559-73c0b9e86921	dddddddd-0000-4000-8000-00000000001c	cccccccc-0000-4000-8000-000000000006	3.80	Solid test run — a couple of plates arrived late, but the host comped round.	2026-10-16 15:00:00+05	\N	\N	\N
d19f457a-e5ca-471d-9a82-d762827cdfaf	dddddddd-0000-4000-8000-00000000001d	cccccccc-0000-4000-8000-000000000006	5.00	Long table, warm hosts, and the seekh kebab sold out early — already asking for a second edition.	2026-10-16 15:00:00+05	\N	\N	\N
47513157-0264-4c04-ae6e-d9fda2102740	dddddddd-0000-4000-8000-00000000001e	cccccccc-0000-4000-8000-000000000006	4.80	Smooth check-in at the door and the QR ticket worked first try.	2026-10-16 15:00:00+05	\N	\N	\N
f127647c-d762-438b-b14a-f16fdc82a7b5	dddddddd-0000-4000-8000-00000000001f	cccccccc-0000-4000-8000-000000000007	4.50	Great value for a demo ticket; portions were generous.	2026-10-15 15:00:00+05	\N	\N	\N
c816f9d7-fd29-4ac8-909b-e3e441f0f608	dddddddd-0000-4000-8000-000000000020	cccccccc-0000-4000-8000-000000000007	4.00	The hosting flow was flawless, though the dessert service ran late.	2026-10-15 15:00:00+05	\N	\N	\N
7d68b25d-4913-45d9-ad35-3e7893339a57	dddddddd-0000-4000-8000-000000000021	cccccccc-0000-4000-8000-000000000007	4.90	Loved the crowd — half the table were followers, and everyone got along.	2026-10-15 15:00:00+05	\N	\N	\N
6186eca2-2681-4c43-a867-14797a3a1bb8	dddddddd-0000-4000-8000-000000000022	cccccccc-0000-4000-8000-000000000007	3.80	Mock payment cleared instantly and the payout report matched to the rupee.	2026-10-15 15:00:00+05	\N	\N	\N
910c5e9d-ecaf-4ac9-9f98-c70faf3db00e	dddddddd-0000-4000-8000-000000000023	cccccccc-0000-4000-8000-000000000007	5.00	Seaside seating sold out fast; book earlier next time.	2026-10-15 15:00:00+05	\N	\N	\N
5f06e296-4e8a-4f59-a0ed-43383014b33f	dddddddd-0000-4000-8000-000000000033	cccccccc-0000-4000-8000-00000000000b	4.80	The tasting course pacing was the best of the night.	2026-10-11 15:00:00+05	\N	\N	\N
a328df11-228e-4551-9512-6d6f80d2e2a4	dddddddd-0000-4000-8000-000000000034	cccccccc-0000-4000-8000-00000000000b	4.50	Family-friendly, high chairs available, booking took two taps.	2026-10-11 15:00:00+05	\N	\N	\N
40026732-3d78-4af4-892e-055fdfa84e91	dddddddd-0000-4000-8000-000000000035	cccccccc-0000-4000-8000-00000000000b	4.00	Heritage room was atmospheric; the photos practically took themselves.	2026-10-11 15:00:00+05	\N	\N	\N
0ae4ef8a-a974-4399-93ac-c1b883c70a94	dddddddd-0000-4000-8000-000000000036	cccccccc-0000-4000-8000-00000000000b	4.90	Brunch coffee refills kept coming. Solid meetup format.	2026-10-11 15:00:00+05	\N	\N	\N
aefc5f62-a20c-411e-baa7-3d52d966bc01	dddddddd-0000-4000-8000-000000000037	cccccccc-0000-4000-8000-00000000000b	3.80	Solid test run — a couple of plates arrived late, but the host comped round.	2026-10-11 15:00:00+05	\N	\N	\N
de45e791-6d36-41d5-8c63-2e2067ed0486	dddddddd-0000-4000-8000-000000000038	cccccccc-0000-4000-8000-00000000000c	5.00	Long table, warm hosts, and the seekh kebab sold out early — already asking for a second edition.	2026-10-10 15:00:00+05	\N	\N	\N
2a48fbfc-9384-4769-8715-2778705f269b	dddddddd-0000-4000-8000-000000000039	cccccccc-0000-4000-8000-00000000000c	4.80	Smooth check-in at the door and the QR ticket worked first try.	2026-10-10 15:00:00+05	\N	\N	\N
8e86d424-7515-4f94-a600-1cddeb9e1968	dddddddd-0000-4000-8000-00000000003a	cccccccc-0000-4000-8000-00000000000c	4.50	Great value for a demo ticket; portions were generous.	2026-10-10 15:00:00+05	\N	\N	\N
09843864-7a68-4410-8ce1-3b93f9482903	dddddddd-0000-4000-8000-00000000003b	cccccccc-0000-4000-8000-00000000000c	4.00	The hosting flow was flawless, though the dessert service ran late.	2026-10-10 15:00:00+05	\N	\N	\N
85e3b8ca-1547-4a9a-8c7c-e1ed3046d008	dddddddd-0000-4000-8000-00000000003c	cccccccc-0000-4000-8000-00000000000c	4.90	Loved the crowd — half the table were followers, and everyone got along.	2026-10-10 15:00:00+05	\N	\N	\N
6c6666e6-c7aa-4756-ac9b-61c43e3176fc	dddddddd-0000-4000-8000-00000000004c	cccccccc-0000-4000-8000-000000000010	3.80	Mock payment cleared instantly and the payout report matched to the rupee.	2026-10-06 15:00:00+05	\N	\N	\N
75e12467-d101-41a8-99f0-3a2fb0c30015	dddddddd-0000-4000-8000-00000000004d	cccccccc-0000-4000-8000-000000000010	5.00	Seaside seating sold out fast; book earlier next time.	2026-10-06 15:00:00+05	\N	\N	\N
d73b9c44-152f-4d87-86cc-e7a769410d9f	dddddddd-0000-4000-8000-00000000004e	cccccccc-0000-4000-8000-000000000010	4.80	The tasting course pacing was the best of the night.	2026-10-06 15:00:00+05	\N	\N	\N
8b40352f-7b64-4b49-9a98-a7e5488a8b4a	dddddddd-0000-4000-8000-00000000004f	cccccccc-0000-4000-8000-000000000010	4.50	Family-friendly, high chairs available, booking took two taps.	2026-10-06 15:00:00+05	\N	\N	\N
d8be0737-8a0f-48de-8757-1425f3b65dc2	dddddddd-0000-4000-8000-000000000050	cccccccc-0000-4000-8000-000000000010	4.00	Heritage room was atmospheric; the photos practically took themselves.	2026-10-06 15:00:00+05	\N	\N	\N
4b830f4d-dc53-4a91-beb1-96e042409fb0	dddddddd-0000-4000-8000-000000000051	cccccccc-0000-4000-8000-000000000011	4.90	Brunch coffee refills kept coming. Solid meetup format.	2026-10-05 15:00:00+05	\N	\N	\N
d2ec0730-b76c-48ed-878d-78ff87b964ca	dddddddd-0000-4000-8000-000000000052	cccccccc-0000-4000-8000-000000000011	3.80	Solid test run — a couple of plates arrived late, but the host comped round.	2026-10-05 15:00:00+05	\N	\N	\N
e60da878-e381-4a45-877c-9c5227187cc7	dddddddd-0000-4000-8000-000000000053	cccccccc-0000-4000-8000-000000000011	5.00	Long table, warm hosts, and the seekh kebab sold out early — already asking for a second edition.	2026-10-05 15:00:00+05	\N	\N	\N
5b491d05-d8fd-4e12-aa61-7437b2432427	dddddddd-0000-4000-8000-000000000054	cccccccc-0000-4000-8000-000000000011	4.80	Smooth check-in at the door and the QR ticket worked first try.	2026-10-05 15:00:00+05	\N	\N	\N
d029cdad-973d-4f7b-9af7-24b11469bc5d	dddddddd-0000-4000-8000-000000000055	cccccccc-0000-4000-8000-000000000011	4.50	Great value for a demo ticket; portions were generous.	2026-10-05 15:00:00+05	\N	\N	\N
538ab013-ee6d-4744-b10e-3db38fb15962	dddddddd-0000-4000-8000-000000000001	cccccccc-0000-4000-8000-000000000015	4.00	The hosting flow was flawless, though the dessert service ran late.	2026-10-01 15:00:00+05	\N	\N	\N
e59a7ae5-20fc-4cd8-bb23-97b4fc771700	dddddddd-0000-4000-8000-000000000002	cccccccc-0000-4000-8000-000000000015	4.90	Loved the crowd — half the table were followers, and everyone got along.	2026-10-01 15:00:00+05	\N	\N	\N
76fba58e-4585-4807-a7dc-ac97992b262e	dddddddd-0000-4000-8000-000000000003	cccccccc-0000-4000-8000-000000000015	3.80	Mock payment cleared instantly and the payout report matched to the rupee.	2026-10-01 15:00:00+05	\N	\N	\N
e2644f02-d5fe-44e0-a031-6d5fc706ef0e	dddddddd-0000-4000-8000-000000000004	cccccccc-0000-4000-8000-000000000015	5.00	Seaside seating sold out fast; book earlier next time.	2026-10-01 15:00:00+05	\N	\N	\N
7be13bcf-488b-481a-ab62-606d5cc9ee2e	dddddddd-0000-4000-8000-000000000005	cccccccc-0000-4000-8000-000000000015	4.80	The tasting course pacing was the best of the night.	2026-10-01 15:00:00+05	\N	\N	\N
f6cb1eea-8f59-4178-a428-a3aa27c63b00	dddddddd-0000-4000-8000-000000000006	cccccccc-0000-4000-8000-000000000016	4.50	Family-friendly, high chairs available, booking took two taps.	2026-09-30 15:00:00+05	\N	\N	\N
6ba43bf6-7c5f-41c6-abfa-00f1fce0b337	dddddddd-0000-4000-8000-000000000007	cccccccc-0000-4000-8000-000000000016	4.00	Heritage room was atmospheric; the photos practically took themselves.	2026-09-30 15:00:00+05	\N	\N	\N
c1a79c3e-0be6-47d6-8040-595706a456af	dddddddd-0000-4000-8000-000000000008	cccccccc-0000-4000-8000-000000000016	4.90	Brunch coffee refills kept coming. Solid meetup format.	2026-09-30 15:00:00+05	\N	\N	\N
96ea641a-d5d2-4380-b0e2-0a3e58cdc1ae	dddddddd-0000-4000-8000-000000000009	cccccccc-0000-4000-8000-000000000016	3.80	Solid test run — a couple of plates arrived late, but the host comped round.	2026-09-30 15:00:00+05	\N	\N	\N
51f9b838-d2e7-4f7e-9394-cc1712902c5e	dddddddd-0000-4000-8000-00000000000a	cccccccc-0000-4000-8000-000000000016	5.00	Long table, warm hosts, and the seekh kebab sold out early — already asking for a second edition.	2026-09-30 15:00:00+05	\N	\N	\N
971f161d-dd7c-4800-8aa2-af9e648cca46	dddddddd-0000-4000-8000-00000000001a	cccccccc-0000-4000-8000-00000000001a	4.80	Smooth check-in at the door and the QR ticket worked first try.	2026-09-26 15:00:00+05	\N	\N	\N
\.


--
-- Data for Name: saved_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.saved_events (user_id, event_id, created_at) FROM stdin;
11111111-1111-1111-1111-111111111111	eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	2026-11-02 01:46:02.987506+05
dddddddd-0000-4000-8000-000000000001	cccccccc-0000-4000-8000-000000000003	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000008	cccccccc-0000-4000-8000-000000000004	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000000f	cccccccc-0000-4000-8000-000000000005	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000016	cccccccc-0000-4000-8000-000000000008	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000001d	cccccccc-0000-4000-8000-000000000009	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000024	cccccccc-0000-4000-8000-00000000000a	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000002b	cccccccc-0000-4000-8000-00000000000d	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000032	cccccccc-0000-4000-8000-00000000000e	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000039	cccccccc-0000-4000-8000-00000000000f	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000040	cccccccc-0000-4000-8000-000000000012	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000047	cccccccc-0000-4000-8000-000000000013	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000004e	cccccccc-0000-4000-8000-000000000014	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000055	cccccccc-0000-4000-8000-000000000017	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000005c	cccccccc-0000-4000-8000-000000000018	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000063	cccccccc-0000-4000-8000-000000000019	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000006	cccccccc-0000-4000-8000-00000000001c	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000000d	cccccccc-0000-4000-8000-00000000001d	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000014	cccccccc-0000-4000-8000-00000000001e	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000001b	cccccccc-0000-4000-8000-000000000003	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000022	cccccccc-0000-4000-8000-000000000004	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000029	cccccccc-0000-4000-8000-000000000005	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000030	cccccccc-0000-4000-8000-000000000008	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000037	cccccccc-0000-4000-8000-000000000009	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000003e	cccccccc-0000-4000-8000-00000000000a	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000045	cccccccc-0000-4000-8000-00000000000d	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000004c	cccccccc-0000-4000-8000-00000000000e	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000053	cccccccc-0000-4000-8000-00000000000f	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000005a	cccccccc-0000-4000-8000-000000000012	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000061	cccccccc-0000-4000-8000-000000000013	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000004	cccccccc-0000-4000-8000-000000000014	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000000b	cccccccc-0000-4000-8000-000000000017	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000012	cccccccc-0000-4000-8000-000000000018	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000019	cccccccc-0000-4000-8000-000000000019	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000020	cccccccc-0000-4000-8000-00000000001c	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000027	cccccccc-0000-4000-8000-00000000001d	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000002e	cccccccc-0000-4000-8000-00000000001e	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000035	cccccccc-0000-4000-8000-000000000003	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000003c	cccccccc-0000-4000-8000-000000000004	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-000000000043	cccccccc-0000-4000-8000-000000000005	2026-11-02 01:46:22.404751+05
dddddddd-0000-4000-8000-00000000004a	cccccccc-0000-4000-8000-000000000008	2026-11-02 01:46:22.404751+05
\.


--
-- Data for Name: saved_locations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.saved_locations (id, user_id, kind, name, city, area, address, latitude, longitude, created_at) FROM stdin;
\.


--
-- Data for Name: special_menus; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.special_menus (id, restaurant_id, name, description, price_per_guest, min_guests, tags, cover_image, status, views_this_week, bookings_count, created_at) FROM stdin;
3cd8fbf6-4038-4bd4-8e6e-41525700708c	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	Chefs Tasting	Seven courses with optional pairing	110.00	2	{tasting,wine}	assets/images/dish_sushi.png	active	142	28	2026-11-02 01:46:03.01387+05
b5a4bdd2-f11f-4b1c-82c1-dd12bbeeace2	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	Pasta Lab	Make-and-eat for groups	65.00	4	{workshop,italian}	assets/images/dish_pasta.png	active	77	11	2026-11-02 01:46:03.01387+05
1d5ef0d7-d5f8-48c0-86a0-bc86626c376c	bbbbbbbb-0000-4000-8000-000000000001	Seaside BBQ Dinner Menu	Mock Pakistani package for the DHA Phase 8 test listing.	5000.00	2	{seaside,demo}	assets/images/venue_rooftop.png	active	43	6	2026-11-02 01:46:22.435275+05
63423562-d946-404a-9cc1-c639adde0e9a	bbbbbbbb-0000-4000-8000-000000000005	Chef's Tasting Experience Menu	Mock Fusion package for the DHA Phase 6 test listing.	13500.00	2	{tasting,demo}	assets/images/hero_tasting.png	active	70	1	2026-11-02 01:46:22.435275+05
00823c32-210b-4121-898e-73a093b7bd55	bbbbbbbb-0000-4000-8000-000000000006	Premium Meat Tasting Menu	Mock Grill package for the DHA Phase 6 test listing.	12500.00	2	{grill,demo}	assets/images/dish_steak.png	active	104	20	2026-11-02 01:46:22.435275+05
ba0b8f49-1499-490f-a3dd-85848042fc5a	bbbbbbbb-0000-4000-8000-00000000000a	Karachi Heritage Tasting Menu	Mock Continental package for the Clifton test listing.	4000.00	2	{heritage,demo}	assets/images/venue_interior.png	active	174	2	2026-11-02 01:46:22.435275+05
\.


--
-- Data for Name: stripe_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.stripe_events (id, type, received_at) FROM stdin;
\.


--
-- Data for Name: supported_cities; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.supported_cities (id, name, country, areas, lat, lng, active, created_at) FROM stdin;
779b6028-1a5b-4a64-a394-de9dd67955ac	Karachi	Pakistan	{DHA,Clifton,Gulshan-e-Iqbal,"North Nazimabad",PECHS,Gulistan-e-Johar,Bahadurabad,"Tariq Road"}	24.860700	67.001100	t	2026-11-02 01:46:03.091082+05
98502833-e3a9-4d37-b87b-5c7554f08e3f	Lahore	Pakistan	{DHA,Gulberg,"Model Town","Johar Town",Cantt,"Bahria Town"}	31.520400	74.358700	t	2026-11-02 01:46:03.091082+05
f1e7b19a-1e11-4955-acfa-7492ee96ba46	Islamabad	Pakistan	{F-6,F-7,F-8,F-10,F-11,G-9,G-10,G-11}	33.684400	73.047900	t	2026-11-02 01:46:03.091082+05
4721ecc9-4174-48cb-89c7-67c10dc20c1e	Rawalpindi	Pakistan	{"Satellite Town","Bahria Town"}	33.565100	73.016900	t	2026-11-02 01:46:03.091082+05
0fdec06b-33f2-4cb4-890d-d901a78baccb	Faisalabad	Pakistan	{D-Ground,"Peoples Colony"}	31.450400	73.135000	t	2026-11-02 01:46:03.091082+05
41419678-eae5-4978-bf63-9f82c7560b04	Multan	Pakistan	{Cantt,Gulgasht}	30.157500	71.524900	t	2026-11-02 01:46:03.091082+05
ad6fde71-52c1-43c6-a358-e7783734f520	Peshawar	Pakistan	{Hayatabad,"University Town"}	34.015100	71.524900	t	2026-11-02 01:46:03.091082+05
ee321976-ba99-4076-bf02-084053170e52	Hyderabad	Pakistan	{Latifabad,Qasimabad}	25.396000	68.357800	t	2026-11-02 01:46:03.091082+05
\.


--
-- Data for Name: table_reservations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.table_reservations (id, restaurant_id, branch_id, table_id, user_id, guest_name, guest_phone, party_size, start_at, duration_minutes, status, reference, notes, source, created_at, updated_at) FROM stdin;
6ec90b55-f9c1-42ba-be6f-1eaf4c3ab19f	bbbbbbbb-0000-4000-8000-000000000001	\N	\N	27e49df8-1635-47a2-a5b7-94b2433adf73	QA Mobile		2	2026-11-07 00:00:00+05	90	pending	TR-FABW5		customer	2026-11-04 17:39:53.402221+05	2026-11-04 17:39:53.402221+05
87832676-7034-4178-bc54-e2169f8f37d5	bbbbbbbb-0000-4000-8000-000000000001	\N	\N	a665a235-ddd1-408a-a637-125441c5f6ac	QA Api		2	2026-11-10 19:00:00+05	90	pending	TR-FJREH		customer	2026-11-04 17:46:49.204243+05	2026-11-04 17:46:49.204243+05
\.


--
-- Data for Name: user_avatars; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_avatars (user_id, content_type, byte_size, bytes, updated_at) FROM stdin;
\.


--
-- Data for Name: user_blocks; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_blocks (blocker_id, blocked_id, created_at) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, name, handle, phone, city, bio, role, followers_count, following_count, dinners_hosted, dinners_joined, rating, review_count, avatar_url, badges, tastes, accent_hex, joined_year, created_at, email, password_hash, instagram, is_demo, show_follow_list, show_activity, dm_from_followers_only, allow_tagging, dietary, allergies, home_area, is_deleted) FROM stdin;
a1873a4e-6eba-4ed7-83d0-913bb7855e3e	QA Tester	qa1793795003	\N	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#5A4A7A	2026	2026-11-04 17:23:24.026558+05	qa.1793795003.moved@test.local	scrypt:ba633c670e0405d5130fb0a27ee2fb86:d5af9d5cf606dcedbff46d5942e6a69f9f31c184f76e90e90badb8f74df1abc40280f32cb8a74d94806768e57f7a9c8cecdf458f41bfdd35b87db3394bdbf78c		f	t	t	f	t	{}	{}		f
76546a2a-1e74-4772-a075-d46ed0ad5053	QA Tester	qa1793795022	\N	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#5A4A7A	2026	2026-11-04 17:23:43.035063+05	qa.1793795022.moved@test.local	scrypt:f4419b286b8859d545c1eddeb5d768a5:d0a20b92dc514c2ff9781c67b64dc021b3cbf3e110b7acce85763245e57015eb418cff57f7014ddc8e134ed236d6953b49c71740cc94beecb0cf176af0bbb748		f	t	t	f	t	{}	{}		f
99427fa6-6c79-43c1-9b24-95292ad23640	Diner 5022	diner.5022tyg	+923001793795022	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#4A5A7A	2026	2026-11-04 17:23:46.143542+05	\N	\N		f	t	t	f	t	{}	{}		f
55555555-5555-5555-5555-555555555555	Dana Ops	dana.admin	\N	Lyon	Platform moderator.	super_admin	0	0	0	0	0.00	0	assets/images/portrait_6.png	{}	{}	#333333	2021	2026-11-02 01:46:02.909474+05	\N	\N		t	t	t	f	t	{}	{}		f
27e49df8-1635-47a2-a5b7-94b2433adf73	QA Mobile	qamobile1	\N	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#4A7A5A	2026	2026-11-04 17:28:27.55721+05	qa.mobile.1@test.local	scrypt:ebf6926555f5f8bc23e9284b1d634915:dc4031725169d8055992fe66c9623aad96fd78babc2aa6b422330ebdea813c9ef2d6b80815179cd84a26dd674596705f490383ca92d5260206f535c764c18a6b		f	t	t	f	t	{}	{}		f
a665a235-ddd1-408a-a637-125441c5f6ac	QA Api	qaapi1793796408	\N	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#7A6A4A	2026	2026-11-04 17:46:49.033146+05	qa.api.1793796408@test.local	scrypt:aecf3c03ba01d25864c0278c9d4a969d:173599044ae6e5b4ce6de681d9b1482002e919a195eb92ef1e624e50460a0bd30a415bdc3081e3781c584edc74f054a4ff62fa4715a71cfdd7546d3b2c589a0c		f	t	t	f	t	{}	{}		f
e8ef63b7-155f-4593-98f5-7573e7e35d5b	QA Env	qaenv1793796487	\N	Karachi		user	0	0	0	0	0.00	0	\N	{}	{}	#7A6A4A	2026	2026-11-04 17:48:07.572803+05	qa.env.1793796487@test.local	scrypt:a2c37f58f9691360d6b55bb92a52ffba:7ef6b6f34716955375fea003371fb1b7e56dc8d8a1a439f64de9973d41f009145f006c4c318b3741ab770d81e7ca4405a9973a6a93cb032c942237adf60fd952		f	t	t	f	t	{}	{}		f
11111111-1111-1111-1111-111111111111	Alex Morgan	alex.morgan	+15550001111	Lyon	Weekend foodie chasing long tables.	user	12	40	0	6	4.60	3	assets/images/portrait_1.png	{}	{Japanese,pasta,"natural wine"}	#4A5A7A	2024	2026-11-02 01:46:02.909474+05	\N	\N		t	t	t	f	t	{}	{}		f
22222222-2222-2222-2222-222222222222	Nora Feld	nora.hosts	+15550002222	Lyon	Host and chef. Six-seat suppers, seasonal menus.	host	820	34	42	3	4.90	118	assets/images/portrait_2.png	{"Top Host"}	{Tasting,wine}	#C26B4E	2022	2026-11-02 01:46:02.909474+05	\N	\N		t	t	t	f	t	{}	{}		f
33333333-3333-3333-3333-333333333333	Ava Chen	ava.eats	+15550003333	Lyon	Diner, photographer, dessert-first.	user	156	210	0	11	4.80	9	assets/images/portrait_3.png	{}	{dessert,brunch}	#7A4A6B	2023	2026-11-02 01:46:02.909474+05	\N	\N		t	t	t	f	t	{}	{}		f
44444444-4444-4444-4444-444444444444	Marco Rossi	marco.rooftop	+15550004444	Lyon	Partner manager for the Rooftop and Trattoria groups.	partner_admin	5	5	0	0	0.00	0	assets/images/portrait_5.png	{}	{}	#4A7A5A	2023	2026-11-02 01:46:02.909474+05	\N	\N		t	t	t	f	t	{}	{}		f
aaaaaaaa-0000-4000-8000-000000000001	Karachi Partners Desk	karachi.desk	+923450000001	Karachi	Candidate-partner desk for the Karachi test environment. Most listings are verified partners; a few remain unverified candidates.	partner_admin	0	0	0	0	0.00	0	\N	{}	{}	\N	2025	2026-11-02 01:46:03.388416+05	karachi.desk+demo@example.test	scrypt:fbbe70a79009bb5cc1fa3d996c266717:a624ba3ca0d904ec005d758e878a606eb619177c10a4e1ca03c159d784fae5c24dd8e7e96daacf31202a1fe1c8a80f4d29e1687358887ee3922e3933f7ce33db		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000004	Usman Memon	usman.memon3	+923110000003	Karachi	Test diner #4 for the Karachi environment.	user	6	156	0	9	4.14	0	assets/images/portrait_4.png	{}	{cafés,BBQ}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner004.demo@example.test	scrypt:f65d85568c817c55fcad3a39e1749559:234cffdd7b5e7664e4f2e749bb9b04530ca63bf482740af0e37c5a304fb94bcd81af7d73295cfe9add19506b2f5ba6411e96fa5332303eee1b195aad24b0f240		t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000001	Fatima Tariq	fatima_tariqft	+923001000001	Karachi	Karachi food & lifestyle creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	influencer	128400	79	3	5	4.45	41	assets/images/portrait_1.png	{verified}	{karahi,cafés}	#C26B4E	2024	2026-11-02 01:46:05.099036+05	fatima_tariqft.demo@example.test	scrypt:170263e32eb5afdbc5d56febe0624aa5:96b9a868f693905be760634d9d00f0ce624940cb560e25a5e71d1346c63ec79cde8795e5a188bc19ccd2a28387ec94357a09171e6f59203c2840fc84e6550a76	@fatima_tariqft	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000002	Dua Anees	trendingwithdua	+923001000002	Karachi	Karachi local food discoveries creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	influencer	96500	274	3	2	4.03	23	assets/images/portrait_2.png	{verified}	{karahi,biryani}	#7A4A6B	2024	2026-11-02 01:46:05.099036+05	trendingwithdua.demo@example.test	scrypt:283363f2d9eaba9bf299b7f7624bbf23:ac0629c0eff298e58d3ed9c89e490969895cc1faf0147553b1ea44240d493e6fea007e8bb31c84fbb2c006c1a0d79d898895c84027c0ae85cc1e6c8878d34b17	@trendingwithdua	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000003	Madiha Razzak	foodienextdoor	+923001000003	Karachi	Karachi food photography & reviews creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	45200	57	3	4	4.19	42	assets/images/portrait_3.png	{}	{"street food",seafood}	#4A5A7A	2024	2026-11-02 01:46:05.099036+05	foodienextdoor.demo@example.test	scrypt:be980198a66f79b0762901a463175b65:857a79564887d3062d75a23c5a37f001e3391fa3bf1bffbde44141a3b43ae5ec44d42c341392cd003622113f4be3bf031d29fc36cef71fc518acf93e1a1a1eeb	@foodienextdoor	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000004	Safia Alam	_tolittlethings	+923001000004	Karachi	Karachi food & lifestyle creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	38900	180	3	9	4.63	51	assets/images/portrait_4.png	{}	{brunch,BBQ}	#4A7A5A	2024	2026-11-02 01:46:05.099036+05	_tolittlethings.demo@example.test	scrypt:5505fd849d2d1b38df84e8f92138fafb:d416c8703a8bfee705fb79139950b64bf52571c7a22c21129dc3dd39ff8ad6a6ab7a7659b7934794e8d08f96829b438d647552a3edf2ae98c7dc1874bf16424b	@_tolittlethings	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000005	Varisha Ali	varishaslens	+923001000005	Karachi	Karachi food & lifestyle creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	27400	265	3	3	4.22	43	assets/images/portrait_5.png	{"Rising Host"}	{karahi,brunch}	#8A5A2B	2024	2026-11-02 01:46:05.099036+05	varishaslens.demo@example.test	scrypt:bcd16fd42654930b3c6f191d3cb677f2:4b49c06058227566f24a9ecd9225428ddb7b5d5a2d49cfd2e5ac4020dc4065b8dfe2150089acde42a0107d7bbd6a7dfeda294d842aa32829a01a595aca4aa07d	@varishaslens	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000006	Sham Kumar	lifewsham	+923001000006	Karachi	Karachi food & local businesses creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	84000	78	3	7	4.92	37	assets/images/portrait_6.png	{}	{cafés,brunch}	#C26B4E	2024	2026-11-02 01:46:05.099036+05	lifewsham.demo@example.test	scrypt:e7ef579a234b79e53c731e35cbfa1389:51dded42fdbde50a4ff6f71ab8808c96c97b3abd72f856d3ba797c574f0c77519489adbfcf2d1c680bc2acd455174ce54d5cac1b7a3b2efcdba9146a46495162	@lifewsham	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000007	Sai Naqui	sairanaqui	+923001000007	Karachi	Karachi premium dining creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	52600	240	3	4	4.01	31	assets/images/portrait_1.png	{}	{desserts,biryani}	#7A4A6B	2024	2026-11-02 01:46:05.099036+05	sairanaqui.demo@example.test	scrypt:0eec7a5c1931bc6ce80f60a2708770ed:0836d4a1e4f9a540fb1979c6ff366f3bb93d6e78f219d36d993603b6e8e1e2659bd21c8f522e04ae848c2b7ccf64de644db4825dfbb00bcb50e36334b4eef8ee	@sairanaqui	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000008	Hunain Raja	hunainahmedraja	+923001000008	Karachi	Karachi food & entrepreneurship creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	61000	150	3	6	4.10	52	assets/images/portrait_2.png	{}	{biryani,brunch}	#4A5A7A	2024	2026-11-02 01:46:05.099036+05	hunainahmedraja.demo@example.test	scrypt:86e698d885f85d118e6a4be60f86a1a9:bbe38b3fc956d66386e51d683bc67e22084678eddf662485fecca7dfcb35026e63ebef766439f1757a7c9e01bad3cf25e51c70817cd18a9d244d9660edb9828d	@hunainahmedraja	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-000000000009	Narmeen Aamir	wanderbitesadventures	+923001000009	Karachi	Karachi café & restaurant reviews creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	33800	60	3	2	4.67	58	assets/images/portrait_3.png	{"Rising Host"}	{brunch,cafés}	#4A7A5A	2024	2026-11-02 01:46:05.099036+05	wanderbitesadventures.demo@example.test	scrypt:596b37582f60914cd2654c4f468b719a:f762f41c2e980f5994d8084c09ebfc6e109638a028f99e87c9e5a7ef98a2feb403bb232a08c17172eed9aab2b6e239a3ea10bfb1036faaed23fc91779ccd3c39	@wanderbitesadventures	t	t	t	f	t	{}	{}		f
ffffffff-0000-4000-8000-00000000000a	Raheel Tariq	muhammadraheel03	+923001000010	Karachi	Karachi street food & breakfast creator. Seeded as a candidate host profile for discovery testing — not a signed DineCircle creator.	host	74200	45	3	4	4.32	51	assets/images/portrait_4.png	{}	{cafés,brunch}	#8A5A2B	2024	2026-11-02 01:46:05.099036+05	muhammadraheel03.demo@example.test	scrypt:d0cd1975d6cd1d8aa5a77b33b72ea6ab:27656c54690a9e5c3a54d3a3a7375bf9b5af24334fd4f43d8eb98745fcb9e8e0a74f7efe23b9f0bb291fa2f33f56b96b511434544f8db19a05b2713f89fba971	@muhammadraheel03	t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000001	Ayesha Khan	ayesha.khan0	+923110000000	Karachi	Test diner #1 for the Karachi environment.	user	4	96	0	4	4.08	5	assets/images/portrait_1.png	{}	{biryani,seafood}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner001.demo@example.test	scrypt:b3bfc17ef61c255c8fd057033e8f3a40:17205ef08b68ef024424fe7e7839f0be23a8706c2ea6bd9543756ecedcbd5355015a6973dfc317c01e8d0e4a5867ea34129bc074c997051cc8179f0f6aaa77dc		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000002	Bilal Sheikh	bilal.sheikh1	+923110000001	Karachi	Test diner #2 for the Karachi environment.	user	8	151	0	6	3.92	10	assets/images/portrait_2.png	{}	{BBQ,brunch}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner002.demo@example.test	scrypt:383757099d9096f17594bc943c688bc4:8663c77d90d5e0fe9784aee885d3a5fd7a0c9e650cf4c9bd86ebc8f2ee38a019576906f720165de209e99fb7ee407e3a84d5cd66a8020f27b4ae17a45ebcb59c		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000003	Hina Qureshi	hina.qureshi2	+923110000002	Karachi	Test diner #3 for the Karachi environment.	user	4	86	0	11	4.53	6	assets/images/portrait_3.png	{}	{brunch,brunch}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner003.demo@example.test	scrypt:677b716440b553b5c609e5cd30ce0a09:1495cdd71f58852efe590c795c28ffe24b1a8e347bfd0203a33773391b3f1b15d8c84574a70fcb4f9de15299524455ddf799952d8b35f3e5566e4172bcfaed78		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000005	Zara Ansari	zara.ansari4	+923110000004	Karachi	Test diner #5 for the Karachi environment.	user	34	18	0	18	4.48	11	assets/images/portrait_5.png	{}	{seafood,biryani}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner005.demo@example.test	scrypt:0f99dabd4c25365b33d6f66121396087:9ae1348806d7dcd40bc62a852a9c62bbb26618be69b81f8bda13a92842388e24a188f3fdaf1ca56c426e42c57ad87759b8e5a8bb0ba1e4712aa479e40eb6d293		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000006	Hamza Siddiqui	hamza.siddiqui5	+923110000005	Karachi	Test diner #6 for the Karachi environment.	user	38	110	0	6	4.68	12	assets/images/portrait_6.png	{}	{cafés,BBQ}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner006.demo@example.test	scrypt:438cace1aae22cb42386ef131b36491b:eea95a0fb89642e960327d1e5e99f7be3c0e4fcf7b740cc28994bd0fd5fe64827259e846733aa04d1e7a64d7e68fa388acb9f73da4b2876b6a2a6f9cbe830344		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000007	Iqra Chaudhry	iqra.chaudhry6	+923110000006	Karachi	Test diner #7 for the Karachi environment.	user	31	30	0	16	4.79	2	assets/images/portrait_1.png	{}	{biryani,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner007.demo@example.test	scrypt:c4d0c412d56ac4ba9153fe6b3ac2a88b:0ebb8487ecebb803848ef310c1bdf5396e22254f148f096ebd59721a77ced0527e9f034aec08aa85b556636719317641997430ce6311b4729ec7598e5fb115cb		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000008	Daniyal Ibrahim	daniyal.ibrahim7	+923110000007	Karachi	Test diner #8 for the Karachi environment.	user	25	77	0	10	4.45	2	assets/images/portrait_2.png	{}	{brunch,seafood}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner008.demo@example.test	scrypt:da032b41e5af7328fa4dbabccc6c421d:395e65a7efca1f17a256bc3f7c9cd436480ff24d7ecb7f5477512ec88251496a9805865000dfa0f0230bac5a4bfaa5345c4dc0cec23abc4f55a49b2e969d2ca8		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000009	Sana Haider	sana.haider8	+923110000008	Karachi	Test diner #9 for the Karachi environment.	user	39	156	0	6	3.83	6	assets/images/portrait_3.png	{}	{desserts,desserts}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner009.demo@example.test	scrypt:a6f057cbec15536d34224f5e60e05e5c:c33af29df2fd8cf3ae74f23c647c74e698be40912c8a1da6430a81df0a31c9b668c2c3e1b10d2acb76c806dd3311352b5cd1fd8a6493b13c72de9c4aa19b9cf0		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000a	Faisal Malik	faisal.malik9	+923110000009	Karachi	Test diner #10 for the Karachi environment.	user	28	112	0	12	3.61	5	assets/images/portrait_4.png	{}	{desserts,desserts}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner010.demo@example.test	scrypt:8927ba0acb061b87defbff60937a293a:efb83d5d41205198e896b8da68f2b8cfc46e1f6ed87324ba9efc2cdca03908e6b68719f9f6bc932d4f9e50d01385342dea42a9e2ee4c0cc0f45a77e86b63d60b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000b	Mahnoor Khan	mahnoor.khan10	+923110000010	Karachi	Test diner #11 for the Karachi environment.	user	2	3	0	18	4.12	8	assets/images/portrait_5.png	{}	{desserts,desserts}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner011.demo@example.test	scrypt:b8c00e65c450a4e592a0e0b6ca7e062d:eeaf0ed00753f21d27c08fe0ae38e4c175868e4376ee998c4e8135319951a7bf7e2696a1a8ff1165fd6ed16516e552ae0d97e08e3da9b3b8f9d7409cdba188de		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000c	Ahmed Sheikh	ahmed.sheikh11	+923110000011	Karachi	Test diner #12 for the Karachi environment.	user	30	172	0	7	3.87	1	assets/images/portrait_6.png	{}	{cafés,karahi}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner012.demo@example.test	scrypt:79d253128b73e5675cee1ee1be220e31:ad9e446d0bdc0f18a03ebfbb69382d7e52c1872c0913db4a62cf790fd640ec03c972c897c125b80fdfdfb1f9869b4f841ef552112a11e21ada566865b37eaa75		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000d	Alina Qureshi	alina.qureshi12	+923110000012	Karachi	Test diner #13 for the Karachi environment.	user	28	132	0	13	3.59	12	assets/images/portrait_1.png	{}	{BBQ,seafood}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner013.demo@example.test	scrypt:06e5bd3e4effbfab575a9d8fedec54ec:6b62f31e9a6fb73bc56b2fe1abdf41d6a522073082a2305c275748aadff671e0066431c0f3791113a7fa0bde019653964a29dc3c3fcf8f8e6baaa77803c41a68		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000e	Junaid Memon	junaid.memon13	+923110000013	Karachi	Test diner #14 for the Karachi environment.	user	17	78	0	1	4.59	9	assets/images/portrait_2.png	{}	{seafood,seafood}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner014.demo@example.test	scrypt:039c8fcc2496730a50cf9a91433cb70c:fde71358c592d57338144eaabb7ac9e1bc7c7c1eb66db408c09c8338b573f0b087f860ca231a7b74390852782372d619a5357f4e782edd3213c2590e69236945		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000000f	Kiran Ansari	kiran.ansari14	+923110000014	Karachi	Test diner #15 for the Karachi environment.	user	30	124	0	18	3.89	3	assets/images/portrait_3.png	{}	{"street food",BBQ}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner015.demo@example.test	scrypt:ed1f5bb8bd5b5350f8924abd711c00c1:b43dbf3e114c5f75bdaf924799037b77033f59eb5557ed40f0f6be2f98197acbf412e6b24b23959181540e5b113014a6bfbba2d1bee884737d94ec12dbe2ebc3		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000010	Laiba Siddiqui	laiba.siddiqui15	+923110000015	Karachi	Test diner #16 for the Karachi environment.	user	27	47	0	8	3.59	4	assets/images/portrait_4.png	{}	{brunch,brunch}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner016.demo@example.test	scrypt:b30af9bfd02e39d5698108028b763d29:ef310efb79ffe9d76d93ff2af4725bc8d4c9d02e12ef1e42c6e22cb00dd2663016ae26adccf33788cf9322f62531d06a29d971837304c67a414ef3b234936532		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000011	Musa Chaudhry	musa.chaudhry16	+923110000016	Karachi	Test diner #17 for the Karachi environment.	user	14	101	0	3	4.11	8	assets/images/portrait_5.png	{}	{"street food",karahi}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner017.demo@example.test	scrypt:a88e02d958e706badea9c5613cea7bd7:e410e7c2b03c781bde6854fe8353f69cc6ad64f2290d70cf3f943a63a5c50abfe8f386bdaf12ebd6a4ca9cf3699f1efa345abf6d1587b71d2344728c5a2865a7		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000012	Nida Ibrahim	nida.ibrahim17	+923110000017	Karachi	Test diner #18 for the Karachi environment.	user	25	15	0	2	4.45	10	assets/images/portrait_6.png	{}	{karahi,desserts}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner018.demo@example.test	scrypt:79301269c3afaae06f0c33fc6269b3ca:d40f7167c026c9f5c91d537075f54a05cd95f02d8b4d53b01adb4df16078cc7da5850435edba65816c727ea078a3e703e5bd4a05ee4b82573ee7656e611f9c1a		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000013	Owais Haider	owais.haider18	+923110000018	Karachi	Test diner #19 for the Karachi environment.	user	18	95	0	8	4.64	8	assets/images/portrait_1.png	{}	{biryani,cafés}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner019.demo@example.test	scrypt:c6fe71b1bf6c7163bd340b3a5afbb2fd:de3e4dbae4caf4c9fa95532ce74ca1b7c9893aa70885f7070014a531e5d5fc2a66058d23e007683f9b5e91980f1b6c093fb52ad0035b6b131735d8c50dff9160		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000014	Saba Malik	saba.malik19	+923110000019	Karachi	Test diner #20 for the Karachi environment.	user	10	11	0	10	4.07	9	assets/images/portrait_2.png	{}	{brunch,biryani}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner020.demo@example.test	scrypt:64d83220fe1a8ab50de9ec666bfb8c29:4dcd6a3823cc93529c5c18b03967f8ddfac5fff83a58e48aae32b4ad2e92aa7cc8c7b23498897668e05e7262e928d4c21ee95e095a8ea3512b6f44ecaa437a3b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000015	Ayesha Khan	ayesha.khan20	+923110000020	Karachi	Test diner #21 for the Karachi environment.	user	10	171	0	1	3.57	2	assets/images/portrait_3.png	{}	{"street food",BBQ}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner021.demo@example.test	scrypt:913884ebc75c8fcf3897ef82cdccb78e:2ad1cbf3d1d5c0074a6997a886769030a08bbe7a10287b53eca814582541b397f1b536078718b3abae001f655485ca65567d3ba1bc67462dfae18c8ce57fe389		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000016	Bilal Sheikh	bilal.sheikh21	+923110000021	Karachi	Test diner #22 for the Karachi environment.	user	2	15	0	5	3.91	6	assets/images/portrait_4.png	{}	{biryani,seafood}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner022.demo@example.test	scrypt:a3c89f7a035a2acf9761742c35798b7e:c2805c177a289633e33965f3d2c394f82adbf3c0ab65ce3d42b0cc4a8dc2422b8636983cefaec1d19b19b32252e847217530153998ec49a51109bc6150bf7635		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000017	Hina Qureshi	hina.qureshi22	+923110000022	Karachi	Test diner #23 for the Karachi environment.	user	18	200	0	5	3.69	1	assets/images/portrait_5.png	{}	{BBQ,seafood}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner023.demo@example.test	scrypt:b73a1d161f6d705328741a5c50037eb8:9779b712594a25d8da747921f68bc6e15f53229578bc6a0fed46ebad09ebbdd98d8548533abb530a5becfe9c2c1226d4aeef188a1b5e537f55505c83796f81a5		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000018	Usman Memon	usman.memon23	+923110000023	Karachi	Test diner #24 for the Karachi environment.	user	28	17	0	15	4.65	4	assets/images/portrait_6.png	{}	{BBQ,biryani}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner024.demo@example.test	scrypt:bdb5f04c1b15453d9a2d211ddb9e5c39:10382902148b7c4620835fab059b1aa6425f921becd98aa26fe89e24204f42261e7d7ee9d9ab554ea2cf5d1e4f79a325e4cd333abc81b1d8a0e35f5c7d1454bb		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000019	Zara Ansari	zara.ansari24	+923110000024	Karachi	Test diner #25 for the Karachi environment.	user	14	180	0	8	4.45	3	assets/images/portrait_1.png	{}	{karahi,"street food"}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner025.demo@example.test	scrypt:a7514ec68b25594a9dd0ebc7b7ee2088:e8e7505bf9670bc416d1090bcd2783f526774307bab4c15fadae0fb0506dffa2a0316bd0761cfcec83434367aaa24030ffb97b510b77d922f15dcc880cf02eb8		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001a	Hamza Siddiqui	hamza.siddiqui25	+923110000025	Karachi	Test diner #26 for the Karachi environment.	user	22	84	0	4	3.69	2	assets/images/portrait_2.png	{}	{cafés,biryani}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner026.demo@example.test	scrypt:af04593c18732123c6e4e3c7713f7b8c:cec8c45e1a96bcd6a852b73bcf9760946a74df7ab056ccac906546f22e981b53cc0f7b508e8827a79eab582bf2bd815d33348de4b019223bab456bc073104e3e		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001b	Iqra Chaudhry	iqra.chaudhry26	+923110000026	Karachi	Test diner #27 for the Karachi environment.	user	30	108	0	12	4.22	11	assets/images/portrait_3.png	{}	{desserts,desserts}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner027.demo@example.test	scrypt:35711b70a1ff6bec69f9ed836025b967:a7b3e2e3df6c106e47698a6a344fa1e80f739c469b4ed42910279aafd35f7165b2e1b4336c64476c21b17594f5bb1988e1ec8d4bdebdd26ced29401ff5977d23		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001c	Daniyal Ibrahim	daniyal.ibrahim27	+923110000027	Karachi	Test diner #28 for the Karachi environment.	user	29	47	0	1	4.63	1	assets/images/portrait_4.png	{}	{biryani,BBQ}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner028.demo@example.test	scrypt:4a573a8adb47de7e3867af3b208a3534:ec245d45fe7e9fdf995605322075f8cad0af3e9e1680066c0b933e27be63b74fb165c62578dd841ab5e0da82c1419b6f166b71be12c8d9a4900c113c5af40734		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001d	Sana Haider	sana.haider28	+923110000028	Karachi	Test diner #29 for the Karachi environment.	user	13	87	0	18	4.87	3	assets/images/portrait_5.png	{}	{BBQ,karahi}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner029.demo@example.test	scrypt:da66be246f42dddf924f325864edcb6f:f21a132af74e90357472affbe71775c058570de3753f0c244ff86923b4ddc19f1a9fbc8f73e5b836e658682beea7c5abc4114f5ef23dcbf4d4ffccbc9d6f2034		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001e	Faisal Malik	faisal.malik29	+923110000029	Karachi	Test diner #30 for the Karachi environment.	user	24	133	0	4	3.72	7	assets/images/portrait_6.png	{}	{cafés,cafés}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner030.demo@example.test	scrypt:062e0b8340017be4761b39c993c14911:ff3c02eba7b8b94c04fc5ee359ba1964ddc1f81bdc3e961281d610499fbe311526ad0fab81135dd95bb0d5afa81586f2eb761b4485805b8317e884616ad2bb8b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000001f	Mahnoor Khan	mahnoor.khan30	+923110000030	Karachi	Test diner #31 for the Karachi environment.	user	33	118	0	18	3.50	5	assets/images/portrait_1.png	{}	{brunch,BBQ}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner031.demo@example.test	scrypt:939e84ca0074d1c7eaa69e1fb361d084:fd93a35d8c5ee46b4824225fb2863226dcf51f1ed8d961280707aeeba966685a65d85944b22e4ebfe5730d495add70604192c3f786328db37d88b7ebb4d99f1c		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000020	Ahmed Sheikh	ahmed.sheikh31	+923110000031	Karachi	Test diner #32 for the Karachi environment.	user	9	77	0	5	4.10	9	assets/images/portrait_2.png	{}	{biryani,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner032.demo@example.test	scrypt:cb6ad0b186fc08c0a34e62852d8dd413:f79561438d7419bf019154237eefcac0dbfae76a79ea7d7de1f2fd2b0070a3b3ba8d448663e9e8a3495f8d117e7334ec653cd8d1f44faff782c8db2a61552612		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000021	Alina Qureshi	alina.qureshi32	+923110000032	Karachi	Test diner #33 for the Karachi environment.	user	32	58	0	14	4.59	1	assets/images/portrait_3.png	{}	{karahi,cafés}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner033.demo@example.test	scrypt:a9c9f2133b3ab3fd92264438bd33cb10:1faaa6e6cdc75c4c9afbfaacaf1e87fcbd7f8c7da59ac65b799bc5e1a26d2dba3c797b320a09bb77c1e133febb7c01c8917e417ab647866f9ef16c80b71811e9		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000022	Junaid Memon	junaid.memon33	+923110000033	Karachi	Test diner #34 for the Karachi environment.	user	14	43	0	10	4.88	0	assets/images/portrait_4.png	{}	{karahi,biryani}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner034.demo@example.test	scrypt:0fd36da39baea226f781537f32215c88:75404390a92fce695bdc74e46d5a2043a5905669cc5605dfddd2f3a694b8202cc51408b6db85755a578e7f1f0da96ea5341f6f22f5a506cc10cb9a58b1c13f2b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000023	Kiran Ansari	kiran.ansari34	+923110000034	Karachi	Test diner #35 for the Karachi environment.	user	17	33	0	18	4.42	9	assets/images/portrait_5.png	{}	{karahi,BBQ}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner035.demo@example.test	scrypt:0f4a5463537d4549354b1a605f0325ee:8990178b22c3f2396c46ca3df63bcdb3ece38a17829e45044ee2591b79f7cccaaab4656ba846499507a47dc58af2a754e2f61e690b1bb8cd2bb27d05fa56fc10		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000024	Laiba Siddiqui	laiba.siddiqui35	+923110000035	Karachi	Test diner #36 for the Karachi environment.	user	23	129	0	9	4.33	8	assets/images/portrait_6.png	{}	{seafood,"street food"}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner036.demo@example.test	scrypt:7d229b556c364b06c00113d3e53130b7:dfaf49d5c465b1c809560bbe5ecbd98192dc5c808de4c716f1edf05707b305d9d6dd7de1a3586bd862d05cc43824529e4b599c603ed129fe6bd0c356814c5fe1		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000025	Musa Chaudhry	musa.chaudhry36	+923110000036	Karachi	Test diner #37 for the Karachi environment.	user	32	70	0	2	4.72	9	assets/images/portrait_1.png	{}	{seafood,seafood}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner037.demo@example.test	scrypt:4ad18104b522bd9edfd15b2f447a4142:f6c04274334c533332c6b6c67b870f9933f52d077f08fdcf192b2c0f9e394d60fdd2a099b8e19010f1028c48a5d0a49081203656258f16d8d9d312ae3aef3761		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000026	Nida Ibrahim	nida.ibrahim37	+923110000037	Karachi	Test diner #38 for the Karachi environment.	user	38	65	0	16	4.12	0	assets/images/portrait_2.png	{}	{desserts,brunch}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner038.demo@example.test	scrypt:2ada4437198c97993e8a3600afc8c390:0e533dc815b8b7a418551dd0cd0ee09bf8b9d3321346ca37ccda4906e676171b7ee4942b781c6c70f3c1e36ab855135d5ec9727864c4c064aedd1f823fe02ff6		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000027	Owais Haider	owais.haider38	+923110000038	Karachi	Test diner #39 for the Karachi environment.	user	9	177	0	11	3.96	1	assets/images/portrait_3.png	{}	{karahi,desserts}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner039.demo@example.test	scrypt:f603c123781662d267cb787463702706:f972c913e6daa9f82331f593696e1cb08d8b6e3e0a19300f4dc508e8857ded90aad69345c884f9a8f81ddf5c8cc764da92d3a94e6a3d606b978169f81a485e49		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000028	Saba Malik	saba.malik39	+923110000039	Karachi	Test diner #40 for the Karachi environment.	user	30	63	0	12	4.40	9	assets/images/portrait_4.png	{}	{cafés,seafood}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner040.demo@example.test	scrypt:38a8270082fe8b419710523b322f3d4a:0a7b64709aed7caab5c4953a61703f5868a110d985ceeef5841d6ed508f7700d0ec6414c2b8a3bdd1a572eda951aa9649c07fe8532d01d333f92ea01271af3c0		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000029	Ayesha Khan	ayesha.khan40	+923110000040	Karachi	Test diner #41 for the Karachi environment.	user	4	62	0	12	4.43	2	assets/images/portrait_5.png	{}	{brunch,cafés}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner041.demo@example.test	scrypt:496a2f0828915e8049f5e70d1ca259f9:938b81ffe48ff76e381494da3f1d881f38a192b965867805723b3a520ffd74b3576a0de63e486175542f04767cd481b694994d302c54b19416cd51ef1a783ebb		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002a	Bilal Sheikh	bilal.sheikh41	+923110000041	Karachi	Test diner #42 for the Karachi environment.	user	11	44	0	7	4.74	8	assets/images/portrait_6.png	{}	{seafood,seafood}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner042.demo@example.test	scrypt:b51be687c46cf4e596bc34f0450bbeeb:a4817284d97422a392428c991b3df9c1cb311693ca82b37ef5794a4b73393967f044ba3c5cd0754eab7b186612884b6618c85cd4409b84bc1ee03a1bc2f29417		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002b	Hina Qureshi	hina.qureshi42	+923110000042	Karachi	Test diner #43 for the Karachi environment.	user	25	91	0	15	4.30	0	assets/images/portrait_1.png	{}	{desserts,biryani}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner043.demo@example.test	scrypt:47690c4fde07bde8dbf5da1f1a0bb194:ed1b9bc326f32f102233d9a93f05e6944fbe2eff40170ee040b09ac39d4fc73ded91669df50ad8860656af7ef84f1ab618a1112c4b86918bbec69db78b2345d4		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002c	Usman Memon	usman.memon43	+923110000043	Karachi	Test diner #44 for the Karachi environment.	user	32	118	0	5	3.84	1	assets/images/portrait_2.png	{}	{karahi,desserts}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner044.demo@example.test	scrypt:1fba1366b89aa4525a4959e958380657:685fbc934af20925ed5c6a0ba1cea0eeba27634a1001dc793436b59db2c81a9f0e01981169ecd2df64fbb9a63ac3a1c5652ef4ff3c5132fc7a255247e1c41c9c		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002d	Zara Ansari	zara.ansari44	+923110000044	Karachi	Test diner #45 for the Karachi environment.	user	3	112	0	11	4.35	0	assets/images/portrait_3.png	{}	{brunch,"street food"}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner045.demo@example.test	scrypt:0c8697e87cfd27323c7d19cb44b3281b:77e4fce68418a6e0ad35baa2ecc31e9855397f68a19a9da5e768af6c5186fb17bb5fb9015e0bebeef319d6d78f04699cf22dfb7274182a766678429081a462a5		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002e	Hamza Siddiqui	hamza.siddiqui45	+923110000045	Karachi	Test diner #46 for the Karachi environment.	user	19	88	0	12	4.29	10	assets/images/portrait_4.png	{}	{BBQ,biryani}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner046.demo@example.test	scrypt:2cae3508ecac1a62690183e9a1cd74d4:7d95e6c30bc9eb2c80739c49015486ebcfc1048031ca1cea01a366b55a890ed83707ddb100e66fd8089af2301d5eb81ae3300064c6616cb3324322b91e84ba68		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000002f	Iqra Chaudhry	iqra.chaudhry46	+923110000046	Karachi	Test diner #47 for the Karachi environment.	user	37	15	0	12	4.57	10	assets/images/portrait_5.png	{}	{"street food",cafés}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner047.demo@example.test	scrypt:e9ee1de1b36df3422af44dfea996090d:7b3c54bce46c51a8057716fda3c01694c0662b2bc0f7f070598c2f0b457c09fa6548dafc089a739d85614289a179e0be86bac02b71b046837b1ea5d5c1045bf5		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000030	Daniyal Ibrahim	daniyal.ibrahim47	+923110000047	Karachi	Test diner #48 for the Karachi environment.	user	19	138	0	14	3.89	0	assets/images/portrait_6.png	{}	{"street food","street food"}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner048.demo@example.test	scrypt:7765f2c4533a012b6f814e3d5aa879d4:b5a0a9bf83e0d6acfea42f44f55eedff2bd30e532e97ef8af68d3a56ef701f6c5506992233014b258baf0dfcaf732478ecb02eb8445a97175d8c7d7be5a0471b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000031	Sana Haider	sana.haider48	+923110000048	Karachi	Test diner #49 for the Karachi environment.	user	10	72	0	6	3.72	10	assets/images/portrait_1.png	{}	{brunch,BBQ}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner049.demo@example.test	scrypt:627c25bb08dd39ad3724f7d8e5a5b4fe:50561a362a25695ed299e2ef2c9c07a55016ad99d67664133530f6fadb7869c61545215d0f266a4b5892d27ecb25d0398677a533ff4026ddb81b4f7b5a6cf193		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000032	Faisal Malik	faisal.malik49	+923110000049	Karachi	Test diner #50 for the Karachi environment.	user	13	122	0	12	4.10	11	assets/images/portrait_2.png	{}	{"street food",desserts}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner050.demo@example.test	scrypt:7903e279189ff666e46e2932eaaa78ba:89bb23815ab8b5709641484b17addcc0dec170b2bcf275450a09fdcde3bae8e04c9d09ad0644457d78e19576a14c23e0c5af05c26150ddb81325fc017f1bb0eb		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000033	Mahnoor Khan	mahnoor.khan50	+923110000050	Karachi	Test diner #51 for the Karachi environment.	user	19	120	0	10	4.61	2	assets/images/portrait_3.png	{}	{"street food",brunch}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner051.demo@example.test	scrypt:0d969e34b0ab7456b3a27d79a0cb94d3:f73b38f8bdefeab200b85844e1d505d117978d27cc41418ed45fc77299582891900159e947d907e264877c1c87bfb91546868ef60edf70b4a3facce86e181132		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000034	Ahmed Sheikh	ahmed.sheikh51	+923110000051	Karachi	Test diner #52 for the Karachi environment.	user	3	158	0	17	4.24	8	assets/images/portrait_4.png	{}	{seafood,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner052.demo@example.test	scrypt:70f5ade1b9f32767ff433cc650f81d0c:0f0b1533d6883cfdfbb69803334a4acd3e356675afd067674b8e97fcbc726da97372c5d8427ee50e409df4f92964f5f1f7710d87697679713ae1180a4345d546		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000035	Alina Qureshi	alina.qureshi52	+923110000052	Karachi	Test diner #53 for the Karachi environment.	user	3	160	0	4	4.52	1	assets/images/portrait_5.png	{}	{"street food",biryani}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner053.demo@example.test	scrypt:9782afb356960d8cbb7ee48b7107f222:88bee8bf57c97cb698ba50e5f6d5cbf32538203f504cabe02959b1123a84948d5450e88d6ea37bc33442cdd0ebdefb0a826e0f38c22733919fd45527548046d4		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000036	Junaid Memon	junaid.memon53	+923110000053	Karachi	Test diner #54 for the Karachi environment.	user	6	63	0	17	4.23	6	assets/images/portrait_6.png	{}	{cafés,"street food"}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner054.demo@example.test	scrypt:bafeb785964df95ba393e7b4530f22e6:c7777f351e5ec044e3da6f02101bc740a447bcbd1d2eebdc2474d9eb5ce7b55b8601163793d0fab0ee9ec648a73f86a266326975132ea549f638512ccbd657ec		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000037	Kiran Ansari	kiran.ansari54	+923110000054	Karachi	Test diner #55 for the Karachi environment.	user	31	60	0	4	4.22	3	assets/images/portrait_1.png	{}	{karahi,seafood}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner055.demo@example.test	scrypt:6d5dab1d456d6567cdde6ff34d7f98d0:938a901ebeb7b6c79448f9511f9b0faae3751a0ca2ccf67cc6973afb1a65901fff12e585702e7c177ad0e2b323235ff395e063e9dccdfffd661ec1a80af6e65d		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000038	Laiba Siddiqui	laiba.siddiqui55	+923110000055	Karachi	Test diner #56 for the Karachi environment.	user	6	136	0	9	4.78	6	assets/images/portrait_2.png	{}	{karahi,BBQ}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner056.demo@example.test	scrypt:4d1d0cbaecdff8c715a1c2e1a31e5e9f:3b1884572fb20ff121cdc76ec5d33a8744fe4035628ff176c753837ab436a0b75729ecb99a9b2bf8a4e4f1bbd752ca88bc303d5ac042228d56ba8353d20cd6ad		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000039	Musa Chaudhry	musa.chaudhry56	+923110000056	Karachi	Test diner #57 for the Karachi environment.	user	19	132	0	6	4.09	1	assets/images/portrait_3.png	{}	{karahi,BBQ}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner057.demo@example.test	scrypt:9ea27f8bc3810f951fe17abdea201f71:fb4674cfdb0edc12e1ca38f5642f2ed30cba8a862e226280bbc4965a30c68d103e2bc48a00c1c1f22b91d812fae6fe3778d78f760cd43b98242dde637c4f5f54		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003a	Nida Ibrahim	nida.ibrahim57	+923110000057	Karachi	Test diner #58 for the Karachi environment.	user	25	197	0	10	3.63	5	assets/images/portrait_4.png	{}	{desserts,biryani}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner058.demo@example.test	scrypt:0f700734fa01f73a35411412f001bf57:7abc70f7256c087e60c09ab281c87228b970f935c1f6af62b3aef6a5ce2d346daaf89ebb14e7adbc7e0075682ccec5528d3380590769455f4037517382511413		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003b	Owais Haider	owais.haider58	+923110000058	Karachi	Test diner #59 for the Karachi environment.	user	9	35	0	17	4.76	9	assets/images/portrait_5.png	{}	{BBQ,"street food"}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner059.demo@example.test	scrypt:12105821b0fec20de6b806a4251b659b:51e44de9be868a21e5d4499110e6b07bd156b2ef5e602121749d39cdf17bb602989600c77a0df161e3aef4898f6f771755b21f0d235a06115e8852c5c58ed960		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003c	Saba Malik	saba.malik59	+923110000059	Karachi	Test diner #60 for the Karachi environment.	user	35	110	0	15	4.10	4	assets/images/portrait_6.png	{}	{biryani,desserts}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner060.demo@example.test	scrypt:4db8db6cfbc5645f90856b97987d3b57:5c60a05bd96901f3bc67d49ea2b863d6114a36ac0adc219379c370cf82abf9f590df4802f26a10eac767e9f3e284d2a8e5e6599ced2bf94a7ff44abfad9e1874		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003d	Ayesha Khan	ayesha.khan60	+923110000060	Karachi	Test diner #61 for the Karachi environment.	user	14	31	0	3	4.60	8	assets/images/portrait_1.png	{}	{karahi,karahi}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner061.demo@example.test	scrypt:e8ab793903bbe60762b5daf1972939bb:b81cd7dff205a62ff0db04e3c3ff75d53242e5a2179d34386a6f35e249a2376e870497471e4c1254c52f1d9ebf5285d88c70072ee95311a98f3c0c8fcc856039		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003e	Bilal Sheikh	bilal.sheikh61	+923110000061	Karachi	Test diner #62 for the Karachi environment.	user	21	60	0	6	3.76	6	assets/images/portrait_2.png	{}	{biryani,cafés}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner062.demo@example.test	scrypt:204b5bbf514ee661b4ca6d1924f24ffc:7131a03117f869c4c6c23f91cf252d71305357f01751ecc6e37da0877531713cd45d5e07051730251093658b87d8e8fdc61004b75db41d1a54f857ad49bafee8		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000003f	Hina Qureshi	hina.qureshi62	+923110000062	Karachi	Test diner #63 for the Karachi environment.	user	35	194	0	7	4.87	0	assets/images/portrait_3.png	{}	{biryani,biryani}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner063.demo@example.test	scrypt:58121fd3253762aad11f2108c7225e6c:7887a21ea5eb3eb8805e5e834a2c7386400643f5d6991221967bccb021e67e49c5fb6d1263e613d69e3072b1115d91b906d30a37d9d2f6659af548fb58579308		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000040	Usman Memon	usman.memon63	+923110000063	Karachi	Test diner #64 for the Karachi environment.	user	29	29	0	12	4.14	4	assets/images/portrait_4.png	{}	{"street food",biryani}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner064.demo@example.test	scrypt:cd304f6775b8692201a0ff1d44793ff7:011006a98abfa4af79949a14d5aa3cf966c28950ed0cc0d7b062c553eb53b04f04cc3bdaebcc625eafa5477d2f4020c57e31996e6ca261126cc16c02f40dd261		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000041	Zara Ansari	zara.ansari64	+923110000064	Karachi	Test diner #65 for the Karachi environment.	user	8	168	0	15	3.51	1	assets/images/portrait_5.png	{}	{cafés,seafood}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner065.demo@example.test	scrypt:da2403075777335d05f6a3aabe1527f7:25398e98fd1eb88f8094f24aabaa2a2eb1e88dc75c8260d34d815d57e30051b886f5ebdb77e8fc30242d03d1cdc614d6cb0d65ad0ddc971321cea3159277f921		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000042	Hamza Siddiqui	hamza.siddiqui65	+923110000065	Karachi	Test diner #66 for the Karachi environment.	user	5	122	0	12	3.60	3	assets/images/portrait_6.png	{}	{seafood,seafood}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner066.demo@example.test	scrypt:32081d8b6430bdee79425513a751f985:dfc422f56b9acddcdf83d511c7fd00951dc9664ce06cbacd9f99576b7d80f557f392263aa8404937cfa55f9d5e7bd74eb9e2aa8ba3fbd9ad37a6d6169776ab25		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000043	Iqra Chaudhry	iqra.chaudhry66	+923110000066	Karachi	Test diner #67 for the Karachi environment.	user	33	60	0	15	4.79	5	assets/images/portrait_1.png	{}	{cafés,desserts}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner067.demo@example.test	scrypt:654084bfbca46e77882cc30a7578bcd4:25c193c4f73da0c3484fc70001576f877fe96930923aae55e28806521e0809d348fb5c4b8d0698e7d4de13d1cb9fdc3bf43ac4dcef6cc757041d64a522e2c2de		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000044	Daniyal Ibrahim	daniyal.ibrahim67	+923110000067	Karachi	Test diner #68 for the Karachi environment.	user	31	14	0	12	4.46	11	assets/images/portrait_2.png	{}	{"street food",BBQ}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner068.demo@example.test	scrypt:d6a5d9d436138d8444be6e7a10cd7957:c76bad6192fd106785f1eecda97f8c837ee303721f76cf859bf82b27bc2ae33dbf552a93745e8bdb9f91b0524bfcf3b79c15aec4ac8d6e2bc8cb4cfb9e66a671		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000045	Sana Haider	sana.haider68	+923110000068	Karachi	Test diner #69 for the Karachi environment.	user	16	95	0	7	3.83	11	assets/images/portrait_3.png	{}	{BBQ,karahi}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner069.demo@example.test	scrypt:a3c58b546b9fd75f24c382d1c52492b0:f2afe33b9173adfc8f2b9ba5106461004fd41850d1c1956c929c8b0505e0e3e6daec1995c1f78a6c41f48f23a8e2f93edffb03a9e43bd7190c8b65f248ee2824		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000046	Faisal Malik	faisal.malik69	+923110000069	Karachi	Test diner #70 for the Karachi environment.	user	10	175	0	15	4.70	6	assets/images/portrait_4.png	{}	{BBQ,brunch}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner070.demo@example.test	scrypt:8286b288ea188137c90993a62994ce2e:07877b112f5c5fde6d130b599951061f8cd37c864f5ca6983c47e986cf5ed850aac72c24345162be8d8292c2d5a85c8fd728798cc42cdedbd7270381f312db83		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000047	Mahnoor Khan	mahnoor.khan70	+923110000070	Karachi	Test diner #71 for the Karachi environment.	user	32	39	0	2	3.86	10	assets/images/portrait_5.png	{}	{BBQ,seafood}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner071.demo@example.test	scrypt:b8f7bc8b86d44058ef1cfe8cf03e74b7:d03848a64e895c9496a29829acbba40e8c4e45d11cc6e3a6270ab93504b18ee5f8bdb65ea41a2a56c250bea77ff6d0ba7d82507ee57026ffc9cd059c77f9b193		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000048	Ahmed Sheikh	ahmed.sheikh71	+923110000071	Karachi	Test diner #72 for the Karachi environment.	user	13	20	0	3	4.96	3	assets/images/portrait_6.png	{}	{BBQ,seafood}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner072.demo@example.test	scrypt:831bb825040914220f574d21c1a4bfe4:9900953c7563853b5acbface7316451b1a4e8f2bd549ae05e47ce7a02c047bd24de3776908210f65f8c0f6fa61f724a27986670193b06cc6fd61c38d40963e3c		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000049	Alina Qureshi	alina.qureshi72	+923110000072	Karachi	Test diner #73 for the Karachi environment.	user	35	131	0	14	4.89	5	assets/images/portrait_1.png	{}	{brunch,desserts}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner073.demo@example.test	scrypt:5633671a81935fc361bdaf206a6e4754:3d0d89c70cec70e3cea957086c85617645a40f19ca72d9f69da92a12290b0ebf1a4be93897167afc3d9996d0b63caee27ff40ee4da681104e46aa6252b671555		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004a	Junaid Memon	junaid.memon73	+923110000073	Karachi	Test diner #74 for the Karachi environment.	user	29	3	0	12	3.71	5	assets/images/portrait_2.png	{}	{seafood,brunch}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner074.demo@example.test	scrypt:a6f9ee3ac40b6007907e5e7a5fc5f035:8b1c75a211cfae3f5e6ac982705befe409ac926bc42edab6d939f3a0104355ede79c6a5f368bb7bbbdfc913a5c14f95e661451f1efbe286885313f7dda71fa97		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004b	Kiran Ansari	kiran.ansari74	+923110000074	Karachi	Test diner #75 for the Karachi environment.	user	2	120	0	5	4.75	9	assets/images/portrait_3.png	{}	{cafés,brunch}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner075.demo@example.test	scrypt:2680b2d877cecc2393eea2d06b24e9d1:5a5f56994a6a24d94360171485dec00ce2d6dbf80e7861da803091fe39705b3d8155518ba722a693e8c32dad5b2ae46eb66b6d5d36e2121cf4b7994478735b02		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004c	Laiba Siddiqui	laiba.siddiqui75	+923110000075	Karachi	Test diner #76 for the Karachi environment.	user	0	82	0	12	4.90	2	assets/images/portrait_4.png	{}	{biryani,biryani}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner076.demo@example.test	scrypt:9b21693fbfe4be9deb305d6c178e7010:9eb695e5d93b1094fc1a32dc6b79e2fbea137c866dd97362cd060a7e430be336240092e6ec1fe8a40f87a4dd29b498af48208857b812c096502fd42cd41d79b4		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004d	Musa Chaudhry	musa.chaudhry76	+923110000076	Karachi	Test diner #77 for the Karachi environment.	user	31	89	0	1	4.86	11	assets/images/portrait_5.png	{}	{karahi,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner077.demo@example.test	scrypt:ebb8cf6fa315f313a13ecb53f54b0af3:a20f05e7c82822785b9d959bddeea303a99d22bea3e144beb0eb6c0985cd2ca7b6ab8f55ffaa6836a54a100fafbd23f056e66bb2e28ffedb714499bcc1bc0ef3		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004e	Nida Ibrahim	nida.ibrahim77	+923110000077	Karachi	Test diner #78 for the Karachi environment.	user	37	4	0	9	3.75	4	assets/images/portrait_6.png	{}	{desserts,"street food"}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner078.demo@example.test	scrypt:d7ccfe969030fad316460a055bbe5e67:60b42ab3ee68be0852ae256d60df554f4471425def7badb5d58e0cd8308cd4bee40cc84c9c9f892c6a1bdc94d2730735f344a6325ae2942b5d10c9a08ea7ccbf		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000004f	Owais Haider	owais.haider78	+923110000078	Karachi	Test diner #79 for the Karachi environment.	user	23	71	0	5	4.19	4	assets/images/portrait_1.png	{}	{cafés,seafood}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner079.demo@example.test	scrypt:e2c8abef32de94ca9fd6e345963be5a1:446feea278b2a375b9fe9407e6b8f196a50bba6dbdabd2c28541fbf27a34d882eda186cd41a9639eedc77fdb221e7a5240e10bfae871e61f6fbb6760abce27ac		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000050	Saba Malik	saba.malik79	+923110000079	Karachi	Test diner #80 for the Karachi environment.	user	31	154	0	12	4.24	10	assets/images/portrait_2.png	{}	{cafés,BBQ}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner080.demo@example.test	scrypt:0743d5a5252f536283f7e76b2309607a:324ea3dd7d4d87f6928c8c84cacfe72e5d2032fd68d401fa1c009c9f05d799a77d7a04973c40ae9d2b129a7f23b1429d6d93fe0c904f9b1958bfe49d5bf93d2d		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000051	Ayesha Khan	ayesha.khan80	+923110000080	Karachi	Test diner #81 for the Karachi environment.	user	11	130	0	11	4.04	0	assets/images/portrait_3.png	{}	{karahi,biryani}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner081.demo@example.test	scrypt:edf0169f21b294cb9c975d7396f3a7cd:87118060c1e55bb4907800bc74770c21b7416925c0ff9b42640cd32d647defc842ed931174523879b0eb3af20a0edd156111bcf7f5bc077f8f28fb482b118986		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000052	Bilal Sheikh	bilal.sheikh81	+923110000081	Karachi	Test diner #82 for the Karachi environment.	user	13	122	0	16	3.80	7	assets/images/portrait_4.png	{}	{karahi,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner082.demo@example.test	scrypt:ec39b858703a7d312d2dfb29d57564b4:d2dd13b8e5280ada1dff58858ed7ebd675b7bcdabb274722e5669cc9826353048e91e96c5c8888c313257bb88d44603b7db75071406971bbb4defc1c183597ea		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000053	Hina Qureshi	hina.qureshi82	+923110000082	Karachi	Test diner #83 for the Karachi environment.	user	2	146	0	3	4.42	5	assets/images/portrait_5.png	{}	{desserts,cafés}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner083.demo@example.test	scrypt:17295f951a6d3a9af2c4b3f62fa34f05:5d215e1b8f421c4e7b7875db24c679627104e78966fba6d247975351ca403f6880f784ec46fb47a90a4e27b679220db9fa33e6b5e914904860cdff7603dcdf23		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000054	Usman Memon	usman.memon83	+923110000083	Karachi	Test diner #84 for the Karachi environment.	user	17	87	0	14	4.63	9	assets/images/portrait_6.png	{}	{brunch,desserts}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner084.demo@example.test	scrypt:fb44c5f4333ea77e26cac04e95fb9a97:a307332451c06f5c72c8db776a91c860c4defd2815a67e1b1931d2c0b324f69465908daa8c632aa59b8fe8aa77f359d89f886885e94edb657adc4c6ce16fc43b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000055	Zara Ansari	zara.ansari84	+923110000084	Karachi	Test diner #85 for the Karachi environment.	user	38	153	0	16	4.49	2	assets/images/portrait_1.png	{}	{karahi,brunch}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner085.demo@example.test	scrypt:f8b029b024c28af3cd33861de1f755e1:f43cd2bd3d5ef7c95648c4218cc32ff8fbbd0994db38065c50d9e50d1629f1c72731834a6d90b79c6cce080b4963574ba3a82162d5c7004c16a170b4968d8fe9		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000056	Hamza Siddiqui	hamza.siddiqui85	+923110000085	Karachi	Test diner #86 for the Karachi environment.	user	25	3	0	9	4.52	2	assets/images/portrait_2.png	{}	{brunch,desserts}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner086.demo@example.test	scrypt:d738608eeb95ae1a051ae2023a529cd9:d7d6b03ec4b26406558ad6e983cfa788483999542d658f961556dafc719a9b54759c6c74289949f742e5ac021e4a9451a00e8151010d1729eb39b130ca66926f		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000057	Iqra Chaudhry	iqra.chaudhry86	+923110000086	Karachi	Test diner #87 for the Karachi environment.	user	12	187	0	5	4.02	4	assets/images/portrait_3.png	{}	{seafood,BBQ}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner087.demo@example.test	scrypt:6724506f8c8f26e4e6a46c4d2fff1bd0:e8a307cc67325c5570549dcc4f9bb82041c22bfbd8c90e5b7844d86a8b162e0f66c4143459f84a49079557762b41f1d853c88b5e93d4b36c7c981d40ae94aed0		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000058	Daniyal Ibrahim	daniyal.ibrahim87	+923110000087	Karachi	Test diner #88 for the Karachi environment.	user	28	98	0	13	4.89	9	assets/images/portrait_4.png	{}	{biryani,brunch}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner088.demo@example.test	scrypt:825f9d9471bf065af5c018e2df8523c6:b54fd2cdcd2d38b64c04298e8a4494afd0132cbbf5b9f8884b72dbbc25c940883d62375c2e835ad0a7545d070200a858728408f2727f3e825121c63b81c9d4e9		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000059	Sana Haider	sana.haider88	+923110000088	Karachi	Test diner #89 for the Karachi environment.	user	3	72	0	13	4.52	5	assets/images/portrait_5.png	{}	{"street food",karahi}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner089.demo@example.test	scrypt:b3091bf39df3be91d440deced380704a:a853e9d52bd97d96224c47e431feca0a84b4d844c83e93eaab3f1b3e9a4a70ef6dbe51ac4ffea53a0f722f9b54004eb9321caa0ddb68af22e8a59cfa0d9850e1		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005a	Faisal Malik	faisal.malik89	+923110000089	Karachi	Test diner #90 for the Karachi environment.	user	2	74	0	12	4.15	1	assets/images/portrait_6.png	{}	{brunch,"street food"}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner090.demo@example.test	scrypt:e93f7e1b2b2ced4c567417fd9c97add5:925eb01e975729669aed340e792c542b4d2869f320a7aee933100dfc31a1ca0443d21b1e2bff340c20a35fa653d4ce527b066401f893da654ef5b8dca494c735		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005b	Mahnoor Khan	mahnoor.khan90	+923110000090	Karachi	Test diner #91 for the Karachi environment.	user	23	78	0	15	3.62	11	assets/images/portrait_1.png	{}	{cafés,seafood}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner091.demo@example.test	scrypt:b60e6aa95be41b83e6acf87ef24d34f4:1d72c074c2057c561b79c11e569e6f8a495e6f55ae5375ef353a63f8633682438260b8eeb2a786a9a07f3dc772abe328078bf24a5174963754d478a682c032af		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005c	Ahmed Sheikh	ahmed.sheikh91	+923110000091	Karachi	Test diner #92 for the Karachi environment.	user	17	80	0	1	3.90	11	assets/images/portrait_2.png	{}	{brunch,cafés}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner092.demo@example.test	scrypt:5f75f3baa1601c204b825a3338a0b0f8:3e85eccf1975ec33af117eb1a5949578ed503a6f0a398840adc53aeec0428c47e1490ade1495f729dfac90dc78c45122e23831d30c09dd39da8ca948a2e09321		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005d	Alina Qureshi	alina.qureshi92	+923110000092	Karachi	Test diner #93 for the Karachi environment.	user	35	50	0	5	4.67	8	assets/images/portrait_3.png	{}	{brunch,desserts}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner093.demo@example.test	scrypt:bdc2402392bdf9851060f2eed208dc08:21c08a8c569fc2ead6b506cca878bc10048185df83f57a89f8bff176f384b1b3f77ee14ed8738436baf4c797ab56e5a35eb4afe1f3b068fe93dd7a0bb9636a1a		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005e	Junaid Memon	junaid.memon93	+923110000093	Karachi	Test diner #94 for the Karachi environment.	user	22	102	0	8	4.26	8	assets/images/portrait_4.png	{}	{cafés,BBQ}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner094.demo@example.test	scrypt:b8a5349cd523bbfea3527d911a2d1b22:15d7d3a19626bfe49c9a15d4d065809f9298da9788cb3ed81982af50672196d69d9581498a26f3d460b91aaaf6fe2a319849840a43bf6f3684f98f88ac1fb1e7		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-00000000005f	Kiran Ansari	kiran.ansari94	+923110000094	Karachi	Test diner #95 for the Karachi environment.	user	19	39	0	13	3.89	8	assets/images/portrait_5.png	{}	{brunch,"street food"}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner095.demo@example.test	scrypt:a105da05ba5ec2f7804202bbe28b99f8:536a0273d2cf16acf6a0a803b928f37f7467357394715025beaa991cc75f0bc499b9fd206addabc12d1014c8eb5472a5058869c43425311374d0edf0afeb135b		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000060	Laiba Siddiqui	laiba.siddiqui95	+923110000095	Karachi	Test diner #96 for the Karachi environment.	user	0	114	0	3	3.81	11	assets/images/portrait_6.png	{}	{cafés,brunch}	#C26B4E	2025	2026-11-02 01:46:22.080529+05	diner096.demo@example.test	scrypt:f1ebe8533d5496ac598469a12fb48b59:e21f53050652d78ec971239661377731eea77f454c5d4fe98ecf91770838afd3879cae49b9b3671a39a5c885f33011a03e889e9aecbe8a26b23039516823219d		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000061	Musa Chaudhry	musa.chaudhry96	+923110000096	Karachi	Test diner #97 for the Karachi environment.	user	21	69	0	11	4.90	2	assets/images/portrait_1.png	{}	{biryani,"street food"}	#7A4A6B	2025	2026-11-02 01:46:22.080529+05	diner097.demo@example.test	scrypt:11c233afa5f48f3951f427bebfa3ad72:0076db62e9f4aff673f0ca26837f0ab3e161c64403d986f577af59d89f7236a5c70e7dccac51fd7f89a5efc11f14bf13f62c36b6bd8f9ce17b451cd0267f3763		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000062	Nida Ibrahim	nida.ibrahim97	+923110000097	Karachi	Test diner #98 for the Karachi environment.	user	19	146	0	9	4.55	12	assets/images/portrait_2.png	{}	{BBQ,BBQ}	#4A5A7A	2025	2026-11-02 01:46:22.080529+05	diner098.demo@example.test	scrypt:96f96f1469e07928b08f9ee9e4b997ef:963ebe008441d079eb5edf0710b3318b2b754bb4301f2cdf36dd3ed8a7347cf5b529f91e16bd17856c8a345ade8174a135af61b0226e6950f2b5290182970af7		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000063	Owais Haider	owais.haider98	+923110000098	Karachi	Test diner #99 for the Karachi environment.	user	35	191	0	18	4.51	10	assets/images/portrait_3.png	{}	{desserts,cafés}	#4A7A5A	2025	2026-11-02 01:46:22.080529+05	diner099.demo@example.test	scrypt:13cfd78f5ad549166d24daef29e0962e:7fa1b6f3365e4f36307bda29ea1a47e12408832c34af6c48e212f13c9288839633d336d05c711291708c1ffbc5e1e7065065518dd9bdd14824fc41d62a20e18a		t	t	t	f	t	{}	{}		f
dddddddd-0000-4000-8000-000000000064	Saba Malik	saba.malik99	+923110000099	Karachi	Test diner #100 for the Karachi environment.	user	35	116	0	5	4.04	5	assets/images/portrait_4.png	{}	{biryani,"street food"}	#8A5A2B	2025	2026-11-02 01:46:22.080529+05	diner100.demo@example.test	scrypt:ea9825a12ab94c082f1d3464d6689ea5:4269487928767536c13dc01aab25fca12e0dab66eda6e3bfc953fea4a13772f3127f7366791f687f1a09894a4a97786980d417167c9247f20e50f052e0b9e5ad		t	t	t	f	t	{}	{}		f
\.


--
-- Data for Name: venue_follows; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.venue_follows (user_id, restaurant_id, created_at) FROM stdin;
\.


--
-- Data for Name: withdrawals; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.withdrawals (id, host_id, amount, method, status, created_at) FROM stdin;
32323232-3232-3232-3232-323232323231	22222222-2222-2222-2222-222222222222	400.00	Bank •••• 7890	completed	2026-10-13 09:00:00+05
32323232-3232-3232-3232-323232323232	22222222-2222-2222-2222-222222222222	250.00	PayPal	processing	2026-10-31 09:00:00+05
\.


--
-- Name: activity activity_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_pkey PRIMARY KEY (id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: auth_tokens auth_tokens_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_tokens
    ADD CONSTRAINT auth_tokens_pkey PRIMARY KEY (token);


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_reference_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_reference_key UNIQUE (reference);


--
-- Name: bookings bookings_stripe_payment_intent_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_stripe_payment_intent_id_key UNIQUE (stripe_payment_intent_id);


--
-- Name: chat_messages chat_messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_pkey PRIMARY KEY (id);


--
-- Name: collaboration_invites collaboration_invites_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaboration_invites
    ADD CONSTRAINT collaboration_invites_pkey PRIMARY KEY (id);


--
-- Name: conversation_participants conversation_participants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_pkey PRIMARY KEY (conversation_id, user_id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: dinner_events dinner_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinner_events
    ADD CONSTRAINT dinner_events_pkey PRIMARY KEY (id);


--
-- Name: email_change_challenges email_change_challenges_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_change_challenges
    ADD CONSTRAINT email_change_challenges_pkey PRIMARY KEY (user_id);


--
-- Name: feedback feedback_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_pkey PRIMARY KEY (id);


--
-- Name: feedback feedback_ticket_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_ticket_key UNIQUE (ticket);


--
-- Name: follows follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_pkey PRIMARY KEY (follower_id, followee_id);


--
-- Name: menu_items menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_pkey PRIMARY KEY (id);


--
-- Name: message_read_receipts message_read_receipts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_read_receipts
    ADD CONSTRAINT message_read_receipts_pkey PRIMARY KEY (message_id, user_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: otp_codes otp_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.otp_codes
    ADD CONSTRAINT otp_codes_pkey PRIMARY KEY (phone);


--
-- Name: partner_subscriptions partner_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_subscriptions
    ADD CONSTRAINT partner_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: partner_subscriptions partner_subscriptions_restaurant_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_subscriptions
    ADD CONSTRAINT partner_subscriptions_restaurant_id_key UNIQUE (restaurant_id);


--
-- Name: partner_verification_requests partner_verification_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_verification_requests
    ADD CONSTRAINT partner_verification_requests_pkey PRIMARY KEY (id);


--
-- Name: payouts payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_pkey PRIMARY KEY (id);


--
-- Name: promo_codes promo_codes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.promo_codes
    ADD CONSTRAINT promo_codes_pkey PRIMARY KEY (code);


--
-- Name: qr_scans qr_scans_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_scans
    ADD CONSTRAINT qr_scans_pkey PRIMARY KEY (id);


--
-- Name: refunds refunds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_pkey PRIMARY KEY (id);


--
-- Name: reports reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_pkey PRIMARY KEY (id);


--
-- Name: reports reports_reference_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reference_key UNIQUE (reference);


--
-- Name: restaurant_branches restaurant_branches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_branches
    ADD CONSTRAINT restaurant_branches_pkey PRIMARY KEY (id);


--
-- Name: restaurant_deals restaurant_deals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_deals
    ADD CONSTRAINT restaurant_deals_pkey PRIMARY KEY (id);


--
-- Name: restaurant_menu_items restaurant_menu_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_items
    ADD CONSTRAINT restaurant_menu_items_pkey PRIMARY KEY (id);


--
-- Name: restaurant_menu_sections restaurant_menu_sections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_sections
    ADD CONSTRAINT restaurant_menu_sections_pkey PRIMARY KEY (id);


--
-- Name: restaurant_payouts restaurant_payouts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_payouts
    ADD CONSTRAINT restaurant_payouts_pkey PRIMARY KEY (id);


--
-- Name: restaurant_staff restaurant_staff_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_staff
    ADD CONSTRAINT restaurant_staff_pkey PRIMARY KEY (user_id, restaurant_id);


--
-- Name: restaurant_tables restaurant_tables_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_tables
    ADD CONSTRAINT restaurant_tables_pkey PRIMARY KEY (id);


--
-- Name: restaurant_tables restaurant_tables_restaurant_id_label_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_tables
    ADD CONSTRAINT restaurant_tables_restaurant_id_label_key UNIQUE (restaurant_id, label);


--
-- Name: restaurants restaurants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurants
    ADD CONSTRAINT restaurants_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_event_id_author_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_event_id_author_id_key UNIQUE (event_id, author_id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (id);


--
-- Name: saved_events saved_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_events
    ADD CONSTRAINT saved_events_pkey PRIMARY KEY (user_id, event_id);


--
-- Name: saved_locations saved_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_locations
    ADD CONSTRAINT saved_locations_pkey PRIMARY KEY (id);


--
-- Name: special_menus special_menus_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.special_menus
    ADD CONSTRAINT special_menus_pkey PRIMARY KEY (id);


--
-- Name: stripe_events stripe_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stripe_events
    ADD CONSTRAINT stripe_events_pkey PRIMARY KEY (id);


--
-- Name: supported_cities supported_cities_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supported_cities
    ADD CONSTRAINT supported_cities_name_key UNIQUE (name);


--
-- Name: supported_cities supported_cities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.supported_cities
    ADD CONSTRAINT supported_cities_pkey PRIMARY KEY (id);


--
-- Name: table_reservations table_reservations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_pkey PRIMARY KEY (id);


--
-- Name: table_reservations table_reservations_reference_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_reference_key UNIQUE (reference);


--
-- Name: user_avatars user_avatars_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_avatars
    ADD CONSTRAINT user_avatars_pkey PRIMARY KEY (user_id);


--
-- Name: user_blocks user_blocks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_blocks
    ADD CONSTRAINT user_blocks_pkey PRIMARY KEY (blocker_id, blocked_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_handle_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_handle_key UNIQUE (handle);


--
-- Name: users users_phone_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_phone_key UNIQUE (phone);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: venue_follows venue_follows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_follows
    ADD CONSTRAINT venue_follows_pkey PRIMARY KEY (user_id, restaurant_id);


--
-- Name: withdrawals withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawals
    ADD CONSTRAINT withdrawals_pkey PRIMARY KEY (id);


--
-- Name: idx_activity_actor; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_activity_actor ON public.activity USING btree (actor_id, created_at DESC);


--
-- Name: idx_audit_log_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_created ON public.audit_log USING btree (created_at DESC);


--
-- Name: idx_audit_log_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_log_user ON public.audit_log USING btree (user_id);


--
-- Name: idx_auth_tokens_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_auth_tokens_user ON public.auth_tokens USING btree (user_id);


--
-- Name: idx_bookings_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_event ON public.bookings USING btree (event_id);


--
-- Name: idx_bookings_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_bookings_user ON public.bookings USING btree (user_id);


--
-- Name: idx_branches_one_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_branches_one_primary ON public.restaurant_branches USING btree (restaurant_id) WHERE is_primary;


--
-- Name: idx_branches_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_branches_rest ON public.restaurant_branches USING btree (restaurant_id);


--
-- Name: idx_chat_conversation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_conversation ON public.chat_messages USING btree (conversation_id, sent_at);


--
-- Name: idx_chat_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_chat_event ON public.chat_messages USING btree (event_id, sent_at);


--
-- Name: idx_collab_invites_host; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collab_invites_host ON public.collaboration_invites USING btree (host_id);


--
-- Name: idx_collab_invites_restaurant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collab_invites_restaurant ON public.collaboration_invites USING btree (restaurant_id);


--
-- Name: idx_collab_invites_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_collab_invites_status ON public.collaboration_invites USING btree (host_id, status);


--
-- Name: idx_conv_parts_conv; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_parts_conv ON public.conversation_participants USING btree (conversation_id);


--
-- Name: idx_conv_parts_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_conv_parts_user ON public.conversation_participants USING btree (user_id);


--
-- Name: idx_conversations_one_per_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_conversations_one_per_event ON public.conversations USING btree (event_id) WHERE (event_id IS NOT NULL);


--
-- Name: idx_deals_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_deals_rest ON public.restaurant_deals USING btree (restaurant_id, status, ends_at);


--
-- Name: idx_events_approval; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_approval ON public.dinner_events USING btree (restaurant_id, status) WHERE (status = ANY (ARRAY['requested'::text, 'declined'::text]));


--
-- Name: idx_events_host; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_host ON public.dinner_events USING btree (host_id);


--
-- Name: idx_events_restaurant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_restaurant ON public.dinner_events USING btree (restaurant_id);


--
-- Name: idx_events_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_start_at ON public.dinner_events USING btree (start_at);


--
-- Name: idx_events_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_status ON public.dinner_events USING btree (status);


--
-- Name: idx_events_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_events_type ON public.dinner_events USING btree (type);


--
-- Name: idx_feedback_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_feedback_user ON public.feedback USING btree (user_id, created_at DESC);


--
-- Name: idx_menu_items_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_menu_items_event ON public.menu_items USING btree (event_id);


--
-- Name: idx_menu_items_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_menu_items_rest ON public.restaurant_menu_items USING btree (restaurant_id, "position");


--
-- Name: idx_menu_items_section; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_menu_items_section ON public.restaurant_menu_items USING btree (section_id, "position");


--
-- Name: idx_menu_sections_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_menu_sections_rest ON public.restaurant_menu_sections USING btree (restaurant_id, "position");


--
-- Name: idx_notifications_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_notifications_rest ON public.notifications USING btree (restaurant_id, notification_time DESC);


--
-- Name: idx_partner_subs_restaurant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partner_subs_restaurant ON public.partner_subscriptions USING btree (restaurant_id);


--
-- Name: idx_payouts_event; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_payouts_event ON public.payouts USING btree (event_id);


--
-- Name: idx_qr_scans_device; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qr_scans_device ON public.qr_scans USING btree (device_hash, scanned_at DESC);


--
-- Name: idx_qr_scans_restaurant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_qr_scans_restaurant ON public.qr_scans USING btree (restaurant_id, scanned_at DESC);


--
-- Name: idx_refunds_booking; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refunds_booking ON public.refunds USING btree (booking_id);


--
-- Name: idx_refunds_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_refunds_event ON public.refunds USING btree (event_id);


--
-- Name: idx_reports_open_duplicate; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_reports_open_duplicate ON public.reports USING btree (reporter_id, target_type, target_id) WHERE (status = ANY (ARRAY['pending'::text, 'reviewing'::text]));


--
-- Name: idx_reports_reporter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reports_reporter ON public.reports USING btree (reporter_id, created_at DESC);


--
-- Name: idx_reports_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reports_status ON public.reports USING btree (status, created_at DESC);


--
-- Name: idx_reports_target; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reports_target ON public.reports USING btree (target_type, target_id);


--
-- Name: idx_reservations_rest_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_rest_time ON public.table_reservations USING btree (restaurant_id, start_at);


--
-- Name: idx_reservations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_status ON public.table_reservations USING btree (restaurant_id, status);


--
-- Name: idx_reservations_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reservations_user ON public.table_reservations USING btree (user_id, start_at DESC);


--
-- Name: idx_rest_payouts_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rest_payouts_rest ON public.restaurant_payouts USING btree (restaurant_id, period_end DESC);


--
-- Name: idx_rest_tables_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_rest_tables_rest ON public.restaurant_tables USING btree (restaurant_id, is_active);


--
-- Name: idx_restaurant_staff_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_restaurant_staff_rest ON public.restaurant_staff USING btree (restaurant_id, status);


--
-- Name: idx_restaurant_staff_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_restaurant_staff_user ON public.restaurant_staff USING btree (user_id, status);


--
-- Name: idx_restaurants_owner; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_restaurants_owner ON public.restaurants USING btree (owner_id);


--
-- Name: idx_restaurants_partnership; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_restaurants_partnership ON public.restaurants USING btree (partnership_status);


--
-- Name: idx_reviews_author; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_author ON public.reviews USING btree (author_id);


--
-- Name: idx_reviews_event; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_reviews_event ON public.reviews USING btree (event_id);


--
-- Name: idx_saved_events_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_events_user ON public.saved_events USING btree (user_id);


--
-- Name: idx_saved_locations_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_saved_locations_user ON public.saved_locations USING btree (user_id);


--
-- Name: idx_special_menus_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_special_menus_rest ON public.special_menus USING btree (restaurant_id);


--
-- Name: idx_user_blocks_blocked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_user_blocks_blocked ON public.user_blocks USING btree (blocked_id);


--
-- Name: idx_verification_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_rest ON public.partner_verification_requests USING btree (restaurant_id, created_at DESC);


--
-- Name: idx_verification_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_verification_status ON public.partner_verification_requests USING btree (status, created_at DESC);


--
-- Name: idx_withdrawals_host; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_withdrawals_host ON public.withdrawals USING btree (host_id);


--
-- Name: reviews_event_author_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reviews_event_author_idx ON public.reviews USING btree (event_id, author_id) WHERE (event_id IS NOT NULL);


--
-- Name: reviews_restaurant_author_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reviews_restaurant_author_idx ON public.reviews USING btree (restaurant_id, author_id) WHERE (restaurant_id IS NOT NULL);


--
-- Name: activity activity_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: activity activity_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.activity
    ADD CONSTRAINT activity_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: auth_tokens auth_tokens_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auth_tokens
    ADD CONSTRAINT auth_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: chat_messages chat_messages_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: chat_messages chat_messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: chat_messages chat_messages_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: chat_messages chat_messages_parent_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_messages
    ADD CONSTRAINT chat_messages_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES public.chat_messages(id);


--
-- Name: collaboration_invites collaboration_invites_experience_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaboration_invites
    ADD CONSTRAINT collaboration_invites_experience_id_fkey FOREIGN KEY (experience_id) REFERENCES public.dinner_events(id);


--
-- Name: collaboration_invites collaboration_invites_host_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaboration_invites
    ADD CONSTRAINT collaboration_invites_host_id_fkey FOREIGN KEY (host_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: collaboration_invites collaboration_invites_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaboration_invites
    ADD CONSTRAINT collaboration_invites_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: conversation_participants conversation_participants_conversation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES public.conversations(id) ON DELETE CASCADE;


--
-- Name: conversation_participants conversation_participants_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversation_participants
    ADD CONSTRAINT conversation_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: conversations conversations_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conversations
    ADD CONSTRAINT conversations_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: dinner_events dinner_events_host_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinner_events
    ADD CONSTRAINT dinner_events_host_id_fkey FOREIGN KEY (host_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: dinner_events dinner_events_restaurant_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinner_events
    ADD CONSTRAINT dinner_events_restaurant_approved_by_fkey FOREIGN KEY (restaurant_approved_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: dinner_events dinner_events_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinner_events
    ADD CONSTRAINT dinner_events_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: email_change_challenges email_change_challenges_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.email_change_challenges
    ADD CONSTRAINT email_change_challenges_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: feedback feedback_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.feedback
    ADD CONSTRAINT feedback_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: follows follows_followee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_followee_id_fkey FOREIGN KEY (followee_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: follows follows_follower_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.follows
    ADD CONSTRAINT follows_follower_id_fkey FOREIGN KEY (follower_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: menu_items menu_items_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.menu_items
    ADD CONSTRAINT menu_items_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: message_read_receipts message_read_receipts_message_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_read_receipts
    ADD CONSTRAINT message_read_receipts_message_id_fkey FOREIGN KEY (message_id) REFERENCES public.chat_messages(id) ON DELETE CASCADE;


--
-- Name: message_read_receipts message_read_receipts_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_read_receipts
    ADD CONSTRAINT message_read_receipts_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: partner_subscriptions partner_subscriptions_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_subscriptions
    ADD CONSTRAINT partner_subscriptions_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: partner_verification_requests partner_verification_requests_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_verification_requests
    ADD CONSTRAINT partner_verification_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: partner_verification_requests partner_verification_requests_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_verification_requests
    ADD CONSTRAINT partner_verification_requests_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: partner_verification_requests partner_verification_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_verification_requests
    ADD CONSTRAINT partner_verification_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: payouts payouts_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payouts
    ADD CONSTRAINT payouts_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: qr_scans qr_scans_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_scans
    ADD CONSTRAINT qr_scans_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.restaurant_branches(id) ON DELETE SET NULL;


--
-- Name: qr_scans qr_scans_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.qr_scans
    ADD CONSTRAINT qr_scans_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: refunds refunds_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: refunds refunds_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: refunds refunds_guest_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.refunds
    ADD CONSTRAINT refunds_guest_id_fkey FOREIGN KEY (guest_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reports reports_reporter_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reports
    ADD CONSTRAINT reports_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: restaurant_branches restaurant_branches_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_branches
    ADD CONSTRAINT restaurant_branches_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_deals restaurant_deals_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_deals
    ADD CONSTRAINT restaurant_deals_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_menu_items restaurant_menu_items_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_items
    ADD CONSTRAINT restaurant_menu_items_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_menu_items restaurant_menu_items_section_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_items
    ADD CONSTRAINT restaurant_menu_items_section_id_fkey FOREIGN KEY (section_id) REFERENCES public.restaurant_menu_sections(id) ON DELETE CASCADE;


--
-- Name: restaurant_menu_sections restaurant_menu_sections_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_sections
    ADD CONSTRAINT restaurant_menu_sections_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.restaurant_branches(id) ON DELETE CASCADE;


--
-- Name: restaurant_menu_sections restaurant_menu_sections_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_menu_sections
    ADD CONSTRAINT restaurant_menu_sections_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_payouts restaurant_payouts_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_payouts
    ADD CONSTRAINT restaurant_payouts_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_staff restaurant_staff_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_staff
    ADD CONSTRAINT restaurant_staff_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: restaurant_staff restaurant_staff_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_staff
    ADD CONSTRAINT restaurant_staff_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurant_staff restaurant_staff_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_staff
    ADD CONSTRAINT restaurant_staff_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: restaurant_tables restaurant_tables_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_tables
    ADD CONSTRAINT restaurant_tables_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.restaurant_branches(id) ON DELETE CASCADE;


--
-- Name: restaurant_tables restaurant_tables_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurant_tables
    ADD CONSTRAINT restaurant_tables_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: restaurants restaurants_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.restaurants
    ADD CONSTRAINT restaurants_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_author_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_author_id_fkey FOREIGN KEY (author_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: saved_events saved_events_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_events
    ADD CONSTRAINT saved_events_event_id_fkey FOREIGN KEY (event_id) REFERENCES public.dinner_events(id) ON DELETE CASCADE;


--
-- Name: saved_events saved_events_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_events
    ADD CONSTRAINT saved_events_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: saved_locations saved_locations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.saved_locations
    ADD CONSTRAINT saved_locations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: special_menus special_menus_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.special_menus
    ADD CONSTRAINT special_menus_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: table_reservations table_reservations_branch_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES public.restaurant_branches(id) ON DELETE SET NULL;


--
-- Name: table_reservations table_reservations_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: table_reservations table_reservations_table_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_table_id_fkey FOREIGN KEY (table_id) REFERENCES public.restaurant_tables(id) ON DELETE SET NULL;


--
-- Name: table_reservations table_reservations_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.table_reservations
    ADD CONSTRAINT table_reservations_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: user_avatars user_avatars_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_avatars
    ADD CONSTRAINT user_avatars_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_blocks user_blocks_blocked_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_blocks
    ADD CONSTRAINT user_blocks_blocked_id_fkey FOREIGN KEY (blocked_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: user_blocks user_blocks_blocker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_blocks
    ADD CONSTRAINT user_blocks_blocker_id_fkey FOREIGN KEY (blocker_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: venue_follows venue_follows_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_follows
    ADD CONSTRAINT venue_follows_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


--
-- Name: venue_follows venue_follows_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.venue_follows
    ADD CONSTRAINT venue_follows_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: withdrawals withdrawals_host_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawals
    ADD CONSTRAINT withdrawals_host_id_fkey FOREIGN KEY (host_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: activity; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.activity ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_log; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

--
-- Name: auth_tokens; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.auth_tokens ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

--
-- Name: chat_messages; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

--
-- Name: collaboration_invites; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.collaboration_invites ENABLE ROW LEVEL SECURITY;

--
-- Name: conversation_participants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;

--
-- Name: conversations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

--
-- Name: dinner_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dinner_events ENABLE ROW LEVEL SECURITY;

--
-- Name: email_change_challenges; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.email_change_challenges ENABLE ROW LEVEL SECURITY;

--
-- Name: feedback; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.feedback ENABLE ROW LEVEL SECURITY;

--
-- Name: follows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;

--
-- Name: menu_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

--
-- Name: message_read_receipts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.message_read_receipts ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: otp_codes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.otp_codes ENABLE ROW LEVEL SECURITY;

--
-- Name: partner_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partner_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: partner_verification_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partner_verification_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: payouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payouts ENABLE ROW LEVEL SECURITY;

--
-- Name: promo_codes; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

--
-- Name: refunds; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.refunds ENABLE ROW LEVEL SECURITY;

--
-- Name: reports; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_branches; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_branches ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_deals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_deals ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_menu_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_menu_items ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_menu_sections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_menu_sections ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_payouts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_payouts ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_staff; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_staff ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurant_tables; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;

--
-- Name: restaurants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;

--
-- Name: reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.saved_events ENABLE ROW LEVEL SECURITY;

--
-- Name: saved_locations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.saved_locations ENABLE ROW LEVEL SECURITY;

--
-- Name: special_menus; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.special_menus ENABLE ROW LEVEL SECURITY;

--
-- Name: stripe_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stripe_events ENABLE ROW LEVEL SECURITY;

--
-- Name: supported_cities; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.supported_cities ENABLE ROW LEVEL SECURITY;

--
-- Name: table_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.table_reservations ENABLE ROW LEVEL SECURITY;

--
-- Name: user_avatars; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_avatars ENABLE ROW LEVEL SECURITY;

--
-- Name: user_blocks; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- Name: venue_follows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.venue_follows ENABLE ROW LEVEL SECURITY;

--
-- Name: withdrawals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 19hE0hyD4yWqubsnMFaHniZndMyaTavXCxPEmB62IhxbnxPGztVKhnmQQB2c6lC

