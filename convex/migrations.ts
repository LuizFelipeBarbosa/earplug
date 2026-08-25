import { Migrations } from "@convex-dev/migrations";
import { components } from "./_generated/api";
import { DataModel } from "./_generated/dataModel";
import { createProjectForGig } from "./gigs";

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

export const run = migrations.runner();
