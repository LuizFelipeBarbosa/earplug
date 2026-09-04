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

export default crons;
