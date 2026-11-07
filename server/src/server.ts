import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { ZodError } from 'zod';
import type { NextFunction, Request, Response } from 'express';
import { pool } from './db.js';
import { ApiError, requireAuth } from './context.js';
import { apiRateLimiter, authRateLimiter, auditLog, trustProxySetting } from './security.js';
import authRouter from './routes/auth.js';
import bookingsRouter from './routes/bookings.js';
import eventsRouter from './routes/events.js';
import feedbackRouter from './routes/feedback.js';
import hostsRouter from './routes/hosts.js';
import offersRouter from './routes/offers.js';
import partnerRouter from './routes/partner.js';
import partnerMenuRouter from './routes/partner_menu.js';
import partnerOpsRouter from './routes/partner_ops.js';
import partnerImagesRouter from './routes/partner_images.js';
import partnerTablesRouter from './routes/partner_tables.js';
import partnerVenuesRouter, {
  verificationRouter as partnerVerificationRouter,
  adminRouter as partnerAdminRouter,
} from './routes/partner_venues.js';
import tableReservationsRouter from './routes/reservations.js';
import restaurantReviewsRouter from './routes/restaurant_reviews.js';
import restaurantsRouter from './routes/restaurants.js';
import reviewsRouter from './routes/reviews.js';
import reportsRouter from './routes/reports.js';
import searchRouter from './routes/search.js';
import socialRouter from './routes/social.js';
import citiesRouter from './routes/cities.js';
import publicMenuRouter from './routes/public_menu.js';
import dealsRouter, { venueDealsRouter } from './routes/deals.js';
import savedLocationsRouter from './routes/saved_locations.js';
import usersRouter from './routes/users.js';
import publicAvatarsRouter from './routes/public_avatars.js';
import publicVenueImagesRouter from './routes/public_venue_images.js';
import { requireActiveSubscription } from './access.js';


const app = express();
app.disable('x-powered-by');

// Trust forwarded client IPs only when an operator configures the proxy.
// An unrestricted default lets forged IPs bypass authentication rate limits.
app.set('trust proxy', trustProxySetting(process.env.TRUST_PROXY));

/**
 * Minimal request logger: `METHOD path → status durationMs`.
 * No external dependency; keeps ops output tidy and greppable.
 */
function requestLog(req: Request, res: Response, next: NextFunction): void {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const ms = Number(process.hrtime.bigint() - start) / 1e6;
    console.log(`${req.method} ${req.originalUrl} → ${res.statusCode} ${ms.toFixed(1)}ms`);
  });
  next();
}

/**
 * Block startup until Postgres answers, retrying so the API survives a
 * database container that boots a few seconds later (docker-compose ordering).
 */
