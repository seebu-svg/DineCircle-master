#!/usr/bin/env bash
# DineCircle Account & Settings (P1) backend integration test.
# Boots the real API against a freshly seeded DB and verifies P1-1..P1-8 plus
# the audit-log secret redaction. Portable to CI (env-driven).
#
# Every /api/auth route (including GET /me) sits behind a 10 req/min limiter,
# so all auth traffic goes through `a_post`/`a_get`, which pace themselves and
# retry once on a 429 instead of producing a misleading assertion failure.
set -uo pipefail
export PSQL_PAGER=cat PAGER=cat

: "${DATABASE_URL:?set DATABASE_URL to a freshly seeded DineCircle DB}"
: "${DC_PSQL:?set DC_PSQL to a psql command for that DB}"
PORT="${PORT:-4100}"
BASE="http://127.0.0.1:$PORT/api"
AUTH="$BASE/auth"
PW='password123'
NEW_PW='newpassword456'

GROUPS=0
fail() { echo "FAIL: $1" >&2; exit 1; }
ok() { GROUPS=$((GROUPS+1)); echo "  OK $1"; }
q() { $DC_PSQL -c "$1"; }
body() { cat /tmp/dc_body; }

# a_post METHOD PATH TOKEN JSON -> writes body to /tmp/dc_body, code to $CODE
a_post() {
  local method=$1 path=$2 token=$3 json=$4
  sleep 6.5
  CODE=$(curl -s -o /tmp/dc_body -w '%{http_code}' -X "$method" "$AUTH$path" \
    ${token:+-H "Authorization: Bearer $token"} -H 'content-type: application/json' -d "$json")
  if [ "$CODE" = "429" ]; then
    echo "  … auth limiter hit on $path, waiting out the window" >&2
    sleep 61
    CODE=$(curl -s -o /tmp/dc_body -w '%{http_code}' -X "$method" "$AUTH$path" \
      ${token:+-H "Authorization: Bearer $token"} -H 'content-type: application/json' -d "$json")
  fi
}
# api METHOD PATH TOKEN JSON -> non-auth routes (100/min limiter)
api() {
  local method=$1 path=$2 token=$3 json=$4
  CODE=$(curl -s -o /tmp/dc_body -w '%{http_code}' -X "$method" "$BASE$path" \
    ${token:+-H "Authorization: Bearer $token"} ${json:+-H 'content-type: application/json'} ${json:+-d "$json"})
}

npm start >/tmp/dc_p1_server.log 2>&1 &
SP=$!
trap 'kill $SP 2>/dev/null || true' EXIT
for _ in $(seq 1 60); do curl -fsS "$BASE/health" >/dev/null 2>&1 && break; sleep 0.5; done
curl -fsS "$BASE/health" >/dev/null 2>&1 || fail "server not up — see /tmp/dc_p1_server.log"
echo "server up on :$PORT"

STAMP=$(date +%s%N)

# ── P1-1 change password: confirm current, revoke other sessions ─────────────
a_post POST /signup '' "{\"name\":\"P1 Main\",\"email\":\"p1+$STAMP@example.com\",\"password\":\"$PW\"}"
[ "$CODE" = "201" ] || fail "signup P1 main (want 201 got $CODE) $(body)"
TP1=$(jq -r .token <<<"$(body)"); PEMAIL=$(jq -r .user.email <<<"$(body)"); ID_P=$(jq -r .user.id <<<"$(body)")
a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$PW\"}"
TP2=$(jq -r .token <<<"$(body)")
[ "$TP2" != "null" ] || fail "second session login"

a_post POST /change-password "$TP1" "{\"currentPassword\":\"totally-wrong\",\"newPassword\":\"$NEW_PW\"}"
[ "$CODE" = "401" ] || fail "change-password wrong current (want 401 got $CODE)"
a_post POST /change-password "$TP1" "{\"currentPassword\":\"$PW\",\"newPassword\":\"$NEW_PW\"}"
[ "$CODE" = "200" ] || fail "change-password (want 200 got $CODE) $(body)"

