# DineCircle — Global Overflow Audit Report

> **Superseded 2026-10-29.** The counts below were accurate for the 10 core
> screens only; `layout_overflow_extended_test.dart` had never been run green and
> was in fact failing 49 cases, with 6 more in the sheets harness. All 55 are now
> fixed and the full suite is 979 pass / 0 fail. See §6.2 of
> `PARTNER_READINESS_AUDIT.md` for the current status and root causes; treat this
> file as a historical record, not a verification result.

**Date:** 2026-10-29  
**Auditor:** Senior Flutter Engineer  
**Scope:** Full app responsive layout audit across all screens

---

## Executive Summary

✅ **Zero overflow defects** across 10 major screens at 5 device widths (320, 360, 390, 430, 600px) and 3 text scales (1.0x, 1.3x, 2.0x).  
✅ **283 tests passing** (133 existing + 150 new overflow detection tests).  
✅ **flutter analyze** clean — no warnings or errors.  
✅ **Shared responsive helpers** established for future development.

---

## Phase 1: Evidence-Based Detection

### Test Harness Created
**File:** `test/layout_overflow_test.dart`

- Parameterized matrix: 10 screens × 5 widths × 3 text scales = **150 test cases**
- Captures `RenderFlex overflowed` errors via `FlutterError.onError`
- Treats overflow as **test failure** (unlike existing tests that swallow them)
- Covers: HomeScreen, BookingsScreen, DinnerDetailScreen, CreateDinnerScreen, ExploreScreen, ProfileScreen, SavedScreen, NotificationsScreen, HostDashboardScreen, PeopleScreen

### Initial Findings
**60 overflow defects** detected across 7 screens:
- BookingsScreen: 12 failures
- CreateDinnerScreen: 11 failures
- DinnerDetailScreen: 11 failures
- ProfileScreen: 12 failures
- HostDashboardScreen: 9 failures
- NotificationsScreen: 3 failures
- HomeScreen: 2 failures

---

## Phase 2: Shared Responsive Helpers

**File:** `lib/theme/app_layout.dart`

Created reusable responsive widgets:

1. **ResponsiveText** — Auto-truncating text with ellipsis
2. **SafeRow** — Row that wraps dynamic children in Flexible
3. **SafeColumn** — Column with optional Flexible last child
4. **Breakpoint** — Utility for compact/medium/expanded breakpoints
5. **ChipWrap** — Wrap widget for chip/tag collections

These helpers establish consistent patterns to prevent future overflow defects.

---

## Phase 3: Screen-by-Screen Fixes

### Files Modified

#### 1. `lib/widgets/buttons.dart`
**Issue:** PrimaryButton and SecondaryButton Row overflows  
**Fix:** Wrapped Text in Flexible with maxLines + ellipsis

#### 2. `lib/screens/detail/dinner_detail_screen.dart`
**Issues:** 4 Row overflows (lines 667, 711, 832, 1358)  
**Fixes:**
- Line 667: Wrapped item.label Text in Flexible
- Line 832: Wrapped rating and review count Texts in Flexible
- Line 1358: Wrapped label Text in Flexible
- Line 768: Wrapped priceText in Flexible

#### 3. `lib/screens/create/create_dinner_screen.dart`
**Issues:** AppBar actions overflow, step indicator overflow  
**Fixes:**
- Line 484: Wrapped step counter and step name Texts in Flexible
- Line 464: Changed TextButton('Save draft') to IconButton with tooltip
- Line 455: Wrapped AppBar title in FittedBox(scaleDown)

#### 4. `lib/screens/host/host_dashboard_screen.dart`
**Issues:** 3 Row overflows (lines 232, 2045, 2208)  
**Fixes:**
- Line 232: Wrapped AppBar title 'Host Studio' in Flexible
- Line 2073: Added maxLines + ellipsis to events/cuisine text
- Line 2238: Added maxLines + ellipsis to seats/date text
- Line 2083: Wrapped OutlinedButton('Create') in Flexible
- Line 2248: Wrapped ElevatedButton.icon('Promote') in Flexible

#### 5. `lib/screens/home/home_screen.dart`
**Issue:** _InfoChip Row overflow (line 1193)  
**Fix:** Wrapped label Text in Flexible

#### 6. `lib/screens/profile/profile_screen.dart`
**Issue:** _SectionHeader Row overflow (line 915)  
**Fix:** Wrapped title Text in Flexible, added maxLines + ellipsis to 'Edit' text

#### 7. `lib/screens/notifications/notifications_screen.dart`
**Issue:** AppBar actions overflow  
**Fix:**
- Changed TextButton('Mark all read') to IconButton with tooltip
- Wrapped AppBar title in FittedBox(scaleDown)

---

## Phase 4: Verification

### Test Results
```
flutter test
01:39 +283: All tests passed!
```

**Breakdown:**
- 133 existing tests: ✅ All passing
- 150 new overflow detection tests: ✅ All passing

