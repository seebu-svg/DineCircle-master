/**
 * Seed script, the Karachi test world plus a small Lyon reference world.
 *
 * Karachi (everything a tester signs in to see): 20 candidate restaurant venues
 * across DHA, Clifton, Saddar, Gulshan, PECHS, Karsaz, Bahadurabad and Lyari,
 * each with a primary branch (Asia/Karachi service windows), a six-to-ten table
 * floor plan totalling its published seats, its printed kitchen menu in PKR
 * (grill, karahi, biryani, nihari, dim sum, seafood, mezze, buffet, Mughlai,
 * cafe), a live deal, settled earnings periods, a DineCircle set-menu package
 * and mock table reservations. Against that: 18 creator host profiles (10
 * borrowed public handles plus 8 clearly fictional personas), 150 test diners
 * with Karachi home areas, 60 demo events with course menus taken from the
 * host venue's own kitchen, 300 bookings, up to 120 reviews, payouts, a PKR
 * host wallet, the social graph (diner→creator follows, venue follows, saved
 * events, saved places) and the notification and collab-invite feeds.
 *
 * Seventeen venues are seeded `partnership_status = 'verified'` so creators can
 * publish dinners through the funnel; Kanteen, Foods Inn and Al-Bismillah stay
 * `unverified` candidates so the 403 rejection path and the admin verification
 * queue remain testable. Event details, menus, ticket prices, bookings, reviews
 * and earnings are fictional and do not imply an agreed partnership or an actual
 * hosted event.
 *
 * Matches src/schema.sql (uuid ids, renamed columns, special_menus,
 * notifications, partner tables, user_avatars). Re-runnable: truncates every
 * table first. The Lyon world is inlined as trusted literals; the Karachi world
 * is generated deterministically (seeded LCG + fixed uuid buckets) so re-seeds
 * stay stable.
 *
 * Demo logins: every Karachi account (desk, creators, diners) signs in with
 * email + password `dinecircle123` via POST /api/auth/login.
 */
import { randomBytes, scryptSync } from 'node:crypto';
import { pool } from './db.js';

/** Shared test password for all seeded Karachi accounts. */
const DEMO_PASSWORD = 'dinecircle123';

/** Same format as routes/auth.ts hashPassword (scrypt defaults). */
const demoHash = (): string => {
  const salt = randomBytes(16).toString('hex');
  return `scrypt:${salt}:${scryptSync(DEMO_PASSWORD, salt, 64).toString('hex')}`;
};

/** Wall-clock moment `dayOffset` days from today at hour:minute, as ISO. */
function at(dayOffset: number, hour: number, minute = 0): string {
  const now = new Date();
  const d = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  d.setDate(d.getDate() + dayOffset);
  d.setHours(hour, minute, 0, 0);
  return d.toISOString();
}

// Deterministic uuids so relationships stay stable across re-seeds.
const U = {
  alex: '11111111-1111-1111-1111-111111111111',
  nora: '22222222-2222-2222-2222-222222222222',
  ava: '33333333-3333-3333-3333-333333333333',
  marco: '44444444-4444-4444-4444-444444444444',
  admin: '55555555-5555-5555-5555-555555555555',
};
const R = {
  rooftop: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1',
  trattoria: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2',
};
const E = {
  e1: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee1', // upcoming, hosted
  e2: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2', // upcoming, hosted
  e3: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee3', // past → enables review/payout
  e4: 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee4', // upcoming, host-approval gate
};

const q = (sql: string): Promise<unknown> => pool.query(sql);

// ── Karachi test world ──────────────────────────────────────────────────────

/** Deterministic uuid per bucket + index, stable across re-seeds. */
const kid = (bucket: string, n: number): string =>
  `${bucket.repeat(8)}-0000-4000-8000-${n.toString(16).padStart(12, '0')}`;

// Seeded LCG: the same "random" test data on every re-seed.
let seedState = 20261025;
const rand = (): number => {
  seedState = (seedState * 1103515245 + 12345) % 0x7fffffff;
  return seedState / 0x7fffffff;
};
const int = (min: number, max: number): number => min + Math.floor(rand() * (max - min + 1));
const item = <T>(xs: readonly T[], i: number): T => {
  const value = xs[((i % xs.length) + xs.length) % xs.length];
  if (value === undefined) throw new Error('seed list is empty');
  return value;
};
const pick = <T>(xs: readonly T[]): T => item(xs, Math.floor(rand() * xs.length));

/** Chunked multi-row parameterised INSERT. */
async function insertAll(
  table: string,
  columns: readonly string[],
  rows: readonly (readonly unknown[])[],
): Promise<void> {
  for (let i = 0; i < rows.length; i += 200) {
    const chunk = rows.slice(i, i + 200);
    const params: unknown[] = [];
    const tuples = chunk.map((row) => {
      const start = params.length;
      params.push(...row);
      return `(${row.map((_, c) => `$${start + c + 1}`).join(', ')})`;
    });
    await pool.query(
      `INSERT INTO ${table} (${columns.join(', ')}) VALUES ${tuples.join(', ')}`,
      params,
    );
  }
}

// ── Karachi venue & kitchen catalogue ───────────────────────────────────────
// Suggested candidate venues (real, publicly listed Karachi restaurants). Only
// public basics are real, name, area, cuisine, price band, coordinates. Every
// event, ticket price, menu line, booking, review and earning below is
// fictional test data and does not imply an agreed partnership or an actual
// hosted event.
// lat/lng are real public coordinates for each area so the map and `nearby`
// queries place markers on the actual neighbourhood, not a synthetic grid.

/** One dish as the kitchen prints it: [name, description, PKR price, tags]. */
type KDish = [name: string, desc: string, price: number, tags?: readonly string[]];
/** One printed section of a venue's menu. */
type KSection = { name: string; items: KDish[] };

