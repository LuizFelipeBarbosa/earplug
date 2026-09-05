import { makeFunctionReference } from "convex/server";
import type { Infer } from "convex/values";
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import type { Id } from "./_generated/dataModel";
import type { OrganizationRole } from "./lib/authz";
import {
  StripeApiError,
  stripeIdempotencyKey,
  stripeRequest,
} from "./lib/stripeClient";
import type { stripeAccountStatusValidator } from "./payoutAccounts";
import schema from "./schema";

vi.mock("./lib/stripeClient", async (importOriginal) => {
  const actual = await importOriginal<typeof import("./lib/stripeClient")>();
  return { ...actual, stripeRequest: vi.fn() };
});

const startBandOnboarding = makeFunctionReference<
  "action",
  { bandId: Id<"bands"> },
  { url: string }
>("stripeActions:startBandOnboarding");
const startOrganizationOnboarding = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations"> },
  { url: string }
>("stripeActions:startOrganizationOnboarding");
const refreshBandAccountStatus = makeFunctionReference<
  "action",
  { bandId: Id<"bands"> },
  Infer<typeof stripeAccountStatusValidator>
>("stripeActions:refreshBandAccountStatus");
const refreshOrganizationAccountStatus = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations"> },
  Infer<typeof stripeAccountStatusValidator>
>("stripeActions:refreshOrganizationAccountStatus");
const bandExpressDashboardLink = makeFunctionReference<
  "action",
  { bandId: Id<"bands"> },
  { url: string }
>("stripeActions:bandExpressDashboardLink");
const organizationExpressDashboardLink = makeFunctionReference<
  "action",
  { organizationId: Id<"organizations"> },
  { url: string }
>("stripeActions:organizationExpressDashboardLink");

const stripeMock = vi.mocked(stripeRequest);
const baseUrl = "https://preview.earplug.test";

beforeEach(() => {
  stripeMock.mockReset();
  vi.stubEnv("PAYMENTS_ENABLED", "true");
  vi.stubEnv("APP_BASE_URL", baseUrl);
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.restoreAllMocks();
});

