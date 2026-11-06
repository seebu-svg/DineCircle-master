import { readFileSync } from 'node:fs';
import type { PoolConfig } from 'pg';

/** Shared by the API, schema/seed tools and the read-only connection check. */
export function databaseConfig(env: NodeJS.ProcessEnv = process.env): PoolConfig {
  const connectionString = env.DATABASE_URL?.trim();
  if (!connectionString && env.NODE_ENV === 'production') {
    throw new Error('DATABASE_URL is required in production');
  }
  const url = new URL(connectionString || 'postgresql://dinecircle:dinecircle@localhost:5432/dinecircle');
  if (!['postgres:', 'postgresql:'].includes(url.protocol)) {
    throw new Error('DATABASE_URL must be a PostgreSQL connection string');
  }
  // These URL options override node-postgres TLS settings. Reject insecure modes.
  const sslMode = url.searchParams.get('sslmode');
  if (sslMode && !['require', 'verify-ca', 'verify-full', 'disable'].includes(sslMode)) {
    throw new Error('Unsupported DATABASE_URL sslmode');
  }
  if (env.NODE_ENV === 'production' && sslMode === 'disable') {
    throw new Error('TLS cannot be disabled for production databases');
  }
  // Local PostgreSQL runs plaintext; a remote host opts into TLS explicitly
  // with sslmode or DATABASE_SSL_CA_FILE, and production always requires it.
  const tls = env.NODE_ENV === 'production' || (sslMode != null && sslMode !== 'disable') || !!env.DATABASE_SSL_CA_FILE;
  for (const key of ['sslmode', 'sslcert', 'sslkey', 'sslrootcert', 'ssl', 'uselibpqcompat']) {
    if (url.searchParams.has(key) && key !== 'sslmode') {
      throw new Error(`Use DATABASE_SSL_CA_FILE instead of DATABASE_URL option ${key}`);
    }
    url.searchParams.delete(key);
  }
  function positiveInteger(name: string, fallback: number): number {
    const value = env[name];
    if (value === undefined) return fallback;
    const number = Number(value);
    if (!Number.isSafeInteger(number) || number < 1) throw new Error(`${name} must be a positive integer`);
    return number;
  }
  return {
    connectionString: url.toString(),
    ssl: tls ? { rejectUnauthorized: true, ...(env.DATABASE_SSL_CA_FILE ? { ca: readFileSync(env.DATABASE_SSL_CA_FILE, 'utf8') } : {}) } : false,
    max: positiveInteger('DATABASE_POOL_MAX', 10),
    connectionTimeoutMillis: positiveInteger('DATABASE_CONNECT_TIMEOUT_MS', 30000),
    idleTimeoutMillis: 30000,
  };
}