// Karachi food, in rupees, grouped the way these kitchens actually print their
// menus. A venue pulls one or more books; the seed fans them out into
// restaurant_menu_sections + restaurant_menu_items, so the public QR menu, the
// Partner App menu editor and the per-event course list all read one kitchen.
// Prices are illustrative test data, not published rates.
const K_BOOKS: Record<string, readonly KSection[]> = {
  bbq: [
    { name: 'Charcoal Grill', items: [
      ['Chicken tikka (half)', 'Overnight yoghurt marinade, charcoal fired', 650],
      ['Beef seekh kebab (4)', 'Hand-minced, green chilli, coriander', 550],
      ['Malai boti (6)', 'Cream and cheese marinade, mild', 700],
      ['Mutton champ', 'Leg cubes, hand-cut and grilled to order', 1200],
    ] },
    { name: 'Karahi & Handi', items: [
      ['Chicken karahi (half)', 'Bone-in, tomato and julienned ginger', 950],
      ['Mutton karahi (1 kg)', 'Slow reduction, green chilli', 1650],
      ['Chicken handi', 'Butter and ginger, clay-pot service', 1100],
    ] },
    { name: 'Breads & Coolers', items: [
      ['Roghna naan', 'Milk-and-sugar gloss, tandoor', 120, ['vegetarian']],
      ['Garlic naan', 'Coriander and garlic butter', 180, ['vegetarian']],
      ['Mint lemon soda', 'Crushed mint, lemon, black salt', 180, ['vegetarian']],
      ['Kashmiri chai', 'Pink tea with pistachio', 250, ['vegetarian']],
    ] },
  ],
  karahi: [
    { name: 'Karahi Corner', items: [
      ['Chicken karahi (half)', 'Bone-in, tomato, ginger, green chilli', 900],
      ['Mutton karahi (1 kg)', 'Slow-cooked with animal fat', 1600],
      ['Chicken masala (boneless)', 'Thick onion masala, no bone', 1050],
      ['Daal makhani (half)', 'Overnight black lentils, butter', 450, ['vegetarian']],
    ] },
    { name: 'Rice & Breads', items: [
      ['Chicken pulao', 'Whole-spice rice, shorba on the side', 420],
      ['Sada rice', 'Plain steamed, to cut the heat', 180, ['vegetarian']],
      ['Plain naan', 'Tandoor, fresh every few minutes', 60, ['vegetarian']],
      ['Taftan', 'Thick, seeded, long-fermented', 150, ['vegetarian']],
    ] },
    { name: 'Chai & Dessert', items: [
      ['Doodh patti chai', 'Kettle-strong, full milk', 100, ['vegetarian']],
      ['Kheer', 'Slow-cooked rice pudding, cardamom', 180, ['vegetarian']],
      ['Gulab jamun (2)', 'Warm, cardamom syrup', 160, ['vegetarian']],
    ] },
  ],
  biryani: [
    { name: 'Biryani', items: [
      ['Mitha chicken biryani', 'House sweet masala, aloo and raisin', 420],
      ['Beef biryani', 'Sealed dum, fried onion, saffron milk', 480],
      ['Sindhi biryani', 'Potato-heavy, mild, aamchood tang', 450],
      ['Prawn biryani', 'Coastal masala, coriander stalk', 750],
    ] },
    { name: 'Kebabs & Sides', items: [
      ['Chicken shorba', 'Clear broth, herbs, lemon', 250],
      ['Chapli kebab', 'Peshawari flat kebab, tomato, coriander', 550],
      ['Raita', 'Whisked yoghurt, roasted cumin', 120, ['vegetarian']],
    ] },
    { name: 'Desserts', items: [
      ['Kheer', 'Saffron rice pudding', 180, ['vegetarian']],
      ['Shahi tukra', 'Fried bread soaked in rabri', 240, ['vegetarian']],
    ] },
  ],
  cafe: [
    { name: 'All-Day Breakfast', items: [
      ['Desi omelette', 'Two eggs, onion, green chilli, toast', 320, ['vegetarian']],
      ['Halwa puri plate', 'Chana and two puffed puris', 380, ['vegetarian']],
      ['Chicken ruti roll', 'Egg-washed paratha, achaar', 280],
    ] },
    { name: 'Brunch Plates', items: [
      ['Zinger burger', 'Crisp chicken fillet, coleslaw', 620],
      ['Chicken cheese sandwich', 'Grilled sourdough, two cheeses', 620],
      ['Fettuccine alfredo', 'Cream, parmesan, parsley', 850, ['vegetarian']],
      ['French toast', 'Caramelised banana, honey butter', 480, ['vegetarian']],
    ] },
    { name: 'Coffee & Chai', items: [
      ['Espresso', 'Local roastery, single origin', 250, ['vegetarian']],
      ['Cappuccino', 'Silky micro-foam', 320, ['vegetarian']],
      ['Iced latte', 'Double shot, milk, ice', 380, ['vegetarian']],
      ['Doodh patti chai', 'Strong milk tea, cardamom', 150, ['vegetarian']],
    ] },
  ],
  chinese: [
    { name: 'Dim Sum', items: [
      ['Chicken dimsum (8)', 'Steamed, spring onion, chilli oil', 380],
      ['Prawn har gow (6)', 'Translucent wheat skin', 480],
      ['Chicken and mushroom siu mai (6)', 'Open-topped, ginger', 420],
    ] },
    { name: 'Wok & Rice', items: [
      ['Chicken chow mein', 'Hand-pulled noodles, pak choi', 520],
      ['American chopsui', 'Vermicelli, mixed vegetables, egg', 480, ['vegetarian']],
      ['Prawn salt and pepper', 'Crisp coating, chilli, spring onion', 950],
      ['Chicken sweet and sour', 'Pineapple, capsicum, house sauce', 620],
    ] },
    { name: 'Soups', items: [
      ['Hot and sour soup', 'Pepper, vinegar, shredded chicken', 300],
      ['Chicken corn soup', 'Sweetcorn, egg ribbon', 280],
    ] },
  ],
  seafood: [
    { name: 'From the Grill', items: [
      ['Grilled pomfret', 'Whole fish, butter garlic, lemon', 1450],
      ['Fish tikka', 'Boneless, ajwain marinade, charcoal', 950],
      ['Tandoori jhinga (6)', 'Prawns in red chilli yoghurt', 1250],
    ] },
    { name: 'Karahi & Rice', items: [
      ['Prawn karahi', 'Tomato, ginger, green chilli', 1350],
      ['Kekri masala (half)', 'Crab in coastal ginger-garlic masala', 1800],
      ['Prawn biryani', 'Coastal masala, coriander', 750],
    ] },
    { name: 'Coolers', items: [
      ['Lemon mint cooler', 'Muddled mint, lemon, soda', 250, ['vegetarian']],
      ['Rose lassi', 'Thick yoghurt, rose syrup', 280, ['vegetarian']],
      ['Arabic coffee', 'Cardamom, poured small', 200, ['vegetarian']],
    ] },
  ],
  breakfast: [
    { name: 'Nihari & Paye', items: [
      ['Nihari with bone', 'Overnight simmer, marrow on the side', 650],
      ['Nihari without bone', 'Wheat-thickened, ginger and chilli', 850],
      ['Mutton paye', 'Slow-cooked trotters, green chilli', 800],
      ['Chicken nihari (half)', 'Lighter cut, same overnight stock', 550],
    ] },
    { name: 'Haleem & Chana', items: [
      ['Haleem plate', 'Wheat, lentils and meat, fried onion', 420],
      ['Dal chana', 'Black chickpea, tamarind, chilli', 250, ['vegetarian']],
      ['Anda bhurji', 'Two eggs, onion, tomato, coriander', 300, ['vegetarian']],
    ] },
    { name: 'Breads & Chai', items: [
      ['Sheermal', 'Saffron-tinted, flaky', 120, ['vegetarian']],
      ['Puri (2)', 'Fresh fried to order', 40, ['vegetarian']],
      ['Doodh patti', 'Kettle-strong milk tea', 100, ['vegetarian']],
      ['Kashmiri chai', 'Pink tea, pistachio and almond', 220, ['vegetarian']],
    ] },
  ],
  mughlai: [
    { name: 'Mughlai Curries', items: [
      ['Butter chicken', 'Tomato-cashew gravy, kasuri methi', 780],
      ['Rogan josh', 'Kashmiri mutton, fennel and yoghurt', 1100],
      ['Daal Mughlai', 'Slow lentils, cream and butter', 450, ['vegetarian']],
    ] },
    { name: 'Kebabs', items: [
      ['Bihari kebab', 'Thin beef strips, roasted gram, cream', 650],
      ['Chicken tikka (half)', 'Charcoal, red masala', 650],
      ['Galouti kebab (4)', 'Melt-in-mouth minced mutton, on sheermal', 900],
    ] },
    { name: 'Rice & Desserts', items: [
      ['Dum pilao (mutton)', 'Sealed pot, saffron, whole spice', 650],
      ['Gulab jamun (4)', 'Warm, cardamom syrup', 200, ['vegetarian']],
      ['Kheer', 'Saffron rice pudding', 180, ['vegetarian']],
    ] },
  ],
  mezze: [
    { name: 'Mezze', items: [
      ['Hummus', 'Blended chickpea, tahini, olive oil', 450, ['vegetarian']],
      ['Moutabal', 'Smoked aubergine, yoghurt, pomegranate', 480, ['vegetarian']],
      ['Fattoush', 'Day-old bread, sumac, garden leaves', 550, ['vegetarian']],
      ['Stuffed vine leaf (4)', 'Rice, lemon and herb', 420, ['vegetarian']],
    ] },
    { name: 'Grill Platters', items: [
      ['Mixed grill (for two)', 'Shish tawook, kebab, hummus, bread', 1450],
      ['Lamb chops', 'Charcoal, rosemary salt', 1900],
      ['Grilled sea bass', 'Whole, olive and lemon', 1350],
    ] },
    { name: 'Sweets & Coffee', items: [
      ['Baklava (4)', 'Walnut phyllo, orange-blossom syrup', 380, ['vegetarian']],
      ['Kunafa', 'Shredded pastry, sweet cheese, syrup', 520, ['vegetarian']],
      ['Turkish coffee', 'Cardamom, served with water', 260, ['vegetarian']],
    ] },
  ],
  buffet: [
    { name: 'Buffet Counter', items: [
      ['Family buffet (per head)', 'Karachi classics, twelve plates, refill style', 1250],
      ['Kids buffet (under 10)', 'Half portions, no fish', 650],
      ['Friday seafood night', 'Prawns, calamari, grilled fish', 1650],
    ] },
    { name: 'Live Stations', items: [
      ['Karahi station', 'Cooked to order, chicken or mutton', 950],
      ['Chapli kebab station', 'Peshawari, hand-pressed', 600],
      ['Dessert corner', 'Gulab jamun, kheer, seasonal fruit', 240, ['vegetarian']],
    ] },
  ],
  grill: [
    { name: 'Cuts', items: [
      ['Chicken steak (250 g)', 'Charcoal, house marinade', 1250],
      ['Beef tenderloin (300 g)', 'Pan-seared, peppercorn jus', 2200],
      ['Lamb chops (3)', 'French-trimmed, rosemary', 2600],
      ['Mixed grill platter', 'Chicken, beef and lamb, four sauces', 2400],
    ] },
    { name: 'Small Plates', items: [
      ['Chicken cheese balls (6)', 'Molten centre, marinara', 520, ['vegetarian']],
      ['Calamari', 'Crisp rings, lemon aioli', 850],
      ['Loaded fries', 'Cheese, chicken, chilli', 650],
    ] },
    { name: 'Desserts', items: [
      ['Chocolate fondant', 'Molten centre, vanilla ice cream', 520, ['vegetarian']],
      ['New York cheesecake', 'Baked, berry compote', 480, ['vegetarian']],
    ] },
  ],
};

/** A venue's printed kitchen: which books it serves, in menu order. */
const venueSections = (r: KVenue): readonly KSection[] =>
  r.books.flatMap((b) => K_BOOKS[b] ?? []);

interface KVenue {
  readonly name: string;
  readonly area: string;
  readonly event: string;
  readonly tagline: string;
  readonly cuisines: readonly string[];
  readonly price: string;
  readonly rating: string;
  readonly reviews: number;
  readonly cover: string;
  readonly tags: readonly string[];
  readonly lat: number;
  readonly lng: number;
  /** Book names from K_BOOKS this kitchen serves, in printed order. */
  readonly books: readonly string[];
  /** Daily service window, venue-local (Asia/Karachi). */
  readonly hours: readonly [string, string];
  /** Seating areas the Partner App books tables in. */
  readonly zones: readonly string[];
  readonly plus: boolean;
}