async function setupBand(role: "admin" | "member" | null = "admin") {
  const t = convexTest(schema);
  const asUser = t.withIdentity({
    subject: "stripe_band_user",
    email: "band@example.com",
    name: "Band Admin",
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
  return { t, asUser, bandId };
}

async function setupOrganization(role: OrganizationRole | null = "owner") {
  const t = convexTest(schema);
  const asUser = t.withIdentity({
    subject: "stripe_org_user",
    email: "owner@example.com",
    name: "Organization Owner",
  });
  const { userId } = await asUser.mutation(api.users.ensureUser, {});
  const { organizationId, detailsId } = await t.run(async (ctx) => {
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
    const detailsId = await ctx.db.insert("organizationPrivateDetails", {
      organizationId,
      legalName: "Neighborhood Venues LLC",
      businessEmail: "office@example.com",
      contactName: "Organization Owner",
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
      verificationDocStorageIds: [],
      updatedAt: 1,
    });
    return { organizationId, detailsId };
  });
  return { t, asUser, userId, organizationId, detailsId };
}

async function seedBandAccount(
  setup: Awaited<ReturnType<typeof setupBand>>,
  detailsSubmitted = false,
) {
  return await setup.t.run((ctx) =>
    ctx.db.insert("bandPayoutAccounts", {
      bandId: setup.bandId,
      stripeAccountId: "acct_band",
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted,
      requirementsDue: [],
      updatedAt: 1,
    }),
  );
}

describe("startBandOnboarding", () => {
  test("creates and attaches one Express account, then issues fresh links on repeat calls", async () => {
    const { t, asUser, bandId } = await setupBand();
    stripeMock
      .mockResolvedValueOnce({ id: "acct_band" })
      .mockResolvedValueOnce({ url: "https://connect.stripe.test/first" })
      .mockResolvedValueOnce({ url: "https://connect.stripe.test/second" });

    expect(await asUser.action(startBandOnboarding, { bandId })).toEqual({
      url: "https://connect.stripe.test/first",
    });
    expect(stripeMock).toHaveBeenNthCalledWith(
      1,
      "POST",
      "/v1/accounts",
      {
        type: "express",
        country: "US",
        capabilities: { transfers: { requested: true } },
        business_type: "individual",
        business_profile: {
          name: "Private Signals",
          product_description: "Live music performances booked through EarPlug",
        },
        metadata: { bandId, earplug: "band" },
        settings: { payouts: { schedule: { interval: "daily" } } },
      },
      { idempotencyKey: stripeIdempotencyKey("band-account", bandId) },
    );
    const account = await t.run((ctx) =>
      ctx.db
        .query("bandPayoutAccounts")
        .withIndex("by_bandId", (q) => q.eq("bandId", bandId))
        .unique(),
    );
    expect(account?.stripeAccountId).toBe("acct_band");
    expect(await asUser.action(startBandOnboarding, { bandId })).toEqual({
      url: "https://connect.stripe.test/second",
    });
    expect(stripeMock).toHaveBeenCalledTimes(3);
    expect(
      stripeMock.mock.calls.filter(([, path]) => path === "/v1/accounts"),
    ).toHaveLength(1);
    for (const call of stripeMock.mock.calls.slice(1)) {
      // Exact arity proves account links receive no idempotency option.
      expect(call).toEqual([
        "POST",
        "/v1/account_links",
        {
          account: "acct_band",
          type: "account_onboarding",
          refresh_url: `${baseUrl}/band/stripe/refresh?band=${bandId}`,
          return_url: `${baseUrl}/band/stripe/return?band=${bandId}`,
        },
      ]);
    }
  });

  test("preserves the payments gate error without a Stripe prefix", async () => {
    vi.stubEnv("PAYMENTS_ENABLED", "false");
    const { asUser, bandId } = await setupBand();
    stripeMock.mockImplementation(() => {
      throw new Error("Payments are not enabled");
    });
    await expect(
      asUser.action(startBandOnboarding, { bandId }),
    ).rejects.toThrow(/^Payments are not enabled$/);
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });

  test("wraps a Stripe account-link failure after attaching the new account", async () => {
    const { asUser, bandId } = await setupBand();
    stripeMock
      .mockResolvedValueOnce({ id: "acct_band" })
      .mockRejectedValueOnce(
        new StripeApiError("Invalid return URL", { status: 400 }),
      );
    await expect(
      asUser.action(startBandOnboarding, { bandId }),
    ).rejects.toThrow(/^Stripe: Invalid return URL$/);
  });
});

describe("startOrganizationOnboarding", () => {
  test("creates a company account with ticket-charge capabilities and reuses it", async () => {
    const { t, asUser, organizationId, detailsId } = await setupOrganization();
    stripeMock
      .mockResolvedValueOnce({ id: "acct_org" })
      .mockResolvedValueOnce({ url: "https://connect.stripe.test/org-first" })
      .mockResolvedValueOnce({ url: "https://connect.stripe.test/org-second" });
    expect(
      await asUser.action(startOrganizationOnboarding, { organizationId }),
    ).toEqual({ url: "https://connect.stripe.test/org-first" });
    expect(stripeMock).toHaveBeenNthCalledWith(
      1,
      "POST",
      "/v1/accounts",
      {
        type: "express",
        country: "US",
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        business_type: "company",
        business_profile: {
          name: "Neighborhood Venues LLC",
          product_description: "Live music performances booked through EarPlug",
        },
        metadata: { organizationId, earplug: "organization" },
        settings: { payouts: { schedule: { interval: "daily" } } },
        email: "office@example.com",
      },
      { idempotencyKey: stripeIdempotencyKey("org-account", organizationId) },
    );
    expect(await t.run((ctx) => ctx.db.get(detailsId))).toMatchObject({
      stripeAccountId: "acct_org",
      stripeChargesEnabled: false,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: false,
    });
    expect(
      await asUser.action(startOrganizationOnboarding, { organizationId }),
    ).toEqual({ url: "https://connect.stripe.test/org-second" });
    expect(stripeMock).toHaveBeenCalledTimes(3);
    expect(
      stripeMock.mock.calls.filter(([, path]) => path === "/v1/accounts"),
    ).toHaveLength(1);
    for (const call of stripeMock.mock.calls.slice(1)) {
      expect(call).toEqual([
        "POST",
        "/v1/account_links",
        {
          account: "acct_org",
          type: "account_onboarding",
          refresh_url: `${baseUrl}/org/stripe/refresh?org=${organizationId}`,
          return_url: `${baseUrl}/org/stripe/return?org=${organizationId}`,
        },
      ]);
    }
  });

  test("omits email and falls back to the organization name when private details are absent", async () => {
    const { t, asUser, organizationId, detailsId } = await setupOrganization();
    await t.run((ctx) =>
      ctx.db.delete("organizationPrivateDetails", detailsId),
    );
    stripeMock.mockResolvedValueOnce({ id: "acct_org" });
    await expect(
      asUser.action(startOrganizationOnboarding, { organizationId }),
    ).rejects.toThrow("Organization private details not found");
    expect(stripeMock).toHaveBeenCalledTimes(1);
    const params = stripeMock.mock.calls[0][2];
    expect(params).not.toHaveProperty("email");
    expect(params).toMatchObject({
      business_profile: { name: "Neighborhood Venues" },
    });
  });

  test("allows a platform admin without organization membership", async () => {
    const { t, asUser, userId, organizationId, detailsId } =
      await setupOrganization(null);
    await t.run(async (ctx) => {
      await ctx.db.insert("platformAdmins", { userId, grantedAt: 1 });
      await ctx.db.patch("organizationPrivateDetails", detailsId, {
        stripeAccountId: "acct_org",
      });
    });
    stripeMock.mockResolvedValueOnce({
      url: "https://connect.stripe.test/admin",
    });
    expect(
      await asUser.action(startOrganizationOnboarding, { organizationId }),
    ).toEqual({ url: "https://connect.stripe.test/admin" });
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });
});

describe("action authorization", () => {
  test.each(["member", null] as const)(
    "rejects band role %s before any Stripe request",
    async (role) => {
      const { asUser, bandId } = await setupBand(role);
      for (const action of [
        startBandOnboarding,
        refreshBandAccountStatus,
        bandExpressDashboardLink,
      ]) {
        await expect(asUser.action(action, { bandId })).rejects.toThrow(
          "Not an admin of this band",
        );
      }
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );

  test.each(["manager", "finance", "door", null] as const)(
    "rejects organization role %s before any Stripe request",
    async (role) => {
      const { asUser, organizationId } = await setupOrganization(role);
      for (const action of [
        startOrganizationOnboarding,
        refreshOrganizationAccountStatus,
        organizationExpressDashboardLink,
      ]) {
        await expect(asUser.action(action, { organizationId })).rejects.toThrow(
          "Not permitted for this organization",
        );
      }
      expect(stripeMock).not.toHaveBeenCalled();
    },
  );
});

describe("account status refresh", () => {
  test("persists a band snapshot and returns the derived status", async () => {
    const setup = await setupBand();
    const accountId = await seedBandAccount(setup);
    stripeMock.mockResolvedValueOnce({
      id: "acct_band",
      charges_enabled: true,
      payouts_enabled: true,
      details_submitted: true,
      requirements: { currently_due: ["individual.verification.document"] },
    });
    expect(
      await setup.asUser.action(refreshBandAccountStatus, {
        bandId: setup.bandId,
      }),
    ).toEqual({
      state: "enabled",
      stripeAccountId: true,
      chargesEnabled: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: ["individual.verification.document"],
    });
    expect(stripeMock.mock.calls).toEqual([["GET", "/v1/accounts/acct_band"]]);
    const account = await setup.t.run((ctx) => ctx.db.get(accountId));
    expect(account).toMatchObject({
      chargesEnabled: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: ["individual.verification.document"],
    });
    expect(account?.updatedAt).toBeGreaterThan(1);
  });

  test("persists an organization snapshot and returns the derived status", async () => {
    const { t, asUser, organizationId, detailsId } = await setupOrganization();
    await t.run((ctx) =>
      ctx.db.patch("organizationPrivateDetails", detailsId, {
        stripeAccountId: "acct_org",
      }),
    );
    stripeMock.mockResolvedValueOnce({
      id: "acct_org",
      charges_enabled: true,
      payouts_enabled: false,
      details_submitted: true,
      requirements: {
        currently_due: ["company.tax_id"],
        past_due: ["company.name"],
      },
    });
    expect(
      await asUser.action(refreshOrganizationAccountStatus, { organizationId }),
    ).toEqual({
      state: "restricted",
      stripeAccountId: true,
      chargesEnabled: true,
      payoutsEnabled: false,
      detailsSubmitted: true,
      requirementsDue: ["company.tax_id", "company.name"],
    });
    expect(stripeMock.mock.calls).toEqual([["GET", "/v1/accounts/acct_org"]]);
    const details = await t.run((ctx) => ctx.db.get(detailsId));
    expect(details).toMatchObject({
      stripeChargesEnabled: true,
      stripePayoutsEnabled: false,
      stripeDetailsSubmitted: true,
      stripeRequirementsDue: ["company.tax_id", "company.name"],
    });
    expect(details?.updatedAt).toBeGreaterThan(1);
  });

  test("returns stored status without Stripe requests when no account is attached", async () => {
    const band = await setupBand();
    expect(
      await band.asUser.action(refreshBandAccountStatus, {
        bandId: band.bandId,
      }),
    ).toEqual({
      state: "none",
      stripeAccountId: false,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
    });
    const org = await setupOrganization();
    expect(
      await org.asUser.action(refreshOrganizationAccountStatus, {
        organizationId: org.organizationId,
      }),
    ).toEqual({
      state: "onboarding",
      stripeAccountId: false,
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
    });
    expect(stripeMock).not.toHaveBeenCalled();
  });
});

describe("Express dashboard links", () => {
  test("requires an attached band account and submitted details before issuing a login link", async () => {
    const setup = await setupBand();
    const { t, asUser, bandId } = setup;
    await expect(
      asUser.action(bandExpressDashboardLink, { bandId }),
    ).rejects.toThrow("Finish Stripe setup first");
    const accountId = await seedBandAccount(setup);
    await expect(
      asUser.action(bandExpressDashboardLink, { bandId }),
    ).rejects.toThrow("Finish Stripe setup first");
    expect(stripeMock).not.toHaveBeenCalled();
    await t.run((ctx) =>
      ctx.db.patch("bandPayoutAccounts", accountId, { detailsSubmitted: true }),
    );
    const now = 1_800_000_000_000;
    vi.spyOn(Date, "now").mockReturnValue(now);
    stripeMock.mockResolvedValueOnce({
      url: "https://connect.stripe.test/band-login",
    });
    expect(await asUser.action(bandExpressDashboardLink, { bandId })).toEqual({
      url: "https://connect.stripe.test/band-login",
    });
    expect(stripeMock.mock.calls).toEqual([
      [
        "POST",
        "/v1/accounts/acct_band/login_links",
        {},
        { idempotencyKey: stripeIdempotencyKey("band-dashboard", bandId, now) },
      ],
    ]);
  });

  test("requires an attached organization account and submitted details before issuing a login link", async () => {
    const { t, asUser, organizationId, detailsId } = await setupOrganization();
    await expect(
      asUser.action(organizationExpressDashboardLink, { organizationId }),
    ).rejects.toThrow("Finish Stripe setup first");
    await t.run((ctx) =>
      ctx.db.patch("organizationPrivateDetails", detailsId, {
        stripeAccountId: "acct_org",
      }),
    );
    await expect(
      asUser.action(organizationExpressDashboardLink, { organizationId }),
    ).rejects.toThrow("Finish Stripe setup first");
    expect(stripeMock).not.toHaveBeenCalled();
    await t.run((ctx) =>
      ctx.db.patch("organizationPrivateDetails", detailsId, {
        stripeDetailsSubmitted: true,
      }),
    );
    const now = 1_800_000_000_000;
    vi.spyOn(Date, "now").mockReturnValue(now);
    stripeMock.mockResolvedValueOnce({
      url: "https://connect.stripe.test/org-login",
    });
    expect(
      await asUser.action(organizationExpressDashboardLink, { organizationId }),
    ).toEqual({ url: "https://connect.stripe.test/org-login" });
    expect(stripeMock.mock.calls).toEqual([
      [
        "POST",
        "/v1/accounts/acct_org/login_links",
        {},
        {
          idempotencyKey: stripeIdempotencyKey(
            "org-dashboard",
            organizationId,
            now,
          ),
        },
      ],
    ]);
  });
});

describe("Stripe API errors", () => {
  test.each([
    { name: "startBandOnboarding", action: startBandOnboarding },
    { name: "refreshBandAccountStatus", action: refreshBandAccountStatus },
    { name: "bandExpressDashboardLink", action: bandExpressDashboardLink },
  ])("prefixes Stripe errors from $name", async ({ action }) => {
    const setup = await setupBand();
    if (action !== startBandOnboarding) await seedBandAccount(setup, true);
    stripeMock.mockRejectedValueOnce(
      new StripeApiError("Account unavailable", { status: 400 }),
    );
    await expect(
      setup.asUser.action(action, { bandId: setup.bandId }),
    ).rejects.toThrow(/^Stripe: Account unavailable$/);
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });

  test.each([
    {
      name: "startOrganizationOnboarding",
      action: startOrganizationOnboarding,
    },
    {
      name: "refreshOrganizationAccountStatus",
      action: refreshOrganizationAccountStatus,
    },
    {
      name: "organizationExpressDashboardLink",
      action: organizationExpressDashboardLink,
    },
  ])("prefixes Stripe errors from $name", async ({ action }) => {
    const { t, asUser, organizationId, detailsId } = await setupOrganization();
    if (action !== startOrganizationOnboarding) {
      await t.run((ctx) =>
        ctx.db.patch("organizationPrivateDetails", detailsId, {
          stripeAccountId: "acct_org",
          stripeDetailsSubmitted: true,
        }),
      );
    }
    stripeMock.mockRejectedValueOnce(
      new StripeApiError("Account unavailable", { status: 400 }),
    );
    await expect(asUser.action(action, { organizationId })).rejects.toThrow(
      /^Stripe: Account unavailable$/,
    );
    expect(stripeMock).toHaveBeenCalledTimes(1);
  });
});
