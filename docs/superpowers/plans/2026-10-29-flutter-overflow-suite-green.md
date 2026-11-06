# Flutter Responsive-Layout Suite Green Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take `flutter test` from 55 failures to 0 by fixing the 10 real layout defects behind them, deleting the 45 duplicate matrix cases that fail only because they mount bottom sheets without a Material ancestor, and adding proof for the booked-pass variant that currently escapes the matrix.

**Architecture:** Two changes of different kinds. (1) Test-harness correction: `layout_overflow_extended_test.dart` mounts three bottom sheets as `MaterialApp.home`, so `TextField`/`RadioListTile` throw "No Material widget found" — no overflow is involved. That duplication is already covered properly, through the real `show*Sheet()` hosts, in `layout_overflow_sheets_test.dart`, so the duplicate groups are removed rather than re-implemented. (2) Widget fixes at the four sites that genuinely overflow: two non-scrollable `Column`s inside `isScrollControlled` sheets need `SingleChildScrollView`; two `Row`s need their unbounded children made flexible (`Flexible` + ellipsis for text, `FittedBox(scaleDown)` for the currency label so a price degrades by scaling, not truncation).

**Tech Stack:** Flutter 3.47.5 / Dart, `flutter_test` widget tests, Riverpod overrides via `test/fake_repositories.dart`, shared harness `test/support/overflow_harness.dart`. No new dependencies.

**Spec:** `PARTNER_READINESS_AUDIT.md` §6.2 (test status) and §8 item 1 (release blocker), plus §8 "Recommended next steps" item 1 which names the six widgets.

## Global Constraints

- The audit matrix must not be weakened: widths `320/360/390/430/600` and text scales `1.0x/1.3x/2.0x` stay exactly as they are; `kAuditWidths` / `kAuditTextScales` in `test/support/overflow_harness.dart` must not be edited.
- Never make a test pass by tolerating overflow, by wrapping content in `ClipRect`/`OverflowBox`, or by introducing fixed heights. Content must stay reachable: scroll it, ellipsize it, or scale it down.
- The only deletion of test cases allowed is Task 1's three duplicate sheet groups, and it is only allowed because the identical 15-case matrix for those three sheets already runs against the real modal host in `test/layout_overflow_sheets_test.dart`.
- Do not add `Flexible`/`Expanded` inside a `Row`/`Column` that is not its direct parent, and do not put a flex widget inside a context with unbounded height — both are hard `ParentDataWidget`/`RenderFlex` failures.
- Existing sheet convention to copy: `SingleChildScrollView(padding: EdgeInsets.all(AppSpacing.lg), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, ...))`.
- `flutter analyze` must stay clean (it is currently clean).
- Match surrounding style: 2-space indent, trailing commas, `AppSpacing` constants instead of literal numbers, `//` comments in the same voice as the file.
- All commands run from the repo root `/home/h4til3fishnix/Desktop/DinCircle`.

---

## Baseline evidence (measured, not assumed)

`flutter test test/layout_overflow_extended_test.dart test/layout_overflow_sheets_test.dart` → **471 pass / 55 fail** (526 cases).

| Bucket | Cases | Real cause | Real defect? |
|---|---|---|---|
| `ChangePasswordSheet` (extended) | 15 | `No Material widget found` — `TextField` mounted bare via `MaterialApp.home` | no |
| `ChangeEmailSheet` (extended) | 15 | same (`TextField`) | no |
| `ReportSheet` (extended) | 15 | same (`RadioListTile`) | no |
| `BookingConfirmedScreen` (extended) | 3 (`320/360/390px × 2.0x`) | `Row` at `booking_confirmed_screen.dart:97`, "overflowed by 99 pixels on the right" | yes |
| `MyTablesScreen` (extended) | 1 (`320px × 2.0x`) | `Row` at `my_tables_screen.dart:165`, 28px right | yes |
| `EditProfileSheet` (sheets) | 4 | `Column` at `edit_profile_sheet.dart:111`, 20px (320×2.0) up to 320px (keyboard at 320×2.0) bottom | yes |
| `BookingCheckInSheet` (sheets) | 2 | `Column` at `booking_check_in_sheet.dart:83`, 107px / 27px bottom | yes |

The 45 "No Material" cases are not layout failures: the same three sheets pass all 15 matrix cases **plus** the keyboard cases in `layout_overflow_sheets_test.dart`, which opens them through `showChangePasswordSheet` / `showChangeEmailSheet` / `ReportSheet.show`.

