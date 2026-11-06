/**
 * User-profile integration suite: the editable profile card, public vs. self
 * payloads, anonymised-account visibility and the profile-photo pipeline
 * (upload → public byte route → replace → remove → purge on account delete).
 *
 * Execute from server/:  npm run test:integration
 */
import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { bootstrap, one, type ApiHandle } from './util.js';

const handle: ApiHandle = await bootstrap();
const base = handle.base;
after(() => handle.close());

type Json = Record<string, any>;

async function api(
  token: string | null,
  method: string,
  path: string,
  body?: unknown,
): Promise<{ status: number; json: Json }> {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const json = (await res.json().catch(() => ({}))) as Json;
  return { status: res.status, json };
}

let seq = 0;
const PASSWORD = 'correct horse battery staple';

async function signUpAccount(
  prefix = 'member',
): Promise<{ token: string; userId: string; email: string }> {
  seq += 1;
  const email = `prof_${prefix}_${seq}@example.com`;
  const { status, json } = await api(null, 'POST', '/auth/signup', {
    name: `Profile ${prefix}`,
    email,
    password: PASSWORD,
  });
  assert.equal(status, 201, `signup failed: ${JSON.stringify(json)}`);
  return { token: json.token as string, userId: json.user.id as string, email };
}

// A real 1×1 PNG; the server only sniffs magic bytes, but keep it decodable.
const PNG_1PX =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
const JPEG_HEADER = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);

// ── 1. Editable profile fields ──────────────────────────────────────────────

test('PATCH /users/me edits handle and instagram with normalisation', async () => {
  const me = await signUpAccount('edit');
  const n = seq;
  const res = await api(me.token, 'PATCH', '/users/me', {
    handle: `@Edit.User${n}`,
    instagram: 'https://www.instagram.com/edit.user_ig/',
    bio: 'Line one\nLine two',
  });
  assert.equal(res.status, 200, JSON.stringify(res.json));
  assert.equal(res.json.user.handle, `edit.user${n}`);
  assert.equal(res.json.user.instagram, 'edit.user_ig');
  assert.equal(res.json.user.bio, 'Line one\nLine two');
  // Self payload carries the contact email so the client keeps it.
  assert.equal(res.json.user.email, me.email);

  // Clearing instagram is allowed.
  const cleared = await api(me.token, 'PATCH', '/users/me', { instagram: '' });
  assert.equal(cleared.status, 200);
  assert.equal(cleared.json.user.instagram, '');
  // Unrelated fields stay untouched by a partial write.
  assert.equal(cleared.json.user.handle, `edit.user${n}`);
});

test('PATCH /users/me rejects malformed, reserved and taken handles', async () => {
  const a = await signUpAccount('hA');
  const b = await signUpAccount('hB');

  for (const bad of ['ab', 'has space', '.leading', 'trailing.', 'two..dots', 'x'.repeat(31), 'emoji😀']) {
    const res = await api(a.token, 'PATCH', '/users/me', { handle: bad });
    assert.equal(res.status, 400, `"${bad}" should be rejected`);
  }
  const reserved = await api(a.token, 'PATCH', '/users/me', { handle: 'deleted_abc' });
  assert.equal(reserved.status, 400);

  const claim = await api(a.token, 'PATCH', '/users/me', { handle: `taken_${seq}` });
  assert.equal(claim.status, 200);
  // Re-saving your own handle is not a conflict.
  const resave = await api(a.token, 'PATCH', '/users/me', { handle: `TAKEN_${seq}` });
  assert.equal(resave.status, 200);
  // Someone else claiming it (any case) is.
  const clash = await api(b.token, 'PATCH', '/users/me', { handle: `Taken_${seq}` });
  assert.equal(clash.status, 409);
  assert.match(clash.json.error, /taken/i);
});

