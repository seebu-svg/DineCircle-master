--
-- PostgreSQL database dump
--

\restrict RxdjKlMgGuSdB3qaTUEOyYF7E3CuTeI2XuipQRw6zi0SmweLb0TK8cbkxqEVNM7

-- Dumped from database version 17.11
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
-- Data for Name: dinner_events; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.dinner_events (id, title, tagline, description, host_id, restaurant_id, cover_image, gallery, start_at, end_at, duration_minutes, seats_total, seats_booked, price_per_seat, type, audience, menu_style, included, tags, is_featured, host_note, language, dress_code, cancellation, attendee_ids, status, created_at, views, requires_approval, is_demo, restaurant_approved_at, restaurant_approved_by, decline_reason, collaborator_ids) FROM stdin;
cccccccc-0000-4000-8000-000000000001	Seaside BBQ Dinner	Sea-facing dining since 1989 — demo edition	Mock long-table dinner at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000001	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-10-19 19:00:00+05	2026-10-19 22:00:00+05	180	21	14	5500.00	dinner	inviteOnly	setMenu	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000002,dddddddd-0000-4000-8000-000000000003,dddddddd-0000-4000-8000-000000000004,dddddddd-0000-4000-8000-000000000005}	completed	2026-11-02 01:46:22.134907+05	2424	f	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2	Sunday Slow Brunch	Lazy plates, bottomless coffee	A family-style brunch with fresh-baked bread and a long coffee tail.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2	assets/images/dish_brunch.png	{}	2026-11-11 11:00:00+05	2026-11-11 13:00:00+05	120	16	5	38.00	brunch	public	familyStyle	{"Bottomless coffee",pastries}	{pasta,seasonal,date-night}	f	Kid-friendly.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	1930	f	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee4	Tasting Menu Tryout	Seats held until the host approves	A small preview supper where every seat needs a nod from Nora before it is confirmed.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/hero_tasting.png	{}	2026-11-08 18:00:00+05	2026-11-08 20:30:00+05	150	10	1	45.00	tasting	public	setMenu	{"5 courses"}	{tasting,seasonal}	f	I approve each seat personally — ping me if unsure.	English	Smart casual	Free cancellation up to 48 hours before	{33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	1120	t	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3	Cellar Supper	Candles and old vintages	A completed supper club in the wine cellar.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/hero_tasting.png	{}	2026-10-23 20:00:00+05	2026-10-23 22:30:00+05	150	10	10	72.00	supperClub	public	setMenu	{"5 courses",flight}	{pasta,seasonal,date-night}	f	Thank you all.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	completed	2026-11-02 01:46:02.927338+05	2410	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000002	Kolachi Supper Club Night	Sea-facing dining since 1989 — demo edition	Mock chef tasting at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000002	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-10-18 19:00:00+05	2026-10-18 22:00:00+05	180	31	8	6500.00	tasting	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000006,dddddddd-0000-4000-8000-000000000007,dddddddd-0000-4000-8000-000000000008,dddddddd-0000-4000-8000-000000000009,dddddddd-0000-4000-8000-00000000000a}	completed	2026-11-02 01:46:22.134907+05	2366	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000003	Kolachi Long Table Session	Sea-facing dining since 1989 — demo edition	Mock supper club at Kolachi Restaurant (DHA Phase 8). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000003	bbbbbbbb-0000-4000-8000-000000000001	assets/images/venue_rooftop.png	{}	2026-11-06 19:00:00+05	2026-11-06 22:00:00+05	180	36	15	14000.00	supperClub	public	familyStyle	{"Welcome drink","Shared plates",Dessert}	{seaside,bbq,family}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000000b,dddddddd-0000-4000-8000-00000000000c,dddddddd-0000-4000-8000-00000000000d,dddddddd-0000-4000-8000-00000000000e,dddddddd-0000-4000-8000-00000000000f}	confirmed	2026-11-02 01:46:22.134907+05	2525	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000005	Xander's Supper Club Night	Coffee-house classics, all day — demo edition	Mock kitchen workshop at Xander's Clifton (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000005	bbbbbbbb-0000-4000-8000-000000000002	assets/images/venue_interior.png	{}	2026-11-08 19:00:00+05	2026-11-08 22:00:00+05	180	27	14	8000.00	workshop	public	buffet	{"Welcome drink","Shared plates",Dessert}	{brunch,cafe,meetup}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000015,dddddddd-0000-4000-8000-000000000016,dddddddd-0000-4000-8000-000000000017,dddddddd-0000-4000-8000-000000000018,dddddddd-0000-4000-8000-000000000019}	confirmed	2026-11-02 01:46:22.134907+05	852	f	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000006	Xander's Long Table Session	Coffee-house classics, all day — demo edition	Mock food festival at Xander's Clifton (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000006	bbbbbbbb-0000-4000-8000-000000000002	assets/images/venue_interior.png	{}	2026-10-14 19:00:00+05	2026-10-14 22:00:00+05	180	24	10	7500.00	festival	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{brunch,cafe,meetup}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001a,dddddddd-0000-4000-8000-00000000001b,dddddddd-0000-4000-8000-00000000001c,dddddddd-0000-4000-8000-00000000001d,dddddddd-0000-4000-8000-00000000001e}	completed	2026-11-02 01:46:22.134907+05	2840	f	t	\N	\N		{}
eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1	Omakase Under the Stars	A seven-course chef counter at dusk	A long-table tasting built around whatever the market gave us this morning. Wine pairing optional.	22222222-2222-2222-2222-222222222222	aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1	assets/images/dish_sushi.png	{assets/images/dish_sushi.png,assets/images/hero_tasting.png}	2026-11-05 19:00:00+05	2026-11-05 22:00:00+05	180	12	3	95.00	tasting	public	tastingMenu	{"7 courses","welcome drink"}	{pasta,seasonal,date-night}	t	Meet at the rooftop door; lifts until 23:00.	English	Smart casual	Free cancellation up to 48 hours before	{11111111-1111-1111-1111-111111111111,33333333-3333-3333-3333-333333333333}	confirmed	2026-11-02 01:46:02.927338+05	2842	f	t	\N	\N		{}
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
cccccccc-0000-4000-8000-000000000013	Chinese Fine Dining	Saddar institution for Chinese-Karachi classics — demo edition	Mock long-table dinner at Dynasty (Saddar). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000009	bbbbbbbb-0000-4000-8000-000000000007	assets/images/dish_sushi.png	{}	2026-11-22 19:00:00+05	2026-11-22 22:00:00+05	180	36	9	12500.00	dinner	followers	sharing	{"Welcome drink","Shared plates",Dessert}	{chinese,family,heritage}	t	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000005b,dddddddd-0000-4000-8000-00000000005c,dddddddd-0000-4000-8000-00000000005d,dddddddd-0000-4000-8000-00000000005e,dddddddd-0000-4000-8000-00000000005f}	confirmed	2026-11-02 01:46:22.134907+05	1996	t	t	\N	\N		{}
cccccccc-0000-4000-8000-000000000016	Desi Food Meetup	Desi plates in a cantonment-heritage setting — demo edition	Mock slow brunch at Kanteen (Tipu Sultan). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000002	bbbbbbbb-0000-4000-8000-000000000008	assets/images/dish_pasta.png	{}	2026-09-28 19:00:00+05	2026-09-28 22:00:00+05	180	32	14	6000.00	brunch	public	tastingMenu	{"Welcome drink","Shared plates",Dessert}	{desi,meetup,casual}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000006,dddddddd-0000-4000-8000-000000000007,dddddddd-0000-4000-8000-000000000008,dddddddd-0000-4000-8000-000000000009,dddddddd-0000-4000-8000-00000000000a}	completed	2026-11-02 01:46:22.134907+05	1287	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001a	Foods Supper Club Night	Family buffet and karahi corner — demo edition	Mock chef tasting at Foods Inn (SMCHS). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000006	bbbbbbbb-0000-4000-8000-000000000009	assets/images/dish_brunch.png	{}	2026-09-24 19:00:00+05	2026-09-24 22:00:00+05	180	27	12	4500.00	tasting	public	setMenu	{"Welcome drink","Shared plates",Dessert}	{buffet,family,festival}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000001a,dddddddd-0000-4000-8000-00000000001b,dddddddd-0000-4000-8000-00000000001c,dddddddd-0000-4000-8000-00000000001d,dddddddd-0000-4000-8000-00000000001e}	completed	2026-11-02 01:46:22.134907+05	1592	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000001e	The Long Table Session	Garden dining with old-city charm — demo edition	Mock food festival at The East End (Clifton). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-00000000000a	bbbbbbbb-0000-4000-8000-00000000000a	assets/images/venue_interior.png	{}	2026-12-03 19:00:00+05	2026-12-03 22:00:00+05	180	26	8	12000.00	festival	public	buffet	{"Welcome drink","Shared plates",Dessert}	{heritage,garden,date-night}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-00000000002e,dddddddd-0000-4000-8000-00000000002f,dddddddd-0000-4000-8000-000000000030,dddddddd-0000-4000-8000-000000000032}	confirmed	2026-11-02 01:46:22.134907+05	798	f	t	\N	\N		{}
cccccccc-0000-4000-8000-00000000000e	Chef's Supper Club Night	Counter-side tasting by resident chefs — demo edition	Mock chef tasting at Chef's Table Pakistan (DHA Phase 6). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.	ffffffff-0000-4000-8000-000000000004	bbbbbbbb-0000-4000-8000-000000000005	assets/images/hero_tasting.png	{}	2026-11-17 19:00:00+05	2026-11-17 22:00:00+05	180	18	12	13500.00	tasting	public	sharing	{"Welcome drink","Shared plates",Dessert}	{tasting,chef-counter,premium}	f	Demo note: the mock check-in desk opens 15 minutes early.	English	Smart casual	Free cancellation up to 48 hours before	{dddddddd-0000-4000-8000-000000000042,dddddddd-0000-4000-8000-000000000043,dddddddd-0000-4000-8000-000000000044,dddddddd-0000-4000-8000-000000000045,dddddddd-0000-4000-8000-000000000046,e9658dab-d513-4ea8-a5f2-feece8033d0a}	confirmed	2026-11-02 01:46:22.134907+05	934	f	t	\N	\N		{}
\.


