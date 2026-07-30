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

export default crons;
