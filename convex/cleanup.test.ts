import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { Id } from "./_generated/dataModel";
import { internal } from "./_generated/api";
import schema from "./schema";

const LAUNCH_DATE = 1775266200000; // 2026-04-03 6:30PM PT
const DUPE_EMAIL = "dupe@example.com";

type GigOverrides = {
  title: string;
  venueId: Id<"venues">;
  lineup: Id<"bands">[];
  startsAt?: number;
  goingCount?: number;
};

function gigRow(overrides: GigOverrides) {
  return {
    price: 0,
    doorsTime: "8PM / 9PM",
    flyKey: "paper",
    genres: ["punk"],
    desc: "",
    ticketing: "rsvp" as const,
    cap: "No cap",
    startsAt: LAUNCH_DATE,
    goingCount: 0,
    ...overrides,
  };
}

/** Mirrors the shape of dev after `migrations:migrateAll`: real rows and
 * seeded demo rows side by side, legacy tables still populated. */
async function seedPostMigrationFixture() {
  const t = convexTest(schema);
  const fixture = await t.run(async (ctx) => {
    // Two rows for one person, oldest first — the survivor holds the data.
    const survivor = await ctx.db.insert("users", {
      clerkId: "user_old",
      name: "Luiz B.",
      email: DUPE_EMAIL,
      genres: ["punk"],
      attendedCount: 0,
    });
    const duplicate = await ctx.db.insert("users", {
      clerkId: "user_new",
      name: "Luiz B.",
      email: DUPE_EMAIL,
      genres: [],
      attendedCount: 0,
    });
    const fan = await ctx.db.insert("users", {
      clerkId: "user_fan",
      name: "Anandi J.",
      email: "anandi@example.com",
      genres: [],
      attendedCount: 0,
    });
    const e2eUser = await ctx.db.insert("users", {
      clerkId: "user_e2e",
      name: "e2e+clerk_test",
      email: "e2e+clerk_test@example.com",
      genres: [],
      attendedCount: 0,
    });

    const earplug = await ctx.db.insert("bands", {
      name: "EARPLUG",
      slug: "earplug",
      genres: ["indie"],
      area: "Berkeley, CA",
      colorHex: "#7B8FFF",
      initials: "EP",
      followerCount: 1,
      pastShows: [{ title: "EARPLUG LAUNCH NIGHT", meta: "APR 3" }],
    });
    const sobo = await ctx.db.insert("bands", {
      name: "SOBO",
      slug: "sobo",
      genres: ["rock"],
      area: "Berkeley, CA",
      colorHex: "#E4DC4A",
      initials: "SO",
      followerCount: 1,
      pastShows: [],
    });
    const testBand = await ctx.db.insert("bands", {
      name: "test band",
      slug: "test-band",
      genres: [],
      area: "Bay Area",
      colorHex: "#000000",
      initials: "TB",
      followerCount: 1,
      pastShows: [],
    });
    const demoBand = await ctx.db.insert("bands", {
      name: "Foghorn Diet",
      slug: "foghorn-diet",
      genres: ["garage"],
      area: "Mission, SF",
      colorHex: "#7B8FFF",
      initials: "FD",
      followerCount: 486,
      pastShows: [],
    });

    const realVenue = await ctx.db.insert("venues", {
      name: "Theta Chi Fraternity",
      area: "Berkeley",
      addr: "2499 Piedmont Ave",
      distSF: "11.0 mi",
      distOak: "4.0 mi",
      lat: 37.868,
      lng: -122.25,
    });
    const demoVenue = await ctx.db.insert("venues", {
      name: "The Foghorn Club",
      area: "Mission, SF",
      addr: "2455 Harrison St",
      distSF: "0.8 mi",
      distOak: "6.3 mi",
      lat: 37.7524,
      lng: -122.418,
    });

    const launchGig = await ctx.db.insert(
      "gigs",
      gigRow({
        title: "EARPLUG LAUNCH NIGHT",
        venueId: realVenue,
        lineup: [earplug],
        goingCount: 25,
      }),
    );
    const demoGig = await ctx.db.insert(
      "gigs",
      gigRow({
        title: "Riptide Release Show",
        venueId: demoVenue,
        lineup: [demoBand],
      }),
    );

    // Attachments that must survive the merge, split across both user rows.
    await ctx.db.insert("bandMembers", { bandId: earplug, userId: survivor, role: "admin" });
    await ctx.db.insert("bandMembers", { bandId: testBand, userId: duplicate, role: "admin" });
    await ctx.db.insert("bandMembers", { bandId: sobo, userId: duplicate, role: "member" });
    await ctx.db.insert("follows", { userId: survivor, bandId: sobo });
    await ctx.db.insert("follows", { userId: duplicate, bandId: earplug });
    await ctx.db.insert("gigSaves", { userId: duplicate, gigId: launchGig });
    await ctx.db.insert("gigRsvps", { userId: e2eUser, gigId: demoGig });
    await ctx.db.insert("videos", {
      bandId: demoBand,
      title: "Riptide (practice take)",
      views: 3100,
      lengthSec: 185,
      pinned: false,
      order: 0,
    });

    // Legacy rows the migration left behind.
    const launchEvent = await ctx.db.insert("events", {
      title: "EARPLUG LAUNCH NIGHT",
      dateTime: LAUNCH_DATE,
      bandId: earplug,
      venueId: realVenue,
      rsvpCount: 25,
      status: "confirmed",
    });
    for (const userId of [survivor, fan, duplicate]) {
      await ctx.db.insert("rsvps", {
        eventId: launchEvent,
        userId,
        attendanceStatus: "on_list",
        createdAt: LAUNCH_DATE,
      });
    }
    await ctx.db.insert("eventTickets", {
      eventId: launchEvent,
      userId: fan,
      status: "issued",
      token: "tok_1",
    });
    await ctx.db.insert("savedArtists", { bandId: earplug, userId: fan, createdAt: 1 });
    await ctx.db.insert("bandMemberships", { bandId: earplug, userId: survivor, role: "owner" });
    await ctx.db.insert("notifications", { userId: fan, title: "hi", read: false });

    return {
      survivor, duplicate, fan, e2eUser,
      earplug, sobo, testBand, demoBand,
      realVenue, demoVenue, launchGig, demoGig,
    };
  });
  return { t, ...fixture };
}

