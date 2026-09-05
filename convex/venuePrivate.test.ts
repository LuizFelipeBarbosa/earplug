import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";
import { readVenuePrivateFor, toVenuePrivatePayload } from "./lib/venuePrivate";
import schema from "./schema";

const exactAddress = "99 Private Lane, Oakland";
const createdAt = Date.UTC(2026, 8, 4);
const startsAt = Date.UTC(2026, 9, 17, 20);

async function insertVenue(ctx: MutationCtx, name: string, addr: string) {
  const venueId = await ctx.db.insert("venues", {
    name,
    area: "Downtown, Oakland",
    addr: "Downtown, Oakland",
    distSF: "7 mi",
    distOak: "1 mi",
    lat: 37.8044,
    lng: -122.2711,
    status: "verified",
    addressDisclosure: "onTicket",
    venueType: "club",
  });
  await ctx.db.insert("venuePrivateDetails", {
    venueId,
    addr,
    lat: 37.8058,
    lng: -122.2705,
    normalizedAddr: addr.toLowerCase(),
    loadInNotes: "Use the side entrance.",
    capacity: 200,
    updatedAt: createdAt,
  });
  return venueId;
}

async function setupFixture(
  status: Doc<"bookings">["status"] = "confirmed",
) {
  const t = convexTest(schema);
  const ids = await t.run(async (ctx) => {
    const adminId = await ctx.db.insert("users", {
      clerkId: "band-admin",
      name: "Band Admin",
      email: "admin@example.com",
      genres: [],
      attendedCount: 0,
    });
    const memberId = await ctx.db.insert("users", {
      clerkId: "band-member",
      name: "Band Member",
      email: "member@example.com",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Bay Area Shows",
      slug: "bay-area-shows",
      orgType: "promoter",
      status: "verified",
      ownerUserId: memberId,
      createdAt,
      updatedAt: createdAt,
    });
    // No managing organization or organization memberships: booking tests
    // must obtain access solely through the band's booking.
    const venueId = await insertVenue(ctx, "The Lantern", exactAddress);
    const bandId = await ctx.db.insert("bands", {
      name: "The Satellites",
      slug: "the-satellites",
      genres: ["punk"],
      area: "Bay Area",
      colorHex: "#7B8FFF",
      initials: "TS",
      followerCount: 0,
      bio: "",
      pastShows: [],
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: adminId,
      role: "admin",
    });
    await ctx.db.insert("bandMembers", {
      bandId,
      userId: memberId,
      role: "member",
    });
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      venueId,
      mode: "publicEvent",
      area: "Oakland",
      venueType: "club",
      title: "Autumn Sessions",
      desc: "An evening of live music.",
      genres: ["punk"],
      startsAt,
      ageRequirement: "allAges",
      flyKey: "paper",
      applicationsCloseAt: startsAt - 86_400_000,
      visibility: "public",
      ticketing: "none",
      currency: "USD",
      status: "confirmed",
      slug: "autumn-sessions",
      createdBy: memberId,
      revision: 1,
      applicationCount: 0,
      createdAt,
      updatedAt: createdAt,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 50_000,
      required: true,
      status: "booked",
      bandId,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: adminId,
      message: "We are available.",
      status: "booked",
      createdAt,
      updatedAt: createdAt,
    });
    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status,
      revision: 1,
      startsAt,
      grossMinor: 50_000,
      commissionBps: 1_000,
      commissionMinor: 5_000,
      artistNetMinor: 45_000,
      currency: "USD",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: createdAt,
      payoutHold: false,
      createdBy: memberId,
      createdAt,
      updatedAt: createdAt,
    });
    await ctx.db.patch(slotId, { bookingId });
    return { adminId, memberId, organizationId, venueId, opportunityId };
  });
  return { t, ...ids };
}

