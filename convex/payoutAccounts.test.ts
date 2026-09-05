import { makeFunctionReference } from "convex/server";
import type { Infer } from "convex/values";
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import type { OrganizationRole } from "./lib/authz";
import type { stripeAccountStatusValidator } from "./payoutAccounts";
import schema from "./schema";

type StripeAccountStatus = Infer<typeof stripeAccountStatusValidator>;

const bandPayoutStatus = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  StripeAccountStatus
>("payoutAccounts:bandPayoutStatus");
const organizationStripeStatus = makeFunctionReference<
  "query",
  { organizationId: Id<"organizations"> },
  StripeAccountStatus
>("payoutAccounts:organizationStripeStatus");
const bandOnboardingContext = makeFunctionReference<
  "query",
  { bandId: Id<"bands"> },
  {
    stripeAccountId: string | null;
    bandName: string;
    contactEmail: string | null;
  }
>("payoutAccounts:bandOnboardingContext");
const organizationOnboardingContext = makeFunctionReference<
  "query",
  { organizationId: Id<"organizations"> },
  {
    stripeAccountId: string | null;
    name: string;
    businessEmail: string | null;
    legalName: string | null;
  }
>("payoutAccounts:organizationOnboardingContext");
const attachBandAccount = makeFunctionReference<
  "mutation",
  { bandId: Id<"bands">; stripeAccountId: string },
  null
>("payoutAccounts:attachBandAccount");
const attachOrganizationAccount = makeFunctionReference<
  "mutation",
  { organizationId: Id<"organizations">; stripeAccountId: string },
  null
>("payoutAccounts:attachOrganizationAccount");
const applyAccountSnapshot = makeFunctionReference<
  "mutation",
  { account: Record<string, unknown> },
  null
>("payoutAccounts:applyAccountSnapshot");

const noAccount: StripeAccountStatus = {
  state: "none",
  stripeAccountId: false,
  chargesEnabled: false,
  payoutsEnabled: false,
  detailsSubmitted: false,
  requirementsDue: [],
};

async function setupBand(role: "admin" | "member" | null = "member") {
  const t = convexTest(schema);
  const asUser = t.withIdentity({
    subject: "payout_band_user",
    email: "band@example.com",
    name: "Band User",
  });
  const { userId } = await asUser.mutation(api.users.ensureUser, {});
  const bandId = await t.run(async (ctx) => {
    const bandId = await ctx.db.insert("bands", {
      name: "Private Signals",
      slug: "private-signals",
      genres: ["noise"],
      area: "Bay Area",
      colorHex: "#7B8FFF",
      initials: "PS",
      followerCount: 0,
      pastShows: [],
    });
    if (role !== null) {
      await ctx.db.insert("bandMembers", { bandId, userId, role });
    }
    return bandId;
  });
  return { t, asUser, userId, bandId };
}

async function setupOrganization(role: OrganizationRole | null = "owner") {
  const t = convexTest(schema);
  const asUser = t.withIdentity({
    subject: "payout_org_user",
    email: "owner@example.com",
    name: "Organization User",
  });
  const { userId } = await asUser.mutation(api.users.ensureUser, {});
  const organizationId = await t.run(async (ctx) => {
    const organizationId = await ctx.db.insert("organizations", {
      name: "Neighborhood Venues",
      slug: "neighborhood-venues",
      orgType: "venueOperator",
      status: "verified",
      ownerUserId: userId,
      createdAt: 1,
      updatedAt: 1,
    });
    if (role !== null) {
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId,
        role,
        createdAt: 1,
      });
    }
    return organizationId;
  });
  return { t, asUser, userId, organizationId };
}

const statusCases = [
  { state: "onboarding", detailsSubmitted: false, payoutsEnabled: false },
  { state: "restricted", detailsSubmitted: true, payoutsEnabled: false },
  { state: "enabled", detailsSubmitted: true, payoutsEnabled: true },
  { state: "enabled", detailsSubmitted: false, payoutsEnabled: true },
] as const;

