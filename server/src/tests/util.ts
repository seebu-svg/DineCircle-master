/**
 * Shared bootstrap for the API-level integration tests.
 *
 * Builds an ISOLATED PostgreSQL database (`dinecircle_itest` by default),
 * applies src/schema.sql, runs src/seed.ts for a deterministic fixture world,
 * then boots the real Express API as a child process on a free port with the
 * rate limiters raised. Every module in the test process pins DATABASE_URL
 * before the first `pg` import so `../db.js` can never fall back to the
 * developer `.env`.
 */
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:net';
import { userInfo } from 'node:os';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import 'dotenv/config';

const serverRoot = fileURLToPath(new URL('../..', import.meta.url));

// Resolved from the parent's original DATABASE_URL before we overwrite it.
// `ITEST_ADMIN_DATABASE_URL` lets CI/dev point the *bootstrap* connection at a
// role that may CREATE DATABASE (the app role deliberately cannot), while the
// API under test still connects with the ordinary DATABASE_URL credentials.
//
// Two connection shapes are supported because local Postgres commonly exposes
// the superuser over a unix socket with no password:
//   postgresql://user:pw@host:5432/db          (TCP)
//   postgresql:///postgres?host=/var/run/...   (unix socket, peer auth)
const adminConn = (() => {
  const raw =
    process.env.ITEST_ADMIN_DATABASE_URL ??
    process.env.DATABASE_URL ??
    'postgresql://dinecircle:dinecircle@localhost:5433/dinecircle';
  const url = new URL(raw);
  const socketHost = url.searchParams.get('host') ?? '';
  // Preserve SSL settings so remote hosts (e.g. Supabase pooler) work.
  const sslmode = url.searchParams.get('sslmode') ?? '';
  const sslCaFile = process.env.DATABASE_SSL_CA_FILE ?? '';
  return {
    // A socket path in `?host=` wins over the (empty) URL hostname.
    host: socketHost.startsWith('/') ? socketHost : url.hostname || 'localhost',
    isSocket: socketHost.startsWith('/'),
    port: url.port || '5432',
    // Empty username means peer/trust auth: `pg` resolves it to the OS user,
    // so defaulting to the running user keeps socket logins working instead of
    // forcing a `postgres` role that may not exist for this OS account.
    user:
      decodeURIComponent(url.username) || process.env.PGUSER || userInfo().username,
    password: decodeURIComponent(url.password),
    sslmode,
    sslCaFile,
  };
})();

/**
 * Build pg SSL config object from a connection URL.
 * Strips sslmode from the URL (to prevent pg-connection-string from overriding)
 * and returns both the cleaned URL and the SSL config.
 */
function sslConfigForUrl(connectionString: string): { url: string; ssl: Record<string, unknown> | undefined } {
  try {
    const url = new URL(connectionString);
    const sslmode = url.searchParams.get('sslmode') ?? '';
    url.searchParams.delete('sslmode');
    if (!sslmode || sslmode === 'disable') {
      return { url: url.toString(), ssl: undefined };
    }
    const caFile = adminConn.sslCaFile || process.env.DATABASE_SSL_CA_FILE || '';
    if (caFile) {
      return { url: url.toString(), ssl: { ca: readFileSync(caFile, 'utf8') } };
    }
    // sslmode=require without a CA file: accept any server cert.
    return { url: url.toString(), ssl: { rejectUnauthorized: false } };
  } catch {
    return { url: connectionString, ssl: undefined };
  }
}

/**
 * Build a connection string for `database` using the admin credentials.
 * Credentials are URL-encoded so passwords containing `@`, `:` or `/` survive.
 */
function connStringFor(database: string): string {
  const auth = adminConn.password
    ? `${encodeURIComponent(adminConn.user)}:${encodeURIComponent(adminConn.password)}`
    : encodeURIComponent(adminConn.user);
  if (adminConn.isSocket) {
    // `pg` reads the socket directory from the `host` query parameter.
    return `postgresql://${auth}@/${database}?host=${encodeURIComponent(adminConn.host)}`;
  }
  // Preserve SSL mode from the original DATABASE_URL (required for remote hosts).
  const sslSuffix = adminConn.sslmode ? `?sslmode=${encodeURIComponent(adminConn.sslmode)}` : '';
  return `postgresql://${auth}@${adminConn.host}:${adminConn.port}/${database}${sslSuffix}`;
}

export const TEST_DB = process.env.ITEST_DB_NAME ?? 'dinecircle_itest';

// Everything below (this module's admin pool, the one-shot schema/seed child
// runs, and the API server) connects to the isolated test database.
process.env.DATABASE_URL = connStringFor(TEST_DB);
// The commission rate is deliberately *not* pinned here any more: the suite must
// fail if the shipped default stops being 10% (an unset variable previously
// meant a 0% take rate). Tests that need another rate spawn their own API.
process.env.NODE_ENV = 'test';

const adminPool = new pg.Pool({
  host: adminConn.host,
  port: Number(adminConn.port),
  user: adminConn.user,
  password: adminConn.password || undefined,
  database: 'postgres',
  max: 1,
  ...(adminConn.sslmode && adminConn.sslmode !== 'disable' ? {
    ssl: adminConn.sslCaFile
      ? { ca: readFileSync(adminConn.sslCaFile, 'utf8') }
      : { rejectUnauthorized: false },
  } : {}),
});

