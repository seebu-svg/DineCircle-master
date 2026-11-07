-- Create individual partner accounts for single-venue testing
-- Each account owns exactly ONE venue (restaurant_owner role)
-- Password for all: dinecircle123
-- Idempotent: uses ON CONFLICT DO NOTHING / DO UPDATE

BEGIN;

-- Password hash for 'dinecircle123' (scrypt with random salt)
-- Generated via server's hashPassword() function
\set pwd 'scrypt:feda1a8595309e5b31721e5e87d2da7a:9a51b66d0891801ba84c61a125a522dd788ab18f99323d21ef9729eab0d6ef5a5477ff925dd2044f2c7d9372dc47fa3480129cd6febc4703922fa49dea50d3a1'

-- 1. Kolachi Restaurant
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000001',
  'Kolachi Manager',
  'kolachi.manager',
  'kolachi.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Kolachi Restaurant. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000001', 'aa1d3a67-ecbd-411f-8568-c74182c90204', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 2. Kababjees
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000002',
  'Kababjees Manager',
  'kababjees.manager',
  'kababjees.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Kababjees. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000002', '719b6596-ea5d-4b34-a18f-451e8bf78c44', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 3. Bar B Q Tonight
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000003',
  'BBQ Tonight Manager',
  'bbqtonight.manager',
  'bbqtonight.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Bar B Q Tonight. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000003', '031e3205-3a8f-4f62-b8ba-67bf29858aa5', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 4. Cafe Aylanto
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000004',
  'Cafe Aylanto Manager',
  'aylanto.manager',
  'aylanto.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Cafe Aylanto. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000004', '9e6ff506-c249-407c-aca3-f8e6fa6ebfab', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 5. Okra
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000005',
  'Okra Manager',
  'okra.manager',
  'okra.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Okra. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000005', '5569740e-934b-4cca-8b07-ee523be2eb42', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 6. Xander's
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000006',
  'Xanders Manager',
  'xanders.manager',
  'xanders.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Xander''s. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000006', '716425b8-de51-4148-ad2b-ffda11f3a27d', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 7. Espresso Shahbaz DHA
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000007',
  'Espresso Shahbaz Manager',
  'espresso.manager',
  'espresso.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Espresso Shahbaz DHA. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000007', 'f4077bf3-328c-4ab8-90d7-cb3dc2e04b76', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

-- 8. Cafe Flo
INSERT INTO users (id, name, handle, email, password_hash, city, role, account_type, bio)
VALUES (
  'bbbbbbbb-0001-4000-8000-000000000008',
  'Cafe Flo Manager',
  'cafeflo.manager',
  'cafeflo.partner@example.test',
  :'pwd',
  'Karachi',
  'restaurant_owner',
  'professional',
  'Owner/manager of Cafe Flo. Demo account for single-venue partner testing.'
)
ON CONFLICT (email) DO UPDATE SET
  name = EXCLUDED.name,
  handle = EXCLUDED.handle,
  password_hash = EXCLUDED.password_hash,
  role = EXCLUDED.role,
  account_type = EXCLUDED.account_type;

INSERT INTO restaurant_staff (user_id, restaurant_id, role)
VALUES ('bbbbbbbb-0001-4000-8000-000000000008', 'ce7b49a7-2d15-4304-b625-9a63092b5986', 'owner')
ON CONFLICT (user_id, restaurant_id) DO NOTHING;

COMMIT;

-- Verify the created accounts
SELECT u.email, u.name, u.role, u.account_type, r.name as venue, rs.role as staff_role
FROM users u
JOIN restaurant_staff rs ON rs.user_id = u.id
JOIN restaurants r ON r.id = rs.restaurant_id
WHERE u.email LIKE '%.partner@example.test'
ORDER BY u.email;