test('PATCH /users/me rejects control characters and bad instagram names', async () => {
  const me = await signUpAccount('ctl');
  assert.equal((await api(me.token, 'PATCH', '/users/me', { name: 'Bad\u0000Name' })).status, 400);
  assert.equal((await api(me.token, 'PATCH', '/users/me', { name: 'Two\nLines' })).status, 400);
  assert.equal((await api(me.token, 'PATCH', '/users/me', { bio: 'bell\u0007' })).status, 400);
  assert.equal((await api(me.token, 'PATCH', '/users/me', { instagram: 'not valid!' })).status, 400);
  assert.equal((await api(me.token, 'PATCH', '/users/me', { bio: 'x'.repeat(401) })).status, 400);
});

// ── 2. Public vs. self payloads ─────────────────────────────────────────────

test('other viewers never receive owner-only settings', async () => {
  const owner = await signUpAccount('pii');
  const viewer = await signUpAccount('piiV');
  const patched = await api(owner.token, 'PATCH', '/users/me', {
    homeArea: 'Clifton Block 5',
    dietary: ['Halal'],
    allergies: ['Peanuts'],
    allowTagging: false,
  });
  assert.equal(patched.status, 200);

  const seen = await api(viewer.token, 'GET', `/users/${owner.userId}`);
  assert.equal(seen.status, 200);
  for (const key of ['email', 'phone', 'homeArea', 'dietary', 'allergies', 'dmFromFollowersOnly', 'allowTagging']) {
    assert.ok(!(key in seen.json.user), `public profile leaked ${key}`);
  }
  assert.equal(seen.json.user.handle.length > 0, true);

  // Discovery rows use the same public shape.
  const list = await api(viewer.token, 'GET', '/users?q=Profile&limit=50');
  assert.equal(list.status, 200);
  for (const u of list.json.users as Json[]) {
    assert.ok(!('allergies' in u) && !('email' in u), 'discovery leaked owner-only data');
  }

  // The owner reading their own card still gets everything.
  const self = await api(owner.token, 'GET', `/users/${owner.userId}`);
  assert.deepEqual(self.json.user.allergies, ['Peanuts']);
  assert.equal(self.json.user.email, owner.email);
});

test('malformed and unknown profile ids are 404, not 500', async () => {
  const me = await signUpAccount('ids');
  for (const path of ['/users/not-a-uuid', `/users/${randomUUID()}`,
    '/users/not-a-uuid/followers', '/users/not-a-uuid/following',
    `/users/${randomUUID()}/followers`]) {
    assert.equal((await api(me.token, 'GET', path)).status, 404, path);
  }
});

// ── 3. Profile photo ────────────────────────────────────────────────────────

test('avatar upload is served publicly, cached, replaced and removed', async () => {
  const me = await signUpAccount('pic');

  const up = await api(me.token, 'PUT', '/users/me/avatar', {
    image: `data:image/png;base64,${PNG_1PX}`,
  });
  assert.equal(up.status, 200, JSON.stringify(up.json));
  const path = up.json.user.avatarUrl as string;
  assert.match(path, new RegExp(`^/public/avatars/${me.userId}\\?v=\\d+$`));

  // Public: no bearer token needed.
  const img = await fetch(`${base}${path}`);
  assert.equal(img.status, 200);
  assert.equal(img.headers.get('content-type'), 'image/png');
  assert.match(img.headers.get('cache-control') ?? '', /immutable/);
  const bytes = Buffer.from(await img.arrayBuffer());
  assert.deepEqual(bytes, Buffer.from(PNG_1PX, 'base64'));

  const etag = img.headers.get('etag')!;
  const cached = await fetch(`${base}${path}`, { headers: { 'If-None-Match': etag } });
  assert.equal(cached.status, 304);

  // Replacing bumps the version and the content type follows the bytes.
  const jpeg = Buffer.concat([JPEG_HEADER, Buffer.alloc(64, 1)]).toString('base64');
  const replaced = await api(me.token, 'PUT', '/users/me/avatar', { image: jpeg });
  assert.equal(replaced.status, 200);
  assert.notEqual(replaced.json.user.avatarUrl, path);
  const img2 = await fetch(`${base}${replaced.json.user.avatarUrl}`);
  assert.equal(img2.headers.get('content-type'), 'image/jpeg');

  // Other viewers see the same pointer.
  const viewer = await signUpAccount('picV');
  const seen = await api(viewer.token, 'GET', `/users/${me.userId}`);
  assert.equal(seen.json.user.avatarUrl, replaced.json.user.avatarUrl);

  const removed = await api(me.token, 'DELETE', '/users/me/avatar');
  assert.equal(removed.status, 200);
  assert.equal(removed.json.user.avatarUrl, null);
  assert.equal((await fetch(`${base}/public/avatars/${me.userId}`)).status, 404);
  const row = await one('SELECT 1 FROM user_avatars WHERE user_id = $1::UUID', [me.userId]);
  assert.equal(row, undefined);
  // Idempotent.
  assert.equal((await api(me.token, 'DELETE', '/users/me/avatar')).status, 200);
});