function run(script: string, env: Record<string, string>): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn('npx', ['tsx', script], {
      cwd: serverRoot,
      env: { ...process.env, ...env },
      stdio: ['ignore', 'inherit', 'inherit'],
    });
    child.on('error', reject);
    child.on('exit', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${script} exited with code ${code}`));
    });
  });
}

async function waitForDatabase(rawUrl: string, retries = 20): Promise<void> {
  const { url, ssl } = sslConfigForUrl(rawUrl);
  for (let attempt = 1; ; attempt += 1) {
    try {
      const probe = new pg.Pool({ connectionString: url, max: 1, ...(ssl ? { ssl } : {}) });
      await probe.query('SELECT 1');
      await probe.end();
      return;
    } catch (error) {
      if (attempt >= retries) throw error;
      await new Promise((r) => setTimeout(r, 500));
    }
  }
}

export type ApiHandle = {
  base: string;
  close: () => Promise<void>;
};

/**
 * Ask the OS for a free ephemeral port by binding to :0, reading the assigned
 * port, then releasing it. Guarantees the API server and any per-test alt
 * server never collide (deriving ports from `process.pid` produced overlapping
 * ranges and made the commission test flakily hit the wrong server).
 */
export function getFreePort(): Promise<number> {
  return new Promise((resolve, reject) => {
    const probe = createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const addr = probe.address();
      if (addr === null || typeof addr === 'string') {
        probe.close(() => reject(new Error('no free port')));
        return;
      }
      const { port } = addr;
      probe.close(() => resolve(port));
    });
  });
}

/** Boot the real API on the given port against the current DATABASE_URL. */
async function startServer(port: number, commission?: string): Promise<ApiHandle> {
  const env: Record<string, string> = {
    PORT: String(port),
    NODE_ENV: 'test',
    // Raised ceilings for the integration run (0 would block everything).
    API_RATE_LIMIT_MAX: '100000',
    AUTH_RATE_LIMIT_MAX: '100000',
    ...(commission ? { PLATFORM_COMMISSION_RATE: commission } : {}),
  };
  // Start Node directly so teardown signals reach the API, not an npm wrapper.
  const child = spawn(process.execPath, ['--import', 'tsx', 'src/server.ts'], {
    cwd: serverRoot,
    env: { ...process.env, ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let log = '';
  child.stdout?.on('data', (chunk: Buffer) => { log += chunk.toString(); });
  child.stderr?.on('data', (chunk: Buffer) => { log += chunk.toString(); });

  const base = `http://127.0.0.1:${port}/api`;
  try {
    for (let attempt = 0; attempt < 80; attempt += 1) {
      try {
        const res = await fetch(`${base}/health`);
        if (res.ok) return {
          base,
          close: async () => {
            child.kill('SIGTERM');
            await new Promise((r) => setTimeout(r, 200));
            child.kill('SIGKILL');
          },
        };
      } catch {
        // not listening yet
      }
      if (child.exitCode !== null) {
        throw new Error(`server exited early (code ${child.exitCode}):\n${log}`);
      }
      await new Promise((r) => setTimeout(r, 250));
    }
    throw new Error(`server never became healthy:\n${log}`);
  } catch (error) {
    child.kill('SIGKILL');
    throw error;
  }
}

/**
 * Start an extra API instance on its own free port with an overridden
 * commission rate (used by the configurable-commission test). Reuses the same
 * harness so the child never collides with the primary server's port.
 */
export async function spawnApi(commission?: string): Promise<ApiHandle> {
  const port = await getFreePort();
  return startServer(port, commission);
}

/**
 * Create + seed the isolated database and start the API. Call once per test
 * file, before importing anything that opens a pool.
 */
export async function bootstrap(): Promise<ApiHandle> {
  // Unique suffix per file so parallel `node --test` workers never collide.
  const dbName = `${TEST_DB}_${randomBytes(3).toString('hex')}`;
  await adminPool.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
  await adminPool.query(`CREATE DATABASE ${dbName}`);

  const url = connStringFor(dbName);
  await waitForDatabase(url);
  process.env.DATABASE_URL = url;

  // schema.ts / seed.ts read process.env.DATABASE_URL directly (db.ts), so
  // the parent override flows into the children.
  await run('src/schema.ts', {});
  await run('src/seed.ts', {});

  const port = await getFreePort();
  const handle = await startServer(port);
  return {
    base: handle.base,
    close: async () => {
      await handle.close();
      await adminPool.query(`DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`);
      await adminPool.end();
    },
  };
}

/** Run a statement without reading rows (DDL / setup sabotage). */
export async function exec(sql: string, params: unknown[] = []): Promise<void> {
  await pgPoolQuery(sql, params);
}

/** Direct DB assertions (server-side truth, bypassing the API). */
export async function one<T extends pg.QueryResultRow>(
  sql: string,
  params: unknown[] = [],
): Promise<T | undefined> {
  const rows = await pgPoolQuery<T>(sql, params);
  return rows[0];
}

export async function many<T extends pg.QueryResultRow>(
  sql: string,
  params: unknown[] = [],
): Promise<T[]> {
  return pgPoolQuery<T>(sql, params);
}

async function pgPoolQuery<T extends pg.QueryResultRow>(
  sql: string,
  params: unknown[],
): Promise<T[]> {
  const rawUrl = process.env.DATABASE_URL ?? '';
  const { url, ssl } = sslConfigForUrl(rawUrl);
  const pool = new pg.Pool({ connectionString: url, max: 2, ...(ssl ? { ssl } : {}) });
  try {
    const result = await pool.query<T>(sql, params);
    // DDL/none results carry no rows.
    return result.rows ?? [];
  } finally {
    await pool.end();
  }
}
