import { describe, expect, test } from "vitest";
import crons from "./crons";

describe("crons", () => {
  test("keeps the orphaned media sweep", () => {
    const job = crons.crons["sweep orphaned media blobs"];
    expect(job).toBeDefined();
    expect(job.name).toBe("media:sweepOrphanBlobs");
    expect(job.args).toEqual([{ dryRun: false }]);
    expect(job.schedule).toEqual({ type: "interval", hours: 24 });
  });

  test("applies release backfills every 30 minutes", () => {
    const job = crons.crons["apply release backfills"];
    expect(job).toBeDefined();
    expect(job.name).toBe("migrations:runReleaseBackfills");
    expect(job.args).toEqual([{}]);
    expect(job.schedule).toEqual({ type: "interval", minutes: 30 });
  });
});
