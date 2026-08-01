/** `bands.ts` is pure client-contract surface, while `media.ts` owns
 * `sweepOrphanBlobs` because that sweep is media-domain work. A cross-table
 * counter reconciler and an operator-only gig publisher belong to no single
 * domain, so they live in this dedicated maintenance module. */
import { Infer, v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import {
  assertGigPublishable,
  gigPublishFieldsValidator,
  insertPublishedGig,
} from "./lib/helpers";

const MAX_RECOUNT_BANDS = 1000;
const MAX_JOIN_ROWS_PER_BAND = 1000;

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
    return {
      gigId,
      created: true,
      alreadyExisted: false,
      bandName: band.name,
      venueName: venue.name,
    };
  },
});
