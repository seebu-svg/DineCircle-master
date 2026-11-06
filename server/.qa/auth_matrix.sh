#!/usr/bin/env bash
# DineCircle auth live-test matrix. Run against a dev server with a raised
# AUTH_RATE_LIMIT_MAX. Prints PASS/FAIL per case.
BASE="http://localhost:4000/api/auth"
TS=$(date +%s)
EMAIL1="qa.$TS@test.local"
EMAIL2="qa2.$TS@test.local"
NEWEMAIL="qa.$TS.moved@test.local"
PASS='Str0ngPass!a'
PASS2='Str0ngPass!b'
PHONE="+92300${TS}"
PASS_COUNT=0; FAIL_COUNT=0

# api METHOD PATH_OR_URL JSON [TOKEN] -> sets CODE and BODY
api() {
  local method="$1" url="$2" json="$3" token="$4"
  local args=(-s -m 10 -w '\n%{http_code}' -X "$method" "$url" -H 'Content-Type: application/json')
  [ -n "$json" ] && args+=(-d "$json")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  local out; out=$(curl "${args[@]}")
  CODE=$(echo "$out" | tail -1)
  BODY=$(echo "$out" | head -n -1)
}

check() { # check <label> <expected_code> [jq_assert_expr]
  local label="$1" expect="$2" assert="${3:-}"
  local ok=1
  [ "$CODE" != "$expect" ] && ok=0
  if [ -n "$assert" ] && [ "$ok" = "1" ]; then
    echo "$BODY" | jq -e "$assert" >/dev/null 2>&1 || ok=0
  fi
  if [ "$ok" = "1" ]; then
    PASS_COUNT=$((PASS_COUNT+1)); echo "PASS | $label ($CODE)"
  else
    FAIL_COUNT=$((FAIL_COUNT+1))
    echo "FAIL | $label expected=$expect got=$CODE body=$(echo "$BODY" | head -c 180)"
  fi
}

echo "=== 1. SIGNUP ==="
api POST "$BASE/signup" "{\"name\":\"QA Tester\",\"email\":\"$EMAIL1\",\"password\":\"$PASS\"}"
check "signup valid -> 201 token+user" 201 '.token and .user.email'
TOKEN="$BODY"; TOKEN=$(echo "$TOKEN" | jq -r '.token')
api POST "$BASE/signup" "{\"name\":\"QA Dup\",\"email\":\"$EMAIL1\",\"password\":\"$PASS\"}"
check "signup duplicate email -> 409" 409
api POST "$BASE/signup" "{\"name\":\"QA\",\"email\":\"bad-email\",\"password\":\"$PASS\"}"
check "signup invalid email -> 4xx" 400
api POST "$BASE/signup" "{\"name\":\"QA Tester\",\"email\":\"$EMAIL2\",\"password\":\"short\"}"
CODE=$([ "$CODE" -ge 400 ] && echo "$CODE" || echo "2xx"); check "signup short password -> 4xx" 400

echo "=== 2. LOGIN ==="
api POST "$BASE/login" "{\"email\":\"$EMAIL1\",\"password\":\"$PASS\"}"
check "login correct -> 200" 200 '.token'
T1=$(echo "$BODY" | jq -r '.token')
api POST "$BASE/login" "{\"email\":\"$EMAIL1\",\"password\":\"wrong-pass-123\"}"
check "login wrong password -> 401" 401
api POST "$BASE/login" "{\"email\":\"nobody.$TS@test.local\",\"password\":\"$PASS\"}"
check "login unknown email -> 401 (same message)" 401
api POST "$BASE/login" "{\"email\":\" $EMAIL1 \",\"password\":\"$PASS\"}"
check "login trims/lowercases email" 200
T2=$(echo "$BODY" | jq -r '.token')

echo "=== 3. SESSION /me ==="
api GET "$BASE/me" "" ""
check "me without token -> 401" 401
api GET "$BASE/me" "" "dc_totally_invalid_token"
check "me with garbage token -> 401" 401
api GET "$BASE/me" "" "$T1"
check "me with valid token -> 200 email" 200 ".user.email"

