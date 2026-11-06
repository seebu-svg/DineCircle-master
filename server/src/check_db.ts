/** Read-only readiness check: never applies schema or seeds data. */
import { readFile } from 'node:fs/promises';
import { pool } from './db.js';
try {
  const sql = await readFile(new URL('./schema.sql', import.meta.url), 'utf8');
  const names = [...sql.matchAll(/CREATE TABLE IF NOT EXISTS ([a-z_]+)/g)].map(match => match[1]!);
  const result = await pool.query(`SELECT current_database() AS database, current_user AS role`);
  const tables = await pool.query<{ name: string; installed: boolean; rls: boolean; backend_access: boolean }>(`
    SELECT name, c.oid IS NOT NULL AS installed, coalesce(c.relrowsecurity, false) AS rls,
      coalesce(c.relowner = r.oid OR r.rolsuper OR r.rolbypassrls, false) AS backend_access
    FROM unnest($1::text[]) AS name
    LEFT JOIN pg_class c ON c.oid = to_regclass('public.' || quote_ident(name))
    JOIN pg_roles r ON r.rolname = current_user`, [names]);
  const missingTables = tables.rows.filter(row => !row.installed).map(row => row.name);
  const publicTablesWithoutRls = tables.rows.filter(row => row.installed && !row.rls).map(row => row.name);
  const backendAccessFailures = tables.rows.filter(row => row.installed && !row.backend_access).map(row => row.name);
  console.log({ ...result.rows[0], schema_installed: missingTables.length === 0,
    missingTables, publicTablesWithoutRls, backendAccessFailures });
  if (missingTables.length || publicTablesWithoutRls.length || backendAccessFailures.length) process.exitCode = 1;
} catch {
  console.error('Database check failed. Check DATABASE_URL and that the local PostgreSQL server is running.');
  process.exitCode = 1;
} finally {
  await pool.end();
}