test('avatar upload rejects non-images, corrupt base64, oversize and anonymous calls', async () => {
  const me = await signUpAccount('picBad');

  const html = Buffer.from('<html><script>alert(1)</script></html>').toString('base64');
  assert.equal((await api(me.token, 'PUT', '/users/me/avatar', { image: html })).status, 415);
  assert.equal((await api(me.token, 'PUT', '/users/me/avatar', { image: '!!!notbase64' })).status, 400);
  assert.equal((await api(me.token, 'PUT', '/users/me/avatar', {})).status, 400);

  // One byte over the limit decodes fine but is refused as too large.
  const big = Buffer.concat([JPEG_HEADER, Buffer.alloc(512 * 1024 + 1 - JPEG_HEADER.length)]);
  const tooBig = await api(me.token, 'PUT', '/users/me/avatar', { image: big.toString('base64') });
  assert.equal(tooBig.status, 413);

  assert.equal((await api(null, 'PUT', '/users/me/avatar', { image: PNG_1PX })).status, 401);
  assert.equal((await fetch(`${base}/public/avatars/not-a-uuid`)).status, 404);
});

// ── 4. Account deletion ─────────────────────────────────────────────────────

test('deleting the account purges the photo and hides the profile', async () => {
  const me = await signUpAccount('gone');
  const viewer = await signUpAccount('goneV');
  assert.equal((await api(viewer.token, 'POST', `/users/${me.userId}/follow`)).status, 201);
  const up = await api(me.token, 'PUT', '/users/me/avatar', { image: PNG_1PX });
  assert.equal(up.status, 200);

  const del = await api(me.token, 'DELETE', '/users/me', { password: PASSWORD });
  assert.equal(del.status, 200, JSON.stringify(del.json));

  assert.equal((await fetch(`${base}${up.json.user.avatarUrl}`)).status, 404);
  const row = await one<{ avatar_url: string | null }>(
    'SELECT avatar_url FROM users WHERE id = $1::UUID',
    [me.userId],
  );
  assert.equal(row?.avatar_url, null);
  assert.equal(
    await one('SELECT 1 FROM user_avatars WHERE user_id = $1::UUID', [me.userId]),
    undefined,
  );

  assert.equal((await api(viewer.token, 'GET', `/users/${me.userId}`)).status, 404);
  assert.equal((await api(viewer.token, 'GET', `/users/${me.userId}/followers`)).status, 404);
  const following = await api(viewer.token, 'GET', `/users/${viewer.userId}/following`);
  assert.ok(
    !(following.json.users as Json[]).some((u) => u.id === me.userId),
    'a deleted account must not linger in rosters',
  );
  const found = await api(viewer.token, 'GET', `/users?q=${encodeURIComponent('Deleted user')}&limit=50`);
  assert.ok(!(found.json.users as Json[]).some((u) => u.id === me.userId));
});
