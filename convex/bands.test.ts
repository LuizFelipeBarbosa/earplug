import { convexTest } from "convex-test";
import { describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { bandColorFor } from "./lib/helpers";
import schema from "./schema";

describe("bands: slugs and profile updates", () => {
  async function setup() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "user_admin",
      email: "a@x.com",
      name: "Admin Artist",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    return { t, asAdmin };
  }

  const bandArgs = {
    genres: ["punk"],
    bio: "",
    area: "Bay Area",
    inviteHandles: [],
  };

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
    expect(first.band._id).toBe(first.bandId);
    expect(second.band._id).toBe(second.bandId);
    expect(await t.query(api.bands.bySlug, { slug: "nobody" })).toBeNull();
  });

  test("createBand persists the area and links the sheets collect", async () => {
    const { t, asAdmin } = await setup();
    const { bandId, slug, band } = await asAdmin.mutation(
      api.bands.createBand,
      {
        name: "Static Bloom",
        genres: ["punk", "shoegaze"],
        bio: "Two amps facing each other.",
        inviteHandles: ["@mara.k"],
        area: "Bernal Heights, SF",
        linkIg: "@staticbloom",
        linkBc: "staticbloom.bandcamp.com",
        linkYt: "youtube.com/@staticbloom",
      },
    );

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.area).toBe("Bernal Heights, SF");
    expect(doc?.linkIg).toBe("@staticbloom");
    expect(doc?.linkBc).toBe("staticbloom.bandcamp.com");
    expect(doc?.linkYt).toBe("youtube.com/@staticbloom");
    expect(band.linkYt).toBe("youtube.com/@staticbloom");
    expect((await t.query(api.bands.bySlug, { slug }))?.linkYt).toBe(
      "youtube.com/@staticbloom",
    );
    expect(doc?.bio).toBe("Two amps facing each other.");
    expect(doc?.credits).toBeUndefined();
    // Legacy clients may still send this field, but fake handles are no longer
    // written or presented as memberships.
    expect(doc?.inviteHandles).toBeUndefined();
    // Fake handles are ignored, so only the admin membership counts.
    expect(doc?.followerCount).toBe(1);
    expect(doc?.slug).toBe(slug);
  });

  test("createBand ignores legacy invite handles and counts only the admin", async () => {
    const { t, asAdmin } = await setup();
    const user = await asAdmin.query(api.users.me, {});
    const inviteHandles = ["@a", "@b", "@c"];
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Invite Arithmetic",
      genres: ["math rock"],
      bio: "",
      area: "Bay Area",
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
    expect(band?.inviteHandles).toBeUndefined();
  });

  test("createBand requires a nonblank home base", async () => {
    const { t, asAdmin } = await setup();
    await expect(
      asAdmin.mutation(api.bands.createBand, {
        ...bandArgs,
        name: "Static Bloom",
        area: "  ",
      }),
    ).rejects.toThrow("home base");
    expect(await t.run(async (ctx) => ctx.db.query("bands").take(1))).toEqual(
      [],
    );
  });

  test("updateProfile edits the same band and keeps its slug", async () => {
    const { t, asAdmin } = await setup();
    const { bandId, slug } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      ...bandArgs,
    });

    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      name: " Static Gloom ",
      genres: ["punk", "shoegaze"],
      area: "Berkeley",
      bio: " New record soon. ",
      linkIg: "@staticgloom",
      linkBc: "staticgloom.bandcamp.com",
      linkYt: "youtube.com/@staticgloom",
      credits: " Produced by Mara. ",
    });

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.name).toBe("Static Gloom");
    expect(doc?.initials).toBe("SG");
    expect(doc?.genres).toEqual(["punk", "shoegaze"]);
    expect(doc?.area).toBe("Berkeley");
    expect(doc?.bio).toBe("New record soon.");
    expect(doc?.linkIg).toBe("@staticgloom");
    expect(doc?.linkBc).toBe("staticgloom.bandcamp.com");
    expect(doc?.linkYt).toBe("youtube.com/@staticgloom");
    expect(doc?.credits).toBe("Produced by Mara.");
    // Shared links must survive a rename.
    expect(doc?.slug).toBe(slug);
    // So must the band's color: it is the identity people recognize in the
    // feed. Initials follow the name, the swatch under them does not.
    expect(doc?.colorHex).toBe(bandColorFor("Static Bloom"));

    const resolved = await t.query(api.bands.bySlug, { slug });
    expect(resolved?.name).toBe("Static Gloom");
  });

  test("updateProfile remains compatible with partial and pre-credits clients", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      genres: ["punk"],
      bio: "Old bio",
      area: "Oakland",
      credits: "Existing credits",
    });

    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      bio: " Updated alone. ",
    });
    expect(await t.run(async (ctx) => ctx.db.get(bandId))).toMatchObject({
      name: "Static Bloom",
      genres: ["punk"],
      area: "Oakland",
      bio: "Updated alone.",
      credits: "Existing credits",
    });

    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      name: "SOBO",
      genres: ["rock"],
      area: "Berkeley",
      bio: "Full legacy save",
      inviteHandles: ["@legacy"],
      linkIg: "@sobo",
      linkBc: "",
      linkYt: "",
    });
    const updated = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(updated).toMatchObject({
      name: "SOBO",
      initials: "SO",
      genres: ["rock"],
      area: "Berkeley",
      bio: "Full legacy save",
      credits: "Existing credits",
    });
    expect(updated?.inviteHandles).toBeUndefined();
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
        genres: ["punk"],
        area: "Oakland",
        bio: "",
        linkIg: "",
        linkBc: "",
        linkYt: "",
        credits: "",
      }),
    ).rejects.toThrow();
  });

  test("updateProfile validates before its single atomic patch", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Before",
      genres: ["punk"],
      area: "Oakland",
      bio: "Old bio",
    });

    await expect(
      asAdmin.mutation(api.bands.updateProfile, {
        bandId,
        name: "After",
        genres: ["one", "two", "three", "four"],
        area: "Berkeley",
        bio: "New bio",
        linkIg: "@after",
        linkBc: "after.bandcamp.com",
        linkYt: "youtube.com/@after",
        credits: "New credits",
      }),
    ).rejects.toThrow("no more than three");

    expect(await t.run(async (ctx) => ctx.db.get(bandId))).toMatchObject({
      name: "Before",
      genres: ["punk"],
      area: "Oakland",
      bio: "Old bio",
    });
  });

  test("updateProfile clears blank optional fields", async () => {
    const { t, asAdmin } = await setup();
    const { bandId } = await asAdmin.mutation(api.bands.createBand, {
      name: "Static Bloom",
      genres: ["punk"],
      bio: "Old bio",
      area: "Bay Area",
      linkIg: "@old",
      credits: "Old credits",
    });
    await asAdmin.mutation(api.bands.updateProfile, {
      bandId,
      name: "Static Bloom",
      genres: ["punk"],
      area: "Bay Area",
      bio: " ",
      linkIg: " ",
      linkBc: "",
      linkYt: "",
      credits: " ",
    });

    const doc = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(doc?.bio).toBeUndefined();
    expect(doc?.linkIg).toBeUndefined();
    expect(doc?.credits).toBeUndefined();
    expect(await t.query(api.bands.get, { bandId })).toMatchObject({
      bio: "",
      linkIg: null,
      credits: null,
    });
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

describe("bands:archive", () => {
  test("archives safely, cancels future owned gigs, and preserves historical and shared rows", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-08-28T12:00:00Z"));
    try {
      const t = convexTest(schema);
      const asAdmin = t.withIdentity({
        subject: "archive_admin",
        email: "archive@x.com",
      });
      const { userId: adminId } = await asAdmin.mutation(
        api.users.ensureUser,
        {},
      );
      const archived = await asAdmin.mutation(api.bands.createBand, {
        name: "Archive Me",
        genres: ["punk"],
        bio: "",
        area: "Oakland",
        inviteHandles: [],
      });
      const other = await asAdmin.mutation(api.bands.createBand, {
        name: "Keep Me",
        genres: ["punk"],
        bio: "",
        area: "Oakland",
        inviteHandles: [],
      });
      const venueId = await t.run((ctx) =>
        ctx.db.insert("venues", {
          name: "Archive Room",
          area: "Oakland",
          addr: "1 Archive Way",
          distSF: "8 mi",
          distOak: "1 mi",
          lat: 37.8,
          lng: -122.27,
        }),
      );
      const future = await asAdmin.mutation(api.gigs.publishGig, {
        bandId: archived.bandId,
        title: "Future Owned",
        startsAt: Date.now() + 86_400_000,
        doorsTime: "8PM / 9PM",
        venueId,
        price: 0,
        flyKey: "xerox",
        ticketing: "rsvp",
        ageRequirement: "allAges",
        cap: "No cap",
      });
      const project = (
        await asAdmin.query(api.gigs.manageForBand, { bandId: archived.bandId })
      ).find((candidate) => candidate.publicGigId === future.gigId)!;
      const performerProject = await asAdmin.mutation(api.gigs.addPerformer, {
        projectId: project._id,
        kind: "invited",
        role: "support",
        name: "Invited Band",
      });
      const performerToken = performerProject.performers
        .find((performer) => performer.kind === "invited")!
        .inviteUrl!.split("/")
        .pop()!;
      const bandInvite = await asAdmin.mutation(api.bandInvites.create, {
        bandId: archived.bandId,
      });
      const legacyInviteIds = await t.run(async (ctx) => [
        await ctx.db.insert("bandInvites", {
          bandId: archived.bandId,
          token: "legacy-archive-invite-1",
          createdBy: adminId,
          expiresAt: Date.now() + 86_400_000,
          revoked: false,
          expired: false,
        }),
        await ctx.db.insert("bandInvites", {
          bandId: archived.bandId,
          token: "legacy-archive-invite-2",
          createdBy: adminId,
          expiresAt: Date.now() + 86_400_000,
          revoked: false,
          expired: false,
        }),
      ]);
      const { legacyFutureGigId, pastGigId, sharedGigId } = await t.run(
        async (ctx) => {
          const common = {
            venueId,
            price: 0,
            doorsTime: "8PM / 9PM",
            flyKey: "paper",
            genres: ["punk"],
            desc: "",
            ticketing: "rsvp" as const,
            ageRequirement: "allAges" as const,
            cap: "No cap",
            goingCount: 0,
            lifecycle: "published" as const,
          };
          const pastGigId = await ctx.db.insert("gigs", {
            ...common,
            title: "Past Owned",
            slug: "past-owned",
            startsAt: Date.now() - 86_400_000,
            doorsAt: Date.now() - 86_400_000,
            lineup: [archived.bandId],
            createdByBand: archived.bandId,
          });
          const legacyFutureGigId = await ctx.db.insert("gigs", {
            ...common,
            title: "Legacy Future Owned",
            slug: "legacy-future-owned",
            startsAt: Date.now() + 2 * 86_400_000,
            doorsAt: Date.now() + 2 * 86_400_000,
            lineup: [archived.bandId],
            createdByBand: archived.bandId,
          });
          await ctx.db.insert("gigBands", {
            gigId: legacyFutureGigId,
            bandId: archived.bandId,
            startsAt: Date.now() + 2 * 86_400_000,
          });
          const sharedGigId = await ctx.db.insert("gigs", {
            ...common,
            title: "Shared Future",
            slug: "shared-future",
            startsAt: Date.now() + 2 * 86_400_000,
            doorsAt: Date.now() + 2 * 86_400_000,
            lineup: [archived.bandId, other.bandId],
            createdByBand: other.bandId,
          });
          return { legacyFutureGigId, pastGigId, sharedGigId };
        },
      );

      const firstArchive = await asAdmin.mutation(api.bands.archive, {
        bandId: archived.bandId,
      });
      expect(firstArchive).toMatchObject({
        bandId: archived.bandId,
        alreadyArchived: false,
      });
      expect(
        await asAdmin.query(api.bands.archiveStatus, {
          bandId: archived.bandId,
        }),
      ).toEqual({
        bandId: archived.bandId,
        archivedAt: firstArchive.archivedAt,
      });
      await t.finishAllScheduledFunctions(() => vi.runAllTimers());

      const state = await t.run(async (ctx) => ({
        band: await ctx.db.get(archived.bandId),
        future: await ctx.db.get(future.gigId),
        project: await ctx.db.get(project._id),
        legacyFuture: await ctx.db.get(legacyFutureGigId),
        past: await ctx.db.get(pastGigId),
        shared: await ctx.db.get(sharedGigId),
        performer: await ctx.db
          .query("gigProjectPerformers")
          .withIndex("by_invite_token", (q) =>
            q.eq("inviteToken", performerToken),
          )
          .first(),
        legacyInvites: await Promise.all(
          legacyInviteIds.map((inviteId) => ctx.db.get(inviteId)),
        ),
      }));
      expect(state.band?.archivedAt).toBeDefined();
      expect(state.future?.lifecycle).toBe("cancelled");
      expect(state.project?.status).toBe("cancelled");
      expect(state.legacyFuture?.lifecycle).toBe("cancelled");
      expect(state.past?.lifecycle).toBe("published");
      expect(state.shared?.lifecycle).toBe("published");
      expect(state.performer?.inviteRevoked).toBe(true);
      expect(state.legacyInvites.every((invite) => invite?.revoked)).toBe(true);
      expect(
        await t.query(api.bands.bySlug, { slug: archived.slug }),
      ).toBeNull();
      expect(
        await t.query(api.gigs.resolvePublic, { ref: future.slug }),
      ).toBeNull();
      expect(
        await t.query(api.gigs.resolvePublic, { ref: "past-owned" }),
      ).toBeNull();
      expect(
        (await t.query(api.gigs.resolvePublic, { ref: "shared-future" }))?._id,
      ).toBe(sharedGigId);
      expect(
        await t.query(api.bandInvites.resolve, {
          token: bandInvite.token,
          now: Date.now(),
        }),
      ).toBeNull();
      expect(
        await t.query(api.gigs.resolvePerformerInvite, {
          token: performerToken,
        }),
      ).toBeNull();
      expect(
        (await asAdmin.query(api.bands.myBands, {})).map((row) => row.band._id),
      ).not.toContain(archived.bandId);

      const lateLegacyInviteId = await t.run((ctx) =>
        ctx.db.insert("bandInvites", {
          bandId: archived.bandId,
          token: "late-legacy-token",
          expiresAt: Date.now() + 86_400_000,
          createdBy: adminId,
          revoked: false,
          expired: false,
        }),
      );
      expect(
        await asAdmin.mutation(api.bands.archive, {
          bandId: archived.bandId,
        }),
      ).toEqual({
        bandId: archived.bandId,
        archivedAt: firstArchive.archivedAt,
        alreadyArchived: true,
      });
      await t.finishAllScheduledFunctions(() => vi.runAllTimers());
      expect(
        (await t.run((ctx) => ctx.db.get(lateLegacyInviteId)))?.revoked,
      ).toBe(true);
    } finally {
      vi.useRealTimers();
    }
  });
});

describe("bands: public profile details and setup status", () => {
  async function setup() {
    const t = convexTest(schema);
    const asAdmin = t.withIdentity({
      subject: "setup_admin",
      email: "admin@setup.test",
      name: "Ada Admin",
    });
    await asAdmin.mutation(api.users.ensureUser, {});
    const created = await asAdmin.mutation(api.bands.createBand, {
      name: "Setup Band",
      genres: ["punk"],
      area: "Oakland",
      bio: "A complete setup profile.",
      credits: "Recorded by Ren",
      linkBc: "setup.bandcamp.com",
      linkYt: "youtube.com/@setup",
      linkIg: "@setup",
    });
    return { t, asAdmin, bandId: created.bandId };
  }

  test("profileDetails exposes links, credits, and accepted live member names", async () => {
    const { t, bandId } = await setup();
    const asMember = t.withIdentity({
      subject: "setup_member",
      email: "member@setup.test",
      name: "Mika Member",
    });
    await asMember.mutation(api.users.ensureUser, {});
    const member = await asMember.query(api.users.me, {});
    await t.run(async (ctx) => {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: member!._id,
        role: "member",
      });
    });

    expect(await t.query(api.bands.profileDetails, { bandId })).toEqual({
      credits: "Recorded by Ren",
      linkIg: "@setup",
      linkBc: "setup.bandcamp.com",
      linkYt: "youtube.com/@setup",
      memberNames: ["Ada Admin", "Mika Member"],
    });
  });

  test("setupStatus derives all seven flags and preview is member-accessible", async () => {
    const { t, asAdmin, bandId } = await setup();
    expect(await asAdmin.query(api.bands.setupStatus, { bandId })).toEqual({
      profileComplete: true,
      profileImageAdded: false,
      musicAdded: true,
      socialLinksAdded: true,
      firstGigCreated: false,
      membersInvited: false,
      publicProfilePreviewed: false,
    });

    const asMember = t.withIdentity({
      subject: "setup_member",
      email: "member@setup.test",
      name: "Mika Member",
    });
    await asMember.mutation(api.users.ensureUser, {});
    const member = await asMember.query(api.users.me, {});
    await t.run(async (ctx) => {
      const imageStorageId = await ctx.storage.store(new Blob(["image"]));
      await ctx.db.patch(bandId, { imageStorageId });
      const gigId = await ctx.db.insert("gigs", {
        title: "First gig",
        venueId: await ctx.db.insert("venues", {
          name: "Room",
          area: "Oakland",
          addr: "1 Main",
          distSF: "10 mi",
          distOak: "1 mi",
          lat: 0,
          lng: 0,
        }),
        price: 0,
        startsAt: 1,
        doorsTime: "8PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: ["punk"],
        desc: "",
        ticketing: "rsvp",
        cap: "No cap",
        goingCount: 0,
      });
      await ctx.db.insert("gigBands", { gigId, bandId, startsAt: 1 });
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: member!._id,
        role: "member",
      });
    });
    await asMember.mutation(api.bands.markPreviewed, { bandId });

    expect(await asAdmin.query(api.bands.setupStatus, { bandId })).toEqual({
      profileComplete: true,
      profileImageAdded: true,
      musicAdded: true,
      socialLinksAdded: true,
      firstGigCreated: true,
      membersInvited: true,
      publicProfilePreviewed: true,
    });
  });

  test("setupStatus rejects non-admins and markPreviewed rejects strangers", async () => {
    const { t, bandId } = await setup();
    const asStranger = t.withIdentity({
      subject: "setup_stranger",
      email: "stranger@setup.test",
    });
    await asStranger.mutation(api.users.ensureUser, {});
    await expect(
      asStranger.query(api.bands.setupStatus, { bandId }),
    ).rejects.toThrow("Not an admin");
    await expect(
      asStranger.mutation(api.bands.markPreviewed, { bandId }),
    ).rejects.toThrow("Not a member");
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
