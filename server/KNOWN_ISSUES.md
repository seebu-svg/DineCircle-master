# Known issues — DineCircle backend

This file records defects and gaps that are **acknowledged but not yet
fixed**. Each entry carries a severity tag, the code location, the impact,
and any compensating controls that are in place today. Items here are
reviewed at every security audit; do not use it as a TODO list for new
work — open a plan task instead.

---

## ~~H1 · Socket.IO chat bypasses block list and is never persisted~~ — FIXED

**Resolved:** The `chat_message` handler now calls `isBlockedPair` before
broadcasting, persists the message to `chat_messages` (linked via the
`conversations` table), and returns a `message_ack` to the sender with the
persisted message ID. New conversation-scoped events (`join_conversation`,
`typing_start/stop`, `message_read`) are also authenticated via
`canAccessConversation`.

---

## M6 · Audit log is best-effort and swallows its own failures

**Severity:** Medium
**Location:** `server/src/security.ts` (`auditLog` middleware, ~L105–140)

**What is wrong:**

1. The middleware monkey-patches `(res as any).end` and fires an
   un-awaited `INSERT INTO audit_log`. If the insert fails (for example,
   the table is missing, or the connection pool is exhausted) the error
   is logged to stderr and the response is still sent — so audit data can
   be silently lost.
2. The `resource` column is filled with `req.path`, which includes
   path parameters (`/api/events/abc-123/...`). That makes grouping by
   endpoint awkward and leaks identifiers into a table that is supposed
   to be privacy-safe.
3. The `redactForAudit` helper uses an **exact-match** Set. A request
   body with `{ "passwordResetToken": "..." }` would pass through
   unredacted because only `"token"` is in the set.

**Compensating controls:**

- The audit table is append-only and not read by any application code
  path today — it is a forensic aid. Losing a row is therefore not a
  functional regression.
- `redactForAudit` is conservative: it redacts every field name that
  matches the known sensitive keys, which covers all current request
  shapes.

**Fix path (not scheduled):**

- Replace the `res.end` monkey-patch with `res.on('finish', ...)`, which
  is the documented Express hook for post-response work.
- Store `resource` as the matched route pattern (`req.route?.path`)
  instead of the raw URL.
- Switch `redactForAudit` to a predicate (`key => /password|token|secret|code/i.test(key)`).
