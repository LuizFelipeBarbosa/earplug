import { Migrations } from "@convex-dev/migrations";
import { components, internal } from "./_generated/api";
import { DataModel } from "./_generated/dataModel";
import { createProjectForGig } from "./gigs";
import {
  discoveryListingFlags,
  isDiscoveryListingReady,
} from "./lib/discovery";
import { MAX_MEDIA_PER_BAND, assertUploadAcceptable } from "./lib/helpers";

export const migrations = new Migrations<DataModel>(components.migrations);

/** Widen-phase backfill. Safe to restart: the project lookup is unique by the
 * public gig id, and already-populated public compatibility fields are left
 * intact. Legacy timing is intentionally preserved when the old display string
 * cannot prove a distinct show time. */
export const backfillGigProjects = migrations.define({
  table: "gigs",
  batchSize: 25,
  migrateOne: async (ctx, gig) => {
    const ownerBandId = gig.createdByBand ?? gig.lineup[0];
    if (ownerBandId) await createProjectForGig(ctx, gig, ownerBandId);

    const performers = [];
    for (let index = 0; index < gig.lineup.length; index++) {
      const band = await ctx.db.get(gig.lineup[index]);
      if (band) {
        performers.push({
          name: band.name,
          role: index === 0 ? ("headliner" as const) : ("support" as const),
          bandId: band._id,
        });
      }
    }
    await ctx.db.patch(gig._id, {
      lifecycle: gig.lifecycle ?? "published",
      doorsAt: gig.doorsAt ?? gig.startsAt,
      performers: gig.performers ?? performers,
    });
  },
});

/** Denormalizes valid clip existence after all live media writes already
 * maintain the field. Legacy rows with missing or unacceptable blobs fail
 * closed. */
export const backfillBandHasClip = migrations.define({
  table: "bands",
  batchSize: 50,
  migrateOne: async (ctx, band) => {
    const videos = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_kind_order", (q) =>
        q.eq("bandId", band._id).eq("kind", "video"),
      )
      .take(MAX_MEDIA_PER_BAND);
    let hasClip = false;
    for (const video of videos) {
      const upload = await ctx.db.system.get("_storage", video.storageId);
      if (!upload) continue;
      try {
        assertUploadAcceptable(
          { size: upload.size, contentType: upload.contentType },
          "video",
        );
        hasClip = true;
        break;
      } catch {
        // Keep checking: a later legacy video may still be valid.
      }
    }
    if (band.hasClip !== hasClip) return { hasClip };
  },
});

/** Rebuilds the public listing projection from the matching private project.
 * Missing projects, missing creators, and any other ambiguous legacy state
 * fail closed rather than receiving visibility optimistically. */
export const backfillGigDiscoveryListingReady = migrations.define({
  table: "gigs",
  batchSize: 25,
  migrateOne: async (ctx, gig) => {
    const project = await ctx.db
      .query("gigProjects")
      .withIndex("by_public_gig", (q) => q.eq("publicGigId", gig._id))
      .first();
    let discoveryListingReady = false;
    if (project) {
      const performers = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_project_and_order", (q) =>
          q.eq("projectId", project._id),
        )
        .take(21);
      const flags = await discoveryListingFlags(ctx, project, gig, performers);
      discoveryListingReady = isDiscoveryListingReady(flags);
    }
    if (gig.discoveryListingReady !== discoveryListingReady) {
      return { discoveryListingReady };
    }
  },
});

/** Operational order for the widen-phase rollout. Completed component jobs
 * are skipped, and retries resume from their stored cursor. */
export const runDiscoveryReadinessBackfills = migrations.runner([
  internal.migrations.backfillGigProjects,
  internal.migrations.backfillBandHasClip,
  internal.migrations.backfillGigDiscoveryListingReady,
]);

export const run = migrations.runner();
