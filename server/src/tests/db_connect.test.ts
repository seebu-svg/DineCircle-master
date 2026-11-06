import { test } from 'node:test';
import assert from 'node:assert/strict';

import { isTransientConnectError } from '../db.js';

/** Attach an errno-style code, the shape node-postgres network failures carry. */
function withCode(message: string, code: string): Error {
  return Object.assign(new Error(message), { code });
}

test('transient connect failures are classified for the acquire retry', () => {
  assert.ok(isTransientConnectError(withCode('read ECONNRESET', 'ECONNRESET')));
  assert.ok(isTransientConnectError(withCode('connect ECONNREFUSED 1.2.3.4:5432', 'ECONNREFUSED')));
  assert.ok(isTransientConnectError(withCode('connect ETIMEDOUT', 'ETIMEDOUT')));
  assert.ok(isTransientConnectError(new Error('Connection terminated unexpectedly')));
  assert.ok(isTransientConnectError(new Error('timeout exceeded when trying to connect')));
});

test('query-level failures are never retried', () => {
  assert.ok(!isTransientConnectError(
    new Error('duplicate key value violates unique constraint "users_email_key"'),
  ));
  assert.ok(!isTransientConnectError(new Error('relation "nope" does not exist')));
  assert.ok(!isTransientConnectError(new Error('permission denied for table users')));
});

test('non-error throwables are not retried', () => {
  assert.ok(!isTransientConnectError(undefined));
  assert.ok(!isTransientConnectError('boom'));
});