describe("bandPayoutStatus", () => {
  test("returns the complete none shape without a stored row", async () => {
    const { asUser, bandId } = await setupBand();
    expect(await asUser.query(bandPayoutStatus, { bandId })).toEqual(noAccount);
  });

  test.each(statusCases)(
    "returns $state with detailsSubmitted=$detailsSubmitted and payoutsEnabled=$payoutsEnabled",
    async ({ state, detailsSubmitted, payoutsEnabled }) => {
      const { t, asUser, bandId } = await setupBand();
      await t.run((ctx) =>
        ctx.db.insert("bandPayoutAccounts", {
          bandId,
          stripeAccountId: "acct_private_band",
          chargesEnabled: true,
          payoutsEnabled,
          detailsSubmitted,
          requirementsDue: ["individual.verification.document"],
          updatedAt: 1,
        }),
      );
      expect(await asUser.query(bandPayoutStatus, { bandId })).toEqual({
        state,
        stripeAccountId: true,
        chargesEnabled: true,
        payoutsEnabled,
        detailsSubmitted,
        requirementsDue: ["individual.verification.document"],
      });
    },
  );

  test("rejects non-members and unsigned callers", async () => {
    const { t, asUser, bandId } = await setupBand(null);
    await expect(asUser.query(bandPayoutStatus, { bandId })).rejects.toThrow(
      "Not a member of this band",
    );
    await expect(t.query(bandPayoutStatus, { bandId })).rejects.toThrow(
      "Not signed in",
    );
  });
});

describe("organizationStripeStatus", () => {
  test.each(["owner", "manager", "finance", "door"] as const)(
    "allows a %s to read the none shape without private details",
    async (role) => {
      const { asUser, organizationId } = await setupOrganization(role);
      expect(
        await asUser.query(organizationStripeStatus, { organizationId }),
      ).toEqual(noAccount);
    },
  );

  test.each(statusCases)(
    "returns $state with detailsSubmitted=$detailsSubmitted and payoutsEnabled=$payoutsEnabled",
    async ({ state, detailsSubmitted, payoutsEnabled }) => {
      const { t, asUser, organizationId } = await setupOrganization("door");
      await t.run((ctx) =>
        ctx.db.insert("organizationPrivateDetails", {
          organizationId,
          businessEmail: "office@example.com",
          contactName: "Owner",
          stripeAccountId: "acct_private_org",
          stripeChargesEnabled: true,
          stripePayoutsEnabled: payoutsEnabled,
          stripeDetailsSubmitted: detailsSubmitted,
          stripeRequirementsDue: ["company.tax_id"],
          verificationDocStorageIds: [],
          updatedAt: 1,
        }),
      );
      expect(
        await asUser.query(organizationStripeStatus, { organizationId }),
      ).toEqual({
        state,
        stripeAccountId: true,
        chargesEnabled: true,
        payoutsEnabled,
        detailsSubmitted,
        requirementsDue: ["company.tax_id"],
      });
    },
  );

  test("maps absent optional Stripe fields on an existing private-details row", async () => {
    const { t, asUser, organizationId } = await setupOrganization();
    await t.run((ctx) =>
      ctx.db.insert("organizationPrivateDetails", {
        organizationId,
        businessEmail: "office@example.com",
        contactName: "Owner",
        stripeChargesEnabled: false,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: false,
        verificationDocStorageIds: [],
        updatedAt: 1,
      }),
    );
    expect(
      await asUser.query(organizationStripeStatus, { organizationId }),
    ).toEqual({ ...noAccount, state: "onboarding" });
  });

  test("rejects strangers and unsigned callers but allows a platform admin", async () => {
    const { t, asUser, userId, organizationId } = await setupOrganization(null);
    await expect(
      asUser.query(organizationStripeStatus, { organizationId }),
    ).rejects.toThrow("Not permitted for this organization");
    await expect(
      t.query(organizationStripeStatus, { organizationId }),
    ).rejects.toThrow("Not signed in");
    await t.run((ctx) =>
      ctx.db.insert("platformAdmins", { userId, grantedAt: 1 }),
    );
    expect(
      await asUser.query(organizationStripeStatus, { organizationId }),
    ).toEqual(noAccount);
    expect(
      await asUser.query(organizationOnboardingContext, { organizationId }),
    ).toEqual({
      stripeAccountId: null,
      name: "Neighborhood Venues",
      businessEmail: null,
      legalName: null,
    });
  });
});

