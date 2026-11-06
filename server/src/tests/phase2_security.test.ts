import { test, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { pool } from '../db.js';
import { trustProxySetting } from '../security.js';
import { assertHostAccess } from '../routes/hosts.js';
import { requireAuth } from '../context.js';
import venues from '../routes/partner_venues.js';
import menu from '../routes/partner_menu.js';
import operations from '../routes/partner_ops.js';

const id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1';
const userId = 'bbbbbbbb-bbbb-4bbb-bbbb-bbbbbbbbbbb1';
const original = pool.connect;
const calls: { sql: string; params: unknown[] }[] = [];
function database(responses: object[][]) {
  calls.length = 0;
  (pool as any).connect = async () => ({
    query: async (sql: string, params: unknown[]) => {
      calls.push({ sql, params });
      return { rows: responses.shift() ?? [] };
    }, release() {},
  });
}
afterEach(() => { pool.connect = original; });

test('partner admins cannot inspect or operate other hosts financial records', () => {
  assert.throws(() => assertHostAccess(userId, 'partner_admin', id), { status: 403 });
  assert.doesNotThrow(() => assertHostAccess(userId, 'user', userId));
  assert.doesNotThrow(() => assertHostAccess(userId, 'super_admin', id));
});
test('HTTP bearer middleware rejects missing and expired sessions', async () => {
  database([[]]);
  for (const token of ['', 'Bearer expired']) {
    let error: any;
    await requireAuth({ header: () => token } as any, {} as any, e => { error = e; });
    assert.equal(error.status, 401);
  }
});
test('HTTP bearer middleware resolves the database identity and role', async () => {
  database([[{ user_id: userId, role: 'restaurant_owner' }]]);
  const req = { header: () => 'Bearer valid' } as any;
  let error: unknown;
  await requireAuth(req, {} as any, e => { error = e; });
  assert.equal(error, undefined); assert.equal(req.userId, userId);
  assert.equal(req.userRole, 'restaurant_owner');
  assert.match(calls[0]!.sql, /NOT u.is_deleted/);
});

const acceptInvite = (venues as any).stack.find((layer: any) => layer.route?.path === '/:restaurantId/staff/accept').route.stack[0].handle;
async function accept() {
  let body: unknown;
  await acceptInvite({ userId, params: { restaurantId: id } }, { json(value: unknown) { body = value; } });
  return body;
}
test('revoked invite cannot be reactivated during acceptance', async () => {
  database([[], [{ status: 'revoked' }]]);
  await assert.rejects(accept, { status: 409 });
  assert.match(calls[0]!.sql, /UPDATE restaurant_staff/);
  assert.match(calls[0]!.sql, /status = 'invited'/);
  assert.equal(calls.length, 2);
});
test('valid invite accepts and keeps the mobile response contract', async () => {
  database([[{ role: 'staff' }], []]);
  assert.deepEqual(await accept(), { data: { restaurantId: id, role: 'staff', status: 'active' } });
  assert.match(calls[1]!.sql, /AND role = 'user'/);
});
test('acceptance remains idempotent for an active member', async () => {
  database([[], [{ status: 'active' }]]);
  assert.deepEqual(await accept(), { data: { restaurantId: id, status: 'active' } });
});

for (const [router, path, method] of [
  [menu, '/:restaurantId/menu', 'get'],
  [menu, '/:restaurantId/menu/sections', 'post'],
  [menu, '/:restaurantId/menu/items', 'post'],
  [menu, '/:restaurantId/menu/items/:itemId', 'patch'],
  [menu, '/:restaurantId/menu/items/:itemId', 'delete'],
  [operations, '/:restaurantId/deals', 'get'],
  [operations, '/:restaurantId/deals', 'post'],
  [operations, '/:restaurantId/deals/:dealId', 'patch'],
  [operations, '/:restaurantId/deals/:dealId', 'delete'],
] as const) {
  test(`${method.toUpperCase()} ${path} rejects cross-tenant access before resource query`, async () => {
    database([[{ role: null, owns: false }], [{ id }]]);
    const handler = (router as any).stack.find((layer: any) => layer.route?.path === path && layer.route.methods[method]).route.stack[0].handle;
    await assert.rejects(() => handler({ userId, userRole: 'restaurant_owner', params: { restaurantId: id } }, {}), { status: 403 });
    assert.equal(calls.length, 2);
    assert.ok(calls.every(call => !/INSERT|UPDATE|DELETE/.test(call.sql)));
  });
}

test('forwarded IP trust defaults to disabled and explicit true means one hop', () => {
  assert.equal(trustProxySetting(undefined), false);
  assert.equal(trustProxySetting(''), false);
  assert.equal(trustProxySetting('false'), false);
  assert.equal(trustProxySetting('true'), 1);
  assert.equal(trustProxySetting('2'), 2);
  assert.equal(trustProxySetting('loopback'), 'loopback');
});
