/**
 * Karachi demo venue seed, recognisable Karachi restaurants and cafés, built
 * as COMPLETE DineCircle storefronts for MVP testing.
 *
 * ⚠️  DESTRUCTIVE: running this DELETES every existing venue (and, by FK
 * cascade, its branches, menu, deals, tables, reservations, experiences,
 * reviews, follows, subscription and scan rows). Take a pg_dump first.
 *
 * Every record written here is test content:
 *   • restaurants.is_demo = true and a `demo` tag on every venue
 *   • restaurants.is_partner = false, partnership_status = 'unverified'
 *     → no venue is presented as an official DineCircle partner
 *   • rating / review_count are left at 0: DineCircle does not invent ratings
 *   • phone numbers are placeholder ranges, not the businesses' real lines
 *   • menus, prices, deals and experiences are SAMPLE data written for testing
 *
 * What each venue gets: identity + description + cuisine, cover and gallery,
 * address/area/coordinates, contact, per-weekday opening hours (Asia/Karachi
 * service windows), amenities, a printed kitchen menu in PKR with photos and
 * dietary tags, two demo deals with validity, terms and redemption steps, a
 * bookable table floor, and,where the venue has one,a curated demo
 * experience led by one of the [HOSTS] accounts.
 *
 * Usage: npm run db:seed:karachi
 */
import { pool, query } from './db.js';

const DEMO_TAG = 'demo';
const OWNER_FALLBACK_ID = 'aaaaaaaa-0000-4000-8000-0000000000aa';
const HOST_FALLBACK_ID = 'aaaaaaaa-0000-4000-8000-0000000000bb';

const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;

/** Lowercase per-weekday `{windows:[{open,close}]}` shape the availability
 *  engine actually reads. Optional closed days become `{closed:true}`. */
function hours(open: string, close: string, closed: readonly string[] = []): string {
  const out: Record<string, unknown> = {};
  for (const day of DAYS) {
    out[day] = closed.includes(day) ? { closed: true } : { windows: [{ open, close }] };
  }
  return JSON.stringify(out);
}

