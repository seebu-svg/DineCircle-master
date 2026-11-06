---
kind: design
name: Use Wrap for detail chips and SafeArea for bottom sheets in bookings screen
source: session
category: adr
---

# Use Wrap for detail chips and SafeArea for bottom sheets in bookings screen

_Source: coding plans from commit period d432364 → 6034d90 — records intent at planning time; the implementation may lag or differ._

## Context
The BookingsScreen had RenderFlex overflow on `_PastBookingCard` because date/time/seats and price/promo rows used `Row` with chip widgets, and all bottom sheets (`_DirectionsSheet`, `_ContactHostSheet`, `_ReviewFormSheet`) relied on manual `MediaQuery.padding.bottom` instead of `SafeArea`, causing overflows on short screens.

## Decision drivers
- avoid RenderFlex overflow on variable-width content
- consistent safe padding across all bottom sheets
- null-safety for restaurant.city / address fields

## Considered options
- **Keep Row + fixed widths or truncation** _(rejected)_ — pros: simpler layout code; cons: still overflows when chips grow; brittle on different screen sizes
- **Wrap for chip rows** — pros: wraps naturally to multiple lines, no overflow; cons: slightly more complex layout math
- **Manual MediaQuery padding for bottom sheets** _(rejected)_ — pros: already worked partially; cons: fragile, inconsistent across sheets, breaks on notches/dynamic type
- **SafeArea wrapping all bottom sheet content** — pros: handles notches, dynamic type, keyboard uniformly; cons: requires adding to each sheet widget tree

## Decision
Replace the `Row` children of `_PastBookingCard._buildActions` with `Wrap` so detail chips wrap instead of overflowing, and wrap every bottom sheet's content in `SafeArea` (with `isScrollControlled: true` on `showModalBottomSheet`). Also null-guard `restaurant.city` and `restaurant.address` so literal "null" never renders.

## Consequences
Chips and action buttons no longer overflow on narrow devices. All bottom sheets respect system insets consistently. Null fields render as empty strings rather than the text "null". The check-in button is gated behind `booking.status == BookingStatus.confirmed` (heuristic) plus a future check-in-open flag.