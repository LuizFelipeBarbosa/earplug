/** `bands.ts` is pure client-contract surface, while `media.ts` owns
 * `sweepOrphanBlobs` because that sweep is media-domain work. A cross-table
 * counter reconciler and an operator-only gig publisher belong to no single
 * domain, so they live in this dedicated maintenance module. `seed.ts` writes
 * decorative followerCounts such as 486 and 1214 without creating `follows`
 * or `bandMembers` rows to support them. Every seeded band therefore drifts
 * from its true zero count, and a non-dry-run `recountBandFollowers` would
 * zero all of those decorative values. Run it non-dry only against production
 * or genuinely unseeded data. */
import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import { createProjectForGig } from "./gigs";
import {
  assertGigPublishable,
  gigPublishFieldsValidator,
  insertPublishedGig,
} from "./lib/helpers";

const MAX_RECOUNT_BANDS = 1000;
const MAX_JOIN_ROWS_PER_BAND = 1000;
const MAX_BACKFILL_GIGS = 2000;

const recountChangeValidator = v.object({
  bandId: v.id("bands"),
  name: v.string(),
  before: v.number(),
  after: v.number(),
  follows: v.number(),
  members: v.number(),
});
type RecountChange = Infer<typeof recountChangeValidator>;

export const recountBandFollowers = internalMutation({
  args: {
    dryRun: v.optional(v.boolean()),
    bandId: v.optional(v.id("bands")),
  },
  returns: v.object({
    scanned: v.number(),
    correct: v.number(),
    updated: v.number(),
    wouldUpdate: v.number(),
    skipped: v.number(),
    aborted: v.boolean(),
    changes: v.array(recountChangeValidator),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    let bands: Doc<"bands">[];
    if (args.bandId !== undefined) {
      const band = await ctx.db.get(args.bandId);
      if (band === null) {
        return {
          scanned: 0,
          correct: 0,
          updated: 0,
          wouldUpdate: 0,
          skipped: 0,
          aborted: false,
          changes: [],
        };
      }
      bands = [band];
    } else {
      bands = await ctx.db
        .query("bands")
        .withIndex("by_name")
        .take(MAX_RECOUNT_BANDS);
      if (bands.length === MAX_RECOUNT_BANDS) {
        console.warn(
          `recountBandFollowers aborted: bands hit the ${MAX_RECOUNT_BANDS}-row guard`,
        );
        return {
          scanned: 0,
          correct: 0,
          updated: 0,
          wouldUpdate: 0,
          skipped: 0,
          aborted: true,
          changes: [],
        };
      }
    }

    let scanned = 0;
    let correct = 0;
    let updated = 0;
    let wouldUpdate = 0;
    let skipped = 0;
    const changes: RecountChange[] = [];
    for (const band of bands) {
      scanned++;
      const follows = await ctx.db
        .query("follows")
        .withIndex("by_band", (q) => q.eq("bandId", band._id))
        .take(MAX_JOIN_ROWS_PER_BAND);
      const members = await ctx.db
        .query("bandMembers")
        .withIndex("by_band", (q) => q.eq("bandId", band._id))
        .take(MAX_JOIN_ROWS_PER_BAND);
      if (
        follows.length === MAX_JOIN_ROWS_PER_BAND ||
        members.length === MAX_JOIN_ROWS_PER_BAND
      ) {
        console.warn(
          `recountBandFollowers skipped ${band._id}: a join read hit the ${MAX_JOIN_ROWS_PER_BAND}-row guard`,
        );
        skipped++;
        continue;
      }

      const after = follows.length + members.length;
      if (after === band.followerCount) {
        correct++;
        continue;
      }

      changes.push({
        bandId: band._id,
        name: band.name,
        before: band.followerCount,
        after,
        follows: follows.length,
        members: members.length,
      });
      if (dryRun) {
        wouldUpdate++;
      } else {
        await ctx.db.patch(band._id, { followerCount: after });
        updated++;
      }
    }

    return {
      scanned,
      correct,
      updated,
      wouldUpdate,
      skipped,
      aborted: false,
      changes,
    };
  },
});

/** Creates the `gigBands` join rows for gigs that predate the join table —
 * on production that is all 14 rows reshaped out of the legacy `events` table.
 * A gig with no join row still exists and still appears in the feed, but it is
 * invisible to `gigs:pastForBand` and `analytics:bandRecap`, so the band's
 * history reads as empty while the gig sits right there in the table.
 *
 * Idempotent by (gigId, bandId): pairs that already have a row are counted and
 * left alone, so a partial run can simply be re-run. Nothing is ever deleted
 * or patched here — there is no gig-edit path in v1, so a join row's
 * denormalized `startsAt` cannot drift from its gig.
 *
 * Dry run by default, like every other mutation in this module. */
export const backfillGigBands = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({
    gigsScanned: v.number(),
    pairsExisting: v.number(),
    pairsMissing: v.number(),
    rowsCreated: v.number(),
    done: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const gigs = await ctx.db
      .query("gigs")
      .withIndex("by_startsAt")
      .take(MAX_BACKFILL_GIGS);

    let pairsExisting = 0;
    let pairsMissing = 0;
    let rowsCreated = 0;
    for (const gig of gigs) {
      const rows = await ctx.db
        .query("gigBands")
        .withIndex("by_gig", (q) => q.eq("gigId", gig._id))
        .take(MAX_JOIN_ROWS_PER_BAND);
      const indexed = new Set(rows.map((row) => row.bandId));
      for (const bandId of new Set(gig.lineup)) {
        if (indexed.has(bandId)) {
          pairsExisting++;
          continue;
        }
        pairsMissing++;
        if (dryRun) continue;
        await ctx.db.insert("gigBands", {
          gigId: gig._id,
          bandId,
          startsAt: gig.startsAt,
        });
        rowsCreated++;
      }
    }

    return {
      gigsScanned: gigs.length,
      pairsExisting,
      pairsMissing,
      rowsCreated,
      // A truncated read leaves older gigs unvisited. Re-running is safe but
      // would revisit the same page, so crossing this needs a cursor first.
      done: gigs.length < MAX_BACKFILL_GIGS,
    };
  },
});

