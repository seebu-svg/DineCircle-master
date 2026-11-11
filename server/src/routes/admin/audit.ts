import { Router } from 'express';
import { z } from 'zod';
import type { Request } from 'express';
import { query } from '../../db.js';
import { requireAdminConsole } from '../../access.js';
import { adminPage, pushEquals, pushSearch, renderList, searchTerm } from './_shared.js';

/**
 * Audit Log.
 *
 * The `auditLog` middleware (`src/security.ts`, mounted in `server.ts`) already
 * records every authenticated mutating request, so this module is read-only
 * over that table plus the export the console offers in place of the prototype's
 * "Clear audit log" button. Deleting operator history would defeat the point of
 * keeping it, so nothing here writes a destructive statement.
 */
const router = Router();

const AUDIT_SELECT = `
  a.id, a.action, a.resource, a.resource_id, a.changes, a.status_code,
  a.ip_address, a.user_agent, a.created_at,
  u.name AS actor_name, u.email AS actor_email, u.role AS actor_role`;

const AUDIT_FROM = `
  FROM audit_log a
  LEFT JOIN users u ON u.id = a.user_id`;

function shape(row: Record<string, unknown>) {
  return {
    id: row.id,
    action: row.action,
    resource: row.resource,
    resourceId: row.resource_id,
    changes: row.changes,
    statusCode: row.status_code,
    ipAddress: row.ip_address,
    userAgent: row.user_agent,
    createdAt: row.created_at,
    actorName: row.actor_name ?? 'Anonymous',
    actorEmail: row.actor_email,
    actorRole: row.actor_role,
    method: String(row.action ?? '').includes('create')
      ? 'POST'
      : String(row.action ?? '').includes('delete')
        ? 'DELETE'
        : String(row.action ?? '').includes('update')
          ? 'PATCH'
          : 'REQUEST',
  };
}

/** The filters shared by the list and the CSV export, so both answer the same
 *  question the operator typed. */
function filters(req: Request) {
  const where: string[] = [];
  const params: unknown[] = [];
  pushEquals(where, params, String(req.query.action ?? ''), 'a.action');
  pushEquals(where, params, String(req.query.resource ?? ''), 'a.resource');
  const actor = String(req.query.actor ?? '').trim();
  if (actor !== '' && actor !== 'all') {
    params.push(actor);
    where.push(`(u.name ILIKE $${params.length} OR u.email ILIKE $${params.length})`);
  }
  pushSearch(where, params, searchTerm(req), ['a.action', 'a.resource', 'a.resource_id']);
  return { where, params };
}

/**
 * GET /api/admin/audit-log?page&limit&action&resource&actor&q
 */
router.get('/', async (req, res) => {
  requireAdminConsole(req);
  const { where, params } = filters(req);

  await renderList(res, 'auditLog', {
    select: AUDIT_SELECT,
    from: AUDIT_FROM,
    where,
    params,
    order: 'a.created_at DESC',
    page: adminPage(req),
  }, shape);
});

const exportSchema = z.object({
  action: z.string().trim().max(80).optional(),
  resource: z.string().trim().max(60).optional(),
  q: z.string().trim().max(80).optional(),
});

/** Escapes a CSV cell: quotes doubled, and a leading =/+/-/@ neutralised so an
 *  exported log cannot become a formula when opened in a spreadsheet. */
function csvCell(value: unknown): string {
  const text = value === null || value === undefined ? '' : String(value);
  const guarded = /^[=+\-@]/.test(text) ? `'${text}` : text;
  return `"${guarded.replace(/"/g, '""')}"`;
}

/**
 * POST /api/admin/audit-log/export
 * Returns the visible filter as CSV, capped at 5000 rows so an export cannot
 * turn into a full-table dump over a slow connection.
 */
router.post('/export', async (req, res) => {
  requireAdminConsole(req);
  const input = exportSchema.parse(req.body ?? {});

  const where: string[] = [];
  const params: unknown[] = [];
  pushEquals(where, params, input.action ?? '', 'a.action');
  pushEquals(where, params, input.resource ?? '', 'a.resource');
  pushSearch(where, params, input.q ?? '', ['a.action', 'a.resource', 'a.resource_id']);

  const rows = await query<Record<string, unknown>>(
    `SELECT ${AUDIT_SELECT} ${AUDIT_FROM}
      ${where.length > 0 ? `WHERE ${where.join(' AND ')}` : ''}
      ORDER BY a.created_at DESC LIMIT 5000`,
    params,
  );

  const header = [
    'timestamp',
    'actor',
    'actor_role',
    'actor_email',
    'action',
    'resource',
    'resource_id',
    'status_code',
    'ip_address',
    'changes',
  ];
  const body = rows.map((r) =>
    [
      r.created_at instanceof Date ? r.created_at.toISOString() : r.created_at,
      r.actor_name,
      r.actor_role,
      r.actor_email,
      r.action,
      r.resource,
      r.resource_id,
      r.status_code,
      r.ip_address,
      typeof r.changes === 'string' ? r.changes : JSON.stringify(r.changes ?? {}),
    ]
      .map(csvCell)
      .join(','),
  );

  const csv = [header.map(csvCell).join(','), ...body].join('\r\n');
  res
    .status(200)
    .type('text/csv; charset=utf-8')
    .setHeader('Content-Disposition', 'attachment; filename="dinecircle-audit-log.csv"');
  res.send(csv);
});

export default router;
