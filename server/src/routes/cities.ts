import { Router } from 'express';
import { query } from '../db.js';

const router = Router();

type CityRow = {
  id: string;
  name: string;
  country: string;
  areas: string[];
  lat: string | number | null;
  lng: string | number | null;
  active: boolean;
};

/**
 * GET /api/cities, all DineCircle-supported cities with their areas.
 *
 * The Flutter location picker loads this on open; a network failure falls back
 * to a hard-coded list, so the endpoint must never throw for missing data.
 */
router.get('/', async (_req, res) => {
  const rows = await query<CityRow>(
    'SELECT id, name, country, areas, lat, lng, active FROM supported_cities WHERE active ORDER BY name',
  );

  // When the table is empty (fresh install, seed not yet run) return a
  // built-in set so the app always has something to show.
  if (rows.length === 0) {
    res.json({ cities: fallbackCities });
    return;
  }

  res.json({
    cities: rows.map((r) => ({
      name: r.name,
      country: r.country,
      areas: r.areas,
      latitude: r.lat === null ? null : Number(r.lat),
      longitude: r.lng === null ? null : Number(r.lng),
    })),
  });
});

const fallbackCities = [
  { name: 'Karachi', country: 'Pakistan', areas: ['DHA', 'Clifton', 'Gulshan-e-Iqbal', 'North Nazimabad', 'PECHS', 'Gulistan-e-Johar', 'Bahadurabad', 'Tariq Road'], latitude: 24.8607, longitude: 67.0011 },
  { name: 'Lahore', country: 'Pakistan', areas: ['DHA', 'Gulberg', 'Model Town', 'Johar Town', 'Cantt', 'Bahria Town'], latitude: 31.5204, longitude: 74.3587 },
  { name: 'Islamabad', country: 'Pakistan', areas: ['F-6', 'F-7', 'F-8', 'F-10', 'F-11', 'G-9', 'G-10', 'G-11'], latitude: 33.6844, longitude: 73.0479 },
  { name: 'Rawalpindi', country: 'Pakistan', areas: ['Satellite Town', 'Bahria Town'], latitude: 33.5651, longitude: 73.0169 },
  { name: 'Faisalabad', country: 'Pakistan', areas: ['D-Ground', 'Peoples Colony'], latitude: 31.4504, longitude: 73.1350 },
  { name: 'Multan', country: 'Pakistan', areas: ['Cantt', 'Gulgasht'], latitude: 30.1575, longitude: 71.5249 },
  { name: 'Peshawar', country: 'Pakistan', areas: ['Hayatabad', 'University Town'], latitude: 34.0151, longitude: 71.5249 },
  { name: 'Hyderabad', country: 'Pakistan', areas: ['Latifabad', 'Qasimabad'], latitude: 25.3960, longitude: 68.3578 },
];

export default router;
