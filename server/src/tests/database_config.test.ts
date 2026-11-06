import { test } from 'node:test';
import assert from 'node:assert/strict';
import { databaseConfig } from '../database_config.js';
test('local development uses bounded plaintext pool', () => {
  assert.equal(databaseConfig({}).ssl, false);
  assert.equal(databaseConfig({}).max, 10);
  // Remote TLS handshakes can exceed 10s on high-latency links.
  assert.equal(databaseConfig({}).connectionTimeoutMillis, 30000);
});
test('remote TLS is verified and URL cannot override it', () => {
  const config = databaseConfig({ DATABASE_URL: 'postgresql://postgres:password@db.example.com:5432/postgres?sslmode=require', DATABASE_POOL_MAX: '4' });
  assert.deepEqual(config.ssl, { rejectUnauthorized: true });
  assert.equal(config.max, 4);
  assert.ok(!config.connectionString?.includes('sslmode'));
});
test('production requires credentials and TLS', () => {
  assert.throws(() => databaseConfig({ NODE_ENV: 'production' }), /required/);
  assert.throws(() => databaseConfig({ NODE_ENV: 'production', DATABASE_URL: 'postgresql://localhost/db?sslmode=disable' }), /TLS/);
});
test('invalid settings fail early', () => {
  assert.throws(() => databaseConfig({ DATABASE_POOL_MAX: '0' }), /positive integer/);
  assert.throws(() => databaseConfig({ DATABASE_CONNECT_TIMEOUT_MS: 'abc' }), /positive integer/);
  assert.throws(() => databaseConfig({ DATABASE_URL: 'postgresql://localhost/db?sslmode=no-verify' }), /sslmode/);
  assert.throws(() => databaseConfig({ DATABASE_URL: 'postgresql://localhost/db?ssl=false' }), /DATABASE_SSL_CA_FILE/);
});
