import { Router } from 'express';
import crypto from 'node:crypto';
import { z } from 'zod';
import { query } from '../../db.js';
import { ApiError, notFound } from '../../context.js';
import { requireAdminConsole, requireSuperAdmin } from '../../access.js';
import { one } from '../../api.js';
import { hashPassword } from '../../passwords.js';

/**
 * Platform Settings.
 *
 * Three things live behind this module: the single `platform_settings` row, the
 * `subscription_plans` reference table, and the admin roster. The settings row
 * is a whitelisted key set rather than free-form JSON, so a typo in the console
 * cannot park an unknown key in production that nothing reads.
 *
 * `maintenanceMode` is written honestly: no route consumes it yet, so the
 * console labels it as a flag for the operator rather than a switch that takes
 * the apps down.
 */
const router = Router();

/** Every key the settings screen owns, with the type the screen sends. */
const configSchema = z
  .object({
    platformName: z.string().trim().min(2).max(60),
    supportEmail: z.string().trim().email().max(160),
    currency: z.string().trim().length(3),
    timezone: z.string().trim().min(1).max(60),
    city: z.string().trim().min(1).max(60),
    riskFlagThreshold: z.number().int().min(1).max(20),
    autoApproveVenues: z.boolean(),
    requireReceipt: z.boolean(),
    emailOnNewApplication: z.boolean(),
    emailOnPaymentUpload: z.boolean(),
    weeklyDigest: z.boolean(),
    maintenanceMode: z.boolean(),
  })
  .partial();

const SETTINGS_KEYS = Object.keys(configSchema.shape);

async function readSettings() {
  const [row] = await query<{ config: Record<string, unknown>; updated_at: Date; updated_by: string | null }>(
    `SELECT config, updated_at, updated_by FROM platform_settings WHERE id = 'default'`,
  );
  return row;
}

router.get('/', async (req, res) => {
  requireAdminConsole(req);

  const settings = await readSettings();
  const [plans, admins] = await Promise.all([
    query<Record<string, unknown>>(
      `SELECT id, name, cycle, price_pkr, is_active, inclusions, updated_at
         FROM subscription_plans ORDER BY price_pkr ASC`,
    ),
    query<Record<string, unknown>>(
      `SELECT u.id, u.name, u.email, u.role, u.admin_scope, u.avatar_url,
              u.created_at, u.suspended_at,
              (SELECT count(*)::int FROM audit_log a
                WHERE a.user_id = u.id) AS actions_30d
         FROM users u
        WHERE u.role IN ('super_admin','partner_admin')
        ORDER BY CASE u.role WHEN 'super_admin' THEN 0 ELSE 1 END, u.name ASC`,
    ),
  ]);

  res.json(
    one('settings', {
      config: settings?.config ?? {},
      updatedAt: settings?.updated_at ?? null,
      knownKeys: SETTINGS_KEYS,
      plans: plans.map((p) => ({
        id: p.id,
        name: p.name,
        cycle: p.cycle,
        price: Number(p.price_pkr),
        isActive: p.is_active,
        inclusions: p.inclusions,
        updatedAt: p.updated_at,
      })),
      admins: admins.map((a) => ({
        id: a.id,
        name: a.name,
        email: a.email,
        role: a.role,
        scope: a.admin_scope,
        avatarUrl: a.avatar_url,
        createdAt: a.created_at,
        suspendedAt: a.suspended_at,
        status: a.suspended_at ? 'suspended' : 'active',
        actions30d: a.actions_30d,
      })),
    }),
  );
});

/**
 * PATCH /api/admin/settings
 * Merges the supplied whitelisted keys into the row. Unknown keys are rejected
 * rather than stored, so the config stays a description of real behaviour.
 */