Extra evidence gathered while planning (throwaway probe, now deleted): `BookingConfirmedScreen` **with** a booking (`_PassPreviewCard`) overflows at every width and scale — 119px at 320×1.0, 209px at 320×1.3, 80px + 419px at 320×2.0. The matrix only ever mounts the `booking == null` fallback, which is why that defect was invisible. Task 6 closes it.

---

## File Structure

| File | Responsibility in this plan |
|---|---|
| `test/layout_overflow_extended_test.dart` | screen matrix; loses 3 duplicate sheet groups (Task 1), gains a booked-pass card entry (Task 6) |
| `lib/widgets/edit_profile_sheet.dart` | sheet body becomes scrollable (Task 2) |
| `lib/widgets/booking_check_in_sheet.dart` | sheet card becomes scrollable (Task 3) |
| `lib/screens/booking_confirmed/booking_confirmed_screen.dart` | fallback pass-badge row (Task 4) + `_PassPreviewCard` header/hint rows (Task 6) |
| `lib/screens/tables/my_tables_screen.dart` | date/time/price row (Task 5) |
| `PARTNER_READINESS_AUDIT.md`, `OVERFLOW_AUDIT_REPORT.md` | record the verified result (Task 7) |

---

### Task 1: Remove the duplicate bare-mounted sheet matrices

**Files:**
- Modify: `test/layout_overflow_extended_test.dart:39-41` (imports), `:176`, `:178-182`, `:233-241`

**Interfaces:**
- Consumes: nothing.
- Produces: an extended harness whose every remaining case renders a screen (never a bare sheet). After this task the file reports exactly 4 failures — the real defects that Tasks 4 and 5 fix.

- [ ] **Step 1: Confirm the 45 cases fail for the Material reason, not for layout**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "ChangeEmailSheet 390px" --reporter expanded 2>&1 | head -20`
Expected: `No Material widget found.`, `TextField-[<'newEmailField'>]`, and **no** `RenderFlex overflowed` line.

- [ ] **Step 2: Delete the three duplicate groups and their now-unused imports**

Remove these lines from `test/layout_overflow_extended_test.dart`:

```dart
  runMatrix('ChangePasswordSheet', const ChangePasswordSheet(), [signedIn()]);

  runMatrix(
    'ChangeEmailSheet',
    const ChangeEmailSheet(currentEmail: 'test@example.com'),
    [signedIn()],
  );
```

```dart
  runMatrix(
    'ReportSheet',
    const ReportSheet(targetType: ReportTargetType.user, targetId: 'u1'),
    [
      signedIn(),
      safetyRepositoryProvider.overrideWithValue(fakeSafety),
      myReportsProvider.overrideWith((ref) async => const []),
    ],
  );
```

Remove the three imports that only these groups used:

```dart
import 'package:dine_circle/screens/safety/report_sheet.dart';
import 'package:dine_circle/screens/settings/change_email_sheet.dart';
import 'package:dine_circle/screens/settings/change_password_sheet.dart';
```

Keep `models/safety.dart` (the `fakeSafety` fixture uses `ReportReason`, `ReportItem`, `ReportTargetType`, `ReportStatus`).

- [ ] **Step 3: Document why they are gone**

Add this comment where the `ReportSheet` group used to be, directly after the `FeedbackFormScreen` matrix:

```dart
  // ReportSheet, ChangeEmailSheet and ChangePasswordSheet are intentionally
  // absent here: they are bottom sheets, not screens, and mounting them as
  // `MaterialApp.home` has no Material ancestor, so TextField/RadioListTile
  // throw "No Material widget found" instead of reporting a layout defect.
  // They run the same 5 widths x 3 scales matrix — plus keyboard-insert cases —
  // through their real `show*Sheet()` hosts in layout_overflow_sheets_test.dart.