describe("readVenuePrivateFor", () => {
  test.each(["confirmed", "completed", "paid"] as const)(
    "reveals the exact address to a band admin with a %s booking",
    async (status) => {
      const { t, adminId, venueId } = await setupFixture(status);
      await t.run(async (ctx) => {
        const venue = (await ctx.db.get(venueId))!;
        const admin = (await ctx.db.get(adminId))!;
        const result = await readVenuePrivateFor(ctx, venue, admin);

        expect(result).not.toBeNull();
        expect(result!.details.addr).toBe(exactAddress);
        expect(result!.operational).toBe(false);
        const payload = toVenuePrivatePayload(result!.details, result!.operational);
        expect(payload).toMatchObject({
          addr: exactAddress,
          loadInNotes: null,
          capacity: null,
        });
      });
    },
  );

  test("denies a plain member even when their band has a confirmed booking", async () => {
    const { t, memberId, venueId } = await setupFixture();
    await t.run(async (ctx) => {
      const venue = (await ctx.db.get(venueId))!;
      const member = (await ctx.db.get(memberId))!;

      expect(await readVenuePrivateFor(ctx, venue, member)).toBeNull();
    });
  });

  test.each([
    "offer_sent",
    "artist_accepted",
    "awaiting_payment",
    "cancelled_by_organizer",
    "cancelled_by_artist",
    "force_majeure",
    "disputed",
    "refunded",
    "declined",
    "expired",
    "withdrawn",
  ] as const)("denies an admin whose only booking is %s", async (status) => {
    const { t, adminId, venueId } = await setupFixture(status);
    await t.run(async (ctx) => {
      const venue = (await ctx.db.get(venueId))!;
      const admin = (await ctx.db.get(adminId))!;

      expect(await readVenuePrivateFor(ctx, venue, admin)).toBeNull();
    });
  });

  test("grants access only at the venue of the confirmed booking", async () => {
    const { t, adminId, venueId, opportunityId } = await setupFixture();
    await t.run(async (ctx) => {
      const otherAddress = "20 Other Street, Oakland";
      const otherVenueId = await insertVenue(ctx, "Other Room", otherAddress);
      await ctx.db.patch(opportunityId, { venueId: otherVenueId });
      const venue = (await ctx.db.get(venueId))!;
      const otherVenue = (await ctx.db.get(otherVenueId))!;
      const admin = (await ctx.db.get(adminId))!;

      expect(await readVenuePrivateFor(ctx, venue, admin)).toBeNull();
      const result = await readVenuePrivateFor(ctx, otherVenue, admin);
      expect(result?.details.addr).toBe(otherAddress);
      expect(result?.operational).toBe(false);
    });
  });

  test("denies an anonymous reader of an on-ticket venue", async () => {
    const { t, venueId } = await setupFixture();
    await t.run(async (ctx) => {
      const venue = (await ctx.db.get(venueId))!;

      expect(await readVenuePrivateFor(ctx, venue, null)).toBeNull();
    });
  });

  test("still reveals a public venue's address to an anonymous reader", async () => {
    const { t, venueId } = await setupFixture();
    await t.run(async (ctx) => {
      await ctx.db.patch(venueId, { addressDisclosure: "public" });
      const venue = (await ctx.db.get(venueId))!;
      const result = await readVenuePrivateFor(ctx, venue, null);

      expect(result?.details.addr).toBe(exactAddress);
      expect(result?.operational).toBe(false);
    });
  });

  test("preserves organization access and the suspended-organization guard", async () => {
    const { t, memberId, organizationId, venueId } = await setupFixture();
    await t.run(async (ctx) => {
      await ctx.db.patch(venueId, { managedByOrganizationId: organizationId });
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: memberId,
        role: "owner",
        createdAt,
      });
      const venue = (await ctx.db.get(venueId))!;
      const member = (await ctx.db.get(memberId))!;
      const result = await readVenuePrivateFor(ctx, venue, member);

      expect(result?.details.addr).toBe(exactAddress);
      expect(result?.operational).toBe(true);
      const payload = toVenuePrivatePayload(result!.details, result!.operational);
      expect(payload).toMatchObject({
        loadInNotes: "Use the side entrance.",
        capacity: 200,
      });

      await ctx.db.patch(organizationId, { status: "suspended" });
      expect(await readVenuePrivateFor(ctx, venue, member)).toBeNull();
    });
  });
});
