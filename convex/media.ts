import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import {
  MutationCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import {
  MAX_MEDIA_CAPTION,
  MAX_MEDIA_LENGTH_SEC,
  MAX_MEDIA_PER_BAND,
  MAX_MEDIA_TITLE,
  assertUploadAcceptable,
  mediaKindValidator,
  mediaPayloadValidator,
  requireBandAdmin,
  toMediaPayload,
} from "./lib/helpers";

/**
 * Loads the media row and asserts the caller is an admin of the band that owns
 * it. Shared by every mutation that takes a bare `mediaId`.
 *
 * The order is load-then-authorize, which leaks existence: a non-admin can tell
 * a real mediaId from a fake one by which error comes back. Flipping it is the
 * right fix but it changes the error every caller sees, so it wants its own
 * reviewed change rather than a quiet edit here. `bands:setBandPhoto` already
 * authorizes first, so the codebase is inconsistent until that lands.
 */
async function mediaForAdmin(
  ctx: MutationCtx,
  mediaId: Id<"bandMedia">,
): Promise<Doc<"bandMedia">> {
  const media = await ctx.db.get(mediaId);
  if (!media) throw new Error("Media not found");
  await requireBandAdmin(ctx, media.bandId);
  return media;
}

export const generateUploadUrl = mutation({
  args: { bandId: v.id("bands") },
  returns: v.string(),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    // The row cap belongs in addMedia because this URL also uploads gig flyers.
    return await ctx.storage.generateUploadUrl();
  },
});

export const addMedia = mutation({
  args: {
    bandId: v.id("bands"),
    kind: mediaKindValidator,
    storageId: v.id("_storage"),
    title: v.string(),
    caption: v.optional(v.string()),
    lengthSec: v.optional(v.number()),
  },
  returns: v.object({ mediaId: v.id("bandMedia") }),
  handler: async (ctx, args) => {
    const user = await requireBandAdmin(ctx, args.bandId);
    const media = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order", (q) => q.eq("bandId", args.bandId))
      .take(MAX_MEDIA_PER_BAND + 1);
    if (media.length >= MAX_MEDIA_PER_BAND) {
      throw new Error(`A band can have at most ${MAX_MEDIA_PER_BAND} media.`);
    }
    if (media.some((item) => item.storageId === args.storageId)) {
      throw new Error("That upload is already in this band's media.");
    }

    let order = -1;
    for (const item of media) {
      order = Math.max(order, item.order);
    }

    const meta = await ctx.db.system.get("_storage", args.storageId);
    if (meta === null) throw new Error("Upload not found");
    assertUploadAcceptable(
      { size: meta.size, contentType: meta.contentType },
      args.kind,
    );
    // There is deliberately no storage.delete on rejection: it would be part
    // of the throwing transaction and silently roll back, so the orphan sweep
    // must reclaim the blob instead.
    if (args.title.length > MAX_MEDIA_TITLE) {
      throw new Error(
        `Media titles can be at most ${MAX_MEDIA_TITLE} characters.`,
      );
    }
    if (
      args.caption !== undefined &&
      args.caption.length > MAX_MEDIA_CAPTION
    ) {
      throw new Error(
        `Media captions can be at most ${MAX_MEDIA_CAPTION} characters.`,
      );
    }
    if (args.kind === "photo" && args.lengthSec !== undefined) {
      throw new Error("lengthSec is only valid for video media");
    }
    if (
      args.lengthSec !== undefined &&
      (!Number.isFinite(args.lengthSec) ||
        args.lengthSec < 0 ||
        args.lengthSec > MAX_MEDIA_LENGTH_SEC)
    ) {
      throw new Error(`Invalid lengthSec — ${MAX_MEDIA_LENGTH_SEC} seconds max.`);
    }

    const mediaId = await ctx.db.insert("bandMedia", {
      bandId: args.bandId,
      kind: args.kind,
      storageId: args.storageId,
      contentType: meta.contentType,
      sizeBytes: meta.size,
      title: args.title,
      caption: args.caption,
      order: order + 1,
      pinned:
        args.kind === "video" &&
        !media.some((item) => item.kind === "video"),
      ...(args.kind === "video" ? { views: 0 } : {}),
      ...(args.kind === "video" && args.lengthSec !== undefined
        ? { lengthSec: args.lengthSec }
        : {}),
      uploadedBy: user._id,
    });
    return { mediaId };
  },
});

export const deleteMedia = mutation({
  args: { mediaId: v.id("bandMedia") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const media = await mediaForAdmin(ctx, args.mediaId);

    const band = await ctx.db.get(media.bandId);
    if (band?.imageStorageId === media.storageId) {
      await ctx.db.patch(band._id, { imageStorageId: undefined });
    }
    // Physical blob deletion belongs exclusively to sweepOrphanBlobs so shared or missing blobs cannot wedge row deletion.
    await ctx.db.delete(media._id);

    const remaining = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order", (q) => q.eq("bandId", media.bandId))
      .order("asc")
      .take(MAX_MEDIA_PER_BAND);
    for (let order = 0; order < remaining.length; order++) {
      if (remaining[order].order !== order) {
        await ctx.db.patch(remaining[order]._id, { order });
      }
    }
    if (media.kind === "video" && media.pinned) {
      const firstRemainingVideo = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_kind_order", (q) =>
          q.eq("bandId", media.bandId).eq("kind", "video"),
        )
        .order("asc")
        .first();
      if (firstRemainingVideo) {
        await ctx.db.patch(firstRemainingVideo._id, { pinned: true });
      }
    }
    return null;
  },
});

