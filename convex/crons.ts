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

export default crons;
