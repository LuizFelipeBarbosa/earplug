import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

describe("deprecated videos shim", () => {
  async function setupBand() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "videos_admin",
      email: "videos-admin@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Videos Shim Band",
      genres: ["punk"],
      bio: "",
      inviteHandles: [],
    });
    return { t, asAdmin, bandId };
  }

  test("forBand returns only ordered videos with the exact legacy payload shape", async () => {
    const { t, bandId } = await setupBand();
    const [laterStorageId, photoStorageId, firstStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      later: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: laterStorageId,
        title: "Later",
        views: 12,
        lengthSec: 34,
        order: 2,
        pinned: false,
      }),
      photo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorageId,
        title: "Excluded photo",
        order: 1,
        pinned: false,
      }),
      first: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: firstStorageId,
        title: "First",
        order: 0,
        pinned: true,
      }),
    }));

    const videos = await t.query(api.videos.forBand, { bandId });
    expect(videos.map((video) => video._id)).toEqual([ids.first, ids.later]);
    expect(videos.map((video) => video._id)).not.toContain(ids.photo);
    const expectedKeys = [
      "_id",
      "bandId",
      "title",
      "views",
      "lengthSec",
      "pinned",
      "order",
    ].sort();
    for (const video of videos) {
      expect(Object.keys(video).sort()).toEqual(expectedKeys);
    }
    expect(videos[0]).toMatchObject({
      title: "First",
      views: 0,
      lengthSec: 0,
      pinned: true,
      order: 0,
    });
    expect(videos[1]).toMatchObject({
      title: "Later",
      views: 12,
      lengthSec: 34,
      pinned: false,
      order: 2,
    });
  });

  test("pinVideo unpins its sibling and rejects non-admins and photo ids", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstStorageId, secondStorageId, photoStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      first: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: firstStorageId,
        title: "First",
        order: 0,
        pinned: true,
      }),
      second: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: secondStorageId,
        title: "Second",
        order: 1,
        pinned: false,
      }),
      photo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorageId,
        title: "Photo",
        order: 0,
        pinned: false,
      }),
    }));

    await asAdmin.mutation(api.videos.pinVideo, { videoId: ids.second });
    const afterPin = await t.run(async (ctx) => ({
      first: await ctx.db.get(ids.first),
      second: await ctx.db.get(ids.second),
    }));
    expect(afterPin.first?.pinned).toBe(false);
    expect(afterPin.second?.pinned).toBe(true);

    const asMember = t.withIdentity({
      subject: "videos_member",
      email: "videos-member@example.com",
    });
    const { userId } = await asMember.mutation(api.users.ensureUser, {});
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId,
        role: "member",
      });
    });
    await expect(
      asMember.mutation(api.videos.pinVideo, { videoId: ids.first }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asAdmin.mutation(api.videos.pinVideo, { videoId: ids.photo }),
    ).rejects.toThrow("Video not found");
  });

  test("moveVideo swaps only video neighbors and no-ops at the ends", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstStorageId, photoStorageId, secondStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      first: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: firstStorageId,
        title: "First",
        order: 0,
        pinned: true,
      }),
      photo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorageId,
        title: "Interposed photo",
        order: 1,
        pinned: false,
      }),
      second: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: secondStorageId,
        title: "Second",
        order: 2,
        pinned: false,
      }),
    }));

    await asAdmin.mutation(api.videos.moveVideo, {
      videoId: ids.first,
      direction: "down",
    });
    let docs = await t.run(async (ctx) => ({
      first: await ctx.db.get(ids.first),
      photo: await ctx.db.get(ids.photo),
      second: await ctx.db.get(ids.second),
    }));
    expect(docs.first?.order).toBe(2);
    expect(docs.second?.order).toBe(0);
    expect(docs.photo?.order).toBe(1);

    await asAdmin.mutation(api.videos.moveVideo, {
      videoId: ids.second,
      direction: "up",
    });
    await asAdmin.mutation(api.videos.moveVideo, {
      videoId: ids.first,
      direction: "down",
    });
    docs = await t.run(async (ctx) => ({
      first: await ctx.db.get(ids.first),
      photo: await ctx.db.get(ids.photo),
      second: await ctx.db.get(ids.second),
    }));
    expect(docs.first?.order).toBe(2);
    expect(docs.second?.order).toBe(0);
    expect(docs.photo?.order).toBe(1);
  });

  test("forBand is public and returns an empty array when the band has no media", async () => {
    const { t, bandId } = await setupBand();
    expect(await t.query(api.videos.forBand, { bandId })).toEqual([]);

    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId,
        title: "Public clip",
        order: 0,
        pinned: true,
      });
    });
    const publicResult = await t.query(api.videos.forBand, { bandId });
    expect(publicResult).toHaveLength(1);
    expect(publicResult[0].title).toBe("Public clip");
  });
});
