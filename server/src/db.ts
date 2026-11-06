import pg from 'pg';
import 'dotenv/config';

import { databaseConfig } from './database_config.js';

export const pool = new pg.Pool(databaseConfig());
// Idle socket failures must not become unhandled EventEmitter errors.
pool.on('error', () => console.error('An idle database connection failed; the pool will reconnect.'));

export type QueryParams = ReadonlyArray<unknown>;

const TRANSIENT_CONNECT_CODES = new Set(['ECONNRESET', 'ECONNREFUSED', 'ETIMEDOUT', 'EPIPE']);

/** Cold handshakes to a remote Postgres occasionally drop mid-connection.
 *  These failures happen while acquiring a client, before any SQL runs, so a
 *  single acquire retry is safe and cannot duplicate a sent query. */
export function isTransientConnectError(error: unknown): boolean {
  const code = (error as NodeJS.ErrnoException | null)?.code ?? '';
  const message = (error as Error | null)?.message ?? '';
  return (
    TRANSIENT_CONNECT_CODES.has(code) ||
    /connection terminated|connection timed out|timeout exceeded/i.test(message)
  );
}

/** Acquire a pool client, retrying once when connection establishment fails. */
async function acquireClient(): Promise<pg.PoolClient> {
  try {
    return await pool.connect();
  } catch (error) {
    if (!isTransientConnectError(error)) throw error;
    console.warn('Transient database connection failure; retrying once.');
    return await pool.connect();
  }
}

/** Thin wrapper so routes can `await query<T>(sql, params)` and get typed rows. */
export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params: QueryParams = [],
): Promise<T[]> {
  // Acquire first, then run the SQL on that client so the retry only ever
  // covers connection establishment, never a query that was already sent.
  const client = await acquireClient();
  try {
    const result = await client.query<T>(text, params as unknown[]);
    return result.rows;
  } finally {
    client.release();
  }
}

/** Run `fn` inside a transaction with commit/rollback. */
export async function withTransaction<T>(
  fn: (client: pg.PoolClient) => Promise<T>,
): Promise<T> {
  const client = await acquireClient();
  try {
    await client.query('BEGIN');
    const value = await fn(client);
    await client.query('COMMIT');
    return value;
  } catch (error) {
    // A dead connection cannot roll back; the original error still matters.
    await client.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    client.release();
  }
}
