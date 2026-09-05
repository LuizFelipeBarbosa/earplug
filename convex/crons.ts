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

// The runner is idempotent: the migrations component skips completed jobs and
// resumes interrupted jobs from their stored cursor, so running every 30 minutes
// is a no-op once a release's backfills are fully applied. The cron applies new
// release backfills within 30 minutes of deploy without requiring the
// `deployment:functions:runInternalMutations` permission that Netlify's deploy
// key lacks.
crons.interval(
  "apply release backfills",
  { minutes: 30 },
  internal.migrations.runReleaseBackfills,
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

export default crons;
