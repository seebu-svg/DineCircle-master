---
kind: design
name: Use Stripe PaymentIntent with server-side clientSecret for checkout
source: session
category: adr
---

# Use Stripe PaymentIntent with server-side clientSecret for checkout

_Source: coding plans from commit period 880d7d5 → b9d16a9 — records intent at planning time; the implementation may lag or differ._

**Status:** accepted

## Context
The checkout flow was failing with a 500 error when attempting to create bookings. The intended flow is: client POSTs `/api/events/:id/bookings`, server creates booking as `pending_payment`, calls `gateway.createIntent()` to create a Stripe PaymentIntent, returns the `clientSecret` to the Flutter client which then presents Stripe's PaymentSheet, and a webhook settles the payment.

## Decision drivers
- secure payment handling (server holds secret)
- Stripe SDK integration via PaymentSheet
- asynchronous settlement via webhooks

## Considered options
- **Server-side Stripe PaymentIntent + client Secret** — pros: Secret never leaves the server; Stripe PaymentSheet handles UI securely; webhook-driven settlement is reliable; cons: Requires database columns (`stripe_payment_intent_id`, `stripe_amount_cents`) and a Stripe webhook endpoint
- **Simulated payments (`PAYMENTS_MODE=simulated`)** — pros: No external dependency; instant settlement; no webhook needed; cons: Not real money; only useful for development/testing

## Decision
Adopt Stripe PaymentIntent created on the server: the backend stores `stripe_payment_intent_id` and `stripe_amount_cents` on the `bookings` row, returns the `clientSecret` to the Flutter client, and relies on a Stripe webhook to transition the booking to `paid`. A simulated fallback mode exists behind `PAYMENTS_MODE=simulated` if Stripe integration fails.

## Consequences
Requires the `bookings` table to have the two Stripe columns and a configured `STRIPE_WEBHOOK_SECRET`; adds an external dependency on Stripe's API and network availability; introduces webhook reliability concerns that must be monitored.