#!/usr/bin/env bash
# Local proof of the assertions the CI smoke makes about POST /api/events,
# run against a freshly seeded scratch database.
set -uo pipefail
cd "$(dirname "$0")/.."

DB=ci_smoke_check
EXPORT_URL="postgresql://h4til3fishnix@/$DB?host=/var/run/postgresql"

dropdb --if-exists --force "$DB" >/dev/null 2>&1
createdb "$DB" || exit 1

DATABASE_URL="$EXPORT_URL" npx tsx src/schema.ts >/dev/null || { echo "SCHEMA FAILED"; exit 1; }
DATABASE_URL="$EXPORT_URL" npx tsx src/seed.ts >/dev/null || { echo "SEED FAILED"; exit 1; }

PORT=4011 DATABASE_URL="$EXPORT_URL" npx tsx src/server.ts >/tmp/ci_smoke_server.log 2>&1 &
SRV=$!
for _ in $(seq 1 40); do curl -fsS http://localhost:4011/api/health >/dev/null 2>&1 && break; sleep 0.5; done

BASE=http://localhost:4011/api
ROOFTOP=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1
TRATTORIA=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa2
STAMP=$(date +%s)

TOKEN_A=$(curl -s -X POST $BASE/auth/signup -H 'content-type: application/json' \
  -d "{\"name\":\"Smoke Guest\",\"email\":\"smoke+$STAMP@example.com\",\"password\":\"password123\"}" | jq -r .token)
curl -s -o /dev/null -X POST $BASE/users/me/host -H "Authorization: Bearer $TOKEN_A"

TOKEN_M=$(curl -s -X POST $BASE/auth/signin -H 'content-type: application/json' \
  -d '{"phone":"+15550004444"}' | jq -r .token)

START=$(node -e 'console.log(new Date(Date.now()+7*864e5).toISOString())')
mk() { printf '{"title":"Smoke %s","restaurantId":"%s","coverImage":"assets/images/dish_pasta.png","startAt":"%s","seatsTotal":8,"pricePerSeat":42,"audience":"public"}' "$1" "$2" "$START"; }

echo -n "host @ unverified trattoria (want 403): "
curl -s -o /tmp/s1.json -w '%{http_code}\n' -X POST $BASE/events \
  -H "Authorization: Bearer $TOKEN_A" -H 'content-type: application/json' -d "$(mk A "$TRATTORIA")"

echo -n "partner admin @ verified rooftop (want 201): "
curl -s -o /tmp/s2.json -w '%{http_code}\n' -X POST $BASE/events \
  -H "Authorization: Bearer $TOKEN_M" -H 'content-type: application/json' -d "$(mk B "$ROOFTOP")"

echo -n "partner admin lists its venues (want 200): "
curl -s -o /tmp/s3.json -w '%{http_code}\n' $BASE/partner/restaurants -H "Authorization: Bearer $TOKEN_M"
echo -n "  venue count: "; jq '.data.restaurants | length' /tmp/s3.json

echo -n "partner admin reads its dashboard (want 200): "
curl -s -o /tmp/s4.json -w '%{http_code}\n' "$BASE/partner/restaurants/$ROOFTOP/dashboard" \
  -H "Authorization: Bearer $TOKEN_M"
echo -n "  verified / tables / capacity: "
jq -r '"\(.data.restaurant.verified) / \(.data.today.tables) / \(.data.today.capacity)"' /tmp/s4.json

echo -n "partner admin reads earnings (want 200): "
curl -s -o /tmp/s5.json -w '%{http_code}\n' "$BASE/partner/restaurants/$ROOFTOP/earnings" \
  -H "Authorization: Bearer $TOKEN_M"
echo -n "  commissionRate: "; jq -c '.data.earnings' /tmp/s5.json

echo -n "customer availability at rooftop (want 200): "
curl -s -o /tmp/s6.json -w '%{http_code}\n' "$BASE/restaurants/$ROOFTOP/availability?partySize=2" \
  -H "Authorization: Bearer $TOKEN_A"
echo -n "  slots: "; jq -r '.data.slots | length' /tmp/s6.json

echo -n "partner inbox (want 200, envelope): "
curl -s -o /tmp/s7.json -w '%{http_code}\n' $BASE/partner/notifications -H "Authorization: Bearer $TOKEN_M"
echo -n "  meta: "; jq -c '.meta' /tmp/s7.json

kill $SRV 2>/dev/null
wait $SRV 2>/dev/null
dropdb --if-exists --force "$DB" >/dev/null 2>&1
echo "cleaned up"
