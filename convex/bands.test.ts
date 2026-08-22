import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
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
    // Invite handles are stored strings, not members, so only the admin counts.
    expect(doc?.followerCount).toBe(1);
    expect(doc?.slug).toBe(slug);
  });

  test("createBand counts only the admin row, not invite handles", async () => {
    const { t, asAdmin } = await setup();
    const user = await asAdmin.query(api.users.me, {});
    const inviteHandles = ["@a", "@b", "@c"];
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Invite Arithmetic",
      genres: ["math rock"],
      bio: "",
      inviteHandles,
    });

    const { band, memberships, follows } = await t.run(async (ctx) => ({
      band: await ctx.db.get(bandId),
      memberships: await ctx.db
        .query("bandMembers")
        .withIndex("by_band", (q) => q.eq("bandId", bandId))
        .take(10),
      follows: await ctx.db
        .query("follows")
        .withIndex("by_band", (q) => q.eq("bandId", bandId))
        .take(10),
    }));

    expect(band?.followerCount).toBe(1);
    expect(memberships).toHaveLength(1);
    expect(memberships[0]).toMatchObject({ role: "admin", userId: user!._id });
    expect(follows).toHaveLength(0);
    expect(band?.inviteHandles).toEqual(inviteHandles);
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

describe("bands: array-shaped query contract", () => {
  test("list paginates every band continuously in name order", async () => {
    const t = convexTest(schema);
    await t.run(async (ctx) => {
      for (const name of [
        "Zulu Static",
        "Beta Noise",
        "Echo Park",
        "Alpha Set",
        "Delta Wave",
      ]) {
        await ctx.db.insert("bands", {
          name,
          slug: name.toLowerCase().replace(/\s+/g, "-"),
          genres: ["punk"],
          area: "Bay Area",
          colorHex: "#7B8FFF",
          initials: name.slice(0, 2).toUpperCase(),
          followerCount: 0,
          bio: "",
          pastShows: [],
        });
      }
    });

    const names: string[] = [];
    let cursor: string | null = null;
    let isDone = false;
    do {
      const result: {
        page: Array<{ name: string }>;
        continueCursor: string;
        isDone: boolean;
      } = await t.query(api.bands.list, {
        paginationOpts: { numItems: 2, cursor },
      });
      names.push(...result.page.map((band) => band.name));
      cursor = result.continueCursor;
      isDone = result.isDone;
    } while (!isDone);

    expect(names).toEqual([
      "Alpha Set",
      "Beta Noise",
      "Delta Wave",
      "Echo Park",
      "Zulu Static",
    ]);
    expect(new Set(names).size).toBe(names.length);
  });

  test("search is a top-level array; q: '' returns every band", async () => {
    const t = convexTest(schema);
    await t.mutation(internal.seed.seedDemo, {});

    const all = await t.query(api.bands.search, { q: "" });
    expect(Array.isArray(all)).toBe(true);
    expect(all.length).toBe(6);

    const hits = await t.query(api.bands.search, { q: "Foghorn" });
    expect(hits.length).toBe(1);
    expect(hits[0].name).toBe("Foghorn Diet");
  });

  test("myBands is [] when unauthenticated, even with bands present", async () => {
    const t = convexTest(schema);
    await t.mutation(internal.seed.seedDemo, {});
    expect(await t.query(api.bands.myBands, {})).toEqual([]);
  });
});