a_post GET /me "$TP2" ''
[ "$CODE" = "401" ] || fail "other session not revoked after password change (got $CODE)"
a_post GET /me "$TP1" ''
[ "$CODE" = "200" ] || fail "current session should survive a password change (got $CODE)"

a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "401" ] || fail "old password still authenticates (got $CODE)"
a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$NEW_PW\"}"
[ "$CODE" = "200" ] || fail "new password login (want 200 got $CODE)"
TP1=$(jq -r .token <<<"$(body)")
ok "P1-1 change password (confirm + rehash + revoke others, keep current device)"

# ── P1-2 change email: password confirm, unique check, new login handle ──────
a_post POST /signup '' "{\"name\":\"P1 Other\",\"email\":\"p1o+$STAMP@example.com\",\"password\":\"$PW\"}"
[ "$CODE" = "201" ] || fail "signup other user (got $CODE)"
TQ=$(jq -r .token <<<"$(body)"); QEMAIL=$(jq -r .user.email <<<"$(body)")

a_post POST /change-email "$TQ" "{\"email\":\"freshA+$STAMP@example.com\",\"password\":\"wrong\"}"
[ "$CODE" = "401" ] || fail "change-email bad password (want 401 got $CODE)"
a_post POST /change-email "$TQ" "{\"email\":\"$PEMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "409" ] || fail "change-email to a taken address (want 409 got $CODE)"
NEW_EMAIL="freshB+$STAMP@example.com"
a_post POST /change-email "$TQ" "{\"email\":\"$NEW_EMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "200" ] || fail "change-email (want 200 got $CODE) $(body)"
[ "$(jq -r .email <<<"$(body)")" = "$NEW_EMAIL" ] || fail "change-email response echo"
a_post POST /login '' "{\"email\":\"$NEW_EMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "200" ] || fail "login with new email (got $CODE)"
a_post POST /login '' "{\"email\":\"$QEMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "401" ] || fail "old email still resolves a session (got $CODE)"
ok "P1-2 change email (401 bad pw, 409 taken, new address is the login)"

# ── P1-3 change phone: format validation, unique, usable for signin ──────────
a_post POST /change-phone "$TQ" '{"phone":"not-a-phone","password":"'"$PW"'"}'
[ "$CODE" = "400" ] || fail "change-phone bad format (want 400 got $CODE)"
a_post POST /change-phone "$TQ" '{"phone":"+15550002222","password":"'"$PW"'"}'
[ "$CODE" = "409" ] || fail "change-phone to a claimed number (want 409 got $CODE)"
NEW_PHONE="+15559${STAMP: -7}"
a_post POST /change-phone "$TQ" "{\"phone\":\"$NEW_PHONE\",\"password\":\"$PW\"}"
[ "$CODE" = "200" ] || fail "change-phone (want 200 got $CODE) $(body)"
ID_Q=$(jq -r .user.id <<<"$(body)")
a_post POST /signin '' "{\"phone\":\"$NEW_PHONE\"}"
[ "$CODE" = "200" ] || fail "phone signin after change (want 200 got $CODE)"
[ "$(jq -r .user.id <<<"$(body)")" = "$ID_Q" ] || fail "phone signin resolved a different account"
ok "P1-3 change phone (400 format, 409 taken, persists + usable for signin)"

# ── P1-4/5/6 partial PATCH /me: a settings write must not blank other columns
api PATCH /users/me "$TP1" '{"name":"Preserve Me","city":"Karachi","bio":"legacy payload","tastes":["pasta"]}'
[ "$CODE" = "200" ] || fail "legacy full PATCH /me (want 200 got $CODE) $(body)"
api PATCH /users/me "$TP1" '{"showFollowList":false,"showActivity":false}'
[ "$CODE" = "200" ] || fail "privacy PATCH (want 200 got $CODE) $(body)"
[ "$(jq -r .user.name <<<"$(body)")" = "Preserve Me" ] \
  || fail "partial PATCH clobbered name (got $(jq -r .user.name <<<"$(body)"))"
