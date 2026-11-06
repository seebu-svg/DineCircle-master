-- Database security hardening — REFERENCE ONLY
--
-- This file is NOT applied by the server boot path. The actual schema is
-- server/src/schema.sql (applied by server/src/schema.ts at boot), and the
-- API connects as the database owner, so RLS policies defined here would be
-- inert even if applied.
--
-- This file documents what a production-hardened deployment SHOULD look like
-- once the API is moved to a dedicated `dinecircle_api` role with minimal
-- privileges and RLS is enforced. Until then, it is a design reference.
--
-- DO NOT run this script against a live database without reviewing the
-- implications: the API would need to be reconfigured to connect as
-- `dinecircle_api` instead of the owner, and every query would need to set
-- `app.current_user_id` before executing.

-- 1. Audit log table (already in schema.sql — this is the canonical definition)
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID,
  action TEXT NOT NULL,
  resource TEXT NOT NULL,
  resource_id UUID,
  changes JSONB DEFAULT '{}',
  status_code INTEGER,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_user ON audit_log (user_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_created ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_resource ON audit_log (resource);

-- 2. Dedicated API user — password MUST be set by the operator at deploy time.
-- The placeholder below is intentionally invalid so running this script
-- verbatim fails rather than creating a known-credential account.
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'dinecircle_api') THEN
    -- OPERATOR: replace this with a strong, randomly generated password.
    -- The script will fail if you leave the placeholder.
    CREATE USER dinecircle_api WITH PASSWORD 'CHANGE_ME_BEFORE_DEPLOY';
  END IF;
END
$$;

-- Grant only the minimum required privileges
GRANT CONNECT ON DATABASE dinecircle TO dinecircle_api;
GRANT USAGE ON SCHEMA public TO dinecircle_api;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO dinecircle_api;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO dinecircle_api;

-- Revoke default public schema access
REVOKE ALL ON DATABASE dinecircle FROM PUBLIC;

-- 3. Row-Level Security policies for multi-tenant isolation
-- NOTE: these policies are INERT until the API connects as dinecircle_api
-- instead of the database owner. The owner bypasses RLS by default.

-- Restaurants: partner admins can only modify their own restaurants
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;

CREATE POLICY partner_own_restaurants ON restaurants
  FOR ALL
  USING (owner_id = current_setting('app.current_user_id', true)::UUID)
  WITH CHECK (owner_id = current_setting('app.current_user_id', true)::UUID);

-- Partner admins can still see all restaurants for browsing
CREATE POLICY any_user_view_restaurants ON restaurants
  FOR SELECT
  USING (true);

-- Bookings: users can only see their own bookings
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_own_bookings ON bookings
  FOR ALL
  USING (
    user_id = current_setting('app.current_user_id', true)::UUID
    OR event_id IN (
      SELECT de.id FROM dinner_events de
      JOIN restaurants r ON r.id = de.restaurant_id
      WHERE r.owner_id = current_setting('app.current_user_id', true)::UUID
    )
  );

-- Auth tokens: users can only see their own tokens
ALTER TABLE auth_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_own_tokens ON auth_tokens
  FOR ALL
  USING (user_id = current_setting('app.current_user_id', true)::UUID);
