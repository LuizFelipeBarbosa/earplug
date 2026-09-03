import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { Id } from "./_generated/dataModel";
import { insertGigWithBandIndex, uniqueSlug } from "./lib/helpers";
import { normalizeVenueText } from "./venues";

// Port of lib/demo_data.dart (verbatim strings/numbers). startsAt is computed
// relative to run time so gig 1 lands "tonight" (8PM Pacific) and the rest
// follow the demo spacing (JUL 28 → AUG 9 = day offsets 0..12).
//
// TEST FIXTURE ONLY. This exists for the Convex test suite; it must never be
// run against a real deployment. Its rows were purged from dev once and there
// is no longer any purger to undo a second seeding, so re-running it against a
// live deployment would put fake bands back in front of real users for good.

const PT_OFFSET_MS = 7 * 60 * 60 * 1000; // PDT (UTC-7)
const DAY_MS = 24 * 60 * 60 * 1000;

function pacificTime(dayOffset: number, hour24: number, minute: number): number {
  const nowPt = Date.now() - PT_OFFSET_MS;
  const startOfDayPt = nowPt - (nowPt % DAY_MS);
  return (
    startOfDayPt +
    dayOffset * DAY_MS +
    hour24 * 60 * 60 * 1000 +
    minute * 60 * 1000 +
    PT_OFFSET_MS
  );
}

const DEMO_VENUES = [
  { key: "v1", name: "The Foghorn Club", area: "Mission, SF", addr: "2455 Harrison St, San Francisco", distSF: "0.8 mi", distOak: "6.3 mi", lat: 37.7524, lng: -122.418 },
  { key: "v2", name: "Nightcrawler Records", area: "Temescal, Oakland", addr: "486 40th St, Oakland", distSF: "6.1 mi", distOak: "0.9 mi", lat: 37.818, lng: -122.269 },
  { key: "v3", name: "Casa Quake", area: "Bernal Heights, SF", addr: "(address with RSVP)", distSF: "1.2 mi", distOak: "6.7 mi", lat: 37.7399, lng: -122.4166 },
  { key: "v4", name: "The Rusty Anchor", area: "Dogpatch, SF", addr: "701 22nd St, San Francisco", distSF: "1.9 mi", distOak: "5.4 mi", lat: 37.7583, lng: -122.388 },
  { key: "v5", name: "Peralta Hall", area: "West Oakland", addr: "1801 Peralta St, Oakland", distSF: "6.8 mi", distOak: "1.6 mi", lat: 37.806, lng: -122.291 },
  { key: "v6", name: "Sunset Bunker", area: "Outer Sunset, SF", addr: "3820 Noriega St, San Francisco", distSF: "4.3 mi", distOak: "9.8 mi", lat: 37.754, lng: -122.504 },
];

const DEMO_BANDS = [
  {
    key: "b1", name: "Foghorn Diet", genres: ["garage", "surf punk"], area: "Mission, SF",
    colorHex: "#7B8FFF", initials: "FD", followerCount: 486,
    bio: "Reverb-soaked garage punk from a Mission garage that actually floods. Two guitars, no pedalboard budget, all heart.",
    pastShows: [
      { title: "Riptide warmup — Casa Quake", meta: "JUL 12" },
      { title: "Nightcrawler in-store", meta: "JUN 27" },
      { title: "Peralta Hall benefit", meta: "JUN 6" },
      { title: "Bunker session", meta: "MAY 16" },
    ],
  },
  {
    key: "b2", name: "Pigeon Court", genres: ["post-punk"], area: "Temescal, Oakland",
    colorHex: "#B9C4FF", initials: "PC", followerCount: 1214,
    bio: "Wiry post-punk for people who alphabetize their records and then fight about it.",
    pastShows: [
      { title: "Court Is In Session tour", meta: "JUL" },
      { title: "Noise Night Vol. 11", meta: "JUN 20" },
    ],
  },
  {
    key: "b3", name: "Mission Creep", genres: ["hardcore"], area: "Mission, SF",
    colorHex: "#E4DC4A", initials: "MC", followerCount: 743,
    bio: "Fast, short, gone. Sets under 20 minutes, guaranteed.",
    pastShows: [
      { title: "Basement series #4", meta: "JUL 5" },
      { title: "All-Ages Matinee", meta: "JUN 14" },
    ],
  },
  {
    key: "b4", name: "Dial Tone Grief", genres: ["noise rock", "shoegaze"], area: "Bernal Heights, SF",
    colorHex: "#8FE6C4", initials: "DT", followerCount: 312,
    bio: "Two amps facing each other, one long argument. You will feel it in your teeth.",
    pastShows: [{ title: "Noise Night Vol. 10", meta: "MAY 30" }],
  },
  {
    key: "b5", name: "Trash Panda Riot", genres: ["thrash", "party punk"], area: "West Oakland",
    colorHex: "#F0A26B", initials: "TP", followerCount: 927,
    bio: "Party thrash with a raccoon on the kick drum. The raccoon is drawn on. Probably.",
    pastShows: [
      { title: "Riot Fest (the small one)", meta: "JUL 4" },
      { title: "Peralta Hall blowout", meta: "JUN 21" },
    ],
  },
  {
    key: "b6", name: "Static Bloom", genres: ["shoegaze", "punk"], area: "Berkeley",
    colorHex: "#D9A6E8", initials: "SB", followerCount: 158,
    bio: "Loud flowers. Berkeley basements and borrowed fuzz pedals since 2025.",
    pastShows: [{ title: "First show ever — house party", meta: "JUN 28" }],
  },
];