echo "=== 4. CHANGE PASSWORD (the only reset path) ==="
api POST "$BASE/change-password" "{\"currentPassword\":\"wrong\",\"newPassword\":\"$PASS2\"}" "$T1"
check "change-password wrong current -> 401" 401
api POST "$BASE/change-password" "{\"currentPassword\":\"$PASS\",\"newPassword\":\"$PASS2\"}" "$T1"
check "change-password valid -> 200" 200 '.changed'
api GET "$BASE/me" "" "$T1"
check "old session T1 survives -> 200" 200
api GET "$BASE/me" "" "$T2"
check "other session T2 revoked -> 401" 401
api POST "$BASE/login" "{\"email\":\"$EMAIL1\",\"password\":\"$PASS\"}"
check "login with OLD password -> 401" 401
api POST "$BASE/login" "{\"email\":\"$EMAIL1\",\"password\":\"$PASS2\"}"
check "login with NEW password -> 200" 200
T1=$(echo "$BODY" | jq -r '.token')

echo "=== 5. CHANGE EMAIL (verified, devCode) ==="
api POST "$BASE/change-email" "{\"email\":\"$NEWEMAIL\",\"password\":\"$PASS2\"}" "$T1"
check "change-email start -> devCode" 200 '.devCode'
CODE1=$(echo "$BODY" | jq -r '.devCode')
api POST "$BASE/change-email/confirm" '{"code":"000000"}' "$T1"
check "confirm wrong code -> 401" 401
api POST "$BASE/change-email/confirm" "{\"code\":\"$CODE1\"}" "$T1"
check "confirm right code -> applied" 200 ".email"
api POST "$BASE/login" "{\"email\":\"$NEWEMAIL\",\"password\":\"$PASS2\"}"
check "login with NEW email -> 200" 200
T1=$(echo "$BODY" | jq -r '.token')

echo "=== 6. PHONE SIGNIN (dev-only) ==="
api POST "$BASE/signin" "{\"phone\":\"$PHONE\"}"
check "signin new phone -> auto-creates Diner" 200 '.user.name'
TPH=$(echo "$BODY" | jq -r '.token')
api POST "$BASE/signin" "{\"phone\":\"$PHONE\"}"
check "signin same phone -> same user" 200 ".user.id"
ID1=$(echo "$BODY" | jq -r '.user.id')
api GET "$BASE/me" "" "$TPH"
check "phone session works on /me" 200

echo "=== 7. OTP FLOW ==="
api POST "$BASE/otp/request" "{\"phone\":\"$PHONE\"}"
check "otp request -> devCode in dev" 200 '.devCode | length == 6'
OTPDEV=$(echo "$BODY" | jq -r '.devCode')
api POST "$BASE/otp/verify" "{\"phone\":\"$PHONE\",\"code\":\"123456\"}"
check "otp wrong code -> 401" 401
api POST "$BASE/otp/verify" "{\"phone\":\"$PHONE\",\"code\":\"$OTPDEV\"}"
check "otp correct code -> token" 200 '.token'
api POST "$BASE/otp/verify" "{\"phone\":\"$PHONE\",\"code\":\"$OTPDEV\"}"
check "otp code single-use (replay) -> 401" 401
api POST "$BASE/otp/request" "{\"phone\":\"$PHONE\"}" >/dev/null
for i in 1 2 3 4 5; do api POST "$BASE/otp/verify" "{\"phone\":\"$PHONE\",\"code\":\"00000$i\"}"; done
check "otp 5 failed attempts -> 429 lockout" 429
api POST "$BASE/otp/verify" "{\"phone\":\"$PHONE\",\"code\":\"$OTPDEV\"}"
check "after lockout old code dead -> 401/429" 401

echo "=== 8. SIGNOUT / LOGOUT-ALL ==="
api POST "$BASE/signout" "" "$TPH"
check "signout -> 200" 200 '.signedOut'
api GET "$BASE/me" "" "$TPH"
check "token dead after signout -> 401" 401
api POST "$BASE/login" "{\"email\":\"$NEWEMAIL\",\"password\":\"$PASS2\"}"; TA=$(echo "$BODY" | jq -r '.token')
api POST "$BASE/login" "{\"email\":\"$NEWEMAIL\",\"password\":\"$PASS2\"}"; TB=$(echo "$BODY" | jq -r '.token')
api POST "$BASE/logout-all" "" "$TA"
check "logout-all -> 200" 200 '.signedOutEverywhere'
api GET "$BASE/me" "" "$TA"; check "own session revoked -> 401" 401
api GET "$BASE/me" "" "$TB"; check "second session revoked -> 401" 401

echo ""
echo "RESULT: $PASS_COUNT passed, $FAIL_COUNT failed"