const K_RESTAURANTS: readonly KVenue[] = [
  { name: 'Kolachi Restaurant', area: 'DHA Phase 8', event: 'Seaside BBQ Dinner',
    tagline: 'Sea-facing dining since 1989', cuisines: ['Pakistani', 'Seafood', 'BBQ'],
    price: '$$$', rating: '4.50', reviews: 3821, cover: 'assets/images/venue_rooftop.png',
    tags: ['seaside', 'bbq', 'family'], lat: 24.8055, lng: 67.0305,
    books: ['seafood', 'bbq'], hours: ['13:00', '23:30'],
    zones: ['Seafront Deck', 'Verandah', 'Family Section'], plus: true },
  { name: "Xander's Clifton", area: 'Clifton', event: 'Weekend Brunch Meetup',
    tagline: 'Coffee-house classics, all day', cuisines: ['Continental', 'Cafe', 'Brunch'],
    price: '$$', rating: '3.90', reviews: 2140, cover: 'assets/images/venue_interior.png',
    tags: ['brunch', 'cafe', 'meetup'], lat: 24.8122, lng: 67.0332,
    books: ['cafe', 'grill'], hours: ['09:00', '23:00'],
    zones: ['Courtyard', 'Main Hall', 'Bar Counter'], plus: false },
  { name: 'Cafe Aylanto', area: 'Clifton', event: 'Mediterranean Dining Night',
    tagline: 'Levantine courtyard dining', cuisines: ['Lebanese', 'Mediterranean'],
    price: '$$$', rating: '4.10', reviews: 1670, cover: 'assets/images/venue_bar.png',
    tags: ['mediterranean', 'courtyard', 'date-night'], lat: 24.8160, lng: 67.0280,
    books: ['mezze', 'grill'], hours: ['12:00', '23:00'],
    zones: ['Courtyard', 'Inner Room', 'Terrace'], plus: true },
  { name: 'Bar BQ Tonight Clifton', area: 'Boat Basin', event: 'Pakistani BBQ Experience',
    tagline: 'Flip-shop grill, late into the night', cuisines: ['BBQ', 'Pakistani'],
    price: '$$', rating: '4.30', reviews: 2980, cover: 'assets/images/dish_steak.png',
    tags: ['bbq', 'late-night', 'casual'], lat: 24.8100, lng: 67.0255,
    books: ['bbq', 'karahi'], hours: ['16:00', '23:59'],
    zones: ['Open Grill Floor', 'Family Cabin', 'Patio'], plus: false },
  { name: "Chef's Table Pakistan", area: 'DHA Phase 6', event: "Chef's Tasting Experience",
    tagline: 'Counter-side tasting by resident chefs', cuisines: ['Fusion', 'Tasting'],
    price: '$$$$', rating: '4.90', reviews: 1120, cover: 'assets/images/hero_tasting.png',
    tags: ['tasting', 'chef-counter', 'premium'], lat: 24.7980, lng: 67.0550,
    books: ['grill', 'mezze'], hours: ['19:00', '23:30'],
    zones: ['Chef\u2019s Counter', 'Private Room'], plus: true },
  { name: 'The Carnivore Karachi', area: 'DHA Phase 6', event: 'Premium Meat Tasting',
    tagline: 'Fire-grilled premium cuts', cuisines: ['Grill', 'Steakhouse'],
    price: '$$$', rating: '4.70', reviews: 1890, cover: 'assets/images/dish_steak.png',
    tags: ['grill', 'steak', 'date-night'], lat: 24.7995, lng: 67.0570,
    books: ['grill', 'bbq'], hours: ['12:30', '23:30'],
    zones: ['Fire Grill Room', 'Banquet', 'Window Tables'], plus: false },
  { name: 'Dynasty', area: 'Saddar', event: 'Chinese Fine Dining',
    tagline: 'Saddar institution for Chinese-Karachi classics', cuisines: ['Chinese', 'Dim Sum'],
    price: '$$', rating: '4.50', reviews: 3410, cover: 'assets/images/dish_sushi.png',
    tags: ['chinese', 'family', 'heritage'], lat: 24.8965, lng: 67.0245,
    books: ['chinese', 'karahi'], hours: ['12:00', '23:00'],
    zones: ['Ground Hall', 'First Floor', 'Family Lounge'], plus: false },
  { name: 'Kanteen', area: 'Tipu Sultan', event: 'Desi Food Meetup',
    tagline: 'Desi plates in a cantonment-heritage setting', cuisines: ['Pakistani', 'Desi'],
    price: '$$', rating: '4.60', reviews: 1450, cover: 'assets/images/dish_pasta.png',
    tags: ['desi', 'meetup', 'casual'], lat: 24.8525, lng: 67.0420,
    books: ['cafe', 'bbq'], hours: ['11:00', '23:00'],
    zones: ['Canteen Hall', 'Verandah', 'Mezzanine'], plus: false },
  { name: 'Foods Inn', area: 'SMCHS', event: 'Family Food Festival',
    tagline: 'Family buffet and karahi corner', cuisines: ['Pakistani', 'Buffet'],
    price: '$$', rating: '4.30', reviews: 2260, cover: 'assets/images/dish_brunch.png',
    tags: ['buffet', 'family', 'festival'], lat: 24.8510, lng: 67.0010,
    books: ['buffet', 'karahi'], hours: ['12:00', '23:00'],
    zones: ['Buffet Hall', 'Family Annex', 'Garden'], plus: false },
  { name: 'The East End', area: 'Clifton', event: 'Karachi Heritage Tasting',
    tagline: 'Garden dining with old-city charm', cuisines: ['Continental', 'Heritage'],
    price: '$$$', rating: '4.70', reviews: 1980, cover: 'assets/images/venue_interior.png',
    tags: ['heritage', 'garden', 'date-night'], lat: 24.8135, lng: 67.0195,
    books: ['mezze', 'grill'], hours: ['12:00', '23:30'],
    zones: ['Lawn', 'Colonial Room', 'Porch'], plus: true },
  { name: 'Bar B Q Island', area: 'Gulshan-e-Iqbal', event: 'Charcoal Night: Kebab and Karahi',
    tagline: 'Hall-sized charcoal grilling', cuisines: ['BBQ', 'Pakistani', 'Karahi'],
    price: '$$', rating: '4.40', reviews: 2450, cover: 'assets/images/dish_steak.png',
    tags: ['bbq', 'family-hall', 'karahi'], lat: 24.8895, lng: 67.0790,
    books: ['bbq', 'karahi'], hours: ['16:00', '23:59'],
    zones: ['Main Hall', 'Family Section', 'Garden'], plus: false },
  { name: 'Karachi Darbar', area: 'PECHS', event: 'Mughlai Long Table',
    tagline: 'Durbar-style Mughlai plates', cuisines: ['Mughlai', 'North Indian', 'Pakistani'],
    price: '$$', rating: '4.20', reviews: 1980, cover: 'assets/images/venue_interior.png',
    tags: ['mughlai', 'durbar', 'family'], lat: 24.8467, lng: 67.0655,
    books: ['mughlai', 'karahi'], hours: ['12:00', '23:30'],
    zones: ['Durbar Hall', 'Curtained Booths', 'Courtyard'], plus: false },
  { name: 'Waris Nihari', area: 'Saddar', event: 'Nihari Breakfast Table',
    tagline: 'Overnight nihari, Akbar Chowk', cuisines: ['Nihari', 'Desi Breakfast', 'Pakistani'],
    price: '$', rating: '4.60', reviews: 3600, cover: 'assets/images/dish_brunch.png',
    tags: ['nihari', 'breakfast', 'heritage'], lat: 24.8870, lng: 67.0300,
    books: ['breakfast', 'karahi'], hours: ['07:00', '14:00'],
    zones: ['Marble Counter', 'Street Tables', 'Family Corner'], plus: false },
  { name: 'Nazir Kabab House', area: 'DHA Phase 4', event: 'Kabab and Chai Session',
    tagline: 'Skewered plates, open late', cuisines: ['Kabab', 'Pakistani', 'BBQ'],
    price: '$$', rating: '4.30', reviews: 2210, cover: 'assets/images/dish_tacos.png',
    tags: ['kabab', 'late-night', 'takeaway'], lat: 24.8435, lng: 67.0595,
    books: ['bbq', 'biryani'], hours: ['13:00', '23:59'],
    zones: ['Courtyard', 'Hall', 'Family Annex'], plus: false },
  { name: 'Mitha Biryani', area: 'Gulshan-e-Iqbal', event: 'Biryani Trail Tasting',
    tagline: 'Sweet-house biryani since the eighties', cuisines: ['Biryani', 'Sindhi', 'Mughlai'],
    price: '$', rating: '4.50', reviews: 5200, cover: 'assets/images/dish_tacos.png',
    tags: ['biryani', 'heritage', 'takeaway'], lat: 24.8925, lng: 67.0735,
    books: ['biryani', 'karahi'], hours: ['11:00', '23:30'],
    zones: ['Counter', 'Hall', 'Family Screen'], plus: false },
  { name: 'Sierra Coffee', area: 'DHA Phase 5', event: 'Slow Brunch and Filter Coffee',
    tagline: 'Roastery tables, laptops welcome', cuisines: ['Cafe', 'Continental', 'Brunch'],
    price: '$$', rating: '4.40', reviews: 1560, cover: 'assets/images/venue_bar.png',
    tags: ['coffee', 'brunch', 'work-friendly'], lat: 24.8205, lng: 67.0680,
    books: ['cafe', 'mezze'], hours: ['08:00', '23:00'],
    zones: ['Roastery Bar', 'Lounge', 'Window Seats'], plus: true },
  { name: 'Handi Food and Cuisine', area: 'Karsaz', event: 'Family Karahi and Buffet Night',
    tagline: 'Hall dining with a live karahi counter', cuisines: ['Pakistani', 'Buffet', 'Karahi'],
    price: '$$', rating: '4.10', reviews: 2780, cover: 'assets/images/venue_interior.png',
    tags: ['buffet', 'family', 'hall'], lat: 24.8770, lng: 67.0960,
    books: ['buffet', 'karahi', 'biryani'], hours: ['12:00', '23:30'],
    zones: ['Buffet Hall', 'Live Karahi', 'Family Wing'], plus: false },
  { name: 'Great Kamran', area: 'Gulshan-e-Iqbal', event: 'Chinese Karachi Classics Night',
    tagline: 'Dim sum and wok plates, family booths', cuisines: ['Chinese', 'Dim Sum', 'Karachi'],
    price: '$$', rating: '4.20', reviews: 1890, cover: 'assets/images/dish_pasta.png',
    tags: ['chinese', 'dim-sum', 'family'], lat: 24.8940, lng: 67.0695,
    books: ['chinese', 'karahi'], hours: ['13:00', '23:59'],
    zones: ['Red Room', 'Family Booths', 'Main Floor'], plus: false },
  { name: 'Sea Shell', area: 'DHA Phase 8', event: 'Seafood Grill and Arabic Dinner',
    tagline: 'Pomfret, prawns and Arabic majlis', cuisines: ['Seafood', 'Arabic', 'Grill'],
    price: '$$$', rating: '4.30', reviews: 1340, cover: 'assets/images/dish_sushi.png',
    tags: ['seafood', 'arabic', 'date-night'], lat: 24.8040, lng: 67.0290,
    books: ['seafood', 'mezze'], hours: ['12:30', '23:59'],
    zones: ['Seafront Deck', 'Majlis Rooms', 'Main Dining'], plus: false },
  { name: 'Al-Bismillah Hot Foods', area: 'Bahadurabad', event: 'Late Night Karahi and Tikka',
    tagline: 'The neighbourhood karahi and tikka spot', cuisines: ['Karahi', 'BBQ', 'Desi'],
    price: '$$', rating: '4.30', reviews: 2450, cover: 'assets/images/dish_steak.png',
    tags: ['karahi', 'late-night', 'local-favourite'], lat: 24.8800, lng: 67.0450,
    books: ['karahi', 'bbq', 'biryani'], hours: ['16:00', '23:59'],
    zones: ['Hall', 'Family Section', 'Street Counter'], plus: false },
] as const;

// Three venues stay in the candidate pipeline (unverified) so the 403 rejection
// path on POST /events and the admin verification queue stay testable in the
// demo world.
const K_UNVERIFIED_VENUES = new Set<string>(['Kanteen', 'Foods Inn', 'Al-Bismillah Hot Foods']);

// Curated creator shortlist (public handles; fictional follower counts, this
// is not a definitive ranking and none are signed DineCircle hosts).
const K_CREATORS = [
  { name: 'Fatima Tariq', ig: 'fatima_tariqft', focus: 'Food & lifestyle', followers: 128400, area: 'DHA Phase 6' },
  { name: 'Dua Anees', ig: 'trendingwithdua', focus: 'Local food discoveries', followers: 96500, area: 'Clifton' },
  { name: 'Madiha Razzak', ig: 'foodienextdoor', focus: 'Food photography & reviews', followers: 45200, area: 'Gulshan-e-Iqbal' },
  { name: 'Safia Alam', ig: '_tolittlethings', focus: 'Food & lifestyle', followers: 38900, area: 'PECHS' },
  { name: 'Varisha Ali', ig: 'varishaslens', focus: 'Food & lifestyle', followers: 27400, area: 'KDA Scheme 1' },
  { name: 'Sham Kumar', ig: 'lifewsham', focus: 'Food & local businesses', followers: 84000, area: 'Saddar' },
  { name: 'Sai Naqui', ig: 'sairanaqui', focus: 'Premium dining', followers: 52600, area: 'DHA Phase 5' },
  { name: 'Hunain Raja', ig: 'hunainahmedraja', focus: 'Food & entrepreneurship', followers: 61000, area: 'Bahadurabad' },
  { name: 'Narmeen Aamir', ig: 'wanderbitesadventures', focus: 'Café & restaurant reviews', followers: 33800, area: 'Khayaban-e-Bukhari' },
  { name: 'Raheel Tariq', ig: 'muhammadraheel03', focus: 'Street food & breakfast', followers: 74200, area: 'Lyari' },
] as const;

// Eight fictional personas. The creator shortlist above borrows real public
// handles, so the extra discovery depth comes from invented accounts instead of
// attributing made-up metrics to real people. Every one is `is_demo` and says so
// in its bio.
const K_PERSONAS = [
  { name: 'Zoya Rahman', ig: 'karachi.tables', focus: 'Long-table dinners', followers: 18400, area: 'Clifton' },
  { name: 'Harris Vohra', ig: 'biryani.diaries', focus: 'The biryani trail', followers: 22600, area: 'Gulshan-e-Iqbal' },
  { name: 'Meher Qadri', ig: 'meher.plate', focus: 'Heritage recipes and home kitchen suppers', followers: 15900, area: 'Saddar' },
  { name: 'Tania Sohail', ig: 'chai.and.cinemas', focus: 'Chai culture and café walks', followers: 12700, area: 'North Nazimabad' },
  { name: 'Omar Sabzwari', ig: 'omargrillroom', focus: 'Charcoal grill and BBQ', followers: 30100, area: 'DHA Phase 4' },
  { name: 'Rukhsana Yousuf', ig: 'oldcity.bites', focus: 'Burns Road street food', followers: 26800, area: 'Mewa Tandoor' },
  { name: 'Aimen Sheikh', ig: 'aimen.foodnotes', focus: 'Desserts and weekend brunch', followers: 9800, area: 'PECHS' },
  { name: 'Rehan Baloch', ig: 'rehan.seafood', focus: 'Seafood and Arabic grills', followers: 21300, area: 'DHA Phase 8' },
] as const;

const K_HOSTS = [...K_CREATORS, ...K_PERSONAS] as const;

// Karachi areas, used for home locales, saved places and the city picker.
const K_AREAS = ['DHA Phase 4', 'DHA Phase 5', 'DHA Phase 6', 'DHA Phase 8', 'Clifton',
  'Boat Basin', 'Khayaban-e-Bukhari', 'Cavission', 'Gulshan-e-Iqbal', 'PECHS', 'KDA Scheme 1',
  'North Nazimabad', 'Saddar', 'Burns Road', 'Akbar Chowk', 'Bahadurabad', 'Gulistan-e-Johar',
  'Shah Faisal Colony', 'Korangi', 'SITE Area', 'Landhi', 'Malir', 'Lyari', 'Mewa Tandoor',
  'Tipu Sultan', 'SMCHS', 'Federal B Area', 'Gulberg Karachi'] as const;