[ "$(jq -r .user.showFollowList <<<"$(body)")" = "false" ] || fail "showFollowList not persisted"
[ "$(jq -r .user.showActivity <<<"$(body)")" = "false" ] || fail "showActivity not persisted"
api PATCH /users/me "$TP1" '{"dietary":["halal","vegetarian"],"allergies":["peanuts"],"homeArea":"DHA Phase 6"}'
[ "$CODE" = "200" ] || fail "prefs PATCH (want 200 got $CODE) $(body)"
[ "$(jq -r '.user.dietary | sort | join(",")' <<<"$(body)")" = "halal,vegetarian" ] || fail "dietary not persisted"
[ "$(jq -r '.user.allergies[0]' <<<"$(body)")" = "peanuts" ] || fail "allergies not persisted"
[ "$(jq -r .user.homeArea <<<"$(body)")" = "DHA Phase 6" ] || fail "homeArea not persisted"
api PATCH /users/me "$TP1" '{"dietary":["a","b","c","d","e","f","g","h","i","j","k","l","m"]}'
[ "$CODE" = "400" ] || fail "dietary list over cap should be refused (want 400 got $CODE)"
a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$NEW_PW\"}"
[ "$CODE" = "200" ] || fail "re-login for prefs check (got $CODE)"
[ "$(jq -r '.user.dietary | length' <<<"$(body)")" = "2" ] || fail "dietary did not survive re-login"
[ "$(jq -r .user.email <<<"$(body)")" = "$PEMAIL" ] || fail "email missing from the session shape"
TP1=$(jq -r .token <<<"$(body)")
ok "P1-4/5/6 partial PATCH (no clobber, persisted, validated, survives re-login)"

# ── P1-4 enforcement: private connections + hidden activity ──────────────────
api GET "/users/$ID_P/followers" "$TQ" ''
[ "$CODE" = "403" ] || fail "showFollowList=false should 403 another user (got $CODE)"
api GET "/users/$ID_P/followers" "$TP1" ''
[ "$CODE" = "200" ] || fail "owner must still see their own lists (got $CODE)"

NORA=22222222-2222-2222-2222-222222222222
api GET "/users/$NORA" "$TQ" ''
BEFORE=$(jq -r '.hostedUpcoming | length' <<<"$(body)")
[ "${BEFORE:-0}" -gt 0 ] || fail "seeded host should have upcoming events to hide (got $BEFORE)"
q "UPDATE users SET show_activity = false WHERE id = '$NORA';" >/dev/null
api GET "/users/$NORA" "$TQ" ''
AFTER=$(jq -r '.hostedUpcoming | length' <<<"$(body)")
a_post POST /signin '' '{"phone":"+15550002222"}'
TN=$(jq -r .token <<<"$(body)")
api GET "/users/$NORA" "$TN" ''
OWNERVIEW=$(jq -r '.hostedUpcoming | length' <<<"$(body)")
q "UPDATE users SET show_activity = true WHERE id = '$NORA';" >/dev/null
[ "$AFTER" = "0" ] || fail "show_activity=false did not hide hosted events (got $AFTER)"
[ "$OWNERVIEW" = "$BEFORE" ] || fail "owner lost their own activity view ($OWNERVIEW vs $BEFORE)"
ok "P1-4 privacy enforced (403 private connections, hidden activity, owner unaffected)"

# ── P1-8 logout-all: every session dies, including the caller's ──────────────
a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$NEW_PW\"}"
SA=$(jq -r .token <<<"$(body)")
a_post POST /login '' "{\"email\":\"$PEMAIL\",\"password\":\"$NEW_PW\"}"
SB=$(jq -r .token <<<"$(body)")
[ "$SA" != "$SB" ] || fail "two logins produced the same token"
a_post POST /logout-all "$SA" ''
[ "$CODE" = "200" ] || fail "logout-all (want 200 got $CODE) $(body)"
a_post GET /me "$SA" ''
[ "$CODE" = "401" ] || fail "caller token survived logout-all (got $CODE)"
a_post GET /me "$SB" ''
[ "$CODE" = "401" ] || fail "other device survived logout-all (got $CODE)"
ok "P1-8 logout-all (both sessions revoked immediately)"

