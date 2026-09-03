/** `bands.ts` is pure client-contract surface, while `media.ts` owns
 * `sweepOrphanBlobs` because that sweep is media-domain work. An
 * operator-only gig publisher belongs to no single domain, so it lives in this
 * dedicated maintenance module. */
import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { internalMutation } from "./_generated/server";
import { createProjectForGig } from "./gigs";
import {
  assertGigPublishable,
  gigPublishFieldsValidator,
  insertPublishedGig,
} from "./lib/helpers";

/** Operator path to publish a real upcoming gig on behalf of a band without a
 * signed-in admin — the draft pipeline (`gigs:createDraft` → `gigs:saveDraft`
 * → `gigs:publishDraft`) requires one. Clients cannot call it, and it
 * intentionally has no auth check. Dry-run by default. */
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
