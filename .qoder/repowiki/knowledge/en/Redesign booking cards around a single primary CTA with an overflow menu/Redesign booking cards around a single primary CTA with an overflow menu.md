---
kind: design
name: Redesign booking cards around a single primary CTA with an overflow menu
source: session
category: adr
---

# Redesign booking cards around a single primary CTA with an overflow menu

_Source: coding plans from commit period d7be170 → e4be819 — records intent at planning time; the implementation may lag or differ._

## Context
The Bookings screen had RenderFlex overflow in `_PastBookingCard` (Row instead of Wrap), nullable fields rendering literal "null", check-in buttons shown for every upcoming booking regardless of status, non-scrollable bottom sheets missing SafeArea, and four action buttons per upcoming card exceeding the spec's one-primary-CTA-plus-secondary-menu pattern.

## Decision drivers
- production readiness (no overflows, no null literals)
- one clear action per booking card
- consistent SafeArea usage across all bottom sheets
- status-gated check-in visibility

## Considered options
- **Status-driven primary CTA + PopupMenuItem overflow (Show QR Ticket / Directions / Cancel / Contact Host)** — pros: Matches spec, reduces cognitive load, lets the most common action be one tap
- **Keep the existing 2×2 grid of four equal buttons** — pros: Least code change; cons: Overwhelms users, causes layout overflow, exposes actions that should be hidden by status
- **Move all secondary actions into a dedicated details sheet** — pros: Keeps the card minimal; cons: Adds an extra navigation step for common actions like Directions or Contact Host

## Decision
Replace the four-button grid with one status-selected primary CTA (Complete Payment / Show QR Ticket / Directions / Cancel Booking) and a 'More' PopupMenuItem holding the remaining actions. Gate the QR/check-in button on `booking.status == BookingStatus.confirmed` and guard all address/city/guestName fields with null-safe defaults. Wrap every bottom sheet in SafeArea and mark it `isScrollControlled: true`.

## Consequences
Fixes all identified RenderFlex overflows and null-render bugs, removes fabricated wallet balance data, and standardises bottom-sheet ergonomics. The heuristic for check-in visibility is intentionally simple now and can be refined later when host-opened check-in signals arrive from the backend.