### Static Analysis
```
flutter analyze
No issues found! (ran in 18.0s)
```

### Coverage
- 10 major screens tested
- 5 device widths: 320px (small phone), 360px (compact), 390px (standard), 430px (large), 600px (tablet)
- 3 text scales: 1.0x (default), 1.3x (accessibility), 2.0x (maximum accessibility)
- Total: 150 layout configurations verified

---

## Patterns Applied

### 1. Flexible for Dynamic Text in Rows
```dart
Row(
  children: [
    Icon(...),
    Flexible(
      child: Text(
        'Dynamic content',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
  ],
)
```

### 2. FittedBox for AppBar Titles
```dart
AppBar(
  title: FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerLeft,
    child: const Text('Title', maxLines: 1),
  ),
)
```

### 3. IconButton for AppBar Actions
```dart
actions: [
  IconButton(
    icon: const Icon(Icons.save_rounded),
    tooltip: 'Save draft',
    onPressed: _onSave,
  ),
]
```

### 4. Wrap for Chip Collections
```dart
Wrap(
  spacing: 8.0,
  runSpacing: 8.0,
  children: chips,
)
```

---

## Remaining Risks

### 1. Untested Screens
The following screens were not included in the overflow harness but may have similar issues:
- AuthScreen
- BookingConfirmedScreen
- ChatDetailScreen
- CheckoutScreen
- HelpScreen
- LocationScreen / LocationSettingsScreen / SavedLocationsScreen
- MapScreen
- MessagesScreen
- OffersScreen
- OnboardingScreen
- PaymentsScreen
- FoodPreferencesScreen / PreferencesScreen
- RestaurantDetailScreen
- BlockedUsersScreen / MyReportsScreen / ReportSheet / SafetyActions
- ChangeEmailSheet / ChangePasswordSheet / PrivacySettingsScreen / SettingsScreen
- SplashScreen
- FeedbackFormScreen
- MyTablesScreen
- WalletScreen
- EventManageScreen / AnalyticsScreen

**Recommendation:** Extend the harness to cover these screens in a follow-up audit.

### 2. Bottom Sheets and Dialogs
The harness tests full screens but not modal bottom sheets or dialogs, which can also overflow at extreme text scales.

**Recommendation:** Add targeted tests for:
- BookingCheckInSheet
- BookingReceiptSheet
- EditProfileSheet
- ReportSheet
- ChangeEmailSheet / ChangePasswordSheet

### 3. Keyboard-Visible State
Forms and bottom sheets were not tested with the keyboard visible, which reduces available vertical space.

**Recommendation:** Add keyboard-visible test cases for:
- CreateDinnerScreen (6-step wizard)
- CheckoutScreen
- FeedbackFormScreen
- ChangeEmailSheet / ChangePasswordSheet

### 4. Orientation Changes
All tests use portrait orientation. Landscape on small devices can introduce new overflow scenarios.

**Recommendation:** Add landscape test cases at 320px and 360px widths.

---

## Lessons Learned

### 1. Runtime Detection > Static Audit
Per memory lesson: "Flutter overflow must be traced via runtime RenderFlex log not grep audit." The harness approach (rendering screens and capturing errors) proved far more effective than static code review.

### 2. Flexible Placement Matters
Per memory lesson: "Flexible/Expanded must be direct children of Row/Column/Flex." Several attempted fixes broke tests by placing Flexible inside non-Flex parents (Chips, GestureDetector). The final fixes respect this constraint.

### 3. AppBar Actions Need Special Handling
AppBar trailing actions have constrained width. TextButtons with long labels overflow at high text scales. IconButtons with tooltips are more space-efficient and accessible.

### 4. FittedBox for Titles
AppBar titles with FittedBox(scaleDown) gracefully handle long titles at high text scales without truncation.

---

## Conclusion

The DineCircle app now has **zero known overflow defects** across the 10 most critical screens at 150 different device/text-scale configurations. The shared responsive helpers in `lib/theme/app_layout.dart` establish patterns for future development, and the overflow detection harness provides regression protection.

**Next steps:**
1. Extend harness to remaining screens (see "Untested Screens" above)
2. Add bottom sheet / dialog overflow tests
3. Add keyboard-visible state tests
4. Consider landscape orientation tests
5. Remove `tolerateOverflow()` from existing tests now that overflows are fixed

---

## Appendix: Test Matrix

| Screen | 320px | 360px | 390px | 430px | 600px | Total |
|--------|-------|-------|-------|-------|-------|-------|
| HomeScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| BookingsScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| DinnerDetailScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| CreateDinnerScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| ExploreScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| ProfileScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| SavedScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| NotificationsScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| HostDashboardScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| PeopleScreen | 3 | 3 | 3 | 3 | 3 | 15 |
| **Total** | **30** | **30** | **30** | **30** | **30** | **150** |

Each cell tests 3 text scales (1.0x, 1.3x, 2.0x).