describe("onboarding contexts and account attachment", () => {
  test("returns the admin's email and account, or null for absent values", async () => {
    const { t, asUser, userId, bandId } = await setupBand("admin");
    expect(await asUser.query(bandOnboardingContext, { bandId })).toEqual({
      stripeAccountId: null,
      bandName: "Private Signals",
      contactEmail: "band@example.com",
    });
    expect(
      await t.mutation(attachBandAccount, {
        bandId,
        stripeAccountId: "acct_band",
      }),
    ).toBeNull();
    await t.run((ctx) => ctx.db.patch("users", userId, { email: "" }));
    expect(await asUser.query(bandOnboardingContext, { bandId })).toEqual({
      stripeAccountId: "acct_band",
      bandName: "Private Signals",
      contactEmail: null,
    });
    const account = await t.run((ctx) =>
      ctx.db
        .query("bandPayoutAccounts")
        .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
        .unique(),
    );
    expect(account).toMatchObject({
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
      onboardingStartedAt: expect.any(Number),
      updatedAt: account?.onboardingStartedAt,
    });
  });

  test("requires private details and preserves existing organization Stripe flags", async () => {
    const { t, asUser, organizationId } = await setupOrganization();
    await expect(
      t.mutation(attachOrganizationAccount, {
        organizationId,
        stripeAccountId: "acct_org",
      }),
    ).rejects.toThrow("Organization private details not found");
    const detailsId = await t.run((ctx) =>
      ctx.db.insert("organizationPrivateDetails", {
        organizationId,
        legalName: "Neighborhood Venues LLC",
        businessEmail: "office@example.com",
        contactName: "Owner",
        stripeChargesEnabled: true,
        stripePayoutsEnabled: false,
        stripeDetailsSubmitted: true,
        verificationDocStorageIds: [],
        updatedAt: 1,
      }),
    );
    expect(
      await t.mutation(attachOrganizationAccount, {
        organizationId,
        stripeAccountId: "acct_org",
      }),
    ).toBeNull();
    expect(await t.run((ctx) => ctx.db.get(detailsId))).toMatchObject({
      stripeAccountId: "acct_org",
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: true,
    });
    expect(
      await asUser.query(organizationOnboardingContext, { organizationId }),
    ).toEqual({
      stripeAccountId: "acct_org",
      name: "Neighborhood Venues",
      businessEmail: "office@example.com",
      legalName: "Neighborhood Venues LLC",
    });
  });
});

test("applyAccountSnapshot updates the band using the shared Stripe snapshot sync", async () => {
  const { t, bandId } = await setupBand();
  const accountId = await t.run((ctx) =>
    ctx.db.insert("bandPayoutAccounts", {
      bandId,
      stripeAccountId: "acct_snapshot_band",
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: ["old.requirement"],
      onboardingStartedAt: 1,
      updatedAt: 1,
    }),
  );
  expect(
    await t.mutation(applyAccountSnapshot, {
      account: {
        id: "acct_snapshot_band",
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true,
        requirements: {
          currently_due: ["individual.verification.document"],
          past_due: [
            "individual.verification.document",
            "individual.id_number",
          ],
        },
      },
    }),
  ).toBeNull();
  const account = await t.run((ctx) => ctx.db.get(accountId));
  expect(account).toMatchObject({
    chargesEnabled: true,
    payoutsEnabled: true,
    detailsSubmitted: true,
    requirementsDue: [
      "individual.verification.document",
      "individual.id_number",
    ],
    onboardingStartedAt: 1,
  });
  expect(account?.updatedAt).toBeGreaterThan(1);
});
