#!/usr/bin/env bash
# DineCircle money-path integration test (BUG-02 refund bookkeeping +
# BUG-03 host earnings accrual). Boots the real API against a freshly seeded
# database, then drives a deterministic booking -> check-in -> cancel flow and
# asserts the payouts ledger + host wallet directly. Portable to CI (env-driven).
set -uo pipefail
export PSQL_PAGER=cat PAGER=cat

: "${DATABASE_URL:?set DATABASE_URL to a freshly seeded DineCircle DB}"
: "${DC_PSQL:?set DC_PSQL to a psql command for that DB, e.g. psql -h localhost -p 5432 -U user -d db -tA}"
PORT="${PORT:-4100}"
BASE="http://127.0.0.1:$PORT/api"

# Seeded fixture constants (server/src/seed.ts).
ROOFTOP=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1   # venue owned by partner admin Marco
MARCO_PHONE='+15550004444'

fail() { echo "FAIL: $1" >&2; exit 1; }
q() { $DC_PSQL -c "$1"; }   # tuples-only single value

# ── Boot the server ──────────────────────────────────────────────────────────
npm start >/tmp/dc_money_server.log 2>&1 &
SP=$!
trap 'kill $SP 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do curl -fsS "$BASE/health" >/dev/null 2>&1 && break; sleep 0.5; done
curl -fsS "$BASE/health" >/dev/null 2>&1 || fail "server not up — see /tmp/dc_money_server.log"
echo "server up on :$PORT"

# ── Marco (partner admin) creates a fresh event -> no bookings, no payout row ─
TOKEN_M=$(curl -s -X POST "$BASE/auth/signin" -H 'content-type: application/json' \
  -d "{\"phone\":\"$MARCO_PHONE\"}" | jq -r .token)
[ "$TOKEN_M" != "null" ] || fail "marco signin"
ID_M=$(curl -s "$BASE/auth/me" -H "Authorization: Bearer $TOKEN_M" | jq -r .user.id)

START=$(node -e 'console.log(new Date(Date.now()+7*864e5).toISOString())')
EV=$(curl -s -X POST "$BASE/events" -H "Authorization: Bearer $TOKEN_M" \
  -H 'content-type: application/json' -d "{\"title\":\"Money Path QA\",\"coverImage\":\"assets/images/dish_pasta.png\",\"restaurantId\":\"$ROOFTOP\",\"startAt\":\"$START\",\"seatsTotal\":20,\"pricePerSeat\":50,\"audience\":\"public\"}" \
  | jq -r .event.id)
[ "$EV" != "null" ] || fail "create event"
echo "event=$EV host=$ID_M pricePerSeat=50"

# ── Two guests: A books 2 seats (100), B books 3 seats (150) ─────────────────
STAMP=$(date +%s%N)
TOKEN_A=$(curl -s -X POST "$BASE/auth/signup" -H 'content-type: application/json' \
  -d "{\"name\":\"Money A\",\"email\":\"ma+$STAMP@example.com\",\"password\":\"password123\"}" | jq -r .token)
TOKEN_B=$(curl -s -X POST "$BASE/auth/signup" -H 'content-type: application/json' \
  -d "{\"name\":\"Money B\",\"email\":\"mb+$STAMP@example.com\",\"password\":\"password123\"}" | jq -r .token)
[ "$TOKEN_A" != "null" ] && [ "$TOKEN_B" != "null" ] || fail "guest signups"

BK_A=$(curl -s -X POST "$BASE/events/$EV/bookings" -H "Authorization: Bearer $TOKEN_A" \
  -H 'content-type: application/json' -d '{"seats":2}' | jq -r .booking.id)
BK_B=$(curl -s -X POST "$BASE/events/$EV/bookings" -H "Authorization: Bearer $TOKEN_B" \
  -H 'content-type: application/json' -d '{"seats":3}' | jq -r .booking.id)
[ "$BK_A" != "null" ] && [ "$BK_B" != "null" ] || fail "guest bookings"
echo "BK_A=$BK_A BK_B=$BK_B"

# ── BUG-03: A checks in -> payout accrues from ALL captured live seats ────────
# (A completed + B confirmed, both paid) => gross 250, commission 25 (10%).
curl -s -X POST "$BASE/bookings/$BK_A/checkin" -H "Authorization: Bearer $TOKEN_A" >/tmp/dc_ck.json
GS=$(q "SELECT gross FROM payouts WHERE event_id='$EV';")
CM=$(q "SELECT commission FROM payouts WHERE event_id='$EV';")
echo "after check-in: payout gross=$GS commission=$CM"
[ "$GS" = "250.00" ] || fail "accrual gross (want 250.00 got $GS)"
[ "$CM" = "25.00" ]  || fail "accrual commission (want 25.00 got $CM)"
L1=$(curl -s "$BASE/hosts/$ID_M/wallet" -H "Authorization: Bearer $TOKEN_M" | jq -r .lifetimeNet)

# ── BUG-02: B cancels -> refund the money + recompute the accrued payout ──────
curl -s -X POST "$BASE/bookings/$BK_B/cancel" -H "Authorization: Bearer $TOKEN_B" >/tmp/dc_cn.json
jq -e '.refund.seats==3' /tmp/dc_cn.json >/dev/null || fail "refund seats (want 3)"
PSTAT=$(q "SELECT payment_status FROM bookings WHERE id='$BK_B';")
[ "$PSTAT" = "refunded" ] || fail "BUG-02 refund status (want refunded got $PSTAT)"
GS2=$(q "SELECT gross FROM payouts WHERE event_id='$EV';")
CM2=$(q "SELECT commission FROM payouts WHERE event_id='$EV';")
echo "after cancel:    payout gross=$GS2 commission=$CM2"
[ "$GS2" = "100.00" ] || fail "recompute gross (want 100.00 got $GS2)"
[ "$CM2" = "10.00" ]  || fail "recompute commission (want 10.00 got $CM2)"
L2=$(curl -s "$BASE/hosts/$ID_M/wallet" -H "Authorization: Bearer $TOKEN_M" | jq -r .lifetimeNet)
echo "host lifetimeNet: before=$L1 after=$L2 (delta $(( ${L1%.*} - ${L2%.*} )))"

# The wallet must drop by exactly B's net contribution (150 - 15 = 135).
awk "BEGIN{exit !(($L1-$L2) >= 134.99 && ($L1-$L2) <= 135.01)}" \
  || fail "wallet not reduced by 135 (before=$L1 after=$L2)"

# ── Idempotency: re-cancelling B is refused, and never drifts the ledger ──────
CODE=$(curl -s -o /tmp/dc_cn2.json -w '%{http_code}' -X POST "$BASE/bookings/$BK_B/cancel" \
  -H "Authorization: Bearer $TOKEN_B")
[ "$CODE" = "409" ] || fail "double cancel should 409 (got $CODE)"
GS3=$(q "SELECT gross FROM payouts WHERE event_id='$EV';")
[ "$GS3" = "100.00" ] || fail "idempotency: gross drifted (got $GS3)"

echo "ALL MONEY-PATH CHECKS PASSED (BUG-02 refund bookkeeping + BUG-03 accrual, idempotent + wallet-correct)"