export const pinMedia = mutation({
  args: { mediaId: v.id("bandMedia") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const media = await mediaForAdmin(ctx, args.mediaId);
    if (media.kind !== "video") throw new Error("Only clips can be pinned");

    const siblings = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_kind_order", (q) =>
        q.eq("bandId", media.bandId).eq("kind", "video"),
      )
      .take(MAX_MEDIA_PER_BAND);
    for (const sibling of siblings) {
      if (sibling.pinned && sibling._id !== args.mediaId) {
        await ctx.db.patch(sibling._id, { pinned: false });
      }
    }
    await ctx.db.patch(args.mediaId, { pinned: true });
    return null;
  },
});

export const moveMedia = mutation({
  args: {
    mediaId: v.id("bandMedia"),
    direction: v.union(v.literal("up"), v.literal("down")),
  },
  returns: v.null(),
  handler: async (ctx, args) => {
    const media = await mediaForAdmin(ctx, args.mediaId);
    const siblings = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order", (q) => q.eq("bandId", media.bandId))
      .order("asc")
      .take(MAX_MEDIA_PER_BAND);
    const index = siblings.findIndex((sibling) => sibling._id === args.mediaId);
    if (index === -1) {
      throw new Error("Media not found among band's ordered media");
    }
    const neighborIndex = args.direction === "up" ? index - 1 : index + 1;
    if (neighborIndex < 0 || neighborIndex >= siblings.length) return null;
    const neighbor = siblings[neighborIndex];
    await ctx.db.patch(media._id, { order: neighbor.order });
    await ctx.db.patch(neighbor._id, { order: media.order });
    return null;
  },
});

export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(mediaPayloadValidator),
  handler: async (ctx, args) => {
    const mediaList = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order", (q) => q.eq("bandId", args.bandId))
      .order("asc")
      .take(MAX_MEDIA_PER_BAND);
    const band = await ctx.db.get(args.bandId);
    const payloads = [];
    for (const media of mediaList) {
      const url = await ctx.storage.getUrl(media.storageId);
      payloads.push(toMediaPayload(media, url, band?.imageStorageId));
    }
    return payloads;
  },
});

type SweepResult = {
  scanned: number;
  deleted: number;
  wouldDelete: number;
  skipped: number;
  aborted: boolean;
  done: boolean;
};

export const sweepOrphanBlobs = internalMutation({
  args: {
    dryRun: v.optional(v.boolean()),
    graceMs: v.optional(v.number()),
    cursor: v.optional(v.string()),
  },
  returns: v.object({
    scanned: v.number(),
    deleted: v.number(),
    wouldDelete: v.number(),
    skipped: v.number(),
    aborted: v.boolean(),
    done: v.boolean(),
  }),
  handler: async (ctx, args): Promise<SweepResult> => {
    const dryRun = args.dryRun ?? true;
    const graceMs = args.graceMs ?? 24 * 60 * 60 * 1000;
    const mediaRows = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_order")
      .take(2000);
    const heroBands = await ctx.db
      .query("bands")
      .withIndex("by_name")
      .take(2000);
    const gigs = await ctx.db
      .query("gigs")
      .withIndex("by_startsAt")
      .take(2000);
    const gigProjects = await ctx.db.query("gigProjects").take(2000);
    const users = await ctx.db
      .query("users")
      .withIndex("by_clerk_id")
      .take(2000);

    const cappedTables: string[] = [];
    if (mediaRows.length === 2000) cappedTables.push("bandMedia");
    if (heroBands.length === 2000) cappedTables.push("bands");
    if (gigs.length === 2000) cappedTables.push("gigs");
    if (gigProjects.length === 2000) cappedTables.push("gigProjects");
    if (users.length === 2000) cappedTables.push("users");
    if (cappedTables.length > 0) {
      // A read that hits 2000 may have been silently truncated, omitting a live
      // blob such as a real user avatar. Deleting against an incomplete
      // reference set is unsafe, so do not guess.
      console.warn(
        `sweepOrphanBlobs aborted: ${cappedTables.join(", ")} hit the 2000-row guard`,
      );
      return {
        scanned: 0,
        deleted: 0,
        wouldDelete: 0,
        skipped: 0,
        aborted: true,
        done: true,
      };
    }

    const referenced = new Set<Id<"_storage">>();
    for (const media of mediaRows) referenced.add(media.storageId);
    for (const band of heroBands) {
      if (band.imageStorageId !== undefined) {
        referenced.add(band.imageStorageId);
      }
    }
    for (const gig of gigs) {
      if (gig.flyStorageId !== undefined) referenced.add(gig.flyStorageId);
    }
    for (const project of gigProjects) {
      if (project.flyStorageId !== undefined) referenced.add(project.flyStorageId);
    }
    for (const user of users) {
      if (user.avatarStorageId !== undefined) {
        referenced.add(user.avatarStorageId);
      }
    }

    const page = await ctx.db.system.query("_storage").paginate({
      numItems: 200,
      cursor: args.cursor ?? null,
    });
    let scanned = 0;
    let deleted = 0;
    let wouldDelete = 0;
    let skipped = 0;
    const cutoff = Date.now() - graceMs;
    for (const blob of page.page) {
      scanned++;
      if (blob._creationTime > cutoff || referenced.has(blob._id)) {
        skipped++;
        continue;
      }
      if (dryRun) {
        wouldDelete++;
      } else {
        await ctx.storage.delete(blob._id);
        deleted++;
      }
    }

    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.media.sweepOrphanBlobs, {
        dryRun,
        graceMs,
        cursor: page.continueCursor,
      });
    }
    return {
      scanned,
      deleted,
      wouldDelete,
      skipped,
      aborted: false,
      done: page.isDone,
    };
  },
});
