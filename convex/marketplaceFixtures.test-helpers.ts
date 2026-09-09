/** Test-only fixtures. The multi-dot filename keeps this module out of the
 * Convex bundle (the CLI skips `*.x.ts` files) while vitest's default include
 * pattern (`*.test.ts`) keeps it from being collected as a suite. */
import type {
  TestConvexForDataModel,
  TestConvexForDataModelAndIdentity,
} from "convex-test";
import type { DataModel, Doc, Id, TableNames } from "./_generated/dataModel";
import { paymentRecordsForBooking } from "./lib/paymentSchedule";

export const DAY_MS = 24 * 60 * 60 * 1000;
export const ACTORS = [
  "owner",
  "manager",
  "finance",
  "door",
  "admin",
  "member",
  "platformAdmin",
  "stranger",
] as const;
export type Actor = (typeof ACTORS)[number];

type Fields<Table extends TableNames> = Partial<
  Omit<Doc<Table>, "_id" | "_creationTime">
>;

export type MarketplaceOptions = {
  prefix: string;
  /** Uses the caller's clock when omitted; suites should pass their own NOW. */
  now?: number;
  organization?: Fields<"organizations">;
  venue?: Fields<"venues">;
  band?: Fields<"bands">;
  opportunity?: Fields<"talentOpportunities">;
  slot?: Fields<"opportunitySlots">;
  application?: Fields<"artistApplications">;
  /** Null stops after the application and leaves the slot without a band. */
  booking?: Fields<"bookings"> | null;
  /** No records are inserted unless supplied; ignored when booking is null. */
  paymentRecords?: Fields<"paymentRecords">[];
  bandPayoutAccount?: boolean;
  organizationPrivateDetails?: Fields<"organizationPrivateDetails">;
};

export type MarketplaceIds = {
  users: Record<Actor, Id<"users">>;
  organizationId: Id<"organizations">;
  detailsId: Id<"organizationPrivateDetails">;
  venueId: Id<"venues">;
  bandId: Id<"bands">;
  opportunityId: Id<"talentOpportunities">;
  slotId: Id<"opportunitySlots">;
  applicationId: Id<"artistApplications">;
  bookingId?: Id<"bookings">;
  paymentRecordIds: Id<"paymentRecords">[];
};

/** Seeds a confirmed, fully paid booking by default. Overrides are shallow:
 * callers keep related amounts/statuses consistent for the scenario they need.
 * Dates derive from now and opportunity.startsAt, never a shared fixed date. */
