import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import {
  MAX_MEDIA_BYTES,
  MAX_MEDIA_PER_BAND,
  MAX_VIDEO_THUMBNAIL_BYTES,
  assertUploadAcceptable,
  assertVideoThumbnailAcceptable,
} from "./lib/helpers";
import schema from "./schema";

describe("media mutations", () => {
  async function setupBand() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "media_admin",
      email: "media-admin@example.com",
    });
    const { userId } = await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Media Band",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
      inviteHandles: [],
    });
    return { t, asAdmin, bandId, userId };
  }

  test("addMedia appends globally and auto-pins only the first video", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [videoStorage1, videoStorage2, photoStorage1, photoStorage2] =
      await t.run(async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
        await ctx.storage.store(new Blob([new Uint8Array([4])])),
      ]);

    const video1 = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: videoStorage1,
      title: "First clip",
    });
    const video2 = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: videoStorage2,
      title: "Second clip",
    });
    const photo1 = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: photoStorage1,
      title: "First photo",
    });
    const photo2 = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: photoStorage2,
      title: "Second photo",
    });

    const docs = await t.run(async (ctx) => ({
      video1: await ctx.db.get(video1.mediaId),
      video2: await ctx.db.get(video2.mediaId),
      photo1: await ctx.db.get(photo1.mediaId),
      photo2: await ctx.db.get(photo2.mediaId),
    }));
    expect(docs.video1).toMatchObject({ order: 0, pinned: true, views: 0 });
    expect(docs.video2).toMatchObject({ order: 1, pinned: false, views: 0 });
    expect(docs.photo1).toMatchObject({ order: 2, pinned: false });
    expect(docs.photo2).toMatchObject({ order: 3, pinned: false });
    expect(docs.photo1?.views).toBeUndefined();
  });

  test("stores and resolves a generated video thumbnail", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [videoStorageId, thumbnailStorageId] = await t.run(async (ctx) => [
      await ctx.storage.store(
        new Blob([new Uint8Array([1])], { type: "video/mp4" }),
      ),
      await ctx.storage.store(
        new Blob([new Uint8Array([2])], { type: "image/jpeg" }),
      ),
    ]);

    const { mediaId } = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: videoStorageId,
      thumbnailStorageId,
      title: "Poster clip",
    });

    expect(
      await t.run(
        async (ctx) => (await ctx.db.get(mediaId))?.thumbnailStorageId,
      ),
    ).toBe(thumbnailStorageId);
    expect(await t.query(api.media.forBand, { bandId })).toMatchObject([
      {
        _id: mediaId,
        url: expect.any(String),
        thumbnailUrl: expect.any(String),
      },
    ]);
  });

  test("validates thumbnail ownership, identity, size, and content type", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [videoStorageId, thumbnailStorageId, oversizedId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(
          new Blob([new Uint8Array([1])], { type: "video/mp4" }),
        ),
        await ctx.storage.store(
          new Blob([new Uint8Array([2])], { type: "image/jpeg" }),
        ),
        await ctx.storage.store(
          new Blob([new Uint8Array(MAX_VIDEO_THUMBNAIL_BYTES + 1)], {
            type: "image/jpeg",
          }),
        ),
      ],
    );

    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId: videoStorageId,
        thumbnailStorageId,
        title: "Photo with poster",
      }),
    ).rejects.toThrow("Only video media");
    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "video",
        storageId: videoStorageId,
        thumbnailStorageId: videoStorageId,
        title: "Same blob",
      }),
    ).rejects.toThrow("separate image upload");
    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "video",
        storageId: videoStorageId,
        thumbnailStorageId: oversizedId,
        title: "Oversized poster",
      }),
    ).rejects.toThrow("2 MB max");
    expect(() =>
      assertVideoThumbnailAcceptable({
        size: 1,
        contentType: "image/png",
      }),
    ).toThrow("JPEG");
  });

  test("addMedia preserves insertion order across photos and videos", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstPhotoStorage, secondPhotoStorage, videoStorage] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );

    const firstPhoto = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: firstPhotoStorage,
      title: "First photo",
    });
    const secondPhoto = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: secondPhotoStorage,
      title: "Second photo",
    });
    const video = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: videoStorage,
      title: "Video",
    });

    const media = await t.query(api.media.forBand, { bandId });
    expect(media.map((row) => row._id)).toEqual([
      firstPhoto.mediaId,
      secondPhoto.mediaId,
      video.mediaId,
    ]);
    expect(media.map((row) => row.order)).toEqual([0, 1, 2]);
  });

  test("addMedia rejects members, strangers, and unauthenticated callers", async () => {
    const { t, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );

    const asMember = t.withIdentity({
      subject: "media_member",
      email: "media-member@example.com",
    });
    const { userId: memberId } = await asMember.mutation(
      api.users.ensureUser,
      {},
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: memberId,
        role: "member",
      });
    });
    await expect(
      asMember.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId,
        title: "Member upload",
      }),
    ).rejects.toThrow("Not an admin");

    const asStranger = t.withIdentity({
      subject: "media_stranger",
      email: "media-stranger@example.com",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId,
        title: "Stranger upload",
      }),
    ).rejects.toThrow("Not an admin");

    await expect(
      t.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId,
        title: "Anonymous upload",
      }),
    ).rejects.toThrow("Not signed in");
  });

  test("deleteMedia rejects an admin of a different band", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const { mediaId } = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId,
      title: "Band A photo",
    });

    const asOtherAdmin = t.withIdentity({
      subject: "other_band_admin",
      email: "other-band-admin@example.com",
    });
    await asOtherAdmin.mutation(api.users.ensureUser, {});
    await asOtherAdmin.mutation(api.bands.createBand, {
      name: "Other Band",
      genres: ["noise"],
      bio: "",
      area: "Bay Area",
      inviteHandles: [],
    });

    await expect(
      asOtherAdmin.mutation(api.media.deleteMedia, { mediaId }),
    ).rejects.toThrow("Not an admin");
  });

  test("media actions reject members and unauthenticated callers", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const { mediaId } = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId,
      title: "Admin upload",
    });

    const asMember = t.withIdentity({
      subject: "media_action_member",
      email: "media-action-member@example.com",
    });
    const { userId: memberId } = await asMember.mutation(
      api.users.ensureUser,
      {},
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: memberId,
        role: "member",
      });
    });

    await expect(
      asMember.mutation(api.media.pinMedia, { mediaId }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asMember.mutation(api.media.moveMedia, {
        mediaId,
        direction: "up",
      }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asMember.mutation(api.media.moveWithinKind, {
        mediaId,
        direction: "earlier",
      }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asMember.mutation(api.media.generateUploadUrl, { bandId }),
    ).rejects.toThrow("Not an admin");

    await expect(t.mutation(api.media.pinMedia, { mediaId })).rejects.toThrow(
      "Not signed in",
    );
    await expect(
      t.mutation(api.media.moveMedia, { mediaId, direction: "up" }),
    ).rejects.toThrow("Not signed in");
    await expect(
      t.mutation(api.media.moveWithinKind, {
        mediaId,
        direction: "earlier",
      }),
    ).rejects.toThrow("Not signed in");
    await expect(
      t.mutation(api.media.generateUploadUrl, { bandId }),
    ).rejects.toThrow("Not signed in");
  });

  test("addMedia rejects missing uploads and duplicate storage ids", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const deletedStorageId = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      await ctx.storage.delete(storageId);
      return storageId;
    });
    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId: deletedStorageId,
        title: "Missing",
      }),
    ).rejects.toThrow("Upload not found");

    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([4, 5, 6])])),
    );
    await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId,
      title: "Original",
    });
    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "video",
        storageId,
        title: "Duplicate",
      }),
    ).rejects.toThrow("already in this band's media");
  });

  test("addMedia rejects photo length metadata", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );

    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId,
        title: "Photo",
        lengthSec: 1,
      }),
    ).rejects.toThrow("lengthSec is only valid for video media");
  });

  test("addMedia rejects a band already at the media cap while upload URLs remain available", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [seedStorageId, newStorageId] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
    ]);
    await t.run(async (ctx) => {
      for (let order = 0; order < MAX_MEDIA_PER_BAND; order++) {
        await ctx.db.insert("bandMedia", {
          bandId,
          kind: "photo",
          storageId: seedStorageId,
          title: `Photo ${order}`,
          order,
          pinned: false,
        });
      }
    });

    await expect(
      asAdmin.mutation(api.media.addMedia, {
        bandId,
        kind: "photo",
        storageId: newStorageId,
        title: "One too many",
      }),
    ).rejects.toThrow(`at most ${MAX_MEDIA_PER_BAND}`);
    await expect(
      asAdmin.mutation(api.media.generateUploadUrl, { bandId }),
    ).resolves.toEqual(expect.any(String));
  });

  test("pinMedia changes the pinned video and rejects photos", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstStorageId, secondStorageId, photoStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const first = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: firstStorageId,
      title: "First",
    });
    const second = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: secondStorageId,
      title: "Second",
    });
    const photo = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: photoStorageId,
      title: "Photo",
    });

    await asAdmin.mutation(api.media.pinMedia, { mediaId: second.mediaId });
    const pinned = await t.run(async (ctx) => ({
      first: await ctx.db.get(first.mediaId),
      second: await ctx.db.get(second.mediaId),
    }));
    expect(pinned.first?.pinned).toBe(false);
    expect(pinned.second?.pinned).toBe(true);
    await expect(
      asAdmin.mutation(api.media.pinMedia, { mediaId: photo.mediaId }),
    ).rejects.toThrow("Only clips can be pinned");
  });

  test("moveMedia swaps global neighbors and no-ops at the ends", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [videoStorage1, photoStorage, videoStorage2] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      firstVideo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage1,
        title: "First video",
        order: 0,
        pinned: true,
      }),
      photo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorage,
        title: "Interposed photo",
        order: 1,
        pinned: false,
      }),
      secondVideo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage2,
        title: "Second video",
        order: 2,
        pinned: false,
      }),
    }));

    await asAdmin.mutation(api.media.moveMedia, {
      mediaId: ids.firstVideo,
      direction: "down",
    });
    let docs = await t.run(async (ctx) => ({
      firstVideo: await ctx.db.get(ids.firstVideo),
      photo: await ctx.db.get(ids.photo),
      secondVideo: await ctx.db.get(ids.secondVideo),
    }));
    expect(docs.firstVideo?.order).toBe(1);
    expect(docs.photo?.order).toBe(0);
    expect(docs.secondVideo?.order).toBe(2);

    await asAdmin.mutation(api.media.moveMedia, {
      mediaId: ids.photo,
      direction: "up",
    });
    await asAdmin.mutation(api.media.moveMedia, {
      mediaId: ids.secondVideo,
      direction: "down",
    });
    docs = await t.run(async (ctx) => ({
      firstVideo: await ctx.db.get(ids.firstVideo),
      photo: await ctx.db.get(ids.photo),
      secondVideo: await ctx.db.get(ids.secondVideo),
    }));
    expect(docs.firstVideo?.order).toBe(1);
    expect(docs.photo?.order).toBe(0);
    expect(docs.secondVideo?.order).toBe(2);
  });

  test("moveMedia moves a video above the preceding photo", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstPhotoStorage, videoStorage, lastPhotoStorage] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      firstPhoto: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: firstPhotoStorage,
        title: "First photo",
        order: 0,
        pinned: false,
      }),
      video: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage,
        title: "Video",
        order: 1,
        pinned: true,
      }),
      lastPhoto: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: lastPhotoStorage,
        title: "Last photo",
        order: 2,
        pinned: false,
      }),
    }));

    await asAdmin.mutation(api.media.moveMedia, {
      mediaId: ids.video,
      direction: "up",
    });
    const media = await t.query(api.media.forBand, { bandId });
    expect(media.map((row) => row._id)).toEqual([
      ids.video,
      ids.firstPhoto,
      ids.lastPhoto,
    ]);
    expect(media.map((row) => row.order)).toEqual([0, 1, 2]);
  });

  test("moveWithinKind swaps same-kind neighbors and no-ops at the edge", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [photoStorage1, videoStorage1, photoStorage2, videoStorage2] =
      await t.run(async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
        await ctx.storage.store(new Blob([new Uint8Array([4])])),
      ]);
    const ids = await t.run(async (ctx) => ({
      firstPhoto: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorage1,
        title: "First photo",
        order: 0,
        pinned: false,
      }),
      firstVideo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage1,
        title: "First video",
        order: 1,
        pinned: true,
      }),
      secondPhoto: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorage2,
        title: "Second photo",
        order: 2,
        pinned: false,
      }),
      secondVideo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorage2,
        title: "Second video",
        order: 3,
        pinned: false,
      }),
    }));

    await asAdmin.mutation(api.media.moveWithinKind, {
      mediaId: ids.secondPhoto,
      direction: "earlier",
    });
    let orders = await t.run(async (ctx) => ({
      firstPhoto: (await ctx.db.get(ids.firstPhoto))?.order,
      firstVideo: (await ctx.db.get(ids.firstVideo))?.order,
      secondPhoto: (await ctx.db.get(ids.secondPhoto))?.order,
      secondVideo: (await ctx.db.get(ids.secondVideo))?.order,
    }));
    expect(orders).toEqual({
      firstPhoto: 2,
      firstVideo: 1,
      secondPhoto: 0,
      secondVideo: 3,
    });

    await asAdmin.mutation(api.media.moveWithinKind, {
      mediaId: ids.secondPhoto,
      direction: "later",
    });
    orders = await t.run(async (ctx) => ({
      firstPhoto: (await ctx.db.get(ids.firstPhoto))?.order,
      firstVideo: (await ctx.db.get(ids.firstVideo))?.order,
      secondPhoto: (await ctx.db.get(ids.secondPhoto))?.order,
      secondVideo: (await ctx.db.get(ids.secondVideo))?.order,
    }));
    expect(orders).toEqual({
      firstPhoto: 0,
      firstVideo: 1,
      secondPhoto: 2,
      secondVideo: 3,
    });

    await expect(
      asAdmin.mutation(api.media.moveWithinKind, {
        mediaId: ids.firstPhoto,
        direction: "earlier",
      }),
    ).resolves.toBeNull();
    expect(
      await t.run(async (ctx) => ({
        firstPhoto: (await ctx.db.get(ids.firstPhoto))?.order,
        firstVideo: (await ctx.db.get(ids.firstVideo))?.order,
        secondPhoto: (await ctx.db.get(ids.secondPhoto))?.order,
        secondVideo: (await ctx.db.get(ids.secondVideo))?.order,
      })),
    ).toEqual(orders);
  });

  test("deleteMedia preserves the blob and repacks the remaining media", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [storage0, storage1, storage2] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
      await ctx.storage.store(new Blob([new Uint8Array([3])])),
    ]);
    const ids = await t.run(async (ctx) => [
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: storage0,
        title: "Zero",
        order: 0,
        pinned: false,
      }),
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: storage1,
        title: "One",
        order: 1,
        pinned: false,
      }),
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: storage2,
        title: "Two",
        order: 2,
        pinned: false,
      }),
    ]);

    await asAdmin.mutation(api.media.deleteMedia, { mediaId: ids[1] });
    const after = await t.run(async (ctx) => ({
      deletedBlob: await ctx.db.system.get("_storage", storage1),
      rows: await ctx.db
        .query("bandMedia")
        .withIndex("by_band_kind_order", (q) =>
          q.eq("bandId", bandId).eq("kind", "photo"),
        )
        .collect(),
    }));
    expect(after.deletedBlob).not.toBeNull();
    expect(after.rows.map((row) => row.order)).toEqual([0, 1]);
    expect(after.rows.map((row) => row._id)).toEqual([ids[0], ids[2]]);
  });

  test("deleteMedia preserves a blob shared with another band", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const sharedStorageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const bandAMedia = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: sharedStorageId,
      title: "Band A photo",
    });

    const asOtherAdmin = t.withIdentity({
      subject: "shared_blob_admin",
      email: "shared-blob-admin@example.com",
    });
    await asOtherAdmin.mutation(api.users.ensureUser, {});
    const { bandId: otherBandId } = await asOtherAdmin.mutation(
      api.bands.createBand,
      {
        name: "Shared Blob Band",
        genres: ["noise"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const bandBMedia = await asOtherAdmin.mutation(api.media.addMedia, {
      bandId: otherBandId,
      kind: "photo",
      storageId: sharedStorageId,
      title: "Band B photo",
    });

    await asAdmin.mutation(api.media.deleteMedia, {
      mediaId: bandAMedia.mediaId,
    });
    const otherBandMedia = await t.query(api.media.forBand, {
      bandId: otherBandId,
    });
    expect(otherBandMedia).toMatchObject([
      { _id: bandBMedia.mediaId, url: expect.any(String) },
    ]);
    expect(
      await t.run(async (ctx) =>
        ctx.db.system.get("_storage", sharedStorageId),
      ),
    ).not.toBeNull();
  });

  test("deleteMedia promotes a remaining video when the pinned video is deleted", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [firstStorageId, secondStorageId] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
    ]);
    const first = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: firstStorageId,
      title: "Pinned",
    });
    const second = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: secondStorageId,
      title: "Next",
    });

    await asAdmin.mutation(api.media.deleteMedia, { mediaId: first.mediaId });
    const remaining = await t.run(async (ctx) => ctx.db.get(second.mediaId));
    expect(remaining?.pinned).toBe(true);
    expect(remaining?.order).toBe(0);
  });

  test("band photo mutations validate media and clearing preserves the blob", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [photoStorageId, videoStorageId, otherStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const photo = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: photoStorageId,
      title: "Hero",
    });
    const video = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "video",
      storageId: videoStorageId,
      title: "Clip",
    });

    const asOtherAdmin = t.withIdentity({
      subject: "photo_other_admin",
      email: "photo-other-admin@example.com",
    });
    await asOtherAdmin.mutation(api.users.ensureUser, {});
    const { bandId: otherBandId } = await asOtherAdmin.mutation(
      api.bands.createBand,
      {
        name: "Photo Other Band",
        genres: ["rock"],
        bio: "",
        area: "Bay Area",
        inviteHandles: [],
      },
    );
    const otherPhoto = await asOtherAdmin.mutation(api.media.addMedia, {
      bandId: otherBandId,
      kind: "photo",
      storageId: otherStorageId,
      title: "Other hero",
    });

    await asAdmin.mutation(api.bands.setBandPhoto, {
      bandId,
      mediaId: photo.mediaId,
    });
    expect(
      await t.run(async (ctx) => (await ctx.db.get(bandId))?.imageStorageId),
    ).toBe(photoStorageId);
    await expect(
      asAdmin.mutation(api.bands.setBandPhoto, {
        bandId,
        mediaId: otherPhoto.mediaId,
      }),
    ).rejects.toThrow("different band");
    await expect(
      asAdmin.mutation(api.bands.setBandPhoto, {
        bandId,
        mediaId: video.mediaId,
      }),
    ).rejects.toThrow("Only photos");

    await asAdmin.mutation(api.bands.clearBandPhoto, { bandId });
    const cleared = await t.run(async (ctx) => ({
      band: await ctx.db.get(bandId),
      blob: await ctx.db.system.get("_storage", photoStorageId),
    }));
    expect(cleared.band?.imageStorageId).toBeUndefined();
    expect(cleared.blob).not.toBeNull();
  });

  test("deleteMedia clears the band photo when it deletes the hero row", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const storageId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );
    const { mediaId } = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId,
      title: "Hero",
    });
    await asAdmin.mutation(api.bands.setBandPhoto, { bandId, mediaId });

    await asAdmin.mutation(api.media.deleteMedia, { mediaId });
    const band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band?.imageStorageId).toBeUndefined();
  });
});

