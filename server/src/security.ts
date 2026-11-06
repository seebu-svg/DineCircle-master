import { createHash } from 'node:crypto';
import type { Request, Response, NextFunction } from 'express';
import rateLimit from 'express-rate-limit';
import 'dotenv/config';
import { query } from './db.js';

/**
 * Bearer tokens are stored only as SHA-256 digests — a leaked auth_tokens
 * table can never be replayed against the API. Clients keep presenting the
 * plaintext secret; we hash before every lookup.
 */
export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

/**
 * Rate limiter: 100 requests per minute per IP by default.
 * Applied globally to all /api/* routes. `API_RATE_LIMIT_MAX` overrides the
 * ceiling (positive integer) so integration runs can drive the money path
 * in bulk. Note: express-rate-limit treats `0` as "block everything", not
 * "disabled" — never set it to 0.
 */
function envLimit(name: string, fallback: number): number {
  const raw = Number(process.env[name] ?? '');
  return Number.isInteger(raw) && raw > 0 ? raw : fallback;
}

export const apiRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: envLimit('API_RATE_LIMIT_MAX', 100),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests — please try again later' },
});

/**
 * Stricter rate limiter for auth endpoints: 10 requests per minute
 * (`AUTH_RATE_LIMIT_MAX` overrides it with a positive integer, for tests).
 */
export const authRateLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: envLimit('AUTH_RATE_LIMIT_MAX', 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many authentication attempts — please wait' },
});

/**
 * P2-2 report spam bucket: on top of the one-open-report-per-target DB guard,
 * submissions get 15 per 15 minutes per IP (`REPORT_RATE_LIMIT_MAX` override,
 * same rules as the other limiters — never 0).
 */
export const reportRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: envLimit('REPORT_RATE_LIMIT_MAX', 15),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many reports — please slow down' },
});

/** P2-3 feedback spam bucket: 10 tickets per hour per IP. */
export const feedbackRateLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: envLimit('FEEDBACK_RATE_LIMIT_MAX', 10),
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many feedback submissions — please try again later' },
});

/**
 * Request-body keys that must never reach the audit trail. The predicate
 * matches any key containing a sensitive substring (password, token, secret,
 * code, otp), so `passwordResetToken`, `newPassword`, `otpCode`, etc. are
 * all caught — not just exact matches. Values are replaced with
 * `[redacted]`, never dropped, so the shape stays reviewable.
 */
const SENSITIVE_KEY_PATTERN = /password|token|secret|code|otp|auth/i;

function isSensitiveKey(key: string): boolean {
  return SENSITIVE_KEY_PATTERN.test(key);
}

/**
 * Long string values (base64 photo uploads, pasted essays) are summarised
 * rather than copied: the audit trail records *that* a field was written, and
 * must not grow by hundreds of KB per avatar upload.
 */
const AUDIT_MAX_STRING = 2048;

export function redactForAudit(body: unknown): unknown {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return body ?? {};
  }
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(body as Record<string, unknown>)) {
    if (isSensitiveKey(key)) {
      out[key] = '[redacted]';
    } else if (typeof value === 'string' && value.length > AUDIT_MAX_STRING) {
      out[key] = `[omitted ${value.length} chars]`;
    } else {
      out[key] = value;
    }
  }
  return out;
}

/**
 * Audit logging middleware.
 * Records write operations (POST/PUT/PATCH/DELETE) to the audit_log table.
 * Uses `res.on('finish', ...)` instead of monkey-patching `res.end` so the
 * insert fires after the response is fully sent, and the route pattern
 * (e.g. `/api/events/:id`) is recorded instead of the raw URL.
 */
export function auditLog(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  // Only log mutating methods
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) {
    next();
    return;
  }

  // Fire-and-forget audit insert after the response is sent
  res.on('finish', () => {
    const userId = req.userId ?? null;
    const action = req.method;
    // Use the matched route pattern (e.g. `/api/events/:id`) instead of the
    // raw URL (e.g. `/api/events/abc-123`) so grouping by endpoint works and
    // path parameters do not leak into the audit table.
    const resource = req.route?.path
      ? `${req.baseUrl ?? ''}${req.route.path}`
      : req.originalUrl || req.url;
    const statusCode = res.statusCode;

    query(
      `INSERT INTO audit_log (user_id, action, resource, resource_id, changes, status_code, ip_address, user_agent)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        userId,
        action,
        resource,
        req.params.id ?? null,
        JSON.stringify(redactForAudit(req.body)),
        statusCode,
        req.ip ?? null,
        req.get('user-agent') ?? null,
      ],
    ).catch((err) => {
      console.error('Audit log insert failed:', err);
    });
  });

  next();
}

/** Only operator-configured reverse proxies may supply the client IP. */
export function trustProxySetting(value: string | undefined): string | number | false {
  if (!value || value === 'false') return false;
  if (value === 'true') return 1;
  return /^\d+$/.test(value) ? Number(value) : value;
}