export function seedMarketplace(
  t: TestConvexForDataModel<DataModel>,
  opts: MarketplaceOptions & { booking: null },
): Promise<MarketplaceIds & { bookingId?: never }>;
export function seedMarketplace(
  t: TestConvexForDataModel<DataModel>,
  opts: MarketplaceOptions & { booking?: Fields<"bookings"> },
): Promise<MarketplaceIds & { bookingId: Id<"bookings"> }>;
export function seedMarketplace(
  t: TestConvexForDataModel<DataModel>,
  opts: MarketplaceOptions,
): Promise<MarketplaceIds>;
export async function seedMarketplace(
  t: TestConvexForDataModel<DataModel>,
  opts: MarketplaceOptions,
): Promise<MarketplaceIds> {
  const now = opts.now ?? Date.now();
  const startsAt = opts.opportunity?.startsAt ?? now + 30 * DAY_MS;
  return await t.run(async (ctx) => {
    const users = {} as Record<Actor, Id<"users">>;
    for (const actor of ACTORS) {
      users[actor] = await ctx.db.insert("users", {
        clerkId: `${opts.prefix}_${actor}`,
        name: actor,
        email: `${actor}@${opts.prefix}.test`,
        genres: [],
        attendedCount: 0,
      });
    }
    await ctx.db.insert("platformAdmins", {
      userId: users.platformAdmin,
      grantedAt: now,
    });
    const organizationId = await ctx.db.insert("organizations", {
      name: `${opts.prefix.charAt(0).toUpperCase()}${opts.prefix.slice(1)} Collective`,
      slug: `${opts.prefix}-collective`,
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: users.owner,
      createdAt: now,
      updatedAt: now,
      ...opts.organization,
    });
    for (const role of ["owner", "manager", "finance", "door"] as const) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[role],
        role,
        createdAt: now,
      });
    }
    const detailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      businessEmail: `billing@${opts.prefix}.test`,
      contactName: "Owner",
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: [],
      updatedAt: now,
      ...opts.organizationPrivateDetails,
    });
    const venueId = await ctx.db.insert("venues", {
      name: "Neighborhood Hall",
      area: "Oakland",
      addr: "100 Main Street",
      distSF: "8 mi",
      distOak: "1 mi",
      lat: 37.8,
      lng: -122.27,
      managedByOrganizationId: organizationId,
      status: "verified",
      venueType: "hall",
      ...opts.venue,
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
      ...opts.band,
    });
    for (const role of ["admin", "member"] as const) {
      await ctx.db.insert("bandMembers", {
        bandId,
        userId: users[role],
        role,
      });
    }
    if (opts.bandPayoutAccount !== false) {
      await ctx.db.insert("bandPayoutAccounts", {
        bandId,
        stripeAccountId: "acct_band",
        chargesEnabled: true,
        payoutsEnabled: true,
        detailsSubmitted: true,
        requirementsDue: [],
        updatedAt: now,
      });
    }
    const opportunityId = await ctx.db.insert("talentOpportunities", {
      organizationId,
      venueId,
      mode: "publicEvent",
      area: "Oakland",
      venueType: "hall",
      title: "Friday at the Hall",
      desc: "An evening of local music.",
      genres: ["Indie"],
      startsAt,
      ageRequirement: "allAges",
      flyKey: "xerox",
      applicationsCloseAt: startsAt - DAY_MS,
      visibility: "public",
      ticketing: "rsvp",
      currency: "usd",
      status: "confirmed",
      slug: "friday-at-the-hall",
      createdBy: users.owner,
      revision: 1,
      applicationCount: 0,
      createdAt: now,
      updatedAt: now,
      ...opts.opportunity,
    });
    const slotId = await ctx.db.insert("opportunitySlots", {
      opportunityId,
      order: 0,
      role: "headliner",
      guaranteeMinor: 20000,
      required: true,
      status: "booked",
      ...(opts.booking === null ? {} : { bandId }),
      ...opts.slot,
    });
    const applicationId = await ctx.db.insert("artistApplications", {
      opportunityId,
      slotId,
      bandId,
      submittedBy: users.admin,
      status: "booked",
      message: "We are available",
      createdAt: now,
      updatedAt: now,
      ...opts.application,
    });
    const ids = {
      users,
      organizationId,
      detailsId,
      venueId,
      bandId,
      opportunityId,
      slotId,
      applicationId,
    };
    const paymentRecordIds: Id<"paymentRecords">[] = [];
    if (opts.booking === null) return { ...ids, paymentRecordIds };

    const bookingId = await ctx.db.insert("bookings", {
      opportunityId,
      slotId,
      organizationId,
      bandId,
      applicationId,
      status: "confirmed",
      revision: 3,
      startsAt,
      grossMinor: 20000,
      commissionBps: 1000,
      commissionMinor: 2000,
      artistNetMinor: 18000,
      currency: "usd",
      cancellationTemplate: "standard",
      organizerAcceptedTermsAt: now,
      artistAcceptedTermsAt: now,
      confirmedAt: now,
      payoutHold: false,
      paidMinor: 20000,
      refundedMinor: 0,
      createdBy: users.owner,
      createdAt: now,
      updatedAt: now,
      ...opts.booking,
    });
    await ctx.db.patch(slotId, { bookingId });

    for (const [index, fields] of (opts.paymentRecords ?? []).entries()) {
      paymentRecordIds.push(
        await ctx.db.insert("paymentRecords", {
          bookingId,
          installmentIndex: index,
          label: "Booking payment",
          amountMinor: 0,
          currency: "usd",
          dueAt: now,
          status: "pending",
          attempt: 0,
          refundedMinor: 0,
          createdAt: now,
          updatedAt: now,
          ...fields,
        }),
      );
    }
    return { ...ids, bookingId, paymentRecordIds };
  });
}

export const asActor = (
  t: TestConvexForDataModelAndIdentity<DataModel>,
  prefix: string,
) => (actor: Actor) => t.withIdentity({ subject: `${prefix}_${actor}` });

/** Readers bound to one booking; ledger entries are filtered by that booking. */
export const readers = (
  t: TestConvexForDataModel<DataModel>,
  ids: { bookingId: Id<"bookings"> },
) => ({
  readBooking: () => t.run((ctx) => ctx.db.get(ids.bookingId)),
  records: () => t.run((ctx) => paymentRecordsForBooking(ctx, ids.bookingId)),
  refunds: () =>
    t.run((ctx) =>
      ctx.db.query("refunds")
        .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
        .take(50),
    ),
  payouts: () =>
    t.run((ctx) =>
      ctx.db.query("payouts")
        .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
        .take(50),
    ),
  ledger: () =>
    t.run((ctx) =>
      ctx.db.query("ledgerEntries")
        .withIndex("by_bookingId", (q) => q.eq("bookingId", ids.bookingId))
        .take(50),
    ),
  scheduled: () =>
    t.run((ctx) => ctx.db.system.query("_scheduled_functions").take(100)),
});