describe("media reads and validation", () => {
  async function setupBand() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "media_read_admin",
      email: "media-read-admin@example.com",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Media Read Band",
      genres: ["punk"],
      bio: "",
      area: "Bay Area",
      inviteHandles: [],
    });
    return { t, asAdmin, bandId };
  }

  test("assertUploadAcceptable enforces size and present content types", () => {
    expect(() =>
      assertUploadAcceptable(
        { size: MAX_MEDIA_BYTES + 1, contentType: "image/jpeg" },
        "photo",
      ),
    ).toThrow("too big");
    expect(() =>
      assertUploadAcceptable(
        { size: MAX_MEDIA_BYTES + 1, contentType: "video/mp4" },
        "video",
      ),
    ).toThrow("too big");
    expect(() =>
      assertUploadAcceptable(
        { size: MAX_MEDIA_BYTES, contentType: "video/mp4" },
        "photo",
      ),
    ).toThrow("can't be posted as a photo");
    expect(() =>
      assertUploadAcceptable(
        { size: MAX_MEDIA_BYTES, contentType: "image/jpeg" },
        "photo",
      ),
    ).not.toThrow();
    expect(() =>
      assertUploadAcceptable({ size: MAX_MEDIA_BYTES }, "photo"),
    ).not.toThrow();
    expect(() =>
      assertUploadAcceptable({ size: MAX_MEDIA_BYTES }, "video"),
    ).not.toThrow();
  });

  test("forBand is public, orders both kinds, resolves URLs, and marks only the hero", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [photoStorageId, videoStorageId, lastStorageId] = await t.run(
      async (ctx) => [
        await ctx.storage.store(new Blob([new Uint8Array([1])])),
        await ctx.storage.store(new Blob([new Uint8Array([2])])),
        await ctx.storage.store(new Blob([new Uint8Array([3])])),
      ],
    );
    const ids = await t.run(async (ctx) => ({
      photo: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: photoStorageId,
        title: "Hero photo",
        order: 0,
        pinned: false,
      }),
      video: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: videoStorageId,
        title: "Video",
        order: 1,
        pinned: true,
      }),
      lastPhoto: await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId: lastStorageId,
        title: "Last photo",
        order: 2,
        pinned: false,
      }),
    }));
    await asAdmin.mutation(api.bands.setBandPhoto, {
      bandId,
      mediaId: ids.photo,
    });

    const media = await t.query(api.media.forBand, { bandId });
    expect(media.map((row) => row._id)).toEqual([
      ids.photo,
      ids.video,
      ids.lastPhoto,
    ]);
    expect(media.map((row) => row.kind)).toEqual(["photo", "video", "photo"]);
    expect(media.map((row) => row.isHero)).toEqual([true, false, false]);
    expect(media[1].url).toEqual(expect.any(String));
    expect(media[1].thumbnailUrl).toBeNull();

    await t.run(async (ctx) => ctx.storage.delete(videoStorageId));
    const afterDelete = await t.query(api.media.forBand, { bandId });
    expect(afterDelete[1].url).toBeNull();
    expect(afterDelete.map((row) => row.isHero)).toEqual([true, false, false]);
  });

  test("forBand keeps legacy isHero aligned with avatar, not banner", async () => {
    const { t, asAdmin, bandId } = await setupBand();
    const [avatarStorageId, bannerStorageId] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
    ]);
    const avatar = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: avatarStorageId,
      title: "Avatar",
    });
    const banner = await asAdmin.mutation(api.media.addMedia, {
      bandId,
      kind: "photo",
      storageId: bannerStorageId,
      title: "Banner",
    });
    await asAdmin.mutation(api.bands.setBandAvatar, {
      bandId,
      mediaId: avatar.mediaId,
    });
    await asAdmin.mutation(api.bands.setBandBanner, {
      bandId,
      mediaId: banner.mediaId,
    });

    expect(await t.query(api.media.forBand, { bandId })).toMatchObject([
      {
        _id: avatar.mediaId,
        isHero: true,
        isAvatar: true,
        isBanner: false,
      },
      {
        _id: banner.mediaId,
        isHero: false,
        isAvatar: false,
        isBanner: true,
      },
    ]);
  });
});