```

- [ ] **Step 4: Run the file and count the remainder**

Run: `flutter test test/layout_overflow_extended_test.dart`
Expected: `375` cases, `371` pass, **4** fail, and the four failures are `BookingConfirmedScreen 320/360/390px × 2.0x` and `MyTablesScreen 320px × 2.0x`.

- [ ] **Step 5: Commit**

```bash
git add test/layout_overflow_extended_test.dart
git commit -m "test: drop bare-mounted sheet matrices duplicated by the sheets harness"
```

---

### Task 2: Make `EditProfileSheet` scrollable

**Files:**
- Modify: `lib/widgets/edit_profile_sheet.dart:107-153`

**Interfaces:**
- Consumes: `AppSpacing.lg`, `AppTextStyles.titleLarge` (already imported).
- Produces: `EditProfileSheet.build` returns a scroll view instead of a bare `Padding`; its children, keys and behaviour are unchanged.

- [ ] **Step 1: Reproduce**

Run: `flutter test test/layout_overflow_sheets_test.dart --plain-name "EditProfileSheet"`
Expected: 4 failures —
`Sheet — EditProfileSheet 320px × 2.0x`,
`Sheet + keyboard — EditProfileSheet 320px × 1.0x + keyboard`,
`Sheet + keyboard — EditProfileSheet 320px × 2.0x + keyboard`,
`Sheet + keyboard — EditProfileSheet 390px × 2.0x + keyboard`,
each reporting `A RenderFlex overflowed by N pixels on the bottom` with creator `Column ← Padding ← EditProfileSheet`.

- [ ] **Step 2: Replace the root `Padding` with a scroll view**

```dart
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
```

Leave the whole children list (title, three `TextField`s, error text, `PrimaryButton`, trailing `SizedBox`) exactly as it is, and delete only the old closing `),` that belonged to the removed `Padding` so the braces balance. The file must end up as `SingleChildScrollView( padding: ..., child: Column( ... ), )`.

- [ ] **Step 3: Verify**

Run: `flutter test test/layout_overflow_sheets_test.dart --plain-name "EditProfileSheet"`
Expected: PASS, 19 cases (15 matrix + 4 keyboard).

- [ ] **Step 4: Verify the sheet tests that share the file are still green**

Run: `flutter test test/layout_overflow_sheets_test.dart`
Expected: `104` pass, `2` fail — the two remaining failures are `Sheet — BookingCheckInSheet 320px × 2.0x` and `360px × 2.0x` (Task 3).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/edit_profile_sheet.dart
git commit -m "fix(ui): make the edit-profile sheet scroll instead of overflowing"
```

---

### Task 3: Make `BookingCheckInSheet` scrollable

**Files:**
- Modify: `lib/widgets/booking_check_in_sheet.dart:74-169`

**Interfaces:**
- Consumes: `AppSpacing.md`, `AppSpacing.lg` (already imported).
- Produces: `_CheckInSheet.build` wraps the rounded card in a scroll view; the card, QR, reference text and check-in button are untouched.

- [ ] **Step 1: Reproduce**

Run: `flutter test test/layout_overflow_sheets_test.dart --plain-name "BookingCheckInSheet"`
Expected: 2 failures, `A RenderFlex overflowed by 107 pixels on the bottom` at 320×2.0 and `27 pixels` at 360×2.0, creator `Column ← Padding ← DecoratedBox ← Container ← Padding ← MediaQuery ← Padding ← SafeArea ← _CheckInSheet`, constraints `0.0<=h<=560.0` / `<=640.0`.

- [ ] **Step 2: Wrap the card in a scroll view**

Change the outer `Padding` into a `SingleChildScrollView` with the same inset, keeping the `SafeArea` and `Container`:

```dart
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
```

Everything inside the `Column` (title, restaurant, `QrCodeView(data: reference, size: 180)`, reference text, hint, and the `alreadyUsed`/`FilledButton.icon` block) stays byte-identical, and the closing brackets are adjusted by one level for the new nesting.

- [ ] **Step 3: Verify**

Run: `flutter test test/layout_overflow_sheets_test.dart`
Expected: PASS — `106` pass, 0 fail.

- [ ] **Step 4: Commit**

```bash
git add lib/widgets/booking_check_in_sheet.dart
git commit -m "fix(ui): keep the check-in pass reachable on 2x text scale by scrolling"
```

---

### Task 4: Let the fallback pass-badge row shrink

**Files:**
- Modify: `lib/screens/booking_confirmed/booking_confirmed_screen.dart:97-133`

**Interfaces:**
- Consumes: nothing new; `AppSpacing.sm`, `AppColors.primaryGradient`, `AppTextStyles.labelSmall`, `AppTextStyles.caption` already imported.
- Produces: the `booking == null` pass card header row no longer requires a minimum width.

