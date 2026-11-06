---
kind: design
name: Enforce overflow-safe text rendering across all Flutter screens
source: session
category: adr
---

# Enforce overflow-safe text rendering across all Flutter screens

_Source: coding plans from commit period 880d7d5 → b9d16a9 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
Multiple Flutter screens (home, detail, explore, checkout, bookings, profile, settings, host dashboards) had yellow/black overflow bands caused by Text widgets without `maxLines`/`overflow` inside Rows/Columns, fixed-width containers, and unconstrained dynamic content — especially noticeable on narrow devices like the Note 10.

## Decision drivers
- responsive layout correctness
- consistent truncation behavior
- avoiding hard-coded widths in dynamic rows

## Considered options
- **Wrap every dynamic Text in `Flexible`/`Expanded` with `maxLines` + `TextOverflow.ellipsis`** — pros: Predictable truncation; works on any screen size; minimal visual change; cons: Adds boilerplate across many files
- **Switch to scrollable containers or larger font sizes** — pros: Less truncation; cons: Degrades readability on small screens; does not solve Row overflow

## Decision
Apply a uniform pattern: single-line texts get `maxLines: 1` + `TextOverflow.ellipsis`, multi-line descriptions get bounded `maxLines`, and any Text inside a Row/Column with dynamic siblings is wrapped in `Flexible` rather than using fixed widths.

## Consequences
Eliminates overflow warnings on all screens; long labels truncate instead of breaking layout; requires future widgets to follow the same pattern to avoid regressions.