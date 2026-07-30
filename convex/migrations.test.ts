import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";

describe("band media migrations", () => {
  async function setupBand() {
    const t = convexTest(schema);
    const bandId = await t.run(async (ctx) =>
      ctx.db.insert("bands", {
        name: "Migration Band",
        genres: ["punk"],
        area: "Bay Area",
        colorHex: "#123456",
        initials: "MB",
        followerCount: 0,
        pastShows: [],
        slug: "migration-band",
      }),
    );
    return { t, bandId };
  }

  test("migrateVideosToBandMedia preserves fields, is idempotent, and defaults to dry-run", async () => {
    const { t, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("videos", {
        bandId,
        title: "Migrated clip",
        views: 42,
        lengthSec: 123,
        pinned: true,
        order: 7,
        storageId,
      });
      await ctx.db.insert("videos", {
        bandId,
        title: "Storage-less clip",
        views: 9,
        lengthSec: 45,
        pinned: false,
        order: 8,
      });
    });

    expect(
      await t.mutation(internal.migrations.migrateVideosToBandMedia, {
        dryRun: false,
      }),
    ).toEqual({ migrated: 1, skipped: 1, alreadyDone: 0 });
    const migrated = await t.run(async (ctx) =>
      ctx.db.query("bandMedia").collect(),
    );
    expect(migrated).toHaveLength(1);
    expect(migrated[0]).toMatchObject({
      bandId,
      kind: "video",
      storageId,
      title: "Migrated clip",
      views: 42,
      lengthSec: 123,
      pinned: true,
      order: 7,
    });

    expect(
      await t.mutation(internal.migrations.migrateVideosToBandMedia, {
        dryRun: false,
      }),
    ).toEqual({ migrated: 0, skipped: 1, alreadyDone: 1 });

    const dryRun = await setupBand();
    const dryStorageId = await dryRun.t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([4, 5, 6])])),
    );
    await dryRun.t.run(async (ctx) => {
      await ctx.db.insert("videos", {
        bandId: dryRun.bandId,
        title: "Dry clip",
        views: 1,
        lengthSec: 2,
        pinned: false,
        order: 0,
        storageId: dryStorageId,
      });
    });
    expect(
      await dryRun.t.mutation(
        internal.migrations.migrateVideosToBandMedia,
        {},
      ),
    ).toEqual({ migrated: 1, skipped: 0, alreadyDone: 0 });
    expect(
      await dryRun.t.run(async (ctx) =>
        ctx.db.query("bandMedia").collect(),
      ),
    ).toEqual([]);
  });

  test("backfillLegacyPhotos adopts live unique blobs and leaves the band fields unchanged", async () => {
    const { t, bandId } = await setupBand();
    const [imageStorageId, liveLegacyId, deadLegacyId] = await t.run(
      async (ctx) => {
        const ids = [
          await ctx.storage.store(new Blob([new Uint8Array([1])])),
          await ctx.storage.store(new Blob([new Uint8Array([2])])),
          await ctx.storage.store(new Blob([new Uint8Array([3])])),
        ] as const;
        await ctx.storage.delete(ids[2]);
        return ids;
      },
    );
    await t.run(async (ctx) => {
      await ctx.db.patch(bandId, {
        imageStorageId,
        legacyImageSlotIds: [liveLegacyId, deadLegacyId],
      });
    });

    expect(
      await t.mutation(internal.migrations.backfillLegacyPhotos, {
        dryRun: false,
      }),
    ).toEqual({ adopted: 2, dead: 1, alreadyDone: 0 });
    const afterFirst = await t.run(async (ctx) => ({
      band: await ctx.db.get(bandId),
      media: await ctx.db
        .query("bandMedia")
        .withIndex("by_band_order", (q) => q.eq("bandId", bandId))
        .collect(),
    }));
    expect(afterFirst.band?.imageStorageId).toBe(imageStorageId);
    expect(afterFirst.media.map((row) => row.storageId)).toEqual([
      imageStorageId,
      liveLegacyId,
    ]);
    expect(afterFirst.media.every((row) => row.kind === "photo")).toBe(true);

    expect(
      await t.mutation(internal.migrations.backfillLegacyPhotos, {
        dryRun: false,
      }),
    ).toEqual({ adopted: 0, dead: 1, alreadyDone: 2 });
  });

  test("purgeVideosTable guards unmigrated rows, supports dry-run, and deletes after migration", async () => {
    const { t, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("videos", {
        bandId,
        title: "Legacy clip",
        views: 10,
        lengthSec: 60,
        pinned: true,
        order: 0,
        storageId,
      });
    });

    await expect(
      t.mutation(internal.migrations.purgeVideosTable, { dryRun: false }),
    ).rejects.toThrow("Cannot purge videos");
    await t.mutation(internal.migrations.migrateVideosToBandMedia, {
      dryRun: false,
    });

    expect(
      await t.mutation(internal.migrations.purgeVideosTable, {
        dryRun: true,
      }),
    ).toEqual({ deleted: 1 });
    expect(
      await t.run(async (ctx) => ctx.db.query("videos").collect()),
    ).toHaveLength(1);

    expect(
      await t.mutation(internal.migrations.purgeVideosTable, {
        dryRun: false,
      }),
    ).toEqual({ deleted: 1 });
    expect(
      await t.run(async (ctx) => ctx.db.query("videos").collect()),
    ).toEqual([]);
  });

  test("clearLegacyBandImageFields clears only legacyImageSlotIds", async () => {
    const { t, bandId } = await setupBand();
    const [imageStorageId, legacyStorageId] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
    ]);
    await t.run(async (ctx) => {
      await ctx.db.patch(bandId, {
        imageStorageId,
        legacyImageSlotIds: [legacyStorageId],
      });
    });

    expect(
      await t.mutation(internal.migrations.clearLegacyBandImageFields, {
        dryRun: false,
      }),
    ).toEqual({ cleared: 1 });
    const band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band?.legacyImageSlotIds).toBeUndefined();
    expect(band?.imageStorageId).toBe(imageStorageId);
  });

  test("mediaStats reports every seeded count including dead media", async () => {
    const { t, bandId } = await setupBand();
    const [videoStorage1, videoStorage2, deadPhotoStorage, imageStorageId] =
      await t.run(async (ctx) => {
        const ids = [
          await ctx.storage.store(new Blob([new Uint8Array([1])])),
          await ctx.storage.store(new Blob([new Uint8Array([2])])),
          await ctx.storage.store(new Blob([new Uint8Array([3])])),
          await ctx.storage.store(new Blob([new Uint8Array([4])])),
        ] as const;
        await ctx.storage.delete(ids[2]);
        return ids;
      });
    await t.run(async (ctx) => {
      await ctx.db.patch(bandId, {
        imageStorageId,
        legacyImageSlotIds: [imageStorageId],
      });
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage1,
        title: "Video 1",
        order: 0,
        pinned: true,
      });
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage2,
        title: "Video 2",
        order: 1,
        pinned: false,
      });
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: deadPhotoStorage,
        title: "Dead photo",
        order: 2,
        pinned: false,
      });
      await ctx.db.insert("videos", {
        bandId,
        title: "Legacy video",
        views: 5,
        lengthSec: 50,
        pinned: false,
        order: 0,
      });
    });

    expect(await t.query(internal.migrations.mediaStats, {})).toEqual({
      videoCount: 2,
      photoCount: 1,
      videosRowCount: 1,
      deadBandMediaCount: 1,
      bandsWithImageStorageId: 1,
      bandsWithLegacyImageSlotIds: 1,
    });
  });
});