- [ ] **Step 1: Reproduce**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "BookingConfirmedScreen"`
Expected: 3 failures (`320px × 2.0x`, `360px × 2.0x`, `390px × 2.0x`), each `A RenderFlex overflowed by N pixels on the right` (99 / 59 / 29) with creator `Row` at `booking_confirmed_screen.dart:97`.

- [ ] **Step 2: Make the badge flexible**

The badge is a `Text` with `maxLines: 1` + ellipsis inside a non-flex `Row` child, so the ellipsis can never engage: the `Row` measures it with unbounded width. Wrap the badge `Container` in `Flexible` and add `softWrap: false`:

```dart
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(
                                AppSpacing.radiusSm,
                              ),
                            ),
                            child: Text(
                              'DINECIRCLE PASS',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Flexible(
                          child: Text(
                            bookingId,
                            style: AppTextStyles.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
```

The two `Flexible`s split the row 50/50 (`flex: 1` each), so at 320px/2.0x each gets 112px (232px of card content minus the 8px gap) and both labels ellipsize instead of painting a striped bar.

- [ ] **Step 3: Verify**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "BookingConfirmedScreen"`
Expected: PASS, 15 cases.

- [ ] **Step 4: Confirm the only remaining failure is MyTablesScreen**

Run: `flutter test test/layout_overflow_extended_test.dart`
Expected: `374` pass, **1** fail (`Overflow — MyTablesScreen 320px × 2.0x`).

- [ ] **Step 5: Commit**

```bash
git add lib/screens/booking_confirmed/booking_confirmed_screen.dart
git commit -m "fix(ui): ellipsize the pass badge instead of overflowing its row"
```

---

### Task 5: Rebalance the `MyTablesScreen` date/time/price row

**Files:**
- Modify: `lib/screens/tables/my_tables_screen.dart:160-209`

**Interfaces:**
- Consumes: nothing new; `AppSpacing.xs/sm/md`, `AppColors.textSecondary/primary`, `AppTextStyles.labelSmall/titleSmall` already imported.
- Produces: the meta row keeps date+time on the left and the price flush right, with a hard width budget for both instead of "price takes whatever it wants".

- [ ] **Step 1: Reproduce**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "MyTablesScreen"`
Expected: 1 failure, `A RenderFlex overflowed by 28 pixels on the right`, creator `Row` at `my_tables_screen.dart:165`.

Why: the price `Text` is a non-flex child, so the `Row` gives it its full intrinsic width (≈212px at 2.0x) and the `Expanded` group is left with ~28px, while the two fixed icons plus three `SizedBox` gaps inside it need 56px — the flex children cannot go below that floor.

- [ ] **Step 2: Give both sides a flex budget**

Replace the whole second `Row` (the one starting `Row(children: [ // Date + time share one flexible group…`) with:

```dart
              Row(
                children: [
                  // Date + time share a 3:1 budget with the price. The price
                  // scales down instead of truncating, so currency never
                  // becomes unreadable at accessibility text sizes.
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_rounded,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            booking.dinner.formattedDate,
                            style: AppTextStyles.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        const Icon(
                          Icons.access_time_rounded,
                          color: AppColors.textSecondary,
                          size: 16,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            booking.dinner.formattedTime,
                            style: AppTextStyles.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '\$${booking.totalAmount.toStringAsFixed(2)}',
                          style: AppTextStyles.titleSmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
```

Arithmetic to expect: at 320px the card gives the row 248px; after the 8px gap the flex space is 240px, split 180/60. The left group's floor is 56px of icons+gaps, well under 180px, so its texts ellipsize rather than overflow; the price (≈212px intrinsic at 2.0x) is scaled down into 60px by `FittedBox` and right-aligned at the row edge by `Align`. `FittedBox` only ever scales *down*, so at 1.0x the price keeps its natural size.

- [ ] **Step 3: Verify**

Run: `flutter test test/layout_overflow_extended_test.dart`
Expected: PASS — `375` pass, 0 fail.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/tables/my_tables_screen.dart
git commit -m "fix(ui): budget the table-card meta row so the price cannot starve it"
```

---

### Task 6: Cover and fix the booked-pass card

**Files:**
- Modify: `test/layout_overflow_extended_test.dart` (add one matrix entry after the existing `BookingConfirmedScreen` entry, near line 155)
- Modify: `lib/screens/booking_confirmed/booking_confirmed_screen.dart:364-391` (header row) and `:446-463` (tap hint)

**Interfaces:**
- Consumes: `fixtureBooking({required Dinner dinner, required UserProfile user, ...})` and `fixtureHost(id:, name:)` from `test/fake_repositories.dart` (already imported by the test file).
- Produces: a `BookingConfirmedScreen (pass card)` matrix group of 15 cases that renders `_PassPreviewCard`.

- [ ] **Step 1: Add the missing matrix entry**

Directly after the existing `runMatrix('BookingConfirmedScreen', BookingConfirmedScreen(dinner: fixtureDinner()), [signedIn()]);` block, add:

```dart
  // The booked variant renders _PassPreviewCard instead of the fallback card.
  // It was never exercised, which is how two Rows in that card kept
  // overflowing at every width and text scale.
  final passDinner = fixtureDinner();
  runMatrix(
    'BookingConfirmedScreen (pass card)',
    BookingConfirmedScreen(
      dinner: passDinner,
      booking: fixtureBooking(
        dinner: passDinner,
        user: fixtureHost(id: 'me', name: 'Me'),
      ),
    ),
    [signedIn()],
  );
```

- [ ] **Step 2: Run it and record the failure**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "pass card"`
Expected: 15 failures. Two creators repeat: `Row` at the pass header (`'DINECIRCLE PASS'` badge + `Spacer` + QR icon) and `Row` at the tap hint (`'Tap to view check-in code'`), e.g. `overflowed by 119 pixels on the right` at 320×1.0.

- [ ] **Step 3: Make the header badge flexible**

Inside `_PassPreviewCard.build`, wrap the gradient badge `Container` in `Flexible` (the `Spacer` keeps the QR icon pinned right) and let the label ellipsize:

```dart
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(
                      'DINECIRCLE PASS',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 9,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.qr_code_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
```

- [ ] **Step 4: Make the tap hint shrink**

Wrap the hint label in `Flexible`:

```dart
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.open_in_full_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(
                    child: Text(
                      'Tap to view check-in code',
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
```

- [ ] **Step 5: Verify**

Run: `flutter test test/layout_overflow_extended_test.dart --plain-name "pass card"`
Expected: PASS, 15 cases.

If another `Row` in the same card is reported, apply the same two patterns and re-run: `Flexible` + `maxLines: 1` + `softWrap: false` + `overflow: TextOverflow.ellipsis` for a label, `Flexible(child: FittedBox(fit: BoxFit.scaleDown, ...))` for a number or badge that must stay whole. Do not clip and do not add a fixed height.

- [ ] **Step 6: Verify the whole file**

Run: `flutter test test/layout_overflow_extended_test.dart`
Expected: PASS — `390` pass, 0 fail.

- [ ] **Step 7: Commit**

```bash
git add test/layout_overflow_extended_test.dart lib/screens/booking_confirmed/booking_confirmed_screen.dart
git commit -m "fix(ui): cover the booked pass card and stop its two rows overflowing"
```

---

### Task 7: Full verification and audit record

**Files:**
- Modify: `PARTNER_READINESS_AUDIT.md` (§1 verification table row, §6.2, §8 item 1, §8 recommended step 1)
- Modify: `OVERFLOW_AUDIT_REPORT.md` (executive summary, which still claims "Zero overflow defects" and "283 tests passing")

**Interfaces:**
- Consumes: the pass/fail counts printed by Steps 1-2.
- Produces: no code; the audit documents stop overstating the UI state.

- [ ] **Step 1: Static analysis**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: Full suite**

Run: `flutter test`
Expected: **0 failures**. Expect ≈`924` cases — `954` at baseline, minus the 45 duplicate sheet cases removed in Task 1, plus the 15 booked-pass cases added in Task 6. Record the exact printed count; do not edit docs with a guess.

- [ ] **Step 3: Rewrite §6.2 of `PARTNER_READINESS_AUDIT.md`**

Replace the whole "### 6.2 Customer App test status" section with:

```markdown
### 6.2 Customer App test status

`flutter analyze` → clean. `flutter test` → **<N> pass / 0 fail**.

The 55 failures recorded in the first draft of this audit were two different
problems that looked alike:

| Cause | Cases | Disposition |
|---|---|---|
| `ChangePasswordSheet`, `ChangeEmailSheet`, `ReportSheet` mounted as `MaterialApp.home` | 45 | Duplicate matrix, not a layout defect — a bare sheet has no Material ancestor, so `TextField`/`RadioListTile` threw `No Material widget found`. Removed from `layout_overflow_extended_test.dart`; the same 5 widths × 3 scales matrix (plus keyboard-insert cases) runs against the real `show*Sheet()` hosts in `layout_overflow_sheets_test.dart`. |
| Real RenderFlex overflows | 10 | Fixed: two non-scrollable `Column`s in `isScrollControlled` sheets (`EditProfileSheet`, `BookingCheckInSheet`) now scroll; two `Row`s (`BookingConfirmedScreen` pass badge, `MyTablesScreen` date/time/price) now budget their width. |

While fixing those, the pass card that renders when a booking is present
(`_PassPreviewCard`) turned out to overflow at **every** width and scale,
including 1.0x — the matrix only ever mounted the no-booking fallback. The
card is fixed and now has its own 15-case matrix entry.
```

Replace `<N>` with the count from Step 2.

- [ ] **Step 4: Update the two claims that are now stale**

In `PARTNER_READINESS_AUDIT.md`:
- §1 table, row `Flutter widget tests` → `flutter test` | `<N> pass, 0 layout failures`.
- §8 list item 1 → `1. ~~55 failing Flutter layout tests.~~ **Closed** — 45 were a
  harness artifact (bare-mounted sheets), 10 were real and are fixed; the booked
  pass card gained matrix coverage it never had. See §6.2.`
- §8 "Recommended next steps", item 1 → `1. Closed: the six widgets behind the
  original 55 failures (see §6.2). Next UI follow-up is the second CI job in
  step 6.`

In `OVERFLOW_AUDIT_REPORT.md`, prepend to the Executive Summary:

```markdown
> **Superseded 2026-10-29:** this report's "zero overflow defects" and
> "283 tests passing" claims predate the extended harness
> (`layout_overflow_extended_test.dart`, `layout_overflow_sheets_test.dart`)
> actually running green. The current, verified status is in
> `PARTNER_READINESS_AUDIT.md` §6.2.
```

- [ ] **Step 5: Commit**

```bash
git add PARTNER_READINESS_AUDIT.md OVERFLOW_AUDIT_REPORT.md
git commit -m "docs: record the verified responsive-layout test status"
```

---

## Self-Review

**Spec coverage.** §6.2 named five widgets; §8 named six. Tasks 2-5 cover `ReportSheet` (by de-duplication), `ChangePasswordSheet` / `ChangeEmailSheet` (by de-duplication), `EditProfileSheet` (Task 2), `BookingCheckInSheet` (Task 3), `BookingConfirmedScreen` header row (Task 4 + Task 6), `MyTablesScreen` (Task 5). The release-blocker claim in §8 item 1 is discharged in Task 7. The audit's "Reproduced in isolation: `RenderFlex overflowed by 99 pixels on the right` at 320 px with 2.0x" is exactly the Task 4 failure, reproduced at 99px.

**Placeholder scan.** No TBD/TODO. The only `<N>` is a value the executor must read from a run, and Steps 1-2 produce it before Step 3 uses it. Task 6 Step 5 is a contingency branch, not a stub: it names the exact pattern for any additional `Row` the new matrix exposes.

**Type consistency.** `fixtureBooking(dinner:, user:)` and `fixtureHost(id:, name:)` are the signatures in `test/fake_repositories.dart:99-118` and are used identically in `layout_overflow_sheets_test.dart:62-67`. `runMatrix(String, Widget, List<Override>)` is the local helper at `layout_overflow_extended_test.dart:115`. `kAuditWidths`/`kAuditTextScales` names match `test/support/overflow_harness.dart:16-19`. All identifier names in the code snippets (`_PassPreviewCard`, `_CheckInSheet`, `AppSpacing.xs/sm/md/lg`, `AppColors.primaryGradient`) exist as written in the current files.

**Scope note.** Task 6 adds 15 cases that were not part of the original 55. It is included because the same audit section names the `BookingConfirmedSheet` header row and because that card overflows even at 1.0x — shipping "0 failures" while a real card overflows at default text size would repeat the mistake §6.2 documents. If the work must be strictly bounded to the original 55, Task 6 can be dropped without affecting Tasks 1-5 or 7 (Task 7's `<N>` becomes `909`).