/** Wall-clock moment `dayOffset` days ahead at hour:minute, venue-local-ish. */
function at(dayOffset: number, hour: number, minute = 0): string {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  d.setDate(d.getDate() + dayOffset);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

function daysAhead(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString();
}

/** [name, description, pricePKR, photo?, dietaryTags?] */
type Item = [
  name: string,
  description: string,
  price: number,
  photo?: string,
  tags?: string[],
];

type Section = { name: string; items: Item[] };

type Deal = {
  title: string;
  description: string;
  kind: 'percent' | 'fixed' | 'package';
  value: number;
  code?: string;
  maxRedemptions: number;
  /** Guest-facing conditions: validity windows, exclusions, per-table limits. */
  terms: string;
  /** What the guest says or shows at the table to redeem it. */
  redemption: string;
  /** Bundled detail image; falls back to the venue cover when omitted. */
  image?: string;
  /** Days the offer stays valid from today. Defaults to [DEFAULT_DEAL_DAYS]. */
  validDays?: number;
};

type EventSeed = {
  title: string;
  tagline: string;
  description: string;
  cover: string;
  dayOffset: number;
  hour: number;
  durationMinutes: number;
  seats: number;
  booked: number;
  /** Estimated restaurant dining cost per person, paid to the venue, not a
   *  DineCircle fee. The RSVP itself is free. */
  pricePkr: number;
  type: 'dinner' | 'tasting' | 'supperClub' | 'brunch' | 'workshop' | 'festival';
  menuStyle: 'setMenu' | 'tastingMenu' | 'familyStyle' | 'sharing' | 'buffet';
  /** Key into [HOSTS], the demo host account that leads the experience. */
  hostKey: HostKey;
  included: string[];
  tags: string[];
  hostNote: string;
};

type Venue = {
  key: string;
  name: string;
  tagline: string;
  about: string;
  cuisines: string[];
  area: string;
  address: string;
  priceRange: string;
  amenities: string[];
  tags: string[];
  cover: string;
  gallery: string[];
  lat: number;
  lng: number;
  open: string;
  close: string;
  closedDays?: string[];
  seats: number;
  sections: Section[];
  deals: Deal[];
  tables: [label: string, seats: number, zone: string][];
  events: EventSeed[];
};

const DEMO_NOTE =
  'Demo profile for DineCircle testing. Menu, prices, deals and experiences are '
  + 'sample content, not an official partnership or a real offer.';

/** Every seeded deal is fictional test content and says so in its own copy. */
const DEMO_DEAL_LABEL = 'Demo / Test Offer';
const DEFAULT_DEAL_DAYS = 45;

/**
 * Demo deals are visible by default so the customer and partner apps have
 * something to render. They are labelled test content and belong to venues
 * flagged `is_demo`/`partnership_status='unverified'`, so nothing here claims
 * an approved promotion. Run with `DEAL_STATUS=draft` to stage them hidden
 * until a venue approves the copy.
 */
const DEAL_STATUS = process.env.DEAL_STATUS === 'draft' ? 'draft' : 'active';

/** Guest-facing copy stored in `restaurant_deals.description`. */
function dealDescription(d: Deal): string {
  return `${DEMO_DEAL_LABEL}: ${d.description}`;
}

/** Conditions plus redemption steps, stored in `restaurant_deals.terms`. */
function dealTerms(d: Deal): string {
  return `${d.terms} How to redeem: ${d.redemption}`;
}

const DEMO_EXPERIENCE_NOTE =
  'Demo experience: the inclusions and the estimated dining cost are sample '
  + 'content, not a confirmed restaurant offer. RSVP is free and you pay the '
  + 'restaurant directly.';

/**
 * Demo host accounts that lead the seeded experiences. Each experience names
 * one by [HostKey]; the seed creates the account when it is missing so the
 * host profile screen has a real, followable host behind every event.
 */
const HOSTS = [
  { key: 'food-creator', name: 'Food Creator', handle: 'demo.foodcreator', id: 'aaaaaaaa-0000-4000-8000-0000000000c1' },
  { key: 'lifestyle-creator', name: 'Lifestyle Creator', handle: 'demo.lifestylecreator', id: 'aaaaaaaa-0000-4000-8000-0000000000c2' },
  { key: 'community-host', name: 'Community Host', handle: 'demo.communityhost', id: 'aaaaaaaa-0000-4000-8000-0000000000c3' },
  { key: 'coffee-enthusiast', name: 'Coffee Enthusiast', handle: 'demo.coffeeenthusiast', id: 'aaaaaaaa-0000-4000-8000-0000000000c4' },
  { key: 'social-dining-host', name: 'Social Dining Host', handle: 'demo.socialdininghost', id: 'aaaaaaaa-0000-4000-8000-0000000000c5' },
] as const;

type HostKey = (typeof HOSTS)[number]['key'];

// Asset paths are bundled with the customer app (lib/assets/images).
const A = {
  steak: 'assets/images/dish_steak.png',
  sushi: 'assets/images/dish_sushi.png',
  pasta: 'assets/images/dish_pasta.png',
  brunch: 'assets/images/dish_brunch.png',
  dessert: 'assets/images/dish_dessert.png',
  tacos: 'assets/images/dish_tacos.png',
  tasting: 'assets/images/hero_tasting.png',
  bar: 'assets/images/venue_bar.png',
  interior: 'assets/images/venue_interior.png',
  rooftop: 'assets/images/venue_rooftop.png',
};

const VENUES: Venue[] = [
  // ── 1. Kolachi Restaurant: Do Darya ────────────────────────────────────────
  {
    key: 'kolachi',
    name: 'Kolachi Restaurant',
    tagline: 'Sea-facing Pakistani dining at Do Darya',
    about:
      'A Do Darya seaside institution known for grilled seafood, mutton karahi and '
      + 'long family tables looking out over the water. ' + DEMO_NOTE,
    cuisines: ['Pakistani', 'Seafood', 'BBQ'],
    area: 'Do Darya, DHA Phase 8',
    address: 'Do Darya seafront, DHA Phase 8, Karachi',
    priceRange: '$$$',
    amenities: ['Seafront seating', 'Family sections', 'Valet parking', 'Wheelchair access', 'Card payments'],
    tags: ['seaside', 'bbq', 'family', 'karahi'],
    cover: A.rooftop,
    gallery: [A.steak, A.bar, A.sushi],
    lat: 24.8055, lng: 67.0305,
    open: '13:00', close: '23:30',
    seats: 220,
    sections: [
      {
        name: 'From the Grill',
        items: [
          ['Grilled Prawns', 'Jumbo prawns, lemon butter and green chutney.', 2450, A.steak, ['seafood']],
          ['Fish Tikka', 'Marinated fillets finished over charcoal.', 1890, A.steak, ['seafood', 'spicy']],
          ['Chicken Malai Boti', 'Cream-marinated boneless chicken, charcoal grilled.', 1290, A.steak],
          ['Mutton Chops', 'Four chops, dry rub, served with mint raita.', 2650, A.steak],
        ],
      },
      {
        name: 'Karahi & Curries',
        items: [
          ['Mutton Karahi (Half)', 'Tomato-forward karahi with ginger and green chilli.', 3450],
          ['Chicken Karahi (Full)', 'Cooked to order in a black iron karahi.', 2790, undefined, ['spicy']],
          ['Prawn Karahi', 'Prawns simmered in a light tomato masala.', 2890, undefined, ['seafood']],
        ],
      },
      {
        name: 'Rice & Breads',
        items: [
          ['Mutton Pulao', 'Long-grain rice with slow-cooked mutton stock.', 1490],
          ['Garlic Naan', 'Tandoor naan brushed with garlic butter.', 220, undefined, ['vegetarian']],
          ['Kachumber Salad', 'Onion, tomato, cucumber, lemon.', 390, undefined, ['vegetarian', 'vegan']],
        ],
      },
      {
        name: 'Desserts & Drinks',
        items: [
          ['Kulfi Falooda', 'Traditional kulfi with vermicelli and rose syrup.', 690, A.dessert, ['vegetarian']],
          ['Fresh Lime Soda', 'Sweet or salted.', 350, undefined, ['vegan']],
        ],
      },
    ],
    deals: [
      {
        title: '15% off family dinner',
        description: '15% off the total bill for family tables at dinner service.',
        kind: 'percent', value: 15, code: 'KOLACHI15', maxRedemptions: 200,
        image: A.steak,
        terms: 'Dine-in only, 19:00–23:00, tables of four or more, one offer per table, excludes public holidays.',
        redemption: 'Show this deal to your server before the bill is printed.',
      },
      {
        title: 'BBQ platter for Rs. 2,999',
        description: 'Shared grill platter for four: seekh kebab, chicken tikka, malai boti, naan and raita at a set price.',
        kind: 'package', value: 2999, maxRedemptions: 150,
        image: A.steak, validDays: 30,
        terms: 'Fixed contents, no substitutions, dine-in only, available after 19:00.',
        redemption: 'Ask for the DineCircle BBQ platter when ordering.',
      },
    ],
    tables: [['K1', 2, 'Seafront Deck'], ['K2', 4, 'Seafront Deck'], ['K3', 6, 'Verandah'], ['K4', 8, 'Family Section']],
    events: [
      {
        title: 'BBQ Night with Foodies',
        tagline: 'Shared grill platters and a table full of strangers',
        description:
          'A hosted BBQ dinner at Do Darya for people who plan their week around '
          + 'food. A shared grill table, plenty of introductions, then dinner. '
          + DEMO_EXPERIENCE_NOTE,
        cover: A.steak, dayOffset: 3, hour: 20, durationMinutes: 150,
        seats: 10, booked: 3, pricePkr: 2500, type: 'dinner', menuStyle: 'sharing',
        hostKey: 'food-creator',
        included: ['BBQ platter', 'Naan', 'Drinks', 'Shared dining table', 'Group meetup'],
        tags: ['bbq', 'meetup', 'group'],
        hostNote: 'Meet at the seafront deck entrance 10 minutes early.',
      },
    ],
  },

  // ── 2. Kababjees: Do Darya ─────────────────────────────────────────────────
  {
    key: 'kababjees',
    name: 'Kababjees',
    tagline: 'Charcoal kebabs and family grills',
    about:
      'A busy Do Darya grill house built around seekh kebab, tikka and '
      + 'family-sized platters. ' + DEMO_NOTE,
    cuisines: ['BBQ', 'Pakistani'],
    area: 'Do Darya, DHA Phase 8',
    address: 'Do Darya, DHA Phase 8, Karachi',
    priceRange: '$$',
    amenities: ['Outdoor seating', 'Family hall', 'Takeaway', 'Card payments'],
    tags: ['bbq', 'family', 'casual'],
    cover: A.steak,
    gallery: [A.interior, A.brunch],
    lat: 24.8041, lng: 67.0281,
    open: '16:00', close: '23:59',
    seats: 180,
    sections: [
      {
        name: 'Kebabs',
        items: [
          ['Chicken Seekh Kebab', 'Four skewers, mint chutney and onion.', 990, A.steak],
          ['Beef Seekh Kebab', 'Coarse-ground beef, charred edges.', 1150, A.steak],
          ['Chicken Tikka (Half)', 'Bone-in, red masala marinade.', 1090, undefined, ['spicy']],
          ['Bihari Boti', 'Thin-sliced beef in papaya marinade.', 1390],
        ],
      },
      {
        name: 'Platters',
        items: [
          ['Family Mixed Grill', 'Kebabs, boti, tikka and naan for four.', 4590, A.steak, ['spicy']],
          ['Kababjees Special Platter', 'Chef selection for two.', 2890],
        ],
      },
      {
        name: 'Sides & Drinks',
        items: [
          ['Garlic Naan', 'Fresh from the tandoor.', 200, undefined, ['vegetarian']],
          ['Raita', 'Yoghurt, cucumber and mint.', 250, undefined, ['vegetarian']],
          ['Soft Drink', 'Chilled bottle.', 150, undefined, ['vegan']],
        ],
      },
    ],
    deals: [
      {
        title: '20% off dinner',
        description: '20% off the food bill on dinner orders for dine-in guests.',
        kind: 'percent', value: 20, code: 'KABABJEES20', maxRedemptions: 250,
        image: A.steak,
        terms: 'From 19:00, food only, excludes drinks and desserts, not combinable with other offers.',
        redemption: 'Quote the code to your server before ordering.',
      },
      {
        title: 'Family BBQ combo for Rs. 3,499',
        description: 'Family combo for four: two kebab platters, chicken tikka, naan, salad and soft drinks.',
        kind: 'package', value: 3499, maxRedemptions: 150,
        image: A.steak, validDays: 30,
        terms: 'For four guests, fixed items, dine-in only.',
        redemption: 'Ask for the DineCircle family combo at the counter.',
      },
    ],
    tables: [['B1', 2, 'Patio'], ['B2', 4, 'Family Hall'], ['B3', 6, 'Family Hall'], ['B4', 8, 'Outdoor']],
    events: [],
  },

  // ── 3. Bar B Q Tonight: Clifton ────────────────────────────────────────────
  {
    key: 'bbq-tonight',
    name: 'Bar B Q Tonight',
    tagline: 'Clifton grill house, open late',
    about:
      'A Clifton grill institution with an open charcoal floor and a menu of '
      + 'kebabs, tikka and karahi served late. ' + DEMO_NOTE,
    cuisines: ['BBQ', 'Pakistani', 'Karahi'],
    area: 'Boat Basin, Clifton',
    address: 'Boat Basin, Clifton, Karachi',
    priceRange: '$$',
    amenities: ['Open grill floor', 'Late hours', 'Family cabins', 'Parking'],
    tags: ['bbq', 'late-night', 'casual'],
    cover: A.bar,
    gallery: [A.steak, A.interior],
    lat: 24.8100, lng: 67.0255,
    open: '16:00', close: '23:59',
    seats: 200,
    sections: [
      {
        name: 'Grill',
        items: [
          ['Chicken Malai Boti', 'Creamy marinade, soft char.', 1250, A.steak],
          ['Beef Bihari Kebab', 'Sliced beef, mustard and papaya.', 1450],
          ['Mutton Seekh Kebab', 'Hand-minced mutton skewers.', 1590, A.steak],
          ['Grilled Chicken (Full)', 'Half or full, with chutney.', 1790],
        ],
      },
      {
        name: 'Karahi',
        items: [
          ['Chicken Karahi (Half)', 'Tomato, ginger, green chilli.', 2190, undefined, ['spicy']],
          ['Mutton Karahi (Half)', 'Slow-cooked, bone-in.', 3290],
        ],
      },
      {
        name: 'Breads & Sides',
        items: [
          ['Tandoori Roti', 'Whole wheat, fresh.', 90, undefined, ['vegetarian', 'vegan']],
          ['Green Salad', 'Seasonal vegetables.', 290, undefined, ['vegetarian', 'vegan']],
          ['Mint Lemonade', 'Fresh mint, lemon, soda.', 390, undefined, ['vegan']],
        ],
      },
    ],
    deals: [
      {
        title: '15% off BBQ buffet',
        description: '15% off the per-person BBQ buffet for dine-in guests.',
        kind: 'percent', value: 15, code: 'BBQT15', maxRedemptions: 200,
        image: A.steak,
        terms: 'Buffet timings 19:30–23:00, per person, excludes drinks, dine-in only.',
        redemption: 'Mention the code at reception before the buffet starts.',
      },
      {
        title: 'Buy 2 mains, get 1 free',
        description: 'Order two main courses and the lowest-priced third main is free.',
        kind: 'package', value: 0, maxRedemptions: 120,
        image: A.steak, validDays: 30,
        terms: 'Minimum two paying guests, free item is the lowest-priced main, dine-in only.',
        redemption: 'Tell your server the deal is being applied when ordering.',
      },
    ],
    tables: [['N1', 2, 'Open Grill Floor'], ['N2', 4, 'Patio'], ['N3', 6, 'Family Cabin'], ['N4', 8, 'Family Cabin']],
    events: [],
  },

  // ── 4. Cafe Aylanto: Clifton ───────────────────────────────────────────────
  {
    key: 'cafe-aylanto',
    name: 'Cafe Aylanto',
    tagline: 'Courtyard dining in Clifton',
    about:
      'A courtyard restaurant in Clifton serving Mediterranean and Lebanese '
      + 'plates with a long wine-list feel. ' + DEMO_NOTE,
    cuisines: ['Mediterranean', 'Lebanese', 'Continental'],
    area: 'Clifton',
    address: 'Clifton Block 5, Karachi',
    priceRange: '$$$',
    amenities: ['Courtyard seating', 'Terrace', 'Reservations recommended', 'Card payments'],
    tags: ['mediterranean', 'courtyard', 'date-night'],
    cover: A.bar,
    gallery: [A.pasta, A.dessert, A.interior],
    lat: 24.8160, lng: 67.0280,
    open: '12:00', close: '23:00',
    seats: 120,
    sections: [
      {
        name: 'Mezze',
        items: [
          ['Hummus Beiruti', 'Chickpeas, tahini, chilli and olive oil.', 890, undefined, ['vegetarian', 'vegan']],
          ['Falafel Plate', 'Six falafel, pickles, tahini sauce.', 950, undefined, ['vegetarian', 'vegan']],
          ['Moutabel', 'Smoked aubergine with yoghurt and mint.', 920, undefined, ['vegetarian']],
          ['Fattoush', 'Sumac, crisp pita, seasonal leaves.', 850, undefined, ['vegetarian']],
        ],
      },
      {
        name: 'Mains',
        items: [
          ['Grilled Chicken Breast', 'Lemon-herb marinade, seasonal vegetables.', 2350],
          ['Lamb Kofta', 'Charcoal-grilled, served with rice.', 2890],
          ['Sea Bass Fillet', 'Pan-seared, salsa verde.', 3250, A.sushi, ['seafood']],
        ],
      },
      {
        name: 'Pasta & Risotto',
        items: [
          ['Penne Arrabbiata', 'Tomato, garlic, chilli.', 1750, A.pasta, ['vegetarian', 'spicy']],
          ['Mushroom Risotto', 'Arborio rice, parmesan, truffle oil.', 1950, A.pasta, ['vegetarian']],
        ],
      },
      {
        name: 'Desserts',
        items: [
          ['Baklava', 'Pistachio, honey syrup.', 750, A.dessert, ['vegetarian']],
          ['Chocolate Fondant', 'Warm centre, vanilla ice cream.', 890, A.dessert, ['vegetarian']],
        ],
      },
    ],
    deals: [
      {
        title: '20% off lunch',
        description: '20% off the food bill at lunch service, weekdays.',
        kind: 'percent', value: 20, code: 'AYLANTO20', maxRedemptions: 150,
        image: A.pasta,
        terms: 'Monday–Friday 12:30–16:00, food only, not valid on public holidays.',
        redemption: 'Show the deal to your server before ordering.',
      },
      {
        title: 'Couple dinner for Rs. 4,999',
        description: 'Three courses for two: shared mezze, two mains and one dessert at a set price.',
        kind: 'package', value: 4999, maxRedemptions: 60,
        image: A.pasta, validDays: 30,
        terms: 'For two guests, fixed menu, table booking recommended.',
        redemption: 'Ask for the DineCircle couple dinner when reserving.',
      },
    ],
    tables: [['A1', 2, 'Courtyard'], ['A2', 4, 'Courtyard'], ['A3', 6, 'Terrace'], ['A4', 4, 'Inner Room']],
    events: [
      {
        title: 'Meet New People Dinner',
        tagline: 'One table, eight strangers, no awkward silences',
        description:
          'A hosted dinner built for meeting new people: a selected main, a drink '
          + 'and dessert, with the host keeping the conversation moving. '
          + DEMO_EXPERIENCE_NOTE,
        cover: A.pasta, dayOffset: 5, hour: 20, durationMinutes: 150,
        seats: 8, booked: 2, pricePkr: 3500, type: 'dinner', menuStyle: 'setMenu',
        hostKey: 'community-host',
        included: ['Selected main course', 'Drink', 'Dessert', 'Hosted group conversation'],
        tags: ['meetup', 'social'],
        hostNote: 'Courtyard tables are weather-dependent; indoor seating is the fallback.',
      },
    ],
  },

  // ── 5. Okra: DHA Phase 8 ───────────────────────────────────────────────────
  {
    key: 'okra',
    name: 'Okra',
    tagline: 'Mediterranean plates in DHA',
    about:
      'A DHA dining room with a Mediterranean-leaning kitchen, wood-fired pizza '
      + 'and a quiet terrace. ' + DEMO_NOTE,
    cuisines: ['Mediterranean', 'Continental', 'Italian'],
    area: 'DHA Phase 8',
    address: 'DHA Phase 8, Karachi',
    priceRange: '$$$',
    amenities: ['Terrace', 'Wood-fired oven', 'Private dining', 'Parking'],
    tags: ['mediterranean', 'terrace', 'premium'],
    cover: A.tasting,
    gallery: [A.pasta, A.rooftop, A.tacos],
    lat: 24.8010, lng: 67.0740,
    open: '12:30', close: '23:30',
    closedDays: ['mon'],
    seats: 100,
    sections: [
      {
        name: 'Starters',
        items: [
          ['Burrata & Tomato', 'Fresh burrata, heirloom tomato, basil oil.', 1650, undefined, ['vegetarian']],
          ['Calamari Fritti', 'Light batter, lemon aioli.', 1590, A.sushi, ['seafood']],
          ['Soup of the Day', 'Ask the kitchen.', 690, undefined, ['vegetarian']],
        ],
      },
      {
        name: 'Wood-Fired Pizza',
        items: [
          ['Margherita', 'San Marzano tomato, fior di latte, basil.', 1550, A.pasta, ['vegetarian']],
          ['Spicy Salami', 'Salami, chilli, mozzarella.', 1850, A.pasta, ['spicy']],
          ['Truffle Mushroom', 'Mushroom, truffle cream, parmesan.', 1950, A.pasta, ['vegetarian']],
        ],
      },
      {
        name: 'Mains',
        items: [
          ['Grilled Lamb Chops', 'Four chops, rosemary jus.', 3890],
          ['Pan-Seared Salmon', 'Lemon butter, seasonal greens.', 3250, A.sushi, ['seafood']],
          ['Wild Mushroom Pasta', 'Tagliatelle, cream, parmesan.', 2150, A.pasta, ['vegetarian']],
        ],
      },
      {
        name: 'Desserts',
        items: [
          ['Tiramisu', 'Espresso-soaked sponge, mascarpone.', 890, A.dessert, ['vegetarian']],
          ['Panna Cotta', 'Vanilla, berry compote.', 790, A.dessert, ['vegetarian']],
        ],
      },
    ],
    deals: [
      {
        title: '15% off selected main courses',
        description: '15% off the marked mains on the DineCircle list.',
        kind: 'percent', value: 15, code: 'OKRA15', maxRedemptions: 100,
        image: A.pasta,
        terms: 'Applies to marked mains only, food only, dine-in.',
        redemption: 'Point to this deal when ordering your mains.',
      },
      {
        title: 'Complimentary dessert with 2 mains',
        description: 'One dessert on the house for every two mains ordered.',
        kind: 'package', value: 0, maxRedemptions: 90,
        image: A.dessert, validDays: 30,
        terms: 'One dessert per table, minimum two mains, dine-in only.',
        redemption: 'Ask your server for the complimentary dessert.',
      },
    ],
    tables: [['O1', 2, 'Terrace'], ['O2', 4, 'Terrace'], ['O3', 6, 'Private Dining'], ['O4', 4, 'Main Room']],
    events: [],
  },

  // ── 6. Xander's: Clifton ───────────────────────────────────────────────────
  {
    key: 'xanders',
    name: "Xander's",
    tagline: 'All-day café in Clifton',
    about:
      'A Clifton café doing all-day breakfast, sandwiches and serious coffee. '
      + 'Popular for long weekend brunches. ' + DEMO_NOTE,
    cuisines: ['Cafe', 'Continental', 'Brunch'],
    area: 'Clifton',
    address: 'Clifton Block 4, Karachi',
    priceRange: '$$',
    amenities: ['All-day breakfast', 'Wi-Fi', 'Outdoor seating', 'Card payments'],
    tags: ['brunch', 'cafe', 'meetup'],
    cover: A.brunch,
    gallery: [A.interior, A.dessert],
    lat: 24.8122, lng: 67.0332,
    open: '09:00', close: '23:00',
    seats: 80,
    sections: [
      {
        name: 'All-Day Breakfast',
        items: [
          ['Big Breakfast', 'Eggs, sausage, toast, grilled tomato, hash brown.', 1690, A.brunch, ['vegetarian']],
          ['Eggs Benedict', 'Poached eggs, hollandaise, English muffin.', 1590, A.brunch],
          ['French Toast', 'Brioche, maple syrup, berries.', 1290, A.brunch, ['vegetarian']],
          ['Shakshuka', 'Eggs baked in spiced tomato.', 1390, A.brunch, ['vegetarian', 'spicy']],
        ],
      },
      {
        name: 'Sandwiches & Salads',
        items: [
          ['Club Sandwich', 'Triple decker with fries.', 1450, A.brunch],
          ['Chicken Caesar', 'Cos lettuce, parmesan, croutons.', 1390, undefined, ['spicy']],
          ['Grilled Halloumi Wrap', 'Halloumi, hummus, roasted vegetables.', 1290, undefined, ['vegetarian']],
        ],
      },
      {
        name: 'Coffee & Cake',
        items: [
          ['Cappuccino', 'Double shot, steamed milk.', 590, undefined, ['vegetarian']],
          ['Flat White', 'Stronger, less foam.', 590, undefined, ['vegetarian']],
          ['Carrot Cake', 'Cream cheese frosting.', 750, A.dessert, ['vegetarian']],
          ['Chocolate Brownie', 'Warm, with ice cream.', 790, A.dessert, ['vegetarian']],
        ],
      },
    ],
    deals: [
      {
        title: 'Buy 1 pizza, get 1 at 50% off',
        description: 'Order any pizza and the second one of equal or lower value is half price.',
        kind: 'package', value: 0, maxRedemptions: 200,
        image: A.pasta,
        terms: 'Dine-in only, second pizza must be equal or lower value, excludes delivery.',
        redemption: 'Tell your server before the order is fired.',
      },
      {
        title: 'Breakfast combo for Rs. 1,499',
        description: 'Breakfast for two: eggs any style, toast, fruit and two coffees at a set price.',
        kind: 'package', value: 1499, maxRedemptions: 120,
        image: A.brunch, validDays: 30,
        terms: 'Served 08:00–12:00, for two guests, fixed items.',
        redemption: 'Ask for the DineCircle breakfast combo on arrival.',
      },
    ],
    tables: [['X1', 2, 'Courtyard'], ['X2', 4, 'Main Hall'], ['X3', 4, 'Window'], ['X4', 6, 'Courtyard']],
    events: [
      {
        title: 'Sunday Brunch & Connect',
        tagline: 'Brunch, coffee and easy introductions',
        description:
          'A hosted Sunday brunch with quick introductions before the food lands '
          + 'and open seating after it. ' + DEMO_EXPERIENCE_NOTE,
        cover: A.brunch, dayOffset: 2, hour: 11, durationMinutes: 120,
        seats: 8, booked: 4, pricePkr: 1800, type: 'brunch', menuStyle: 'setMenu',
        hostKey: 'lifestyle-creator',
        included: ['One brunch main', 'Coffee or juice', 'Introductions', 'Social networking'],
        tags: ['brunch', 'meetup'],
        hostNote: 'Table is held for 15 minutes; message the host if you are late.',
      },
    ],
  },

  // ── 7. Espresso Shahbaz DHA: DHA Phase 6 ───────────────────────────────────
  {
    key: 'espresso-shahbaz',
    name: 'Espresso Shahbaz DHA',
    tagline: 'Neighbourhood espresso bar in DHA Phase 6',
    about:
      'A compact DHA Phase 6 espresso bar with pastries, sandwiches and a '
      + 'steady laptop crowd. ' + DEMO_NOTE,
    cuisines: ['Cafe', 'Coffee', 'Desserts'],
    area: 'DHA Phase 6',
    address: 'DHA Phase 6, Karachi',
    priceRange: '$$',
    amenities: ['Wi-Fi', 'Laptop-friendly', 'Takeaway', 'Card payments'],
    tags: ['cafe', 'coffee', 'work-friendly'],
    cover: A.dessert,
    gallery: [A.bar, A.brunch],
    lat: 24.7980, lng: 67.0610,
    open: '08:00', close: '23:00',
    seats: 46,
    sections: [
      {
        name: 'Espresso Bar',
        items: [
          ['Espresso', 'Single or double, house blend.', 380, undefined, ['vegan']],
          ['Flat White', 'Double shot, silky milk.', 560, undefined, ['vegetarian']],
          ['Cortado', 'Equal parts espresso and milk.', 520, undefined, ['vegetarian']],
          ['Iced Latte', 'Double shot over ice.', 620, undefined, ['vegetarian']],
        ],
      },
      {
        name: 'Bakery',
        items: [
          ['Butter Croissant', 'Baked in-house each morning.', 450, A.dessert, ['vegetarian']],
          ['Almond Danish', 'Frangipane, flaked almonds.', 520, A.dessert, ['vegetarian']],
          ['Chocolate Cookie', 'Dark chocolate chunks.', 350, A.dessert, ['vegetarian']],
        ],
      },
      {
        name: 'Sandwiches',
        items: [
          ['Grilled Cheese', 'Sourdough, cheddar, tomato.', 890, undefined, ['vegetarian']],
          ['Chicken Panini', 'Pesto, mozzarella, chicken.', 1150, A.brunch],
          ['Avocado Toast', 'Sourdough, chilli flakes, lime.', 950, A.brunch, ['vegetarian', 'vegan']],
        ],
      },
    ],
    deals: [
      {
        title: 'Buy 1 coffee, get 1 free',
        description: 'Two espresso drinks for the price of one, same size.',
        kind: 'package', value: 0, maxRedemptions: 300,
        image: A.brunch,
        terms: 'Same size only, dine-in, once per visit.',
        redemption: 'Order both drinks together and mention this deal.',
      },
      {
        title: 'Coffee + sandwich for Rs. 999',
        description: 'Any espresso drink with a sandwich from the counter menu at a set price.',
        kind: 'package', value: 999, maxRedemptions: 250,
        image: A.brunch, validDays: 30,
        terms: 'Weekdays 11:00–17:00, selected sandwiches only.',
        redemption: 'Show this deal at the counter when ordering.',
      },
    ],
    tables: [['E1', 2, 'Window'], ['E2', 2, 'Bar'], ['E3', 4, 'Back Room']],
    events: [
      {
        title: 'Coffee Lovers Meetup',
        tagline: 'One good cup and a lot of coffee talk',
        description:
          'A hosted coffee meetup for people who care where the beans come from. '
          + 'One specialty coffee, dessert, then an open conversation about what '
          + 'everyone is drinking. ' + DEMO_EXPERIENCE_NOTE,
        cover: A.brunch, dayOffset: 7, hour: 17, durationMinutes: 90,
        seats: 12, booked: 5, pricePkr: 1200, type: 'workshop', menuStyle: 'setMenu',
        hostKey: 'coffee-enthusiast',
        included: ['One specialty coffee', 'Dessert', 'Coffee discussions', 'Casual networking'],
        tags: ['coffee', 'meetup'],
        hostNote: 'No prior coffee knowledge needed.',
      },
    ],
  },

  // ── 8. Cafe Flo: Clifton ───────────────────────────────────────────────────
  {
    key: 'cafe-flo',
    name: 'Cafe Flo',
    tagline: 'French-leaning café in Clifton',
    about:
      'A Clifton café with a French-leaning pastry counter, crepes and a '
      + 'garden-style room. ' + DEMO_NOTE,
    cuisines: ['Cafe', 'French', 'Desserts'],
    area: 'Clifton',
    address: 'Clifton Block 6, Karachi',
    priceRange: '$$',
    amenities: ['Garden seating', 'Pastry counter', 'Wi-Fi', 'Card payments'],
    tags: ['cafe', 'dessert', 'date-night'],
    cover: A.interior,
    gallery: [A.dessert, A.brunch],
    lat: 24.8145, lng: 67.0265,
    open: '10:00', close: '23:30',
    seats: 60,
    sections: [
      {
        name: 'Crepes & Waffles',
        items: [
          ['Nutella Crepe', 'Thin crepe, hazelnut spread, banana.', 990, A.dessert, ['vegetarian']],
          ['Lemon Sugar Crepe', 'Classic, with a lemon wedge.', 790, A.dessert, ['vegetarian']],
          ['Belgian Waffle', 'Maple syrup, butter.', 950, A.dessert, ['vegetarian']],
        ],
      },
      {
        name: 'Savoury',
        items: [
          ['Croque Monsieur', 'Ham, gruyere, bechamel.', 1450, A.brunch],
          ['Quiche Lorraine', 'Bacon, cream, gruyere.', 1290, A.brunch],
          ['Cheese Omelette', 'Three eggs, herbs, toast.', 1190, A.brunch, ['vegetarian']],
        ],
      },
      {
        name: 'Coffee & Chocolate',
        items: [
          ['Hot Chocolate', 'Dark chocolate, whipped cream.', 690, A.dessert, ['vegetarian']],
          ['Cafe Latte', 'Double shot, steamed milk.', 590, undefined, ['vegetarian']],
          ['Cappuccino', 'Classic ratio.', 590, undefined, ['vegetarian']],
        ],
      },
    ],
    deals: [
      {
        title: '20% off weekday lunch',
        description: '20% off the food bill at weekday lunch service.',
        kind: 'percent', value: 20, code: 'FLO20', maxRedemptions: 120,
        image: A.brunch,
        terms: 'Monday–Friday 12:00–16:00, food only, dine-in.',
        redemption: 'Show the deal to your server before ordering.',
      },
      {
        title: 'Dinner for two for Rs. 5,999',
        description: 'Two starters, two mains and one dessert for two at a set price.',
        kind: 'package', value: 5999, maxRedemptions: 50,
        image: A.dessert, validDays: 30,
        terms: 'For two guests, after 19:00, reservation recommended.',
        redemption: 'Ask for the DineCircle dinner for two when reserving.',
      },
    ],
    tables: [['F1', 2, 'Garden'], ['F2', 4, 'Garden'], ['F3', 4, 'Main Room']],
    events: [],
  },

  // ── 9. Butlers Chocolate Café: Zamzama ─────────────────────────────────────
  {
    key: 'butlers',
    name: 'Butlers Chocolate Café',
    tagline: 'Chocolate café on Zamzama',
    about:
      'A Zamzama chocolate café with a dessert-heavy menu, fondues and a '
      + 'quiet upstairs room. ' + DEMO_NOTE,
    cuisines: ['Cafe', 'Chocolate', 'Desserts'],
    area: 'Zamzama',
    address: 'Zamzama Boulevard, Karachi',
    priceRange: '$$',
    amenities: ['Dessert menu', 'Upstairs seating', 'Takeaway', 'Card payments'],
    tags: ['dessert', 'cafe', 'chocolate'],
    cover: A.dessert,
    gallery: [A.brunch, A.bar],
    lat: 24.8165, lng: 67.0405,
    open: '11:00', close: '23:30',
    seats: 54,
    sections: [
      {
        name: 'Chocolate',
        items: [
          ['Chocolate Fondue for Two', 'Warm chocolate, fruit and marshmallows.', 1890, A.dessert, ['vegetarian']],
          ['Chocolate Lava Cake', 'Molten centre, vanilla ice cream.', 990, A.dessert, ['vegetarian']],
          ['Truffle Box (6)', 'Assorted dark and milk truffles.', 1250, A.dessert, ['vegetarian']],
        ],
      },
      {
        name: 'Cakes & Slices',
        items: [
          ['Chocolate Fudge Cake', 'Three layers, ganache.', 890, A.dessert, ['vegetarian']],
          ['Cheesecake', 'Baked vanilla cheesecake.', 850, A.dessert, ['vegetarian']],
          ['Carrot Cake', 'Walnut, cream cheese.', 790, A.dessert, ['vegetarian']],
        ],
      },
      {
        name: 'Drinks',
        items: [
          ['Signature Hot Chocolate', 'Thick, dark, whipped cream.', 790, undefined, ['vegetarian']],
          ['Iced Mocha', 'Espresso, chocolate, milk.', 750, undefined, ['vegetarian']],
          ['Americano', 'Long black.', 490, undefined, ['vegan']],
        ],
      },
    ],
    deals: [
      {
        title: 'Buy 1 hot chocolate, get 1 free',
        description: 'Two signature hot chocolates for the price of one, same size.',
        kind: 'package', value: 0, maxRedemptions: 300,
        image: A.dessert,
        terms: 'Same size only, dine-in, once per visit.',
        redemption: 'Mention this deal at the counter when ordering.',
      },
      {
        title: 'Cake slice + hot drink for Rs. 999',
        description: 'Any selected cake slice with a regular hot drink at a set price.',
        kind: 'package', value: 999, maxRedemptions: 200,
        image: A.dessert, validDays: 30,
        terms: 'Selected cakes only, dine-in, weekdays.',
        redemption: 'Show this deal when placing your order.',
      },
    ],
    tables: [['C1', 2, 'Upstairs'], ['C2', 4, 'Upstairs'], ['C3', 4, 'Ground Floor']],
    events: [],
  },

  // ── 10. Esquires Coffee: Zamzama ───────────────────────────────────────────
  {
    key: 'esquires',
    name: 'Esquires Coffee',
    tagline: 'Coffee house on Zamzama',
    about:
      'A Zamzama coffee house with a broad drinks menu, breakfast plates and '
      + 'plenty of table space. ' + DEMO_NOTE,
    cuisines: ['Cafe', 'Coffee', 'Breakfast'],
    area: 'Zamzama',
    address: 'Zamzama Boulevard, Karachi',
    priceRange: '$$',
    amenities: ['Wi-Fi', 'Breakfast', 'Group seating', 'Card payments'],
    tags: ['cafe', 'coffee', 'breakfast'],
    cover: A.bar,
    gallery: [A.brunch, A.dessert],
    lat: 24.8170, lng: 67.0420,
    open: '08:30', close: '23:00',
    seats: 70,
    sections: [
      {
        name: 'Breakfast',
        items: [
          ['Full Breakfast', 'Eggs, sausage, beans, toast.', 1590, A.brunch],
          ['Omelette', 'Three eggs, cheese, herbs, toast.', 1290, A.brunch, ['vegetarian']],
          ['Pancake Stack', 'Three pancakes, maple syrup.', 1190, A.brunch, ['vegetarian']],
        ],
      },
      {
        name: 'Coffee',
        items: [
          ['Americano', 'Long black, house blend.', 480, undefined, ['vegan']],
          ['Cappuccino', 'Classic ratio.', 570, undefined, ['vegetarian']],
          ['Mocha', 'Espresso, chocolate, milk.', 650, undefined, ['vegetarian']],
          ['Cold Brew', 'Slow-steeped, served over ice.', 690, undefined, ['vegan']],
        ],
      },
      {
        name: 'Light Meals',
        items: [
          ['Chicken Panini', 'Grilled, with a side salad.', 1250, A.brunch],
          ['Caesar Salad', 'Cos, parmesan, croutons.', 1290, undefined, ['spicy']],
          ['Soup & Toast', 'Soup of the day with sourdough.', 890, undefined, ['vegetarian']],
        ],
      },
    ],
    deals: [
      {
        title: '20% off breakfast',
        description: '20% off any breakfast plate ordered before 11:30.',
        kind: 'percent', value: 20, code: 'ESQ20', maxRedemptions: 200,
        image: A.brunch,
        terms: 'Until 11:30, food only, dine-in.',
        redemption: 'Quote the code at the counter before ordering.',
      },
      {
        title: 'Coffee + dessert for Rs. 899',
        description: 'Any regular coffee with a selected dessert at a set price.',
        kind: 'package', value: 899, maxRedemptions: 200,
        image: A.dessert, validDays: 30,
        terms: 'Selected desserts only, dine-in.',
        redemption: 'Ask for the DineCircle coffee and dessert combo.',
      },
    ],
    tables: [['S1', 2, 'Window'], ['S2', 4, 'Main Floor'], ['S3', 6, 'Group Table'], ['S4', 8, 'Group Table']],
    events: [],
  },

  // ── 11. Café Zouk: Zamzama ─────────────────────────────────────────────────
  // Added so the curated "Pizza & Friends Night" experience has the venue the
  // demo script names. Zamzama café profile: pizza, pasta, courtyard seating.
  {
    key: 'cafe-zouk',
    name: 'Café Zouk',
    tagline: 'Wood-fired pizza and pasta on Zamzama',
    about:
      'A Zamzama café built around a wood-fired oven: thin-crust pizza, pasta and '
      + 'a courtyard that fills up after sunset. ' + DEMO_NOTE,
    cuisines: ['Italian', 'Pizza', 'Café'],
    area: 'Zamzama, DHA Phase 5',
    address: 'Zamzama Boulevard, DHA Phase 5, Karachi',
    priceRange: '$$',
    amenities: ['Courtyard seating', 'Family friendly', 'Takeaway', 'Card payments'],
    tags: ['pizza', 'pasta', 'cafe'],
    cover: A.pasta,
    gallery: [A.interior, A.dessert, A.bar],
    lat: 24.8145, lng: 67.0433,
    open: '12:00', close: '23:30',
    seats: 80,
    sections: [
      {
        name: 'Starters',
        items: [
          ['Bruschetta', 'Grilled sourdough, tomato, basil, olive oil.', 750, undefined, ['vegetarian']],
          ['Garlic Bread with Cheese', 'Mozzarella, garlic butter, parsley.', 650, undefined, ['vegetarian']],
          ['Soup of the Day', 'Ask the counter for today\'s soup.', 690],
        ],
      },
      {
        name: 'Wood-Fired Pizza',
        items: [
          ['Margherita', 'San Marzano tomato, mozzarella, basil.', 1450, A.pasta, ['vegetarian']],
          ['Chicken Tikka Pizza', 'Tikka chunks, onion, green chilli, mozzarella.', 1950, A.pasta, ['spicy']],
          ['Pepperoni', 'Beef pepperoni, tomato, mozzarella.', 1850, A.pasta],
          ['Four Cheese', 'Mozzarella, cheddar, parmesan, blue cheese.', 2150, A.pasta, ['vegetarian']],
        ],
      },
      {
        name: 'Pasta',
        items: [
          ['Chicken Alfredo', 'Fettuccine, cream, parmesan, grilled chicken.', 1650, A.pasta],
          ['Penne Arrabbiata', 'Tomato, garlic, chilli, olive oil.', 1450, A.pasta, ['vegetarian', 'spicy']],
          ['Chicken Lasagna', 'Layered pasta, chicken ragu, béchamel.', 1890, A.pasta],
        ],
      },
      {
        name: 'Desserts & Drinks',
        items: [
          ['Tiramisu', 'Espresso-soaked sponge, mascarpone.', 750, A.dessert, ['vegetarian']],
          ['Chocolate Lava Cake', 'Warm centre, vanilla ice cream.', 690, A.dessert, ['vegetarian']],
          ['Fresh Lime Soda', 'Sweet or salted.', 350, undefined, ['vegan']],
        ],
      },
    ],
    deals: [
      {
        title: '15% off pasta and pizza',
        description: '15% off any wood-fired pizza or pasta dish, dine-in.',
        kind: 'percent', value: 15, code: 'ZOUK15', maxRedemptions: 150,
        image: A.pasta,
        terms: 'Dine-in only, food only, not combinable with the lunch combo.',
        redemption: 'Quote the code to your server before ordering.',
      },
      {
        title: 'Lunch combo for Rs. 1,299',
        description: 'One pasta or pizza with a soft drink at a set lunch price.',
        kind: 'package', value: 1299, maxRedemptions: 120,
        image: A.pasta, validDays: 30,
        terms: 'Monday–Friday 12:00–16:00, selected dishes only.',
        redemption: 'Ask for the DineCircle lunch combo when ordering.',
      },
    ],
    tables: [['Z1', 2, 'Courtyard'], ['Z2', 4, 'Courtyard'], ['Z3', 6, 'Terrace'], ['Z4', 8, 'Garden']],
    events: [
      {
        title: 'Pizza & Friends Night',
        tagline: 'Shared pizza, pasta and a table that talks',
        description:
          'A hosted pizza night built for groups: shared pizzas and pasta, soft '
          + 'drinks, and a couple of ice-breakers from the host before the food '
          + 'arrives. ' + DEMO_EXPERIENCE_NOTE,
        cover: A.pasta, dayOffset: 4, hour: 20, durationMinutes: 120,
        seats: 10, booked: 4, pricePkr: 1999, type: 'dinner', menuStyle: 'sharing',
        hostKey: 'social-dining-host',
        included: ['Shared pizza', 'Pasta', 'Soft drink', 'Interactive group activities'],
        tags: ['pizza', 'meetup', 'group'],
        hostNote: 'Courtyard tables are held for 15 minutes after the start time.',
      },
    ],
  },
];

/** Resolve an owner plus one demo host account per [HOSTS] entry. */
async function resolveActors(): Promise<{
  ownerId: string;
  hostIds: Record<HostKey, string>;
}> {
  const owners = await query<{ id: string }>(
    `SELECT id FROM users WHERE role = 'partner_admin' ORDER BY created_at NULLS LAST LIMIT 1`,
  );
  let ownerId = owners[0]?.id;
  if (!ownerId) {
    await query(
      `INSERT INTO users (id, name, handle, email, role, city)
       VALUES ($1::uuid, 'DineCircle Demo Desk', 'demo.desk', 'demo.desk@example.test',
               'partner_admin', 'Karachi')
       ON CONFLICT (id) DO NOTHING`,
      [OWNER_FALLBACK_ID],
    );
    ownerId = OWNER_FALLBACK_ID;
  }

  const hostIds = {} as Record<HostKey, string>;
  for (const host of HOSTS) {
    await query(
      `INSERT INTO users (id, name, handle, email, role, city)
       VALUES ($1::uuid, $2, $3, $4, 'host', 'Karachi')
       ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name`,
      [host.id, host.name, host.handle, `${host.handle}@example.test`],
    );
    hostIds[host.key] = host.id;
  }
  return { ownerId, hostIds };
}

async function main(): Promise<void> {
  if (process.env.NODE_ENV === 'production' && !process.env.ALLOW_SEED_IN_PRODUCTION) {
    throw new Error('Refusing to reseed in production. Set ALLOW_SEED_IN_PRODUCTION=1 to override.');
  }

  const { ownerId, hostIds } = await resolveActors();

  console.log('Removing existing venues (cascades menus, deals, tables, events, reviews)…');
  await query('DELETE FROM restaurants');

  let venueCount = 0;
  let sectionCount = 0;
  let itemCount = 0;
  let dealCount = 0;
  let tableCount = 0;
  let eventCount = 0;

  for (const v of VENUES) {
    const rows = await query<{ id: string }>(
      `INSERT INTO restaurants
         (owner_id, name, tagline, about, cuisines, neighborhood, address, city,
          phone, email, website, instagram, price_range, rating, review_count,
          seats, tables_count, since, owner_name, amenities, opening_hours,
          profile_completion, accepting_bookings, dine_circle_plus, cover_image,
          gallery, tags, is_partner, partner_perk, latitude, longitude,
          is_demo, partnership_status, logo, facebook, twitter)
       VALUES
         ($1::uuid, $2, $3, $4, $5::text[], $6, $7, 'Karachi',
          $8, '', '', '', $9, 0, 0,
          $10, $11, '2015', 'DineCircle Demo Desk', $12::text[], $13::jsonb,
          100, true, false, $14,
          $15::text[], $16::text[], false, NULL, $17, $18,
          true, 'unverified', '', '', '')
       RETURNING id`,
      [
        ownerId,
        v.name,
        v.tagline,
        v.about,
        v.cuisines,
        v.area,
        v.address,
        `+9221000${String(venueCount + 1).padStart(3, '0')}`, // placeholder, not a real line
        v.priceRange,
        v.seats,
        v.tables.length,
        v.amenities,
        hours(v.open, v.close, v.closedDays),
        v.cover,
        v.gallery,
        v.tags.includes(DEMO_TAG) ? v.tags : [...v.tags, DEMO_TAG],
        v.lat,
        v.lng,
      ],
    );
    const restaurantId = rows[0]!.id;
    venueCount += 1;

    // Primary branch with Asia/Karachi service windows, the availability
    // engine reads the branch hours first.
    await query(
      `INSERT INTO restaurant_branches
         (restaurant_id, name, address, area, city, phone, latitude, longitude,
          is_primary, accepting_reservations, opening_hours, timezone)
       VALUES ($1::uuid, $2, $3, $4, 'Karachi', $5, $6, $7, true, true, $8::jsonb, 'Asia/Karachi')`,
      [
        restaurantId,
        `${v.name}: ${v.area}`,
        v.address,
        v.area,
        `+9221000${String(venueCount).padStart(3, '0')}`,
        v.lat,
        v.lng,
        hours(v.open, v.close, v.closedDays),
      ],
    );

    // Partner subscription kept active so Partner-app testing works too.
    await query(
      `INSERT INTO partner_subscriptions
         (restaurant_id, plan, status, price_pkr, period_start, period_end, auto_renew)
       VALUES ($1::uuid, 'monthly', 'active', 5000, now(), now() + interval '30 days', true)`,
      [restaurantId],
    );

    // Menu.
    for (const [index, section] of v.sections.entries()) {
      const sectionRows = await query<{ id: string }>(
        `INSERT INTO restaurant_menu_sections
           (restaurant_id, name, position, is_active)
         VALUES ($1::uuid, $2, $3, true) RETURNING id`,
        [restaurantId, section.name, index],
      );
      sectionCount += 1;
      for (const [itemIndex, item] of section.items.entries()) {
        const [name, description, price, photo, tags] = item;
        await query(
          `INSERT INTO restaurant_menu_items
             (restaurant_id, section_id, name, description, price, position,
              is_available, dietary_tags, photo_url)
           VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, true, $7::text[], $8)`,
          [restaurantId, sectionRows[0]!.id, name, description, price, itemIndex, tags ?? [], photo ?? ''],
        );
        itemCount += 1;
      }
    }

    // Deals, two per venue, each carrying its own image, validity window,
    // terms and redemption instructions.
    for (const deal of v.deals) {
      await query(
        `INSERT INTO restaurant_deals
           (restaurant_id, title, description, terms, kind, value, code,
            starts_at, ends_at, max_redemptions, redemptions, status, image_url)
         VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, now() - interval '1 day',
                 $8::timestamptz, $9, 0, $10, $11)`,
        [
          restaurantId,
          deal.title,
          dealDescription(deal),
          dealTerms(deal),
          deal.kind,
          deal.value,
          deal.code ?? null,
          daysAhead(deal.validDays ?? DEFAULT_DEAL_DAYS),
          deal.maxRedemptions,
          DEAL_STATUS,
          deal.image ?? v.cover,
        ],
      );
      dealCount += 1;
    }

    // Tables.
    for (const [label, seats, zone] of v.tables) {
      await query(
        `INSERT INTO restaurant_tables (restaurant_id, label, seats, zone, is_active)
         VALUES ($1::uuid, $2, $3, $4, true)`,
        [restaurantId, label, seats, zone],
      );
      tableCount += 1;
    }

    // Experiences.
    for (const e of v.events) {
      const hostId = hostIds[e.hostKey];
      await query(
        `INSERT INTO dinner_events
           (title, tagline, description, host_id, restaurant_id, cover_image, gallery,
            start_at, end_at, duration_minutes, seats_total, seats_booked, price_per_seat,
            type, audience, menu_style, included, tags, is_featured, host_note,
            attendee_ids, status, views, requires_approval, is_demo)
         VALUES
           ($1, $2, $3, $4::uuid, $5::uuid, $6, $7::text[],
            $8::timestamptz, $9::timestamptz, $10, $11, $12, $13,
            $14, 'public', $15, $16::text[], $17::text[], false, $18,
            '{}', 'confirmed', 0, false, true)`,
        [
          e.title,
          e.tagline,
          e.description,
          hostId,
          restaurantId,
          e.cover,
          [e.cover],
          at(e.dayOffset, e.hour),
          at(e.dayOffset, e.hour + Math.floor(e.durationMinutes / 60)),
          e.durationMinutes,
          e.seats,
          e.booked,
          e.pricePkr,
          e.type,
          e.menuStyle,
          e.included,
          e.tags,
          e.hostNote,
        ],
      );
      eventCount += 1;
    }

    console.log(`  ✓ ${v.name} (${v.sections.length} sections, ${v.tables.length} tables)`);
  }

  const summary = await query<{
    restaurants: string; sections: string; items: string; deals: string;
    tables_count: string; events: string;
  }>(
    `SELECT
       (SELECT count(*) FROM restaurants)::text AS restaurants,
       (SELECT count(*) FROM restaurant_menu_sections)::text AS sections,
       (SELECT count(*) FROM restaurant_menu_items)::text AS items,
       (SELECT count(*) FROM restaurant_deals)::text AS deals,
       (SELECT count(*) FROM restaurant_tables)::text AS tables_count,
       (SELECT count(*) FROM dinner_events)::text AS events`,
  );

  console.log('\nSeeded:');
  console.log(`  venues              ${venueCount}`);
  console.log(`  menu sections       ${sectionCount}`);
  console.log(`  menu items          ${itemCount}`);
  console.log(`  deals               ${dealCount} (status: ${DEAL_STATUS})`);
  console.log(`  tables              ${tableCount}`);
  console.log(`  experiences         ${eventCount}`);
  console.log('\nDatabase now reports:', summary[0]);
}

main()
  .then(async () => {
    await pool.end();
  })
  .catch(async (error) => {
    console.error(error);
    await pool.end();
    process.exitCode = 1;
  });