describe("cleanup:cleanupAll", () => {
  test("recovers rsvps, merges duplicates, purges demo + legacy, and re-runs clean", async () => {
    const f = await seedPostMigrationFixture();
    const { t } = f;

    const first = await t.mutation(internal.cleanup.cleanupAll, {});

    // Three legacy rsvps existed, but two belong to the same person and
    // collapse into one gigRsvp during the merge.
    expect(first.rsvpsRecovered).toBe(3);
    expect(first.duplicatesMerged).toBe(1);
    expect(first.demoGigsDeleted).toBe(1);
    expect(first.demoBandsDeleted).toBe(1);
    expect(first.demoVenuesDeleted).toBe(1);
    expect(first.junkBandsDeleted).toBe(1);
    expect(first.junkUsersDeleted).toBe(1);
    expect(first.legacyRowsDeleted).toBe(8); // 1 event, 3 rsvps, 1 ticket, 1 saved, 1 membership, 1 notification

    // End state: 2 real users, 2 real bands, 1 real venue, 1 real gig.
    expect(first.users).toBe(2);
    expect(first.bands).toBe(2);
    expect(first.venues).toBe(1);
    expect(first.gigs).toBe(1);

    await t.run(async (ctx) => {
      // Merge: duplicate gone, survivor kept, its attachments moved across.
      expect(await ctx.db.get(f.duplicate)).toBeNull();
      const survivor = await ctx.db.get(f.survivor);
      expect(survivor).not.toBeNull();
      expect(survivor!.clerkId).toBe("user_old");

      const memberships = await ctx.db
        .query("bandMembers")
        .withIndex("by_user", (q) => q.eq("userId", f.survivor))
        .collect();
      // EARPLUG admin kept; SOBO member moved over; test band's row died with
      // the band it pointed at.
      expect(memberships.map((m) => m.bandId).sort()).toEqual([f.earplug, f.sobo].sort());

      const follows = await ctx.db
        .query("follows")
        .withIndex("by_user", (q) => q.eq("userId", f.survivor))
        .collect();
      expect(follows.map((x) => x.bandId).sort()).toEqual([f.earplug, f.sobo].sort());

      // The duplicate's save moved rather than vanishing.
      const saves = await ctx.db
        .query("gigSaves")
        .withIndex("by_user", (q) => q.eq("userId", f.survivor))
        .collect();
      expect(saves.length).toBe(1);

      // Recovered rsvps point at the launch gig, one row per surviving person.
      const rsvps = await ctx.db
        .query("gigRsvps")
        .withIndex("by_gig", (q) => q.eq("gigId", f.launchGig))
        .collect();
      expect(rsvps.length).toBe(2);
      expect(rsvps.map((r) => r.userId).sort()).toEqual([f.survivor, f.fan].sort());

      // Attendance was not invented.
      expect((await ctx.db.get(f.fan))!.attendedCount).toBe(0);
      // goingCount untouched by the backfill.
      expect((await ctx.db.get(f.launchGig))!.goingCount).toBe(25);

      // Demo + junk gone, real data intact.
      expect(await ctx.db.get(f.demoBand)).toBeNull();
      expect(await ctx.db.get(f.demoVenue)).toBeNull();
      expect(await ctx.db.get(f.demoGig)).toBeNull();
      expect(await ctx.db.get(f.testBand)).toBeNull();
      expect(await ctx.db.get(f.e2eUser)).toBeNull();
      expect(await ctx.db.get(f.earplug)).not.toBeNull();
      expect(await ctx.db.get(f.realVenue)).not.toBeNull();

      // Cascades: the demo band's video and the e2e user's rsvp went with them.
      expect((await ctx.db.query("videos").take(10)).length).toBe(0);
      expect((await ctx.db.query("gigRsvps").take(10)).length).toBe(2);

      // Legacy tables emptied.
      for (const table of ["events", "rsvps", "eventTickets", "savedArtists",
        "bandMemberships", "notifications"] as const) {
        expect((await ctx.db.query(table).take(10)).length).toBe(0);
      }
    });

    // Re-run is a no-op: no work done, identical end state.
    const second = await t.mutation(internal.cleanup.cleanupAll, {});
    expect(second.rsvpsRecovered).toBe(0);
    expect(second.duplicatesMerged).toBe(0);
    expect(second.demoGigsDeleted).toBe(0);
    expect(second.demoBandsDeleted).toBe(0);
    expect(second.demoVenuesDeleted).toBe(0);
    expect(second.junkBandsDeleted).toBe(0);
    expect(second.junkUsersDeleted).toBe(0);
    expect(second.legacyRowsDeleted).toBe(0);
    expect(second.users).toBe(first.users);
    expect(second.bands).toBe(first.bands);
    expect(second.venues).toBe(first.venues);
    expect(second.gigs).toBe(first.gigs);
    expect(second.gigRsvps).toBe(first.gigRsvps);
  });

  test("backfill does not duplicate an rsvp the fan already has", async () => {
    const { t, survivor, launchGig } = await seedPostMigrationFixture();
    await t.run(async (ctx) => {
      await ctx.db.insert("gigRsvps", { userId: survivor, gigId: launchGig });
    });

    // Only the fan and the duplicate are left to recover.
    const { rsvpsRecovered } = await t.mutation(internal.cleanup.backfillRsvps, {});
    expect(rsvpsRecovered).toBe(2);

    await t.run(async (ctx) => {
      const mine = await ctx.db
        .query("gigRsvps")
        .withIndex("by_user_gig", (q) => q.eq("userId", survivor).eq("gigId", launchGig))
        .collect();
      expect(mine.length).toBe(1);
    });
  });

  test("refuses to delete a demo gig that a real band is playing", async () => {
    const { t, earplug, demoGig } = await seedPostMigrationFixture();
    await t.run(async (ctx) => {
      const gig = (await ctx.db.get(demoGig))!;
      await ctx.db.patch(demoGig, { lineup: [...gig.lineup, earplug] });
    });

    await expect(t.mutation(internal.cleanup.cleanupAll, {})).rejects.toThrow(
      /real band/,
    );
  });
});
