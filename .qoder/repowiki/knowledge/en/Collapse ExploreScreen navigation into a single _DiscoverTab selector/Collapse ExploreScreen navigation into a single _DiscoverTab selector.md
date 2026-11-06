---
kind: design
name: Collapse ExploreScreen navigation into a single _DiscoverTab selector
source: session
category: adr
---

# Collapse ExploreScreen navigation into a single _DiscoverTab selector

_Source: coding plans from commit period d7be170 → e4be819 — records intent at planning time; the implementation may lag or differ._

## Context
The existing `ExploreScreen` (1402 lines) layered three overlapping navigation systems — `DiscoveryCategory` chips, top-level filter chips, and category cards — producing 22 chips, duplicated content across Featured Dinners / Trending Experiences / Popular This Week, and no occasion-based discovery. The screen felt like a marketplace feed rather than a premium concierge experience.

## Decision drivers
- visual simplicity over feature density
- no new backend endpoints required
- reuse existing providers (EventFilter, VenueSearch, OfferSearch, PeopleSearch)
- preserve existing widgets to avoid regression

## Considered options
- **Single `_DiscoverTab` enum with four tabs (All | Places | Offers | Experiences) plus occasion cards** — pros: Collapses DiscoveryCategory + selectedFilter + selectedCategory into one state; introduces occasion discovery without new APIs; keeps all filtering in existing providers
- **Keep the three-row chip system and add occasion chips on top** — pros: Minimal change to existing code; cons: Retains the 22-chip visual noise and duplication that motivated the redesign
- **Introduce a new backend endpoint for curated occasions** — pros: Cleaner client-side logic; cons: Adds server work and a new dependency point when existing EventFilter combinations already cover the use cases

## Decision
Replace `_selectedFilter`, `_selectedCategory`, and `_category` with a private `_DiscoverTab` enum and a const list of `_Occasion` items mapped to existing `EventFilter` values. The All tab renders occasion cards, curated experiences, restaurants, and deals; Places/Offers/Experiences tabs render vertical lists using the same providers as before.

## Consequences
Eliminates the triple-layer chip navigation and content duplication while keeping the provider layer untouched. The `DiscoveryCategory` enum is retained only for home-screen coupling. New reusable card widgets (`_OccasionCard`, `_ExperienceCard`, `_DealCard`) are introduced alongside the rewritten `ExploreScreen.build()`.