const K_FIRST = ['Ayesha', 'Bilal', 'Hina', 'Usman', 'Zara', 'Hamza', 'Iqra', 'Daniyal', 'Sana', 'Faisal',
  'Mahnoor', 'Ahmed', 'Alina', 'Junaid', 'Kiran', 'Laiba', 'Musa', 'Nida', 'Owais', 'Saba',
  'Talha', 'Rabia', 'Sameer', 'Anum', 'Bilal', 'Danish', 'Eman', 'Faraz', 'Hira', 'Imran',
  'Javeria', 'Kausar', 'Luqman', 'Mariam', 'Naveed'] as const;
const K_LAST = ['Khan', 'Sheikh', 'Qureshi', 'Memon', 'Ansari', 'Siddiqui', 'Chaudhry', 'Ibrahim',
  'Haider', 'Malik', 'Baloch', 'Sohotra', 'Vohra', 'Abidi', 'Tambo', 'Lakhani', 'Sabzwari',
  'Taghyar', 'Dehwar', 'Jamali'] as const;
const K_EXTRA_EVENTS = ['Supper Club Night', 'Long Table Session', 'Chai and Kebab Evening',
  'Chef\u2019s Table Edition', 'Family Karahi Night'] as const;
const K_TYPES = ['dinner', 'tasting', 'supperClub', 'brunch', 'workshop', 'festival'] as const;
const K_TYPE_LABELS = ['long-table dinner', 'chef tasting', 'supper club', 'slow brunch',
  'kitchen workshop', 'food festival'] as const;
const K_MENU_STYLES = ['setMenu', 'tastingMenu', 'familyStyle', 'sharing', 'buffet'] as const;
const K_PAIRINGS: (string | null)[] = ['Mint lemon soda', 'Lassi', 'Doodh patti chai',
  'Kashmiri chai', 'Nimbu soda', 'Soft drink', null];
const K_DRESS = ['Smart Casual', 'Casual', 'Traditional Attire'] as const;
const K_LANGUAGES = ['English', 'Urdu', 'English, Urdu'] as const;
const K_DIETARY = ['Halal', 'Vegetarian', 'Dairy-Free', 'Nut-Free', 'Gluten-Free'] as const;
const K_ALLERGIES = ['Nuts', 'Dairy', 'Seafood', 'Wheat', 'Eggs'] as const;
const K_REVIEW_TEXTS = [
  'Long table, warm hosts, and the seekh kebab sold out early. Already asking for a second edition.',
  'Smooth check-in at the door and the QR ticket worked first try.',
  'Great value for a demo ticket; portions were generous.',
  'The hosting flow was flawless, though the dessert service ran late.',
  'Loved the crowd: half the table were followers, and everyone got along.',
  'Mock payment cleared instantly and the payout report matched to the rupee.',
  'Seaside seating sold out fast; book earlier next time.',
  'The tasting course pacing was the best of the night.',
  'Family-friendly, high chairs available, booking took two taps.',
  'Heritage room was atmospheric; the photos practically took themselves.',
  'Brunch coffee refills kept coming. Solid meetup format.',
  'Solid test run. A couple of plates arrived late, but the host comped round.',
  'Karahi came piping hot and the naan never stopped arriving. Karachi standard.',
  'Nihari at eleven in the morning with sheermal. The table talked for two hours.',
  'Biryani was properly mitha and the raita balanced it. Would book this again.',
  'Charcoal grill by the open kitchen, and the staff explained every cut.',
  'Quiet family section, good parking, and the chai limit was not enforced.',
  'Dim sum came fresh off the steamer; the hall got loud by nine, as it should.',
] as const;
const K_RATINGS = ['5.00', '4.80', '4.50', '4.00', '4.90', '3.80'] as const;
const K_TASTES = ['BBQ', 'biryani', 'cafés', 'desserts', 'street food', 'karahi', 'brunch',
  'seafood', 'nihari', 'haleem', 'chai', 'dim sum', 'mughlai'] as const;
const K_AVATARS = ['assets/images/portrait_1.png', 'assets/images/portrait_2.png',
  'assets/images/portrait_3.png', 'assets/images/portrait_4.png', 'assets/images/portrait_5.png',
  'assets/images/portrait_6.png'] as const;
const K_ACCENTS = ['#C26B4E', '#7A4A6B', '#4A5A7A', '#4A7A5A', '#8A5A2B'] as const;

// Seat sizes the seed lays out per venue, rotated by venue index so halls are
// not all identical. `restaurants.seats` always equals the sum of the venue's
// restaurant_tables rows, which is what the capacity check reads.
const K_TABLE_SIZES = [2, 4, 4, 6, 6, 8, 10, 12] as const;

const K_PERKS = [
  'Free welcome chai for DineCircle guests',
  'Complimentary dessert on DineCircle tables',
  'Ten percent off the a-la-carte bill for DineCircle guests',
  'Reserved family section held for DineCircle tables',
  'Kitchen tour with the head chef for DineCircle tables',
] as const;

// Mock photo pool for the venue menu items. The kitchen dishes are fictional,
// so the pictures are the bundled placeholders cycled in reading order.
const K_DISH_PHOTOS = ['assets/images/dish_steak.png', 'assets/images/dish_tacos.png',
  'assets/images/dish_brunch.png', 'assets/images/dish_pasta.png',
  'assets/images/dish_sushi.png', 'assets/images/dish_dessert.png'] as const;

const K_RESERVATION_STATUSES = ['confirmed', 'pending', 'seated', 'completed',
  'cancelled', 'no_show'] as const;

/** Table inventory: six to ten tables, spread across the venue's zones. */
function venueTables(r: KVenue, vi: number): { label: string; seats: number; zone: string }[] {
  const count = 6 + (vi % 3) * 2;
  return Array.from({ length: count }, (_, i) => ({
    label: `T-${String(i + 1).padStart(2, '0')}`,
    seats: item(K_TABLE_SIZES, vi + i),
    zone: item(r.zones, i),
  }));
}

/** Daily service windows in the shape reservations.ts reads from jsonb. */
function weekHours(r: KVenue): Record<string, { windows: { open: string; close: string }[] }> {
  const [open, close] = r.hours;
  return Object.fromEntries(
    ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'].map((day) => [day, { windows: [{ open, close }] }]),
  );
}