router.patch('/', async (req, res) => {
  requireAdminConsole(req);
  const body = (req.body ?? {}) as Record<string, unknown>;

  const unknown = Object.keys(body).filter((k) => !SETTINGS_KEYS.includes(k));
  if (unknown.length > 0) {
    throw new ApiError(400, `Unknown setting keys: ${unknown.join(', ')}`);
  }
  const input = configSchema.parse(body);
  if (Object.keys(input).length === 0) {
    res.json({ data: { updated: false } });
    return;
  }

  const current = await readSettings();
  const merged = { ...(current?.config ?? {}), ...input };

  await query(
    `INSERT INTO platform_settings (id, config, updated_by, updated_at)
     VALUES ('default', $1::jsonb, $2::UUID, now())
     ON CONFLICT (id) DO UPDATE SET config = EXCLUDED.config,
                                    updated_by = EXCLUDED.updated_by,
                                    updated_at = now()`,
    [JSON.stringify(merged), req.userId],
  );

  const after = await readSettings();
  res.json(one('settings', { config: after?.config ?? merged, updatedAt: after?.updated_at }));
});

/**
 * POST /api/admin/settings/switch
 * The six on/off toggles, named so the audit row says which one moved instead
 * of logging a generic PATCH with an opaque body.
 */
const SWITCHES = [
  'autoApproveVenues',
  'requireReceipt',
  'emailOnNewApplication',
  'emailOnPaymentUpload',
  'weeklyDigest',
  'maintenanceMode',
] as const;

const switchSchema = z.object({
  key: z.enum(SWITCHES),
  value: z.boolean(),
});

router.post('/switch', async (req, res) => {
  requireAdminConsole(req);
  const input = switchSchema.parse(req.body ?? {});

  const current = await readSettings();
  const merged = { ...(current?.config ?? {}), [input.key]: input.value };
  await query(
    `INSERT INTO platform_settings (id, config, updated_by, updated_at)
     VALUES ('default', $1::jsonb, $2::UUID, now())
     ON CONFLICT (id) DO UPDATE SET config = EXCLUDED.config,
                                    updated_by = EXCLUDED.updated_by,
                                    updated_at = now()`,
    [JSON.stringify(merged), req.userId],
  );

  res.json(one('switch', { key: input.key, value: input.value }));
});

const adminSchema = z.object({
  name: z.string().trim().min(2).max(120),
  email: z.string().trim().email().max(160),
  role: z.enum(['super_admin', 'partner_admin']),
  scope: z.enum(['full', 'operations', 'trust_safety', 'finance', 'support']).default('full'),
});

/**
 * POST /api/admin/settings/admins
 * Minting an operator account is the most privileged write in the console, so
 * it is super-admin only, and the temporary password is returned once for the
 * same reason the partner reset above is: there is no mail provider here.
 */
router.post('/admins', async (req, res) => {
  requireSuperAdmin(req);
  const input = adminSchema.parse(req.body ?? {});

  const [taken] = await query<{ id: string }>(
    'SELECT id FROM users WHERE lower(email) = lower($1)',
    [input.email],
  );
  if (taken) throw new ApiError(409, 'An account with that email already exists.');

  const base =
    input.email.split('@')[0]!.toLowerCase().replace(/[^a-z0-9_]/g, '').slice(0, 14) || 'admin';
  let handle = `admin.${base}`.slice(0, 30);
  for (let attempt = 1; attempt <= 30; attempt += 1) {
    const [clash] = await query<{ one: number }>(
      'SELECT 1 AS one FROM users WHERE handle = $1',
      [handle],
    );
    if (!clash) break;
    handle = `admin.${base}${attempt}`.slice(0, 30);
  }

  const temporary = crypto.randomBytes(6).toString('base64url');
  const [created] = await query<{ id: string }>(
    `INSERT INTO users (name, handle, email, password_hash, city, bio, joined_year,
                        accent_hex, role, admin_scope, account_type)
     VALUES ($1, $2, $3, $4, 'Karachi', '', $5, '#202124', $6, $7, 'personal')
     RETURNING id`,
    [
      input.name,
      handle,
      input.email,
      await hashPassword(temporary),
      new Date().getFullYear(),
      input.role,
      input.scope,
    ],
  );
  if (!created) throw new ApiError(500, 'Could not create the admin account');

  res.status(201).json(
    one('admin', {
      id: created.id,
      name: input.name,
      email: input.email,
      role: input.role,
      scope: input.scope,
      handle,
      temporaryPassword: temporary,
      note: 'No email provider is configured, so share this with the operator directly.',
    }),
  );
});

