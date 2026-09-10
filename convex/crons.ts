import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();

// `{ dryRun: false }` is mandatory and load-bearing: sweepOrphanBlobs defaults
// to dry-run and would silently no-op without it.
crons.interval(
  "sweep orphaned media blobs",
  { hours: 24 },
  internal.media.sweepOrphanBlobs,
  { dryRun: false },
);

// Refresh the shared feed cutoff so quiet feeds age out gigs every 15 minutes.
crons.interval(
  "feed cutoff heartbeat",
  { minutes: 15 },
  internal.clock.heartbeat,
  {},
);

// Held payouts (no ready payout account, or a booking-level hold) get re-checked daily until
// HELD_PAYOUT_MAX_DAYS elapses.
crons.interval(
  "retry held payouts",
  { hours: 24 },
  internal.payouts.retryHeldPayouts,
  {},
);

// Failed refunds get another three attempts once payments are enabled.
crons.interval(
  "retry failed refunds",
  { hours: 6 },
  internal.refunds.retryFailedRefunds,
  {},
);

// Release ticket holds whose reservation window has elapsed.
crons.interval(
  "expire stale ticket reservations",
  { minutes: 15 },
  internal.tickets.expireStaleReservations,
  {},
);

// Reconcile open ticket checkouts that outlive their Stripe session.
crons.interval(
  "sweep stale ticket checkouts",
  { hours: 1 },
  internal.ticketCheckout.sweepStaleCheckouts,
  {},
);

// Failed ticket refunds get another attempt once ticket sales are enabled.
crons.interval(
  "retry failed ticket refunds",
  { hours: 6 },
  internal.ticketRefunds.retryFailedTicketRefunds,
  {},
);

// Reconcile refunds that Stripe reports pending or changed after creation.
crons.interval(
  "reconcile pending Stripe refunds",
  { hours: 6 },
  internal.refunds.reconcilePendingRefunds,
  {},
);

export default crons;
