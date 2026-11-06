---
kind: design
name: Single primary CTA + More menu replaces four action buttons on upcoming booking cards
source: session
category: adr
---

# Single primary CTA + More menu replaces four action buttons on upcoming booking cards

_Source: coding plans from commit period d432364 → 6034d90 — records intent at planning time; the implementation may lag or differ._

## Context
Each `_UpcomingBookingCard` displayed four action buttons in a 2×2 grid, which was excessive per spec and crowded the card. The spec called for one primary call-to-action plus a secondary menu.

## Decision drivers
- follow product spec (1 primary CTA + secondary menu)
- reduce visual clutter on booking cards
- surface the most important action first based on booking status

## Considered options
- **Keep 4-button grid** _(rejected)_ — pros: all actions visible at once; cons: violates spec, too many taps, cramped layout
- **Primary CTA + PopupMenu 'More' with remaining actions** — pros: one clear next step, extra actions discoverable, fits spec; cons: secondary actions require an extra tap

## Decision
Render one status-driven primary CTA on the upcoming card — 'Complete Payment' for pending+awaiting payment, 'Show QR Ticket' for confirmed+check-in open, 'Directions' for confirmed+check-in closed, 'Cancel Booking' for normal pending — and put Directions, Contact Host, Cancel inside a `PopupMenuItem` under a 'More' overflow menu.

## Consequences
Users see one obvious next action per booking state; less-tapped actions are one tap away via the More menu. Check-in/QR visibility is currently gated only by `booking.status == BookingStatus.confirmed` with a note that a proper check-in-open flag will be wired later.