/** Building the Karachi world is one pass over the catalogue above. */
async function seedKarachi(): Promise<void> {
  // Candidate-partner desk owns every Karachi venue (partner routes work).
  const opsId = kid('a', 1);
  await insertAll('users',
    ['id', 'name', 'handle', 'phone', 'email', 'password_hash', 'city', 'home_area', 'bio', 'role', 'joined_year'],
    [[opsId, 'Karachi Partners Desk', 'karachi.desk', '+923450000001', 'karachi.desk+demo@example.test',
      demoHash(), 'Karachi', 'Saddar',
      'Candidate-partner desk for the Karachi test environment. Most listings are verified partners; a few remain unverified candidates.',
      'partner_admin', 2025]]);

  const restIds = K_RESTAURANTS.map((_, i) => kid('b', i + 1));
  const branchIds = K_RESTAURANTS.map((_, i) => kid('4', i + 1));
  const tablesByVenue = K_RESTAURANTS.map((r, vi) => venueTables(r, vi));
  const tableIdsByVenue = tablesByVenue.map((tables, vi) =>
    tables.map((_, i) => kid('7', vi * 10 + i + 1)));
  const seatsByVenue = tablesByVenue.map((tables) =>
    tables.reduce((total, t) => total + t.seats, 0));
  const dishesByVenue = K_RESTAURANTS.map((r) =>
    venueSections(r).flatMap((s) => s.items.map((d) => ({ name: d[0], desc: d[1], section: s.name }))));

  // ── 20 candidate restaurants (real names; 17 verified partners, 3 candidates) ──
  await insertAll('restaurants',
    ['id', 'owner_id', 'name', 'tagline', 'about', 'cuisines', 'neighborhood', 'address', 'city',
      'phone', 'email', 'website', 'instagram', 'price_range', 'rating', 'review_count', 'seats',
      'tables_count', 'since', 'owner_name', 'amenities', 'opening_hours', 'profile_completion',
      'accepting_bookings', 'dine_circle_plus', 'cover_image', 'gallery', 'tags', 'is_partner',
      'partner_perk', 'partnership_status', 'latitude', 'longitude'],
    K_RESTAURANTS.map((r, i) => {
      const verified = !K_UNVERIFIED_VENUES.has(r.name);
      return [
        item(restIds, i), opsId, r.name, r.tagline,
        `Test listing: ${r.name} in ${r.area} is seeded as a DineCircle candidate venue. The venue has not agreed to any partnership. Name, area, cuisine and price band are public; the menu, hours, events and earnings below are mock data.`,
        [...r.cuisines], r.area, `${r.name}, ${r.area}`, 'Karachi',
        `+92213${String(3500001 + i)}`, `rest${String(i + 1).padStart(2, '0')}.demo@example.test`, '', '',
        r.price, r.rating, r.reviews, item(seatsByVenue, i), item(tablesByVenue, i).length,
        String(int(1970, 2019)),
        `${r.name.split(' ')[0]} Management`,
        ['Indoor seating', 'Family section', 'VA parking', ...(r.plus ? ['DineCircle+ host desk'] : [])],
        weekHours(r), verified ? 92 : 68, true, r.plus, r.cover,
        [r.cover, item(K_DISH_PHOTOS, i)], [...r.tags], verified,
        verified ? item(K_PERKS, i) : null, verified ? 'verified' : 'unverified',
        r.lat, r.lng,
      ];
    }));

  // ── 18 creator host profiles (10 borrowed public handles, 8 personas) ────
  // The first two creators are crowned Food Influencers (verified badge) so
  // demo data exercises the top of the ladder; the rest stay eligible hosts,
  // claimable live via POST /users/me/influencer.
  const hostIds = K_HOSTS.map((_, i) => kid('f', i + 1));
  await insertAll('users',
    ['id', 'name', 'handle', 'phone', 'email', 'password_hash', 'city', 'home_area', 'bio', 'role',
      'instagram', 'followers_count', 'following_count', 'dinners_hosted', 'dinners_joined', 'rating',
      'review_count', 'avatar_url', 'badges', 'tastes', 'dietary', 'accent_hex', 'joined_year'],
    K_HOSTS.map((h, i) => [
      item(hostIds, i), h.name, h.ig, `+92300${String(1000001 + i)}`, `${h.ig}.demo@example.test`,
      demoHash(), 'Karachi', h.area,
      i < K_CREATORS.length
        ? `Karachi ${h.focus.toLowerCase()} creator. Seeded as a candidate host profile for discovery testing, not a signed DineCircle creator.`
        : `Fictional Karachi test persona: ${h.focus.toLowerCase()}. Seeded for discovery testing; not a real account.`,
      i <= 1 ? 'influencer' : 'host', `@${h.ig}`, h.followers, int(40, 300), int(3, 14), int(2, 9),
      (4 + rand()).toFixed(2), int(12, 60), item(K_AVATARS, i),
      i <= 1 ? ['verified'] : i % 4 === 0 ? ['Rising Host'] : [], [pick(K_TASTES), pick(K_TASTES)],
      [item(K_DIETARY, i)], item(K_ACCENTS, i), 2024,
    ]));

  // ── 150 test diners, spread over Karachi's home areas ───────────────────
  const dinerIds = Array.from({ length: 150 }, (_, i) => kid('d', i + 1));
  await insertAll('users',
    ['id', 'name', 'handle', 'phone', 'email', 'password_hash', 'city', 'home_area', 'bio', 'role',
      'followers_count', 'following_count', 'dinners_joined', 'rating', 'review_count', 'avatar_url',
      'tastes', 'dietary', 'allergies', 'accent_hex', 'joined_year'],
    dinerIds.map((id, i) => {
      const first = item(K_FIRST, i);
      const last = item(K_LAST, i);
      return [
        id, `${first} ${last}`, `${first}.${last}${i}`.toLowerCase(),
        `+92311${String(i).padStart(7, '0')}`, `diner${String(i + 1).padStart(3, '0')}.demo@example.test`,
        demoHash(), 'Karachi', item(K_AREAS, i),
        `Test diner #${i + 1} for the Karachi environment.`, 'user',
        int(0, 40), int(0, 200), int(1, 18), Number((3.5 + rand() * 1.5).toFixed(2)), int(0, 12),
        item(K_AVATARS, i), [pick(K_TASTES), pick(K_TASTES)],
        i % 6 === 0 ? [item(K_DIETARY, i)] : [], i % 9 === 0 ? [item(K_ALLERGIES, i)] : [],
        item(K_ACCENTS, i), 2025,
      ];
    }));

  // ── 60 demo events (3 per venue; 24 completed editions drive the tail of
  //    the funnel: reviews, payouts, check-ins) ────────────────────────────
  interface KEvent {
    id: string; ri: number; hi: number; ei: number; title: string; type: string;
    past: boolean; gate: boolean; seatsTotal: number; price: number; checkedAt: string | null;
  }
  const events: KEvent[] = [];
  K_RESTAURANTS.forEach((r, ri) => {
    for (let g = 0; g < 3; g += 1) {
      const ei = events.length;
      const type = item(K_TYPES, ei);
      events.push({
        id: kid('c', ei + 1), ri, hi: ei % K_HOSTS.length, ei, type,
        title: g === 0 ? r.event : `${r.name.split(' ')[0]} ${item(K_EXTRA_EVENTS, g - 1)}`,
        past: ei % 5 < 2, gate: ei === 3 || ei === 18 || ei === 41,
        seatsTotal: Math.min(item(seatsByVenue, ri), int(16, 34)), price: int(8, 28) * 500,
        checkedAt: ei % 5 < 2 ? at(-(13 + ei), 19, 15) : null,
      });
    }
  });
  await insertAll('dinner_events',
    ['id', 'title', 'tagline', 'description', 'host_id', 'restaurant_id', 'cover_image',
      'gallery', 'start_at', 'end_at', 'duration_minutes', 'seats_total', 'seats_booked',
      'price_per_seat', 'type', 'audience', 'menu_style', 'included', 'tags', 'is_featured',
      'host_note', 'attendee_ids', 'status', 'views', 'requires_approval', 'language',
      'dress_code'],
    events.map((e) => {
      const r = item(K_RESTAURANTS, e.ri);
      // Brunch and workshop editions sit in the venue's daytime window;
      // dinners start at seven, Karachi time.
      const hour = e.type === 'brunch' || e.type === 'workshop' ? 11 : 19;
      return [
        e.id, e.title, `${r.tagline}: demo edition`,
        `Mock ${item(K_TYPE_LABELS, e.ei)} at ${r.name} (${r.area}). Ticket prices, menu and timings are fictional test data; no venue has confirmed an event.`,
        item(hostIds, e.hi), item(restIds, e.ri), r.cover, [r.cover, item(K_DISH_PHOTOS, e.ei)],
        at(e.past ? -(14 + e.ei) : 2 + e.ei, hour), at(e.past ? -(14 + e.ei) : 2 + e.ei, hour + 3),
        180, e.seatsTotal, 0, e.price, e.type,
        e.gate ? 'followers' : e.ei % 11 === 0 ? 'inviteOnly' : 'public',
        item(K_MENU_STYLES, e.ei), ['Welcome chai', 'Shared plates', 'Dessert'],
        [...r.tags], e.ei % 9 === 0,
        'Demo note: the mock check-in desk opens 15 minutes early.', [],
        e.past ? 'completed' : 'confirmed', int(180, 3200), e.gate,
        item(K_LANGUAGES, e.ei), item(K_DRESS, e.ei),
      ];
    }));

  // ── event courses, drawn from the host venue's own kitchen ──────────────
  await insertAll('menu_items',
    ['event_id', 'position', 'name', 'description', 'pairing', 'signature'],
    events.flatMap((e) => {
      const dishes = item(dishesByVenue, e.ri);
      return Array.from({ length: 3 }, (_, c) => {
        const dish = item(dishes, e.ei * 3 + c);
        return [
          e.id, c, dish.name, `${dish.section}: mock course line for the test edition`,
          pick(K_PAIRINGS), c === 0,
        ];
      });
    }));

  // ── 300 bookings (5 per event; gate events hold pending seats; the mock
  //    payment is a PKR wallet label, no real transaction ever happens) ────
  const bookedSeats = new Map<string, number>();
  const attendees = new Map<string, string[]>();
  const reviewable: { event: KEvent; userId: string }[] = [];
  const bookingRows: unknown[][] = [];
  events.forEach((e) => {
    for (let b = 0; b < 5; b += 1) {
      const bi = e.ei * 5 + b;
      const guest = item(dinerIds, bi);
      const seats = int(1, 4);
      const cancelled = bi % 37 === 0;
      const checkedIn = !cancelled && e.past && bi % 3 !== 0;
      bookingRows.push([
        e.id, guest, seats, e.price, seats * e.price, `DC-K${String(100001 + bi)}`,
        'Mock wallet PKR',
        cancelled ? 'failed' : e.gate && !e.past ? 'authorized' : 'paid',
        cancelled ? 'cancelled' : e.past ? 'completed' : e.gate ? 'pending' : 'confirmed',
        checkedIn, checkedIn ? e.checkedAt : null,
      ]);
      if (!cancelled) {
        bookedSeats.set(e.id, (bookedSeats.get(e.id) ?? 0) + seats);
        attendees.set(e.id, [...(attendees.get(e.id) ?? []), guest]);
        if (e.past) reviewable.push({ event: e, userId: guest });
      }
    }
  });
  await insertAll('bookings',
    ['event_id', 'user_id', 'seats', 'price_per_seat', 'total_amount', 'reference',
      'payment_label', 'payment_status', 'status', 'checked_in', 'checked_in_at'],
    bookingRows);
  for (const e of events) {
    await pool.query(
      'UPDATE dinner_events SET seats_booked = $2, attendee_ids = $3 WHERE id = $1',
      [e.id, bookedSeats.get(e.id) ?? 0, attendees.get(e.id) ?? []],
    );
  }

  // ── reviews, only from guests with completed (mock-paid) bookings ───────
  await insertAll('reviews', ['author_id', 'event_id', 'rating', 'text', 'created_at'],
    reviewable.slice(0, 120).map(({ event, userId }, i) => [
      userId, event.id, item(K_RATINGS, i), item(K_REVIEW_TEXTS, i), at(-(12 + event.ei), 15),
    ]));

  // ── mock host earnings: payouts for the completed editions ───────────────
  await insertAll('payouts', ['event_id', 'payout_date', 'seats_sold', 'gross', 'commission', 'status'],
    events.filter((e) => e.past).map((e) => {
      const seats = bookedSeats.get(e.id) ?? 0;
      const gross = seats * e.price;
      return [e.id, at(-(11 + e.ei), 10), seats, gross, Math.round(gross * 0.1),
        item(['paid', 'processing'], e.ei)];
    }));

  // ── host wallet: a few settled PKR withdrawals for the top creators ─────
  await insertAll('withdrawals', ['host_id', 'amount', 'method', 'status', 'created_at'], [
    [item(hostIds, 0), 285000, 'Bank •••• 4417', 'completed', at(-26, 9)],
    [item(hostIds, 1), 148000, 'JazzCash', 'completed', at(-14, 11)],
    [item(hostIds, 2), 96000, 'EasyPaisa', 'processing', at(-4, 16)],
    [item(hostIds, 5), 64000, 'Bank •••• 2205', 'requested', at(-1, 10)],
  ]);

  // ── social graph: diners follow creators and venues; saved for discovery ─
  await insertAll('follows', ['follower_id', 'followee_id'],
    dinerIds.flatMap((d, i) => [[d, item(hostIds, i)], [d, item(hostIds, i + 3)]]));
  await insertAll('venue_follows', ['user_id', 'restaurant_id'],
    dinerIds.flatMap((d, i) => [[d, item(restIds, i)], [d, item(restIds, i + 7)]]));
  const upcoming = events.filter((e) => !e.past);
  await insertAll('saved_events', ['user_id', 'event_id'],
    Array.from({ length: 90 }, (_, s) => [item(dinerIds, s * 5), item(upcoming, s).id]));

  // ── saved places (location picker) for the first 30 diners ───────────────
  await insertAll('saved_locations',
    ['user_id', 'kind', 'name', 'city', 'area', 'address', 'latitude', 'longitude'],
    dinerIds.slice(0, 30).flatMap((d, i) => {
      const home = item(K_AREAS, i);
      const venue = item(K_RESTAURANTS, i);
      return [
        [d, 'home', `Home: ${home}`, 'Karachi', home, `Flat ${100 + i}, ${home}`, 24.80 + i * 0.002, 67.02 + i * 0.002],
        [d, 'work', `Office: ${item(K_AREAS, i + 5)}`, 'Karachi', item(K_AREAS, i + 5),
          `${item(K_AREAS, i + 5)}, Karachi`, 24.85 + i * 0.001, 67.05 + i * 0.001],
        [d, 'favourite', venue.name, 'Karachi', venue.area, `${venue.name}, ${venue.area}`,
          venue.lat, venue.lng],
      ];
    }));

  // ── activity + chat feeds ──────────────────────────────────────────────
  await insertAll('activity', ['actor_id', 'kind', 'title', 'body', 'event_id', 'amount', 'is_unread'], [
    ...upcoming.slice(0, 16).map((e) => [
      item(hostIds, e.hi), 'newGuest', 'A new guest booked demo seats',
      `${item(K_RESTAURANTS, e.ri).name} test listing picked up new bookings.`, e.id,
      (bookedSeats.get(e.id) ?? 0) * e.price, true]),
    ...events.filter((e) => e.past).slice(0, 12).map((e) => [
      item(hostIds, e.hi), 'payout', 'Mock payout scheduled',
      `Fictional PKR earnings for ${e.title} are queued in the host wallet.`, e.id,
      Math.round((bookedSeats.get(e.id) ?? 0) * e.price * 0.9), false]),
    ...hostIds.map((h, i) => [
      h, 'follower', 'New followers this week',
      `Simulated growth for the ${item(K_HOSTS, i).focus} profile.`, null, null, i % 2 === 0]),
    ...reviewable.slice(0, 8).map(({ event, userId }, i) => [
      userId, 'review', 'A guest reviewed your table',
      `Demo review left on ${event.title}.`, event.id, null, i % 3 !== 0]),
  ]);
  await insertAll('chat_messages', ['event_id', 'author_id', 'text', 'sent_at', 'is_system'],
    upcoming.slice(0, 8).flatMap((e, i) => [
      [e.id, null, 'Welcome to the event chat. This is a demo thread for a test listing.', at(1, 12), true],
      [e.id, item(dinerIds, i * 3), 'Saved my seat for the meetup. See you there!', at(1, 13, 20 + i), false],
      [e.id, item(hostIds, e.hi), 'Host here. The check-in QR goes out the morning of the event (mock).', at(1, 14, 5 + i), false],
      [e.id, item(dinerIds, i * 3 + 1), 'Is the karahi spicy enough for kids? Asking for the table.', at(1, 15, 10 + i), false],
    ]));

  // ── Partner App infrastructure for the Karachi venues ───────────────────
  // The desk owns every venue, so one desk login opens the whole roster in the
  // Partner App: a primary branch with venue-local service windows (Asia/
  // Karachi), a table inventory that totals restaurants.seats, the printed
  // kitchen menu, a live deal and settled payout periods.
  await insertAll('restaurant_staff', ['user_id', 'restaurant_id', 'role', 'status'],
    restIds.map((id) => [opsId, id, 'owner', 'active']));

  await insertAll('restaurant_branches',
    ['id', 'restaurant_id', 'name', 'address', 'area', 'city', 'phone', 'latitude', 'longitude',
      'is_primary', 'accepting_reservations', 'opening_hours', 'timezone'],
    K_RESTAURANTS.map((r, i) => [
      item(branchIds, i), item(restIds, i), `${r.name}: ${r.area}`,
      `${r.name}, ${r.area}, Karachi`, r.area, 'Karachi', `+92213${String(3500001 + i)}`,
      r.lat, r.lng, true, !K_UNVERIFIED_VENUES.has(r.name), weekHours(r), 'Asia/Karachi',
    ]));

  await insertAll('restaurant_tables',
    ['id', 'restaurant_id', 'branch_id', 'label', 'seats', 'zone', 'is_active'],
    tablesByVenue.flatMap((tables, vi) =>
      tables.map((t, ti) => [
        item(item(tableIdsByVenue, vi), ti), item(restIds, vi), item(branchIds, vi),
        t.label, t.seats, t.zone, ti % 13 !== 0,
      ])));

  // Venue menus: the same books the event courses read from, so the QR menu,
  // the menu editor and the dinner listings never disagree about the kitchen.
  const sectionRows: unknown[][] = [];
  const dishRows: unknown[][] = [];
  let sectionSeq = 0;
  K_RESTAURANTS.forEach((r, vi) => {
    venueSections(r).forEach((s, si) => {
      sectionSeq += 1;
      const sectionId = kid('5', sectionSeq);
      sectionRows.push([sectionId, item(restIds, vi), item(branchIds, vi), s.name, si, true]);
      s.items.forEach((d, di) => {
        dishRows.push([
          item(restIds, vi), sectionId, d[0], d[1], d[2], di,
          (vi * 7 + di) % 19 !== 0, [...(d[3] ?? [])], item(K_DISH_PHOTOS, vi + di),
        ]);
      });
    });
  });
  await insertAll('restaurant_menu_sections',
    ['id', 'restaurant_id', 'branch_id', 'name', 'position', 'is_active'], sectionRows);
  await insertAll('restaurant_menu_items',
    ['restaurant_id', 'section_id', 'name', 'description', 'price', 'position', 'is_available',
      'dietary_tags', 'photo_url'], dishRows);

  // One live promotion per verified venue (a third of them paused, so the
  // deals list shows every state), plus two settled earnings periods.
  const dealRows: unknown[][] = [];
  const payoutRows: unknown[][] = [];
  K_RESTAURANTS.forEach((r, i) => {
    if (!K_UNVERIFIED_VENUES.has(r.name)) {
      const slug = r.name.replace(/[^A-Za-z]/g, '').slice(0, 8).toUpperCase();
      const kind = item(['percent', 'fixed', 'package'], i);
      dealRows.push([
        item(restIds, i),
        kind === 'percent' ? `${item([15, 10, 20], i)}% off for DineCircle tables`
          : kind === 'fixed' ? `Rs ${item([500, 750, 1000], i)} off the bill`
            : `${r.event} package price`,
        `Mock ${kind} deal on the ${r.area} test listing. Not an agreed promotion with the venue.`,
        kind, kind === 'percent' ? item([15, 10, 20], i)
          : kind === 'fixed' ? item([500, 750, 1000], i) : int(4, 9) * 1000,
        kind === 'package' ? null : `${slug}${i % 2 === 0 ? 15 : 10}`,
        at(-6, 18), at(30 + i, 23), 200, int(0, 60), i % 7 === 0 ? 'paused' : 'active',
      ]);
    }
    for (const [from, to] of [[-60, -31], [-31, -1]] as const) {
      const gross = int(180, 900) * 1000;
      const commission = Math.round(gross * 0.1);
      payoutRows.push([
        item(restIds, i), at(from, 0, 0), at(to, 0, 0), gross, commission, gross - commission,
        from === -60 ? 'paid' : item(['paid', 'processing'], i),
      ]);
    }
  });
  await insertAll('restaurant_deals',
    ['restaurant_id', 'title', 'description', 'kind', 'value', 'code', 'starts_at', 'ends_at',
      'max_redemptions', 'redemptions', 'status'], dealRows);
  await insertAll('restaurant_payouts',
    ['restaurant_id', 'period_start', 'period_end', 'gross', 'commission', 'net', 'status'],
    payoutRows);

  // A couple of covers per venue so the reservation queue, the floor plan and
  // the today view all open with something to look at. Times are server-clock
  // offsets; `start_at` is stored as the venue's own service hour.
  const reservationRows: unknown[][] = [];
  let resSeq = 0;
  K_RESTAURANTS.forEach((r, vi) => {
    if (K_UNVERIFIED_VENUES.has(r.name) || vi > 11) return;
    for (let s = 0; s < 2; s += 1) {
      resSeq += 1;
      const status = item(K_RESERVATION_STATUSES, vi + s);
      const table = item(item(tablesByVenue, vi), s);
      const past = status === 'completed' || status === 'cancelled' || status === 'no_show';
      reservationRows.push([
        item(restIds, vi), item(branchIds, vi), item(item(tableIdsByVenue, vi), s),
        item(dinerIds, resSeq * 5), `${item(K_FIRST, resSeq)} ${item(K_LAST, resSeq)}`,
        `+9233${String(1000000 + resSeq)}`, Math.max(2, Math.min(table.seats, int(2, 6))),
        at(past ? -3 - s : s, status === 'seated' ? 20 : 21), 90, status,
        `TR-K${String(1001 + resSeq)}`, 'Mock reservation on the Karachi test listing.', 'customer',
      ]);
    }
  });
  await insertAll('table_reservations',
    ['restaurant_id', 'branch_id', 'table_id', 'user_id', 'guest_name', 'guest_phone',
      'party_size', 'start_at', 'duration_minutes', 'status', 'reference', 'notes', 'source'],
    reservationRows);

  // Verification bookkeeping: the candidate venues sit in the admin queue as
  // pending submissions, and one approved row shows what a decided one looks
  // like (reviewed by the seeded platform admin).
  const candidateRequests = K_RESTAURANTS
    .map((r, i) => ({ unverified: K_UNVERIFIED_VENUES.has(r.name), id: item(restIds, i) }))
    .filter((v) => v.unverified)
    .map((v) => [v.id, opsId, 'pending',
      'Desk enquiry: the venue has been contacted; nothing is agreed yet.', '', null, null]);
  await insertAll('partner_verification_requests',
    ['restaurant_id', 'requested_by', 'status', 'note', 'reviewer_note', 'reviewed_by', 'reviewed_at'],
    [
      [item(restIds, 0), opsId, 'approved',
        'Listing basics checked against public information (test submission).',
        'Approved as a demo partner by the seed script.', U.admin, at(-40, 12)],
      ...candidateRequests,
    ]);

  // ── legacy partner surface: special menus, notifications, collab invites ──
  await insertAll('special_menus',
    ['restaurant_id', 'name', 'description', 'price_per_guest', 'min_guests', 'tags',
      'cover_image', 'status', 'views_this_week', 'bookings_count'],
    K_RESTAURANTS.map((r, i) => [
      item(restIds, i), `${r.event} Set Menu`,
      `Mock ${item(r.cuisines, 0)} package for the ${r.area} test listing: three shared plates and chai, priced in PKR.`,
      int(6, 30) * 500, i % 3 === 0 ? 4 : 2, [item(r.tags, 0), 'demo'], r.cover,
      i % 8 === 0 ? 'paused' : 'active', int(20, 180), int(1, 24),
    ]));
  await insertAll('notifications',
    ['restaurant_id', 'title', 'body', 'category', 'read', 'icon', 'tint', 'notification_time'], [
      [item(restIds, 0), 'New demo booking', '2 seats on Seaside BBQ Dinner (mock PKR payment).', 'booking', false, 'calendar', 'C26B4E', at(-1, 9, 30)],
      [item(restIds, 3), 'Grill night filling up', 'Charcoal seats for the Boat Basin test listing are 60% booked.', 'booking', false, 'flame', 'C26B4E', at(-1, 18)],
      [item(restIds, 7), 'Candidate partnership', 'This listing is flagged unverified. Awaiting venue contact.', 'partner', false, 'handshake', '4A7A5A', at(-2, 10)],
      [item(restIds, 8), 'Family festival preview', 'Test event views are climbing for the SMCHS food festival.', 'general', true, 'eye', '4A5A7A', at(-3, 18)],
      [item(restIds, 10), 'Menu published', 'Karahi and tikka lines are live on the public QR menu.', 'menu', false, 'book-open', '8A5A2B', at(-2, 15)],
      [item(restIds, 12), 'Nihari breakfast table', 'Four covers confirmed for the Akbar Chowk edition.', 'reservation', false, 'utensils', 'C26B4E', at(-1, 8)],
      [item(restIds, 14), 'Payout settled', 'A PKR period payout was marked paid in the earnings ledger.', 'payout', true, 'wallet', '4A7A5A', at(-5, 11)],
      [item(restIds, 15), 'DineCircle+ desk', 'Test listing gained the Plus badge in the seeded world.', 'partner', true, 'sparkles', '7A4A6B', at(-6, 12)],
      [item(restIds, 17), 'Dim sum night', 'Two tables hold for the Chinese classics test edition.', 'reservation', false, 'clock', '4A5A7A', at(-1, 19)],
      [item(restIds, 18), 'Seafront deck held', 'Majlis seats reserved for a DineCircle table (mock).', 'reservation', false, 'waves', '4A7A5A', at(-2, 20)],
    ]);
  await insertAll('collaboration_invites',
    ['id', 'host_id', 'restaurant_id', 'title', 'message', 'status', 'created_at'], [
      [kid('9', 1), item(hostIds, 0), item(restIds, 0), 'Seaside BBQ: candidate collab',
        'Mock invite: we would love to test a Seaside BBQ Dinner with you once the venue confirms. Nothing is signed yet.', 'invited', at(-4, 10)],
      [kid('9', 2), item(hostIds, 6), item(restIds, 4), "Chef's Table pilot night",
        'Mock invite for a counter-side tasting pilot. Pending venue verification. Treat as a test record.', 'accepted', at(-9, 12)],
      [kid('9', 3), item(hostIds, 9), item(restIds, 7), 'Desi meetup co-host',
        'Mock invite to co-host the Tipu Sultan Desi Food Meetup test event.', 'invited', at(-2, 16)],
      [kid('9', 4), item(hostIds, 11), item(restIds, 10), 'Charcoal night co-host',
        'Mock invite: co-host a kebab and karahi long table in Gulshan-e-Iqbal. Test record, nothing agreed.', 'invited', at(-3, 17)],
      [kid('9', 5), item(hostIds, 13), item(restIds, 12), 'Nihari breakfast table',
        'Mock invite for a morning nihari session at Akbar Chowk, seeded for the host-inbox flow.', 'accepted', at(-11, 8)],
      [kid('9', 6), item(hostIds, 15), item(restIds, 16), 'Biryani trail tasting',
        'Mock invite to run a biryani trail tasting with the Mitha test listing. Declined in the seed to keep the queue honest.', 'declined', at(-16, 14)],
    ]);

  // The city picker reads supported_cities; Karachi carries the real area list
  // the seeded accounts live in.
  await pool.query(
    'UPDATE supported_cities SET areas = $2::text[] WHERE name = $1',
    ['Karachi', [...K_AREAS]],
  );

  // Everything in this seeded world is a test record.
  await q('UPDATE users SET is_demo = true');
  await q('UPDATE restaurants SET is_demo = true');
  await q('UPDATE dinner_events SET is_demo = true');
}