--
-- Data for Name: partner_subscriptions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.partner_subscriptions (id, restaurant_id, plan, status, price_pkr, period_start, period_end, auto_renew, cancelled_at, created_at, updated_at) FROM stdin;
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
-- Data for Name: table_reservations; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.table_reservations (id, restaurant_id, branch_id, table_id, user_id, guest_name, guest_phone, party_size, start_at, duration_minutes, status, reference, notes, source, created_at, updated_at) FROM stdin;
6ec90b55-f9c1-42ba-be6f-1eaf4c3ab19f	bbbbbbbb-0000-4000-8000-000000000001	\N	\N	27e49df8-1635-47a2-a5b7-94b2433adf73	QA Mobile		2	2026-11-07 00:00:00+05	90	pending	TR-FABW5		customer	2026-11-04 17:39:53.402221+05	2026-11-04 17:39:53.402221+05
87832676-7034-4178-bc54-e2169f8f37d5	bbbbbbbb-0000-4000-8000-000000000001	\N	\N	a665a235-ddd1-408a-a637-125441c5f6ac	QA Api		2	2026-11-10 19:00:00+05	90	pending	TR-FJREH		customer	2026-11-04 17:46:49.204243+05	2026-11-04 17:46:49.204243+05
\.


--
-- Name: dinner_events dinner_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinner_events
    ADD CONSTRAINT dinner_events_pkey PRIMARY KEY (id);


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
-- Name: idx_branches_one_primary; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_branches_one_primary ON public.restaurant_branches USING btree (restaurant_id) WHERE is_primary;


--
-- Name: idx_branches_rest; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_branches_rest ON public.restaurant_branches USING btree (restaurant_id);


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
-- Name: idx_partner_subs_restaurant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partner_subs_restaurant ON public.partner_subscriptions USING btree (restaurant_id);


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
-- Name: partner_subscriptions partner_subscriptions_restaurant_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_subscriptions
    ADD CONSTRAINT partner_subscriptions_restaurant_id_fkey FOREIGN KEY (restaurant_id) REFERENCES public.restaurants(id) ON DELETE CASCADE;


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
-- Name: dinner_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.dinner_events ENABLE ROW LEVEL SECURITY;

--
-- Name: partner_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partner_subscriptions ENABLE ROW LEVEL SECURITY;

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
-- Name: table_reservations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.table_reservations ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict RxdjKlMgGuSdB3qaTUEOyYF7E3CuTeI2XuipQRw6zi0SmweLb0TK8cbkxqEVNM7