async function waitForDatabase(retries = 15, delayMs = 1500): Promise<void> {
  for (let attempt = 1; attempt <= retries; attempt += 1) {
    try {
      await pool.query('SELECT 1');
      console.log('Database connection ready');
      return;
    } catch {
      if (attempt === retries) throw new Error('Database never became ready');
      console.log(`Database not ready (attempt ${attempt}/${retries}). Retrying in ${delayMs}ms`);
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
}

// ── Security headers & CORS ─────────────────────────────────────────────────

// Single source of truth for allowed origins.
// Hosted deployments extend this list without a rebuild:
//   CORS_ALLOWED_ORIGINS=https://dinecircle.app,https://www.dinecircle.app
// Mobile clients send no Origin header, so the app itself never depends on it.
const ALLOWED_ORIGINS = new Set([
  'http://localhost:3000',
  'http://localhost:4000',
  'http://localhost:8080',
  'http://127.0.0.1:8080',
  'http://10.0.2.2:3000',
  'http://10.0.2.2:4000',
  'http://192.168.100.70:4000',
  'http://192.168.100.46:4000',
  ...(process.env.CORS_ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean),
]);

function isAllowedOrigin(origin: string): boolean {
  if (ALLOWED_ORIGINS.has(origin)) return true;
  // In development / test, accept any origin so the Flutter hot-reload
  // port and ad-hoc LAN IPs keep working without a manifest update.
  if (process.env.NODE_ENV !== 'production') return true;
  return false;
}

app.use(helmet());
app.use(cors({
  origin: (origin, callback) => {
    // Requests with no Origin header (same-origin, curl, server-to-server)
    // are always allowed, the check below is for cross-origin browser traffic.
    if (!origin) return callback(null, true);
    if (isAllowedOrigin(origin)) return callback(null, true);
    callback(new Error('CORS: origin not allowed'));
  },
}));

// Phase 2a: Stripe webhook route deleted.

app.use(express.json({ limit: '1mb' }));
app.use(requestLog);

// ── Rate limiting ───────────────────────────────────────────────────────────
app.use('/api/', apiRateLimiter);

// ── REST API routes ─────────────────────────────────────────────────────────

// Public: sign-in flow and liveness (with strict rate limiting for auth).
app.use('/api/auth', authRateLimiter, authRouter);

// Public: supported cities for the location picker (no auth required).
app.use('/api/cities', citiesRouter);

// Public: diner-facing venue menu. Mounted before requireAuth so a QR scan
// from a passer-by can read the menu without signing in.
app.use('/api/public/menu', publicMenuRouter);

// Public: diner-facing deals feed. Mounted before requireAuth so discovery
// works without authentication. Only the venue-scoped router may sit on
// /api/restaurants, the feed router's `GET /` would shadow the venue list.
app.use('/api/deals', dealsRouter);
app.use('/api/restaurants', venueDealsRouter);
app.use('/api/restaurants', restaurantReviewsRouter);

// Public: uploaded profile photos. `Image.network` cannot reliably attach a
// bearer token, and avatars are public on every social surface anyway.
app.use('/api/public/avatars', publicAvatarsRouter);

// Public: uploaded venue photos (logo, gallery, dish, deal banner). Same reason
// as avatars, every render site is an `Image.network` with no bearer token.
app.use('/api/public/venue-images', publicVenueImagesRouter);

app.get('/api/health', async (_req: Request, res: Response) => {
  const started = Date.now();
  await pool.query('SELECT 1');
  res.json({
    status: 'ok',
    database: 'unified dinecircle',
    latencyMs: Date.now() - started,
    time: new Date().toISOString(),
  });
});

// Everything below requires a Bearer token.
app.use(requireAuth);

// Audit logging for all authenticated mutating requests.
app.use(auditLog);

// Mobile app routes
app.use('/api/search', searchRouter);
app.use('/api/events', eventsRouter);
app.use('/api/restaurants', restaurantsRouter);
app.use('/api/users', usersRouter);
app.use('/api/hosts', hostsRouter);
app.use('/api/offers', offersRouter);
app.use('/api', reviewsRouter);
app.use('/api', bookingsRouter);
app.use('/api', socialRouter);
// Saved locations (Home, Work, favourites): CRUD under the auth'd user.
app.use('/api/users/me/saved-locations', savedLocationsRouter);
// P2 Safety & Trust: reports (user/content flags + admin queue) and feedback
// (support tickets). `/users/me/blocked` is served by socialRouter above.
app.use('/api', reportsRouter);
app.use('/api', feedbackRouter);
// Shared table-reservation engine: diner-facing availability, booking and
// cancellation. Partner-side management of the same rows lives under
// /api/partner/restaurants/:id/reservations.
app.use('/api', tableReservationsRouter);

// Partner app routes. Every handler resolves the caller's membership for the
// venue in the path (src/access.ts), so registration order below is by
// specificity: platform-wide queues, then venue sub-resources, then the venue
// collection itself, then the legacy partner surface.
// Phase 3: subscription entitlement middleware gates partner modules.
app.use('/api/partner/verification', partnerVerificationRouter);
app.use('/api/partner/restaurants', requireActiveSubscription(true), partnerMenuRouter);
app.use('/api/partner/restaurants', requireActiveSubscription(true), partnerTablesRouter);
app.use('/api/partner/restaurants', requireActiveSubscription(true), partnerOpsRouter);
app.use('/api/partner/restaurants', requireActiveSubscription(true), partnerImagesRouter);
app.use('/api/partner/restaurants', requireActiveSubscription(true), partnerVenuesRouter);
app.use('/api/partner', requireActiveSubscription(true), partnerRouter);

// Admin routes (subscription activation, etc.)
app.use('/api/admin/restaurants', partnerAdminRouter);

app.use((_req: Request, res: Response, _next: NextFunction) => {
  res.status(404).json({ error: 'Route not found' });
});

// Error handler
app.use(
  (error: unknown, _req: Request, res: Response, _next: NextFunction) => {
    if (error instanceof ApiError) {
      res.status(error.status).json({ error: error.message });
      return;
    }
    if (error instanceof ZodError) {
      res.status(400).json({ error: 'Invalid request body', issues: error.issues });
      return;
    }
    // body-parser failures (malformed JSON, payload over the 1 MB limit) carry
    // their own client status and `expose: true`; they are not server faults.
    const httpError = error as { status?: unknown; expose?: unknown; type?: unknown };
    if (
      typeof httpError?.status === 'number' &&
      httpError.status >= 400 &&
      httpError.status < 500 &&
      httpError.expose === true
    ) {
      res.status(httpError.status).json({
        error:
          httpError.type === 'entity.too.large'
            ? 'Request body is too large'
            : 'Malformed request body',
      });
      return;
    }
    // A malformed UUID in a path parameter reaches Postgres before any handler
    // can reject it, so the driver raises 22P02 (invalid_text_representation).
    // That is a bad client request, not a server fault: answering 500 hides the
    // real cause from the app and from support.
    const pgError = error as { code?: unknown };
    if (pgError?.code === '22P02') {
      res.status(400).json({ error: 'Invalid identifier format' });
      return;
    }
    console.error('Unhandled error:', error);
    res.status(500).json({ error: 'Internal server error' });
  },
);

const port = Number(process.env.PORT ?? 4000);
try {
  await waitForDatabase();
} catch (error) {
  console.error('Could not connect to the database. Exiting.');
  console.error(error);
  await pool.end().catch(() => undefined);
  process.exit(1);
}
// Phase 2a: initPayments removed, no payment gateway configured.
// Phase 2b: Socket.IO removed, no real-time chat layer.
const httpServer = app.listen(port, () => {
  console.log(`DineCircle API listening on http://localhost:${port}`);
});

let shuttingDown = false;
function shutdown(signal: string): void {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`\n${signal} received. Shutting down`);
  httpServer.close(async () => {
    await pool.end().catch(() => undefined);
    process.exit(0);
  });
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