/** `gigs:feed` only reads forward from now - FEED_GRACE_MS, while all 14
 * production gigs are past events. `gigs:publishGig` requires
 * `requireBandAdmin`, and no Flutter client is deployed against production, so
 * that path is currently unreachable there. This internal-only mutation is the
 * only path to publish a real upcoming production gig; clients cannot call it,
 * and it intentionally has no auth check. */
export const publishRealGig = internalMutation({
  args: {
    ...gigPublishFieldsValidator.fields,
    dryRun: v.optional(v.boolean()),
  },
  returns: v.object({
    gigId: v.union(v.id("gigs"), v.null()),
    created: v.boolean(),
    alreadyExisted: v.boolean(),
    bandName: v.string(),
    venueName: v.string(),
  }),
  handler: async (ctx, args) => {
    const { dryRun, ...fields } = args;
    const { band, venue } = await assertGigPublishable(ctx, fields);
    const candidates = await ctx.db
      .query("gigs")
      .withIndex("by_title", (q) => q.eq("title", fields.title))
      .take(20);
    const existing: Doc<"gigs"> | undefined = candidates.find(
      (candidate) =>
        candidate.startsAt === fields.startsAt &&
        candidate.venueId === fields.venueId,
    );
    if (existing !== undefined) {
      return {
        gigId: existing._id,
        created: false,
        alreadyExisted: true,
        bandName: band.name,
        venueName: venue.name,
      };
    }
    if (dryRun ?? true) {
      return {
        gigId: null,
        created: false,
        alreadyExisted: false,
        bandName: band.name,
        venueName: venue.name,
      };
    }

    const gigId: Id<"gigs"> = await insertPublishedGig(ctx, fields, band);
    const gig = await ctx.db.get(gigId);
    if (gig) await createProjectForGig(ctx, gig, band._id);
    return {
      gigId,
      created: true,
      alreadyExisted: false,
      bandName: band.name,
      venueName: venue.name,
    };
  },
});