// Demo dates: JUL 28 (day 0), 30, 31, AUG 1, 2, 7, 9. Doors hour = first part
// of the demo `time` string.
const DEMO_GIGS = [
  { title: "Basement Blowout", venue: "v3", price: 0, dayOffset: 0, hour: 20, minute: 0, doorsTime: "8PM / 9PM", flyKey: "paper", lineup: ["b3", "b4", "b6"], goingCount: 43, genres: ["hardcore", "noise"], desc: "Four bands, one basement, zero cover. Bring earplugs (the foam kind).", ticketing: "rsvp" as const },
  { title: "Riptide Release Show", venue: "v1", price: 10, dayOffset: 2, hour: 20, minute: 0, doorsTime: "8PM / 9PM", flyKey: "blue", lineup: ["b1", "b2"], goingCount: 87, genres: ["garage", "surf"], desc: "Foghorn Diet plays 'Riptide' front to back, then whatever falls out.", ticketing: "rsvp" as const },
  { title: "Noise Night Vol. 12", venue: "v2", price: 8, dayOffset: 3, hour: 21, minute: 0, doorsTime: "9PM / 9:30PM", flyKey: "black", lineup: ["b4", "b6"], goingCount: 29, genres: ["noise", "shoegaze"], desc: "In-store racket between the record bins. BYO earplugs, again.", ticketing: "rsvp" as const },
  { title: "Pigeon Court + Mission Creep", venue: "v4", price: 12, dayOffset: 4, hour: 20, minute: 0, doorsTime: "8PM / 8:45PM", flyKey: "bluetype", lineup: ["b2", "b3"], goingCount: 56, genres: ["post-punk", "hardcore"], desc: "Double bill. Loud then louder. Tickets through the venue.", ticketing: "external" as const },
  { title: "All-Ages Matinee", venue: "v5", price: 0, dayOffset: 5, hour: 13, minute: 30, doorsTime: "1:30PM / 2PM", flyKey: "yellow", lineup: ["b5", "b6", "b3"], goingCount: 61, genres: ["punk"], desc: "Daylight punk. Kids welcome, chaperones tolerated.", ticketing: "rsvp" as const },
  { title: "Trash Panda Riot", venue: "v6", price: 5, dayOffset: 10, hour: 21, minute: 0, doorsTime: "9PM / 10PM", flyKey: "black", lineup: ["b5"], goingCount: 18, genres: ["thrash", "punk"], desc: "One band, ninety minutes, a bunker by the beach.", ticketing: "rsvp" as const },
  { title: "Fog City Fest — Day Show", venue: "v1", price: 15, dayOffset: 12, hour: 12, minute: 0, doorsTime: "12PM / 12:30PM", flyKey: "blue", lineup: ["b1", "b2", "b4", "b5"], goingCount: 112, genres: ["punk", "garage"], desc: "Eight hours, four stages worth of bands on one stage.", ticketing: "external" as const },
];

export const seedDemo = internalMutation({
  args: {},
  returns: v.object({ seeded: v.boolean() }),
  handler: async (ctx) => {
    // Idempotency marker: a demo venue by name.
    const marker = await ctx.db
      .query("venues")
      .withIndex("by_name", (q) => q.eq("name", "The Foghorn Club"))
      .unique();
    if (marker) return { seeded: false };

    const venueIds: Record<string, Id<"venues">> = {};
    for (const venue of DEMO_VENUES) {
      venueIds[venue.key] = await ctx.db.insert("venues", {
        name: venue.name,
        area: venue.area,
        addr: venue.addr,
        normalizedName: normalizeVenueText(venue.name),
        normalizedAddr: normalizeVenueText(venue.addr),
        distSF: venue.distSF,
        distOak: venue.distOak,
        lat: venue.lat,
        lng: venue.lng,
      });
    }

    const bandIds: Record<string, Id<"bands">> = {};
    for (const band of DEMO_BANDS) {
      bandIds[band.key] = await ctx.db.insert("bands", {
        name: band.name,
        genres: band.genres,
        area: band.area,
        colorHex: band.colorHex,
        initials: band.initials,
        followerCount: band.followerCount,
        bio: band.bio,
        pastShows: band.pastShows,
        slug: await uniqueSlug(ctx, band.name),
        hasClip: false,
      });
    }

    for (const gig of DEMO_GIGS) {
      await insertGigWithBandIndex(ctx, {
        title: gig.title,
        venueId: venueIds[gig.venue],
        price: gig.price,
        startsAt: pacificTime(gig.dayOffset, gig.hour, gig.minute),
        doorsTime: gig.doorsTime,
        flyKey: gig.flyKey,
        lineup: gig.lineup.map((key) => bandIds[key]),
        genres: gig.genres,
        desc: gig.desc,
        ticketing: gig.ticketing,
        ageRequirement: "allAges",
        cap: "No cap",
        goingCount: gig.goingCount,
      });
    }

    return { seeded: true };
  },
});
