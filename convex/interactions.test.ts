import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import { Id } from "./_generated/dataModel";
import schema from "./schema";

async function setup() {
  const t = convexTest(schema);
  const { venueId, bandId, gigId } = await t.run(async (ctx) => {
    const venueId = await ctx.db.insert("venues", {
      name: "Casa Quake",
      area: "Bernal Heights, SF",
      addr: "(address with RSVP)",
      distSF: "1.2 mi",
      distOak: "6.7 mi",
      lat: 37.7399,
      lng: -122.4166,
    });
    const bandId = await ctx.db.insert("bands", {
      name: "Mission Creep",
      genres: ["hardcore"],
      area: "Mission, SF",
      colorHex: "#E4DC4A",
      initials: "MC",
      followerCount: 10,
      bio: "",
      pastShows: [],
    });
    const gigId = await ctx.db.insert("gigs", {
      title: "Basement Blowout",
      venueId,
      price: 0,
      startsAt: Date.now() + 3600_000,
      doorsTime: "8PM / 9PM",
      flyKey: "paper",
      lineup: [bandId],
      genres: ["hardcore"],
      desc: "",
      ticketing: "rsvp",
      cap: "No cap",
      goingCount: 43,
    });
    return { venueId, bandId, gigId };
  });
  const asFan = t.withIdentity({ subject: "user_fan", email: "fan@x.com" });
  await asFan.mutation(api.users.ensureUser, {});
  return { t, asFan, venueId, bandId, gigId };
}

describe("interactions", () => {
  test("mutations throw when unauthenticated", async () => {
    const { t, gigId, bandId } = await setup();
    await expect(t.mutation(api.interactions.toggleRsvp, { gigId })).rejects.toThrow();
    await expect(t.mutation(api.interactions.toggleFollow, { bandId })).rejects.toThrow();
    await expect(t.mutation(api.interactions.toggleSave, { gigId })).rejects.toThrow();
  });

  test("myInteractions returns empty shape when unauthenticated", async () => {
    const { t } = await setup();
    const result = await t.query(api.interactions.myInteractions, {});
    expect(result).toEqual({
      rsvpGigIds: [],
      followBandIds: [],
      savedGigIds: [],
      attendedCount: 0,
    });
  });

  test("toggleRsvp double-toggle adjusts goingCount both ways", async () => {
    const { t, asFan, gigId } = await setup();
    const on = await asFan.mutation(api.interactions.toggleRsvp, { gigId });
    expect(on).toEqual({ on: true });
    let gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.goingCount).toBe(44);

    let mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([gigId]);

    const off = await asFan.mutation(api.interactions.toggleRsvp, { gigId });
    expect(off).toEqual({ on: false });
    gig = await t.run(async (ctx) => ctx.db.get(gigId));
    expect(gig!.goingCount).toBe(43);
    mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.rsvpGigIds).toEqual([]);
  });

  test("toggleFollow double-toggle adjusts followerCount both ways", async () => {
    const { t, asFan, bandId } = await setup();
    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    let band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band!.followerCount).toBe(11);
    await asFan.mutation(api.interactions.toggleFollow, { bandId });
    band = await t.run(async (ctx) => ctx.db.get(bandId));
    expect(band!.followerCount).toBe(10);
  });

  test("history returns only past RSVPed gigs, newest first", async () => {
    const { t, asFan, venueId, bandId, gigId } = await setup();

    const [oldGigId, olderGigId] = await t.run(async (ctx) => {
      const base = {
        venueId,
        price: 0,
        doorsTime: "8PM / 9PM",
        flyKey: "paper",
        lineup: [bandId],
        genres: ["hardcore"],
        desc: "",
        ticketing: "rsvp" as const,
        cap: "No cap",
        goingCount: 0,
      };
      return [
        await ctx.db.insert("gigs", {
          ...base,
          title: "Last Month",
          startsAt: Date.now() - 30 * 24 * 3600_000,
        }),
        await ctx.db.insert("gigs", {
          ...base,
          title: "Two Months Back",
          startsAt: Date.now() - 60 * 24 * 3600_000,
        }),
      ];
    });

    // RSVP to both past gigs and the upcoming one; only the past two count.
    for (const id of [olderGigId, gigId, oldGigId]) {
      await asFan.mutation(api.interactions.toggleRsvp, { gigId: id });
    }

    expect(await t.query(api.interactions.history, {})).toEqual([]);
    const history = await asFan.query(api.interactions.history, {});
    expect(history.map((h) => h.title)).toEqual(["Last Month", "Two Months Back"]);
    expect(history[0].venueName).toBe("Casa Quake");
  });

  test("toggleSave double-toggle", async () => {
    const { asFan, gigId } = await setup();
    expect(await asFan.mutation(api.interactions.toggleSave, { gigId })).toEqual({ on: true });
    let mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.savedGigIds).toEqual([gigId]);
    expect(await asFan.mutation(api.interactions.toggleSave, { gigId })).toEqual({ on: false });
    mine = await asFan.query(api.interactions.myInteractions, {});
    expect(mine.savedGigIds).toEqual([]);
  });
});