const patchAdminSchema = z.object({
  scope: z.enum(['full', 'operations', 'trust_safety', 'finance', 'support']).optional(),
  role: z.enum(['super_admin', 'partner_admin']).optional(),
});

/**
 * PATCH /api/admin/settings/admins/:userId
 * Scope is UI navigation only; role is what actually authorizes a request, and
 * this route refuses to demote the last super admin out of the console.
 */
router.patch('/admins/:userId', async (req, res) => {
  requireSuperAdmin(req);
  const input = patchAdminSchema.parse(req.body ?? {});
  if (Object.keys(input).length === 0) {
    res.json({ data: { updated: false } });
    return;
  }

  const [target] = await query<{ id: string; role: string }>(
    `SELECT id, role FROM users
      WHERE id = $1::UUID AND role IN ('super_admin','partner_admin')`,
    [req.params.userId],
  );
  if (!target) throw notFound('Admin account');

  if (target.role === 'super_admin' && input.role === 'partner_admin') {
    const [remaining] = await query<{ count: number }>(
      `SELECT count(*)::int AS count FROM users
        WHERE role = 'super_admin' AND id <> $1::UUID AND suspended_at IS NULL`,
      [target.id],
    );
    if ((remaining?.count ?? 0) === 0) {
      throw new ApiError(409, 'This is the last active super admin account');
    }
  }

  const sets: string[] = [];
  const params: unknown[] = [];
  if (input.scope !== undefined) {
    params.push(input.scope);
    sets.push(`admin_scope = $${params.length}`);
  }
  if (input.role !== undefined) {
    params.push(input.role);
    sets.push(`role = $${params.length}`);
  }
  params.push(req.params.userId);
  const [updated] = await query<Record<string, unknown>>(
    `UPDATE users SET ${sets.join(', ')} WHERE id = $${params.length}::UUID
      RETURNING id, name, email, role, admin_scope`,
    params,
  );

  res.json(
    one('admin', {
      ...updated,
      scope: updated!.admin_scope,
    }),
  );
});

/**
 * PUT /api/admin/settings/plans/:id
 * Price and activation only. The plan's cycle is its identity here, so changing
 * it would silently re-date every partner's existing period.
 */
const planSchema = z.object({
  pricePkr: z.number().int().min(0).max(10_000_000).optional(),
  isActive: z.boolean().optional(),
  name: z.string().trim().min(2).max(80).optional(),
  inclusions: z.array(z.string().trim().min(1).max(120)).max(12).optional(),
});

router.put('/plans/:id', async (req, res) => {
  requireSuperAdmin(req);
  const input = planSchema.parse(req.body ?? {});

  const sets: string[] = ['updated_at = now()'];
  const params: unknown[] = [];
  if (input.pricePkr !== undefined) {
    params.push(input.pricePkr);
    sets.push(`price_pkr = $${params.length}`);
  }
  if (input.isActive !== undefined) {
    params.push(input.isActive);
    sets.push(`is_active = $${params.length}`);
  }
  if (input.name !== undefined) {
    params.push(input.name);
    sets.push(`name = $${params.length}`);
  }
  if (input.inclusions !== undefined) {
    params.push(JSON.stringify(input.inclusions));
    sets.push(`inclusions = $${params.length}::jsonb`);
  }
  if (params.length === 0) {
    res.json({ data: { updated: false } });
    return;
  }
  params.push(req.params.id);
  const [plan] = await query<Record<string, unknown>>(
    `UPDATE subscription_plans SET ${sets.join(', ')} WHERE id = $${params.length}
      RETURNING id, name, cycle, price_pkr, is_active, inclusions, updated_at`,
    params,
  );
  if (!plan) throw notFound('Plan');

  res.json(
    one('plan', {
      ...plan,
      price: Number(plan.price_pkr),
      isActive: plan.is_active,
      updatedAt: plan.updated_at,
    }),
  );
});

export default router;