describe("media:sweepOrphanBlobs", () => {
  test("deletes an orphan and preserves every supported storage reference", async () => {
    const t = convexTest(schema);
    const [
      orphanId,
      mediaStorageId,
      thumbnailStorageId,
      heroStorageId,
      avatarStorageId,
      flyerStorageId,
    ] = await t.run(async (ctx) => [
      await ctx.storage.store(new Blob([new Uint8Array([0])])),
      await ctx.storage.store(new Blob([new Uint8Array([1])])),
      await ctx.storage.store(new Blob([new Uint8Array([2])])),
      await ctx.storage.store(new Blob([new Uint8Array([3])])),
      await ctx.storage.store(new Blob([new Uint8Array([4])])),
      await ctx.storage.store(new Blob([new Uint8Array([5])])),
    ]);

    await t.run(async (ctx) => {
      const bandId = await ctx.db.insert("bands", {
        name: "Sweep Band",
        genres: ["punk"],
        area: "Bay Area",
        colorHex: "#000000",
        initials: "SB",
        followerCount: 0,
        pastShows: [],
        slug: "sweep-band",
        imageStorageId: heroStorageId,
      });
      await ctx.db.insert("bandMedia", {
        bandId,
        kind: "video",
        storageId: mediaStorageId,
        thumbnailStorageId,
        title: "Referenced media",
        order: 0,
        pinned: false,
      });
      await ctx.db.insert("users", {
        clerkId: "sweep_avatar_user",
        name: "Avatar User",
        email: "avatar@example.com",
        genres: [],
        attendedCount: 0,
        avatarStorageId,
      });
      const venueId = await ctx.db.insert("venues", {
        name: "Sweep Venue",
        area: "Bay Area",
        addr: "1 Test St",
        distSF: "0 mi",
        distOak: "0 mi",
        lat: 0,
        lng: 0,
      });
      await ctx.db.insert("gigs", {
        title: "Sweep Gig",
        venueId,
        price: 0,
        startsAt: Date.now() + 1_000,
        doorsTime: "8PM",
        flyKey: "custom",
        lineup: [bandId],
        genres: ["punk"],
        desc: "",
        ticketing: "rsvp",
        cap: "No cap",
        goingCount: 0,
        flyStorageId: flyerStorageId,
      });
    });

    const result = await t.mutation(internal.media.sweepOrphanBlobs, {
      graceMs: 0,
      dryRun: false,
    });
    expect(result).toMatchObject({
      scanned: 6,
      deleted: 1,
      wouldDelete: 0,
      skipped: 5,
      aborted: false,
      done: true,
    });
    const blobs = await t.run(async (ctx) => ({
      orphan: await ctx.db.system.get("_storage", orphanId),
      media: await ctx.db.system.get("_storage", mediaStorageId),
      thumbnail: await ctx.db.system.get("_storage", thumbnailStorageId),
      hero: await ctx.db.system.get("_storage", heroStorageId),
      avatar: await ctx.db.system.get("_storage", avatarStorageId),
      flyer: await ctx.db.system.get("_storage", flyerStorageId),
    }));
    expect(blobs.orphan).toBeNull();
    expect(blobs.media).not.toBeNull();
    expect(blobs.thumbnail).not.toBeNull();
    expect(blobs.hero).not.toBeNull();
    expect(blobs.avatar).not.toBeNull();
    expect(blobs.flyer).not.toBeNull();
  });

  test("defaults to a dry run and leaves an orphan intact", async () => {
    const t = convexTest(schema);
    const orphanId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );

    const result = await t.mutation(internal.media.sweepOrphanBlobs, {
      graceMs: 0,
    });
    expect(result.wouldDelete).toBe(1);
    expect(result.deleted).toBe(0);
    expect(
      await t.run(async (ctx) => ctx.db.system.get("_storage", orphanId)),
    ).not.toBeNull();
  });

  test("skips a fresh orphan inside the grace window", async () => {
    const t = convexTest(schema);
    const orphanId = await t.run(async (ctx) =>
      ctx.storage.store(new Blob([new Uint8Array([1, 2, 3])])),
    );

    const result = await t.mutation(internal.media.sweepOrphanBlobs, {
      graceMs: 1_000_000_000_000,
      dryRun: false,
    });
    expect(result).toMatchObject({ deleted: 0, wouldDelete: 0, skipped: 1 });
    expect(
      await t.run(async (ctx) => ctx.db.system.get("_storage", orphanId)),
    ).not.toBeNull();
  });
});