# ── P1-7 delete account: confirm, anonymise, refund, preserve records ────────
E2=eeeeeeee-eeee-eeee-eeee-eeeeeeeeeee2
a_post POST /signup '' "{\"name\":\"Doomed Diner\",\"email\":\"p1d+$STAMP@example.com\",\"password\":\"$PW\"}"
[ "$CODE" = "201" ] || fail "signup doomed diner (got $CODE)"
TD=$(jq -r .token <<<"$(body)"); ID_D=$(jq -r .user.id <<<"$(body)"); DEMAIL=$(jq -r .user.email <<<"$(body)")
SEATS0=$(q "SELECT seats_booked FROM dinner_events WHERE id='$E2';")
api POST "/events/$E2/bookings" "$TD" '{"seats":2}'
BKD=$(jq -r .booking.id <<<"$(body)")
[ "$CODE" = "201" ] && [ "$BKD" != "null" ] || fail "doomed diner booking (got $CODE) $(body)"
SEATS1=$(q "SELECT seats_booked FROM dinner_events WHERE id='$E2';")
[ "$SEATS1" = "$((SEATS0 + 2))" ] || fail "seats not held after booking ($SEATS0 -> $SEATS1)"

api DELETE /users/me "$TD" '{"password":"nope"}'
[ "$CODE" = "401" ] || fail "delete with bad password (want 401 got $CODE)"
api DELETE /users/me "$TD" "{\"password\":\"$PW\"}"
[ "$CODE" = "200" ] || fail "delete account (want 200 got $CODE) $(body)"
a_post GET /me "$TD" ''
[ "$CODE" = "401" ] || fail "token survived account deletion (got $CODE)"
a_post POST /login '' "{\"email\":\"$DEMAIL\",\"password\":\"$PW\"}"
[ "$CODE" = "401" ] || fail "deleted credentials still log in (got $CODE)"

[ "$(q "SELECT is_deleted FROM users WHERE id='$ID_D';")" = "t" ] || fail "is_deleted not set"
[ "$(q "SELECT name FROM users WHERE id='$ID_D';")" = "Deleted user" ] || fail "name not anonymised"
[ "$(q "SELECT coalesce(email,'NULL') FROM users WHERE id='$ID_D';")" = "NULL" ] || fail "email not erased"
[ "$(q "SELECT coalesce(phone,'NULL') FROM users WHERE id='$ID_D';")" = "NULL" ] || fail "phone not erased"
[ "$(q "SELECT coalesce(password_hash,'NULL') FROM users WHERE id='$ID_D';")" = "NULL" ] || fail "password not erased"
[ "$(q "SELECT status||'/'||payment_status FROM bookings WHERE id='$BKD';")" = "cancelled/refunded" ] \
  || fail "departed guest ticket not refunded (got $(q "SELECT status||'/'||payment_status FROM bookings WHERE id='$BKD';"))"
[ "$(q "SELECT seats_booked FROM dinner_events WHERE id='$E2';")" = "$SEATS0" ] \
  || fail "seat not released on deletion ($SEATS1 -> $(q "SELECT seats_booked FROM dinner_events WHERE id='$E2';"))"
[ "$(q "SELECT count(*) FROM bookings WHERE user_id='$ID_D';")" -gt 0 ] \
  || fail "bookings were cascade-erased — existing records must be preserved"
ok "P1-7 delete account (401 confirm, anonymise, refund + release seat, history preserved)"

# ── Security: the audit trail must never record a plaintext secret ───────────
LEAKY=$(q "SELECT count(*) FROM audit_log WHERE changes::text LIKE '%\"$PW\"%' OR changes::text LIKE '%\"$NEW_PW\"%';")
[ "$LEAKY" = "0" ] || fail "audit_log holds $LEAKY plaintext password(s)"
[ "$(q "SELECT count(*) FROM audit_log WHERE changes::text LIKE '%redacted%';")" -gt 0 ] \
  || fail "audit_log redaction never fired"
ok "security: audit_log redacts passwords (0 plaintext leaks, [redacted] present)"

echo "ALL ACCOUNT & SETTINGS (P1) CHECKS PASSED ($GROUPS groups)"
