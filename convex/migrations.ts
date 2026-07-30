import { v } from "convex/values";
import { Id } from "./_generated/dataModel";
import { internalMutation, internalQuery } from "./_generated/server";

// One-shot artifacts: run dry, then live, against dev, then delete this file.
// They remain recoverable from git, following the same lifecycle as the
// migrations deleted at commit 4b5c819.

export const migrateVideosToBandMedia = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({
    migrated: v.number(),
    skipped: v.number(),
    alreadyDone: v.number(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const videos = await ctx.db.query("videos").take(1000);
    let migrated = 0;
    let skipped = 0;
    let alreadyDone = 0;

    for (const video of videos) {
      if (video.storageId === undefined) {
        skipped++;
        continue;
      }

      const existingMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", video.bandId))
        .take(1000);
      if (
        existingMedia.some((media) => media.storageId === video.storageId)
      ) {
        alreadyDone++;
        continue;
      }

      if (!dryRun) {
        await ctx.db.insert("bandMedia", {
          bandId: video.bandId,
          kind: "video",
          storageId: video.storageId,
          title: video.title,
          views: video.views,
          lengthSec: video.lengthSec,
          pinned: video.pinned,
          order: video.order,
        });
      }
      migrated++;
    }

    return { migrated, skipped, alreadyDone };
  },
});

export const backfillLegacyPhotos = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({
    adopted: v.number(),
    dead: v.number(),
    alreadyDone: v.number(),
  }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const bands = await ctx.db.query("bands").take(1000);
    let adopted = 0;
    let dead = 0;
    let alreadyDone = 0;

    for (const band of bands) {
      const candidateIds = [
        band.imageStorageId,
        ...(band.legacyImageSlotIds ?? []),
      ].filter((id): id is Id<"_storage"> => id !== undefined);
      const uniqueCandidateIds = [...new Set(candidateIds)];
      const existingMedia = await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", band._id))
        .take(1000);
      const existingStorageIds = new Set(
        existingMedia.map((media) => media.storageId),
      );
      const highestOrder = existingMedia.reduce<number | undefined>(
        (highest, media) =>
          highest === undefined || media.order > highest
            ? media.order
            : highest,
        undefined,
      );
      let nextOrder = highestOrder === undefined ? 0 : highestOrder + 1;

      for (
        let candidateIndex = 0;
        candidateIndex < uniqueCandidateIds.length;
        candidateIndex++
      ) {
        const storageId = uniqueCandidateIds[candidateIndex];
        const meta = await ctx.db.system.get("_storage", storageId);
        if (meta === null) {
          dead++;
          continue;
        }
        if (existingStorageIds.has(storageId)) {
          alreadyDone++;
          continue;
        }

        if (!dryRun) {
          await ctx.db.insert("bandMedia", {
            bandId: band._id,
            kind: "photo",
            storageId,
            title: `Photo ${candidateIndex + 1}`,
            contentType: meta.contentType,
            sizeBytes: meta.size,
            pinned: false,
            order: nextOrder,
          });
        }
        existingStorageIds.add(storageId);
        nextOrder++;
        adopted++;
      }
    }

    return { adopted, dead, alreadyDone };
  },
});

export const mediaStats = internalQuery({
  args: {},
  returns: v.object({
    videoCount: v.number(),
    photoCount: v.number(),
    videosRowCount: v.number(),
    deadBandMediaCount: v.number(),
    bandsWithImageStorageId: v.number(),
    bandsWithLegacyImageSlotIds: v.number(),
  }),
  handler: async (ctx) => {
    const bandMedia = await ctx.db.query("bandMedia").take(1000);
    const videos = await ctx.db.query("videos").take(1000);
    const bands = await ctx.db.query("bands").take(1000);
    let deadBandMediaCount = 0;

    for (const media of bandMedia) {
      const meta = await ctx.db.system.get("_storage", media.storageId);
      if (meta === null) deadBandMediaCount++;
    }

    return {
      videoCount: bandMedia.filter((media) => media.kind === "video").length,
      photoCount: bandMedia.filter((media) => media.kind === "photo").length,
      videosRowCount: videos.length,
      deadBandMediaCount,
      bandsWithImageStorageId: bands.filter(
        (band) => band.imageStorageId !== undefined,
      ).length,
      bandsWithLegacyImageSlotIds: bands.filter(
        (band) => band.legacyImageSlotIds !== undefined,
      ).length,
    };
  },
});

export const purgeVideosTable = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({ deleted: v.number() }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const bandMedia = await ctx.db.query("bandMedia").take(1000);
    const videos = await ctx.db.query("videos").take(1000);
    const videoMediaCount = bandMedia.filter(
      (media) => media.kind === "video",
    ).length;
    const migratableVideosCount = videos.filter(
      (video) => video.storageId !== undefined,
    ).length;

    // Convex refuses to undeclare a table while it still has rows. Purging
    // before every migratable video is verified in bandMedia would lose data
    // with no way to recover it.
    if (videoMediaCount < migratableVideosCount) {
      throw new Error(
        `Cannot purge videos: found ${migratableVideosCount} migratable legacy rows but only ${videoMediaCount} bandMedia video rows. Run and verify migrateVideosToBandMedia first.`,
      );
    }

    if (!dryRun) {
      for (const video of videos) {
        await ctx.db.delete(video._id);
      }
    }
    return { deleted: videos.length };
  },
});

export const clearLegacyBandImageFields = internalMutation({
  args: { dryRun: v.optional(v.boolean()) },
  returns: v.object({ cleared: v.number() }),
  handler: async (ctx, args) => {
    const dryRun = args.dryRun ?? true;
    const bands = await ctx.db.query("bands").take(1000);
    const bandsToClear = bands.filter(
      (band) => band.legacyImageSlotIds !== undefined,
    );

    // Existing documents are validated against every newly pushed schema, so
    // undeclaring this field while a row still carries it blocks all later
    // deploys, not only the deploy that first removes the field.
    if (!dryRun) {
      for (const band of bandsToClear) {
        await ctx.db.patch(band._id, { legacyImageSlotIds: undefined });
      }
    }

    return { cleared: bandsToClear.length };
  },
});
