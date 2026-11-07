/** Applies schema.sql, idempotent, safe to run repeatedly. */
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool, withTransaction } from './db.js';

const here = dirname(fileURLToPath(import.meta.url));
const sql = await readFile(join(here, 'schema.sql'), 'utf8');

try {
  await withTransaction(async (client) => {
    await client.query('SET LOCAL search_path = public');
    await client.query(sql);
    // Only protect tables owned by this application. Authorization is enforced
    // by Express, so no other role may read or write these rows directly.
    const tables = [...sql.matchAll(/CREATE TABLE IF NOT EXISTS ([a-z_]+)/g)].map(match => match[1]!);
    for (const table of tables) {
      await client.query(`ALTER TABLE public."${table}" ENABLE ROW LEVEL SECURITY`);
      await client.query(`REVOKE ALL ON TABLE public."${table}" FROM PUBLIC`);
    }
  });
  console.log(
    'Schema applied: users, user_avatars, restaurants, dinner_events, menu_items, bookings, '
      + 'refunds, payouts, reviews, follows, saved_events, activity, chat_messages, '
      + 'conversations, conversation_participants, message_read_receipts, '
      + 'special_menus, notifications, otp_codes, email_change_challenges, '
      + 'promo_codes, auth_tokens, user_blocks, reports, feedback, audit_log, '
      + 'supported_cities, saved_locations.',
  );
} catch (error) {
  console.error('Schema failed:', error);
  process.exitCode = 1;
} finally {
  // Always close the pool: this script also runs as a one-shot child (tests,
  // compose init) and must exit instead of idling on open sockets.
  await pool.end();
}
