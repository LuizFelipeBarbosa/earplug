import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { bandColorFor } from "./lib/helpers";
import schema from "./schema";

describe("bands: slugs and profile updates", () => {
  async function setup() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({ subject: "user_admin", email: "a@x.com" });
    await asAdmin.mutation(api.users.ensureUser, {});
    return { t, asAdmin };
  }

  const bandArgs = { genres: ["punk"], bio: "", inviteHandles: [] };

  test("createBand issues unique slugs and bySlug resolves them", async () => {
    const { t, asAdmin } = await setup();
    const first = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });
    const second = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom!",
      ...bandArgs,
    });
    expect(first.slug).toBe("static-bloom");
    expect(second.slug).toBe("static-bloom-2");

    const resolved = await t.query(api.bands.bySlug, {
      slug: "static-bloom-2",
    });
    expect(resolved?._id).toBe(second.bandId);
    expect(await t.query(api.bands.bySlug, { slug: "nobody" })).toBeNull();
  });

  test("createBand persists the area and links the sheets collect", async () => {
    const { t, asAdmin } = await setup();
    const { bandId, slug } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      genres: ["punk", "shoegaze"],
      bio: "Two amps facing each other.",
      inviteHandles: ["@mara.k"],
      area: "Bernal Heights, SF",
      linkIg: "@staticbloom",
      linkBc: "staticbloom.bandcamp.com",
      linkYt: "youtube.com/@staticbloom",
    });

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.area).toBe("Bernal Heights, SF");
    expect(doc?.linkIg).toBe("@staticbloom");
    expect(doc?.linkBc).toBe("staticbloom.bandcamp.com");
    expect(doc?.linkYt).toBe("youtube.com/@staticbloom");
    expect(doc?.bio).toBe("Two amps facing each other.");
    expect(doc?.inviteHandles).toEqual(["@mara.k"]);
    // followerCount seeds from the crew: you plus everyone invited.
    expect(doc?.followerCount).toBe(2);
    expect(doc?.slug).toBe(slug);
  });

  test("createBand without an area falls back to the Bay Area default", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });
    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.area).toBe("Bay Area");
  });

  test("updateProfile edits the same band and keeps its slug", async () => {
    const { t, asAdmin } = await setup();
    const { bandId, slug } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });

    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      name: "Static Gloom",
      genres: ["punk", "shoegaze"],
      area: "Berkeley",
      inviteHandles: ["@mara.k"],
      linkIg: "@staticgloom",
    });

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.name).toBe("Static Gloom");
    expect(doc?.initials).toBe("SG");
    expect(doc?.genres).toEqual(["punk", "shoegaze"]);
    expect(doc?.area).toBe("Berkeley");
    expect(doc?.inviteHandles).toEqual(["@mara.k"]);
    expect(doc?.linkIg).toBe("@staticgloom");
    // Shared links must survive a rename.
    expect(doc?.slug).toBe(slug);
    // So must the band's color: it is the identity people recognize in the
    // feed. Initials follow the name, the swatch under them does not.
    expect(doc?.colorHex).toBe(bandColorFor("Static Bloom"));

    const resolved = await t.query(api.bands.bySlug, { slug });
    expect(resolved?.name).toBe("Static Gloom");
  });

  test("updateProfile rejects non-admins", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });

    const asStranger = t.withIdentity({
      subject: "user_stranger",
      email: "s@x.com",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.mutation(api.bands.updateProfile, {
        bandId,
        name: "Hijacked",
      }),
    ).rejects.toThrow();
  });

  test("get resolves heroUrl from the selected live photo", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });
    expect((await t.query(api.bands.get, { bandId }))?.heroUrl).toBeNull();

    const { storageId, mediaId } = await t.run(async (ctx) => {
      const storageId = await ctx.storage.store(
        new Blob([new Uint8Array([1, 2, 3])]),
      );
      const mediaId = await ctx.db.insert("bandMedia", {
        bandId,
        kind: "photo",
        storageId,
        title: "Band photo",
        order: 0,
        pinned: false,
      });
      return { storageId, mediaId };
    });
    await asAdmin.mutation(api.bands.setBandPhoto, { bandId, mediaId });
    expect((await t.query(api.bands.get, { bandId }))?.heroUrl).toEqual(
      expect.any(String),
    );

    await t.run(async (ctx) => ctx.storage.delete(storageId));
    expect((await t.query(api.bands.get, { bandId }))?.heroUrl).toBeNull();
    expect(
      await t.run(async (ctx) => (await ctx.db.get(bandId))?.imageStorageId),
    ).toBe(storageId);
  });
});