async function main(): Promise<void> {
  // The seed script ships a known partner-admin credential
  // (`+923450000001` / `dinecircle123`) and deterministic demo data. Running
  // it against a production database would therefore create accounts whose
  // password is public. Refuse unless the operator explicitly overrides.
  if (process.env.NODE_ENV === 'production' && !process.env.ALLOW_SEED_IN_PRODUCTION) {
    throw new Error(
      'Refusing to seed in production. Set ALLOW_SEED_IN_PRODUCTION=1 to override.',
    );
  }

  await q(`TRUNCATE users, restaurants, dinner_events, menu_items, bookings,
             payouts, withdrawals, collaboration_invites, reviews, follows,
             venue_follows,
             saved_events, activity, chat_messages,
             special_menus, notifications, otp_codes, promo_codes, auth_tokens,
             audit_log, supported_cities, saved_locations,
             restaurant_branches, restaurant_menu_sections, restaurant_menu_items,
             restaurant_tables, table_reservations, partner_verification_requests,
             restaurant_deals, restaurant_payouts, restaurant_staff, user_avatars
           RESTART IDENTITY CASCADE`);

  // ── Users (one per role) ──────────────────────────────────────────────────
  await q(`INSERT INTO users
      (id, name, handle, phone, city, bio, role, followers_count, following_count,
       dinners_hosted, dinners_joined, rating, review_count, avatar_url, badges,
       tastes, accent_hex, joined_year)
    VALUES
      ('${U.alex}','Alex Morgan','alex.morgan','+15550001111','Lyon',
       'Weekend foodie chasing long tables.','user',12,40,0,6,4.60,3,'assets/images/portrait_1.png','{}',
       ARRAY['Japanese','pasta','natural wine'],'#4A5A7A',2024),
      ('${U.nora}','Nora Feld','nora.hosts','+15550002222','Lyon',
       'Host and chef. Six-seat suppers, seasonal menus.','host',820,34,42,3,4.90,118,'assets/images/portrait_2.png','{Top Host}',
       ARRAY['Tasting','wine'],'#C26B4E',2022),
      ('${U.ava}','Ava Chen','ava.eats','+15550003333','Lyon',
       'Diner, photographer, dessert-first.','user',156,210,0,11,4.80,9,'assets/images/portrait_3.png','{}',
       ARRAY['dessert','brunch'],'#7A4A6B',2023),
      ('${U.marco}','Marco Rossi','marco.rooftop','+15550004444','Lyon',
       'Partner manager for the Rooftop and Trattoria groups.','partner_admin',5,5,0,0,0,0,'assets/images/portrait_5.png','{}','{}','#4A7A5A',2023),
      ('${U.admin}','Dana Ops','dana.admin',NULL,'Lyon',
       'Platform moderator.','super_admin',0,0,0,0,0,0,'assets/images/portrait_6.png','{}','{}','#333333',2021)`);

  // ── Restaurants (owned by the partner admin) ──────────────────────────────
  await q(`INSERT INTO restaurants
      (id, owner_id, name, tagline, about, cuisines, neighborhood, address, city,
       phone, email, website, instagram, price_range, rating, review_count, seats,
       tables_count, since, owner_name, amenities, opening_hours,
       profile_completion, accepting_bookings, dine_circle_plus, cover_image,
       gallery, tags, is_partner, partner_perk, latitude, longitude)
    VALUES
      ('${R.rooftop}','${U.marco}','Skyline Rooftop','Golden-hour dining above the city',
       'A plant-forward rooftop with panoramic views.',ARRAY['Mediterranean','Natural wine'],
       '5th Arr.','12 Quai Saint-Antoine','Lyon','+15552220001','hello@skyline.example',
       'skyline.example','@skylinerooftop','$$$',4.70,214,60,18,'2019','Marco Rossi',
       ARRAY['Terrace','Bar','Wheelchair access'],'{"Mon-Sun":"17:00-24:00"}'::jsonb,
       90,true,true,'assets/images/venue_rooftop.png',
       ARRAY['assets/images/venue_bar.png','assets/images/venue_interior.png'],ARRAY['rooftop','views','dating'],
       true,'Free welcome drink for DineCircle guests',45.7640,4.8350),
      ('${R.trattoria}','${U.marco}','Trattoria Nord','Hand-rolled pasta, low candles',
       'A family-run trattoria hidden off the market square.',ARRAY['Italian','Pasta'],
       '2nd Arr.','4 Place des Cordeliers','Lyon','+15552220002','ciao@trattoria.example',
       'trattoria.example','@trattorianord','$$',4.55,96,40,14,'2015','Marco Rossi',
       ARRAY['Indoor','Outdoor seating'],'{"Tue-Sun":"12:00-22:00"}'::jsonb,
       80,true,false,'assets/images/venue_interior.png',
       ARRAY['assets/images/venue_bar.png'],ARRAY['italian','pasta','cozy'],true,NULL,45.7620,4.8320)`);

  // ── dinner_events (3 upcoming, 1 past) ───────────────────────────────────
  await q(`INSERT INTO dinner_events
      (id, title, tagline, description, host_id, restaurant_id, cover_image, gallery,
       start_at, end_at, duration_minutes, seats_total, seats_booked, price_per_seat,
       type, audience, menu_style, included, tags, is_featured, host_note,
       attendee_ids, status, views, requires_approval)
    VALUES
      ('${E.e1}','Omakase Under the Stars','A seven-course chef counter at dusk',
       'A long-table tasting built around whatever the market gave us this morning. Wine pairing optional.',
       '${U.nora}','${R.rooftop}','assets/images/dish_sushi.png',
       ARRAY['assets/images/dish_sushi.png','assets/images/hero_tasting.png'],'${at(3, 19, 0)}','${at(3, 22, 0)}',
       180,12,3,95.00,'tasting','public','tastingMenu',ARRAY['7 courses','welcome drink'],
       ARRAY['pasta','seasonal','date-night'],true,'Meet at the rooftop door; lifts until 23:00.',
       ARRAY['${U.alex}','${U.ava}'],'confirmed',2840,false),
      ('${E.e2}','Sunday Slow Brunch','Lazy plates, bottomless coffee',
       'A family-style brunch with fresh-baked bread and a long coffee tail.',
       '${U.nora}','${R.trattoria}','assets/images/dish_brunch.png','{}',
       '${at(9, 11, 0)}','${at(9, 13, 0)}',120,16,5,38.00,'brunch','public','familyStyle',
       ARRAY['Bottomless coffee','pastries'],ARRAY['pasta','seasonal','date-night'],false,
       'Kid-friendly.',ARRAY['${U.alex}','${U.ava}'],'confirmed',1930,false),
      ('${E.e4}','Tasting Menu Tryout','Seats held until the host approves',
       'A small preview supper where every seat needs a nod from Nora before it is confirmed.',
       '${U.nora}','${R.rooftop}','assets/images/hero_tasting.png','{}',
       '${at(6, 18, 0)}','${at(6, 20, 30)}',150,10,1,45.00,'tasting','public','setMenu',
       ARRAY['5 courses'],ARRAY['tasting','seasonal'],false,
       'I approve each seat personally. Ping me if unsure.',
       ARRAY['${U.ava}'],'confirmed',1120,true),
      ('${E.e3}','Cellar Supper','Candles and old vintages',
       'A completed supper club in the wine cellar.',
       '${U.nora}','${R.rooftop}','assets/images/hero_tasting.png','{}',
       '${at(-10, 20, 0)}','${at(-10, 22, 30)}',150,10,10,72.00,'supperClub','public','setMenu',
       ARRAY['5 courses','flight'],ARRAY['pasta','seasonal','date-night'],false,
       'Thank you all.',ARRAY['${U.alex}','${U.ava}'],'completed',2410,false)`);

  // ── menu_items ────────────────────────────────────────────────────────────
  await q(`INSERT INTO menu_items (event_id, position, name, description, pairing, signature)
    VALUES
      ('${E.e1}',0,'Chilled dashi','Spring vegetables, yuzu',NULL,false),
      ('${E.e1}',1,'Tuna and bottarga','House soy','Junmai daiginjo',true),
      ('${E.e1}',2,'Aged rice, butter','Cured yolk','Junmai',false),
      ('${E.e2}',0,'Focaccia','Rosemary, olive oil',NULL,false),
      ('${E.e2}',1,'Carbonara','Guanciale, pecorino','Albana',true),
      ('${E.e3}',0,'Beef tartare','Capers, egg yolk','Beaujolais',false),
      ('${E.e3}',1,'Ravioli du jour','Brown butter, sage','Cote du Rhone',true)`);

  // ── bookings (Alex holds e1/e2; e3 completed → enables review; Ava awaits
  //    approval on the host-gated e4) ────────────────────────────────────────
  await q(`INSERT INTO bookings
      (event_id, user_id, seats, price_per_seat, total_amount, reference,
       payment_label, payment_status, status, checked_in)
    VALUES
      ('${E.e1}','${U.alex}',2,95.00,190.00,'DC-7K3MQ','Visa 4242','paid','confirmed',false),
      ('${E.e2}','${U.alex}',1,38.00,38.00,'DC-2P9XW','Visa 4242','paid','confirmed',false),
      ('${E.e3}','${U.alex}',2,72.00,144.00,'DC-9LZ4R','Visa 4242','paid','completed',true),
      ('${E.e4}','${U.ava}',1,45.00,45.00,'DC-4TRNB','Visa 4242','pending_payment','pending',false)`);

  // ── payouts ───────────────────────────────────────────────────────────────
  await q(`INSERT INTO payouts (event_id, payout_date, seats_sold, gross, commission, status)
    VALUES
      ('${E.e3}','${at(-8, 10, 0)}',10,720.00,72.00,'paid'),
      ('${E.e1}','${at(2, 10, 0)}',3,285.00,28.50,'scheduled')`);

  // ── withdrawals (simulated host wallet ledger) ───────────────────────────
  await q(`INSERT INTO withdrawals (id, host_id, amount, method, status, created_at)
    VALUES
      ('32323232-3232-3232-3232-323232323231','${U.nora}',400.00,'Bank •••• 7890','completed','${at(-20, 9, 0)}'),
      ('32323232-3232-3232-3232-323232323232','${U.nora}',250.00,'PayPal','processing','${at(-2, 9, 0)}')`);

  // ── collaboration invites (restaurant → host) ────────────────────────────
  await q(`INSERT INTO collaboration_invites (id, host_id, restaurant_id, title, message, status, created_at)
    VALUES
      ('31313131-3131-3131-3131-313131313131','${U.nora}','${R.rooftop}','Rooftop Sunset Series',
       'The sunset series is confirmed for monthly editions. Your September edition sold out in 48 hours. The October slot is yours whenever you are ready.','accepted','${at(-9, 10, 0)}'),
      ('31313131-3131-3131-3131-313131313132','${U.nora}','${R.rooftop}','Omakase Collaboration Night',
       'Our head chef loved your last tasting night. We would like to co-host a 4-night omakase series this season: chef\u2019s counter, full creative control on the menu.','invited','${at(-1, 8, 0)}'),
      ('31313131-3131-3131-3131-313131313133','${U.nora}','${R.trattoria}','Brand-Sponsored Pasta Evening',
       'A wine brand partner wants to sponsor a steak & pasta tasting evening hosted by you. We cover the venue, product and a guaranteed honorarium. 20 seats, invite-only.','invited','${at(-3, 15, 0)}')`);

  // ── review (Alex reviewed the completed supper) ───────────────────────────
  await q(`INSERT INTO reviews (author_id, event_id, rating, text, created_at)
    VALUES ('${U.alex}','${E.e3}',5.00,'Nora is a magician: best table I have sat at all year.','${at(-7, 15, 0)}')`);

  // ── follows / saved / activity / chat ─────────────────────────────────────
  await q(`INSERT INTO follows (follower_id, followee_id) VALUES ('${U.alex}','${U.nora}')`);
  await q(`INSERT INTO saved_events (user_id, event_id) VALUES ('${U.alex}','${E.e1}')`);
  await q(`INSERT INTO promo_codes (code, discount_pct, active) VALUES
      ('FOODIE5', 5, true), ('WELCOME10', 10, true),
      ('DINE20', 20, true), ('VIP15', 15, true), ('EXPIRED0', 50, false)`);
  await q(`INSERT INTO activity (actor_id, kind, title, body, event_id, amount, is_unread)
    VALUES
      ('${U.nora}','newGuest','A new guest joined your event','The Omakase sold 2 more seats.','${E.e1}',190.00,true),
      ('${U.alex}','follower','Ava started following you','You now have 13 followers.',NULL,NULL,true)`);
  await q(`INSERT INTO chat_messages (event_id, author_id, text, sent_at, is_system)
    VALUES
      ('${E.e1}',NULL,'Welcome to the event chat. Introduce yourself!','${at(3, 12, 0)}',true),
      ('${E.e1}','${U.alex}','Excited for this, first omakase!','${at(3, 12, 30)}',false)`);

  // ── partner tables ────────────────────────────────────────────────────────
  await q(`INSERT INTO special_menus
      (restaurant_id, name, description, price_per_guest, min_guests, tags,
       cover_image, status, views_this_week, bookings_count)
    VALUES
      ('${R.rooftop}','Chefs Tasting','Seven courses with optional pairing',110.00,2,
       ARRAY['tasting','wine'],'assets/images/dish_sushi.png','active',142,28),
      ('${R.trattoria}','Pasta Lab','Make-and-eat for groups',65.00,4,
       ARRAY['workshop','italian'],'assets/images/dish_pasta.png','active',77,11)`);
  await q(`INSERT INTO notifications
      (restaurant_id, title, body, category, read, icon, tint, notification_time)
    VALUES
      ('${R.rooftop}','New booking','2 seats booked for Omakase Under the Stars','booking',false,'calendar','C26B4E','${at(-1, 9, 30)}'),
      ('${R.rooftop}','Payout scheduled','A 720 EUR payout for Cellar Supper is processing','payout',true,'wallet','4A7A5A','${at(-1, 9, 0)}')`);

  // ── Partner App fixtures ────────────────────────────────────────────────
  // Two venues with opposite policies so both partner flows are exercisable
  // out of the box: Skyline is verified (deals + host publishing allowed) and
  // auto-confirms host events; Trattoria is still unverified and asks the venue
  // to approve each host event, which lands it in the Partner App queue.
  await q(`UPDATE restaurants
     SET partnership_status = 'verified', verified_at = now(),
         requires_host_approval = false
   WHERE id = '${R.rooftop}'`);
  await q(`UPDATE restaurants
     SET partnership_status = 'unverified', is_partner = true,
         requires_host_approval = true
   WHERE id = '${R.trattoria}'`);

  // Owner memberships mirror `owner_id`, so the shared membership model in
  // src/access.ts resolves both seeded venues without a special case.
  await q(`INSERT INTO restaurant_staff (user_id, restaurant_id, role, status)
    VALUES ('${U.marco}','${R.rooftop}','owner','active'),
           ('${U.marco}','${R.trattoria}','owner','active')`);

  const rooftopBranch = kid('0', 1);
  const trattoriaBranch = kid('0', 2);
  await q(`INSERT INTO restaurant_branches
      (id, restaurant_id, name, address, area, city, phone, latitude, longitude,
       is_primary, accepting_reservations, opening_hours, timezone)
    VALUES
      ('${rooftopBranch}','${R.rooftop}','Skyline Rooftop','12 Quai Saint-Antoine',
       '5th Arr.','Lyon','+15552220001',45.7640,4.8350,true,true,
       '{"mon":{"windows":[{"open":"18:00","close":"23:00"}]},
         "tue":{"windows":[{"open":"18:00","close":"23:00"}]},
         "wed":{"windows":[{"open":"18:00","close":"23:00"}]},
         "thu":{"windows":[{"open":"18:00","close":"23:00"}]},
         "fri":{"windows":[{"open":"17:00","close":"23:30"}]},
         "sat":{"windows":[{"open":"12:00","close":"23:30"}]},
         "sun":{"windows":[{"open":"12:00","close":"22:00"}]}}'::jsonb,
       'Europe/Paris'),
      ('${trattoriaBranch}','${R.trattoria}','Trattoria Nord','4 Place des Cordeliers',
       '2nd Arr.','Lyon','+15552220002',45.7620,4.8320,true,true,
       '{"tue":{"windows":[{"open":"12:00","close":"22:00"}]},
         "wed":{"windows":[{"open":"12:00","close":"22:00"}]},
         "thu":{"windows":[{"open":"12:00","close":"22:00"}]},
         "fri":{"windows":[{"open":"12:00","close":"22:00"}]},
         "sat":{"windows":[{"open":"12:00","close":"22:00"}]},
         "sun":{"windows":[{"open":"12:00","close":"21:00"}]},
         "mon":{"closed":true}}'::jsonb,
       'Europe/Paris')`);

  // Table inventory totalling the published seat count (60 covers / 8 tables),
  // so capacity checks and the venue's stated capacity agree from day one.
  const tableSeats = [8, 8, 8, 8, 8, 8, 6, 6];
  await q(`INSERT INTO restaurant_tables
      (id, restaurant_id, branch_id, label, seats, zone, is_active)
    VALUES ${tableSeats.map((seats, i) => `('${kid('1', i + 1)}','${R.rooftop}',
      '${rooftopBranch}','T-${String(i + 1).padStart(2, '0')}',${seats},
      '${i < 4 ? 'Terrace' : 'Main'}',true)`).join(',')}`);
  await q(`INSERT INTO restaurant_tables
      (id, restaurant_id, branch_id, label, seats, zone, is_active)
    VALUES ('${kid('1', 21)}','${R.trattoria}','${trattoriaBranch}','T-01',6,'Main',true),
           ('${kid('1', 22)}','${R.trattoria}','${trattoriaBranch}','T-02',4,'Main',true)`);

  const starters = kid('2', 1);
  const mains = kid('2', 2);
  await q(`INSERT INTO restaurant_menu_sections
      (id, restaurant_id, branch_id, name, position, is_active)
    VALUES ('${starters}','${R.rooftop}','${rooftopBranch}','Starters',0,true),
           ('${mains}','${R.rooftop}','${rooftopBranch}','Mains',1,true)`);
  await q(`INSERT INTO restaurant_menu_items
      (restaurant_id, section_id, name, description, price, position,
       is_available, dietary_tags, photo_url)
    VALUES
      ('${R.rooftop}','${starters}','Burrata & heirloom tomato',
       'Basil oil, sourdough crumb',14.00,0,true,ARRAY['vegetarian'],
       'assets/images/dish_brunch.png'),
      ('${R.rooftop}','${starters}','Charred octopus',
       'Smoked paprika, salsa verde',19.00,1,true,ARRAY['gluten-free'],
       'assets/images/dish_tacos.png'),
      ('${R.rooftop}','${mains}','Dry-aged ribeye',
       'Bone marrow butter, confit garlic',42.00,0,true,ARRAY[]::text[],
       'assets/images/dish_steak.png'),
      ('${R.rooftop}','${mains}','Wild mushroom risotto',
       'Aged parmesan, truffle oil',26.00,1,true,ARRAY['vegetarian'],
       'assets/images/dish_pasta.png')`);

  // One live promotion and one settled payout period, so the Partner App's
  // deals and earnings screens have data without any manual setup.
  await q(`INSERT INTO restaurant_deals
      (id, restaurant_id, title, description, kind, value, code, starts_at,
       ends_at, max_redemptions, redemptions, status)
    VALUES ('${kid('3', 1)}','${R.rooftop}','Sunset hour -20%',
      'Twenty percent off all starters between 18:00 and 19:00.',
      'percent',20.00,'SUNSET20','${at(-1, 18, 0)}','${at(30, 23, 0)}',200,12,'active')`);
  await q(`INSERT INTO restaurant_payouts
      (restaurant_id, period_start, period_end, gross, commission, net, status)
    VALUES ('${R.rooftop}','${at(-31, 0, 0)}','${at(-1, 0, 0)}',
      1980.00,198.00,1782.00,'paid')`);

  // ── Supported cities (location picker data) ─────────────────────────────
  await q(`INSERT INTO supported_cities (name, country, areas, lat, lng)
    VALUES
      ('Karachi','Pakistan',ARRAY['DHA','Clifton','Gulshan-e-Iqbal','North Nazimabad','PECHS','Gulistan-e-Johar','Bahadurabad','Tariq Road'],24.8607,67.0011),
      ('Lahore','Pakistan',ARRAY['DHA','Gulberg','Model Town','Johar Town','Cantt','Bahria Town'],31.5204,74.3587),
      ('Islamabad','Pakistan',ARRAY['F-6','F-7','F-8','F-10','F-11','G-9','G-10','G-11'],33.6844,73.0479),
      ('Rawalpindi','Pakistan',ARRAY['Satellite Town','Bahria Town'],33.5651,73.0169),
      ('Faisalabad','Pakistan',ARRAY['D-Ground','Peoples Colony'],31.4504,73.1350),
      ('Multan','Pakistan',ARRAY['Cantt','Gulgasht'],30.1575,71.5249),
      ('Peshawar','Pakistan',ARRAY['Hayatabad','University Town'],34.0151,71.5249),
      ('Hyderabad','Pakistan',ARRAY['Latifabad','Qasimabad'],25.3960,68.3578)`);

  await seedKarachi();

  const counts = await pool.query(`
    SELECT (SELECT count(*) FROM users)         AS users,
           (SELECT count(*) FROM restaurants)   AS restaurants,
           (SELECT count(*) FROM dinner_events) AS events,
           (SELECT count(*) FROM menu_items)    AS menu_items,
           (SELECT count(*) FROM bookings)      AS bookings,
           (SELECT count(*) FROM reviews)       AS reviews,
           (SELECT count(*) FROM payouts)       AS payouts,
           (SELECT count(*) FROM withdrawals)   AS withdrawals,
           (SELECT count(*) FROM collaboration_invites) AS invites,
           (SELECT count(*) FROM restaurant_branches)   AS branches,
           (SELECT count(*) FROM restaurant_tables)     AS venue_tables,
           (SELECT count(*) FROM restaurant_menu_items) AS venue_dishes,
           (SELECT count(*) FROM table_reservations)    AS reservations,
           (SELECT count(*) FROM restaurants WHERE partnership_status = 'unverified') AS unverified_venues,
           (SELECT count(*) FROM dinner_events WHERE is_demo) AS demo_events`);
  console.log('Seeded:', counts.rows[0]);
}

main()
  .catch((error) => {
    console.error('Seed failed:', error);
    process.exitCode = 1;
  })
  .finally(() => pool.end());
