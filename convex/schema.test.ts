/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "./schema";

const modules = import.meta.glob(["./**/*.ts", "!./**/*.test.ts", "!./**/*.test-helpers.ts"]);
const NOW = Date.parse("2026-09-06T12:00:00Z");

async function setupPrivateHost() {
  const t = convexTest(schema, modules);
  const ids = await t.run(async (ctx) => {
    const userId = await ctx.db.insert("users", {
      clerkId: "private_host",
      name: "Riley Host",
      email: "riley@example.test",
      genres: [],
      attendedCount: 0,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: "Riley's Events",
      slug: "rileys-events",
      orgType: "privateHost",
      status: "verified",
      ownerUserId: userId,
      createdAt: NOW,
      updatedAt: NOW,
    });
    const privateLocationId = await ctx.db.insert("privateLocations", {
      organizationId,
      label: "Backyard",
      addr: "42 Garden Street",
      city: "Oakland",
      area: "Rockridge, Oakland",
      lat: 37.84,
      lng: -122.25,
      createdAt: NOW,
      updatedAt: NOW,
    });
    return { userId, organizationId, privateLocationId };
  });
  return { t, ...ids };
}

describe("Phase 5 schema", () => {
  test("stores a private host's non-venue location", async () => {
    const { t, organizationId, privateLocationId } = await setupPrivateHost();
    const location = await t.run((ctx) => ctx.db.get(privateLocationId));

    expect(location).toMatchObject({
      organizationId,
      label: "Backyard",
      addr: "42 Garden Street",
      city: "Oakland",
      area: "Rockridge, Oakland",
      lat: 37.84,
      lng: -122.25,
    });
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("privateLocations")
          .withIndex("by_organizationId", (q) =>
            q.eq("organizationId", organizationId),
          )
          .unique(),
      ),
    ).toEqual(location);
    expect(await t.run((ctx) => ctx.db.get(organizationId))).toMatchObject({
      orgType: "privateHost",
    });
  });

  test("stores a safety report and safety cancellation on a private booking", async () => {
    const { t, userId, organizationId, privateLocationId } =
      await setupPrivateHost();
    const { opportunityId, bookingId, reportId } = await t.run(async (ctx) => {
      const artistUserId = await ctx.db.insert("users", {
        clerkId: "private_booking_artist",
        name: "Alex Artist",
        email: "alex@example.test",
        genres: [],
        attendedCount: 0,
      });
      const bandId = await ctx.db.insert("bands", {
        name: "Static Bloom",
        slug: "static-bloom",
        genres: ["Indie"],
        area: "Oakland",
        colorHex: "#7B8FFF",
        initials: "SB",
        followerCount: 0,
        pastShows: [],
      });
      const startsAt = NOW + 14 * 24 * 60 * 60 * 1000;
      const opportunityId = await ctx.db.insert("talentOpportunities", {
        organizationId,
        hostUserId: userId,
        privateLocationId,
        mode: "privateBooking",
        area: "Rockridge, Oakland",
        title: "Backyard Party",
        desc: "An evening of local music.",
        genres: ["Indie"],
        startsAt,
        ageRequirement: "allAges",
        flyKey: "xerox",
        applicationsCloseAt: startsAt - 24 * 60 * 60 * 1000,
        visibility: "inviteOnly",
        ticketing: "none",
        currency: "usd",
        status: "cancelled",
        slug: "backyard-party",
        createdBy: userId,
        revision: 1,
        applicationCount: 0,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const slotId = await ctx.db.insert("opportunitySlots", {
        opportunityId,
        order: 0,
        role: "headliner",
        guaranteeMinor: 0,
        required: true,
        status: "cancelled",
      });
      const applicationId = await ctx.db.insert("artistApplications", {
        opportunityId,
        slotId,
        bandId,
        submittedBy: artistUserId,
        message: "We are available.",
        status: "booked",
        createdAt: NOW,
        updatedAt: NOW,
      });
      const bookingId = await ctx.db.insert("bookings", {
        opportunityId,
        slotId,
        organizationId,
        bandId,
        applicationId,
        status: "cancelled_by_artist",
        revision: 1,
        startsAt,
        grossMinor: 0,
        commissionBps: 0,
        commissionMinor: 0,
        artistNetMinor: 0,
        currency: "usd",
        cancellationTemplate: "standard",
        organizerAcceptedTermsAt: NOW,
        cancelledAt: NOW,
        cancelledBy: "artist",
        cancelledByUserId: artistUserId,
        cancelReason: "Unsafe access to the performance area.",
        cancellationKind: "safety",
        payoutHold: false,
        createdBy: userId,
        createdAt: NOW,
        updatedAt: NOW,
      });
      const reportId = await ctx.db.insert("safetyReports", {
        bookingId,
        reporterUserId: artistUserId,
        side: "artist",
        category: "safety",
        text: "Unsafe access to the performance area.",
        status: "open",
        createdAt: NOW,
      });
      return { opportunityId, bookingId, reportId };
    });

    const report = await t.run((ctx) => ctx.db.get(reportId));
    expect(report).toMatchObject({
      bookingId,
      side: "artist",
      category: "safety",
      status: "open",
      text: "Unsafe access to the performance area.",
    });
    expect(await t.run((ctx) => ctx.db.get(opportunityId))).toMatchObject({
      privateLocationId,
    });
    expect(await t.run((ctx) => ctx.db.get(bookingId))).toMatchObject({
      cancellationKind: "safety",
    });
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("safetyReports")
          .withIndex("by_bookingId", (q) => q.eq("bookingId", bookingId))
          .unique(),
      ),
    ).toEqual(report);
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("safetyReports")
          .withIndex("by_status_and_createdAt", (q) =>
            q.eq("status", "open").eq("createdAt", NOW),
          )
          .unique(),
      ),
    ).toEqual(report);
  });

  test("stores a host application with its contact details and agreement", async () => {
    const { t, userId } = await setupPrivateHost();
    const applicationId = await t.run((ctx) =>
      ctx.db.insert("organizationApplications", {
        applicantUserId: userId,
        orgName: "Riley's Events",
        orgType: "privateHost",
        kind: "host",
        hostDisplayName: "Riley",
        hostPhone: "415-555-0100",
        hostArea: "Rockridge, Oakland",
        hostAgreementAcceptedAt: NOW,
        contactName: "Riley Host",
        businessEmail: "riley@example.test",
        verificationDocStorageIds: [],
        status: "submitted",
        revision: 1,
        createdAt: NOW,
        updatedAt: NOW,
      }),
    );

    const application = await t.run((ctx) => ctx.db.get(applicationId));
    expect(application).toMatchObject({
      orgType: "privateHost",
      kind: "host",
      hostDisplayName: "Riley",
      hostPhone: "415-555-0100",
      hostArea: "Rockridge, Oakland",
      hostAgreementAcceptedAt: NOW,
    });
    expect(
      await t.run((ctx) =>
        ctx.db
          .query("organizationApplications")
          .withIndex("by_kind_and_status_and_createdAt", (q) =>
            q.eq("kind", "host").eq("status", "submitted").eq("createdAt", NOW),
          )
          .unique(),
      ),
    ).toEqual(application);
  });
});
