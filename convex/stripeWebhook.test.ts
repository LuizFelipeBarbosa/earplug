/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import type { TestConvex } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import type { Id } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";
import * as stripeAccountSync from "./lib/stripeAccountSync";
import schema from "./schema";
import type { StripeEvent } from "./stripeWebhook";

const modules = import.meta.glob("./**/*.ts");
const STRIPE_TEST_SECRET = "whsec_test";
const STRIPE_CONNECT_TEST_SECRET = "whsec_test_connect";
type TestBackend = TestConvex<typeof schema>;

async function signedStripe(
  body: string,
  secret: string,
): Promise<HeadersInit> {
  const timestamp = Math.floor(Date.now() / 1000);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const bytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${body}`),
  );
  const signature = Array.from(new Uint8Array(bytes), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
  return {
    "content-type": "application/json",
    "stripe-signature": `t=${timestamp},v1=${signature}`,
  };
}

function accountEvent(overrides: Partial<StripeEvent> = {}): StripeEvent {
  return {
    id: "evt_account_updated",
    type: "account.updated",
    account: "acct_test",
    livemode: false,
    created: Math.floor(Date.now() / 1000),
    data: {
      object: {
        id: "acct_test",
        charges_enabled: true,
        payouts_enabled: true,
        details_submitted: true,
        requirements: {
          currently_due: ["business_profile.url", "external_account"],
          past_due: ["external_account", "individual.dob.day"],
        },
      },
      previous_attributes: { charges_enabled: false },
    },
    ...overrides,
  };
}

async function deliver(
  t: TestBackend,
  event: unknown,
  kind: "platform" | "connect" = "connect",
): Promise<Response> {
  const body = JSON.stringify(event);
  return await t.fetch(
    kind === "platform" ? "/stripe-webhook" : "/stripe-connect-webhook",
    {
      method: "POST",
      headers: await signedStripe(
        body,
        kind === "platform" ? STRIPE_TEST_SECRET : STRIPE_CONNECT_TEST_SECRET,
      ),
      body,
    },
  );
}

async function seedBandAccount(
  ctx: MutationCtx,
  stripeAccountId = "acct_test",
): Promise<Id<"bandPayoutAccounts">> {
  const bandId = await ctx.db.insert("bands", {
    name: "Webhook Band",
    slug: "webhook-band",
    genres: [],
    area: "oak",
    colorHex: "#000000",
    initials: "WB",
    followerCount: 0,
    pastShows: [],
  });
  return await ctx.db.insert("bandPayoutAccounts", {
    bandId,
    stripeAccountId,
    chargesEnabled: false,
    payoutsEnabled: false,
    detailsSubmitted: false,
    requirementsDue: ["old_requirement"],
    onboardingStartedAt: 1,
    updatedAt: 1,
  });
}

async function seedOrganizationAccount(
  ctx: MutationCtx,
): Promise<Id<"organizationPrivateDetails">> {
  const ownerUserId = await ctx.db.insert("users", {
    clerkId: "user_webhook_owner",
    name: "Webhook Owner",
    email: "owner@example.com",
    genres: [],
    attendedCount: 0,
  });
  const organizationId = await ctx.db.insert("organizations", {
    name: "Webhook Organization",
    slug: "webhook-organization",
    orgType: "promoter",
    status: "verified",
    ownerUserId,
    createdAt: 1,
    updatedAt: 1,
  });
  return await ctx.db.insert("organizationPrivateDetails", {
    organizationId,
    businessEmail: "billing@example.com",
    contactName: "Webhook Owner",
    stripeAccountId: "acct_test",
    stripeChargesEnabled: false,
    stripePayoutsEnabled: false,
    stripeDetailsSubmitted: false,
    stripeRequirementsDue: ["old_requirement"],
    verificationDocStorageIds: [],
    updatedAt: 1,
  });
}

async function eventRows(t: TestBackend, eventId: string) {
  return await t.run(async (ctx) =>
    ctx.db
      .query("stripeEvents")
      .withIndex("by_eventId", (query) => query.eq("eventId", eventId))
      .take(10),
  );
}

beforeEach(() => {
  vi.stubEnv("STRIPE_WEBHOOK_SECRET", STRIPE_TEST_SECRET);
  vi.stubEnv("STRIPE_CONNECT_WEBHOOK_SECRET", STRIPE_CONNECT_TEST_SECRET);
  vi.stubEnv("CONVEX_CLOUD_URL", "https://brilliant-cardinal-773.convex.cloud");
});

afterEach(() => vi.unstubAllEnvs());

describe("Stripe webhook dispatch", () => {
  test("ignores unhandled events and deduplicates their redelivery", async () => {
    const t = convexTest(schema, modules);
    const event = accountEvent({ id: "evt_invoice", type: "invoice.paid" });
    const response = await deliver(t, event, "platform");
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("ignored");
    const rows = await eventRows(t, event.id);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      eventId: event.id,
      type: "invoice.paid",
      status: "ignored",
      appliedAt: expect.any(Number),
    });
    expect(rows[0].error).toBeUndefined();

    const duplicate = await deliver(t, event, "platform");
    expect(duplicate.status).toBe(200);
    expect(await duplicate.text()).toBe("duplicate");
    expect(await eventRows(t, event.id)).toEqual(rows);
  });

  test("syncs a band's Connect account and deduplicates its requirements", async () => {
    const t = convexTest(schema, modules);
    const id = await t.run((ctx) => seedBandAccount(ctx));
    const event = accountEvent();
    const response = await deliver(t, event);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("applied");
    const account = await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id));
    expect(account).toMatchObject({
      chargesEnabled: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: [
        "business_profile.url",
        "external_account",
        "individual.dob.day",
      ],
      onboardingStartedAt: 1,
    });
    expect(account!.updatedAt).toBeGreaterThan(1);
    const rows = await eventRows(t, event.id);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      status: "applied",
      account: "acct_test",
      appliedAt: expect.any(Number),
    });
    expect(rows[0].error).toBeUndefined();
  });

  test("syncs an organization's Stripe-prefixed account fields", async () => {
    const t = convexTest(schema, modules);
    const id = await t.run(seedOrganizationAccount);
    const event = accountEvent();
    const response = await deliver(t, event);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("applied");
    const organization = await t.run((ctx) =>
      ctx.db.get("organizationPrivateDetails", id),
    );
    expect(organization).toMatchObject({
      stripeChargesEnabled: true,
      stripePayoutsEnabled: true,
      stripeDetailsSubmitted: true,
      stripeRequirementsDue: [
        "business_profile.url",
        "external_account",
        "individual.dob.day",
      ],
      businessEmail: "billing@example.com",
    });
    expect(organization!.updatedAt).toBeGreaterThan(1);
    expect((await eventRows(t, event.id))[0].status).toBe("applied");
  });

  test("applies updates for an unknown account without creating an account", async () => {
    const t = convexTest(schema, modules);
    const event = accountEvent();
    const response = await deliver(t, event);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("applied");
    expect((await eventRows(t, event.id))[0].status).toBe("applied");
    expect(
      await t.run((ctx) => ctx.db.query("bandPayoutAccounts").take(10)),
    ).toEqual([]);
    expect(
      await t.run((ctx) => ctx.db.query("organizationPrivateDetails").take(10)),
    ).toEqual([]);
  });

  test("does not write the target or event again for an applied duplicate", async () => {
    const t = convexTest(schema, modules);
    const id = await t.run((ctx) => seedBandAccount(ctx));
    const event = accountEvent();
    expect(await (await deliver(t, event)).text()).toBe("applied");
    const account = await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id));
    const rows = await eventRows(t, event.id);

    // A different delivery time makes an accidental handler rerun observable.
    const now = vi.spyOn(Date, "now").mockReturnValue(Date.now() + 1000);
    try {
      const response = await deliver(t, event);
      expect(response.status).toBe(200);
      expect(await response.text()).toBe("duplicate");
      expect(
        await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
      ).toEqual(account);
      expect(await eventRows(t, event.id)).toEqual(rows);
      expect(rows).toHaveLength(1);
    } finally {
      now.mockRestore();
    }
  });

  test("persists a failed handler outcome and retries the same event after repair", async () => {
    const t = convexTest(schema, modules);
    const [id, duplicateId] = await t.run(async (ctx) => [
      await seedBandAccount(ctx),
      await seedBandAccount(ctx),
    ]);
    const before = await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id));
    const event = accountEvent();
    const response = await deliver(t, event);
    expect(response.status).toBe(500);
    expect(await response.text()).toBe("webhook mutation failed");
    const failedRows = await eventRows(t, event.id);
    expect(failedRows).toHaveLength(1);
    expect(failedRows[0].status).toBe("failed");
    expect(failedRows[0].error).toMatch(
      /unique.*more than one|multiple documents/i,
    );
    expect(failedRows[0].appliedAt).toBeUndefined();
    expect(
      await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
    ).toEqual(before);

    await t.run((ctx) => ctx.db.delete("bandPayoutAccounts", duplicateId));
    const retry = await deliver(t, event);
    expect(retry.status).toBe(200);
    expect(await retry.text()).toBe("applied");
    const appliedRows = await eventRows(t, event.id);
    expect(appliedRows).toHaveLength(1);
    expect(appliedRows[0]).toMatchObject({
      _id: failedRows[0]._id,
      _creationTime: failedRows[0]._creationTime,
      receivedAt: failedRows[0].receivedAt,
      status: "applied",
      appliedAt: expect.any(Number),
    });
    expect(appliedRows[0].error).toBeUndefined();
    expect(
      await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
    ).toMatchObject({ chargesEnabled: true, payoutsEnabled: true });
  });

  test("rolls back partial handler writes while preserving the failure for retry", async () => {
    const t = convexTest(schema, modules);
    const id = await t.run((ctx) => seedBandAccount(ctx));
    const before = await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id));
    const event = accountEvent();
    const syncStripeAccount = stripeAccountSync.syncStripeAccount;
    const failure = new Error("failure after account write");
    // Fail after a real write without adding a production handler override.
    const sync = vi.spyOn(stripeAccountSync, "syncStripeAccount")
      .mockImplementationOnce(async (ctx, account) => {
        await syncStripeAccount(ctx, account);
        throw failure;
      });
    try {
      const response = await deliver(t, event);
      expect(response.status).toBe(500);
      expect(await response.text()).toBe("webhook mutation failed");
      expect(
        await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
      ).toEqual(before);
      const failedRows = await eventRows(t, event.id);
      expect(failedRows).toHaveLength(1);
      expect(failedRows[0]).toMatchObject({
        status: "failed",
        error: failure.message,
      });

      const retry = await deliver(t, event);
      expect(retry.status).toBe(200);
      expect(await retry.text()).toBe("applied");
      const appliedRows = await eventRows(t, event.id);
      expect(appliedRows).toHaveLength(1);
      expect(appliedRows[0]).toMatchObject({
        _id: failedRows[0]._id,
        status: "applied",
        appliedAt: expect.any(Number),
      });
      expect(appliedRows[0].error).toBeUndefined();
      expect(
        await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
      ).toMatchObject({ chargesEnabled: true });
    } finally {
      sync.mockRestore();
    }
  });

  test("ignores livemode mismatches without running the account handler", async () => {
    const t = convexTest(schema, modules);
    const id = await t.run((ctx) => seedBandAccount(ctx));
    const before = await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id));
    const event = accountEvent({ livemode: true });
    const response = await deliver(t, event);
    expect(response.status).toBe(200);
    expect(await response.text()).toBe("ignored-livemode");
    const rows = await eventRows(t, event.id);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      status: "ignored",
      error: "livemode mismatch",
    });
    expect(
      await t.run((ctx) => ctx.db.get("bandPayoutAccounts", id)),
    ).toEqual(before);
  });

  test.each(["band", "organization"] as const)(
    "defaults missing account fields to false and empty requirements for a %s",
    async (kind) => {
      const t = convexTest(schema, modules);
      const id = await t.run(async (ctx) =>
        kind === "band"
          ? await seedBandAccount(ctx)
          : await seedOrganizationAccount(ctx),
      );
      expect(await (await deliver(t, accountEvent())).text()).toBe("applied");
      const response = await deliver(
        t,
        accountEvent({
          id: "evt_account_defaults",
          data: { object: { id: "acct_test" } },
        }),
      );
      expect(response.status).toBe(200);
      expect(await t.run((ctx) => ctx.db.get(id))).toMatchObject(
        kind === "band"
          ? {
              chargesEnabled: false,
              payoutsEnabled: false,
              detailsSubmitted: false,
              requirementsDue: [],
            }
          : {
              stripeChargesEnabled: false,
              stripePayoutsEnabled: false,
              stripeDetailsSubmitted: false,
              stripeRequirementsDue: [],
            },
      );
    },
  );

  test("prefers the band when both account tables contain the same Stripe id", async () => {
    const t = convexTest(schema, modules);
    const [bandId, organizationId] = await t.run(async (ctx) =>
      [
        await seedBandAccount(ctx),
        await seedOrganizationAccount(ctx),
      ] as const,
    );
    const organization = await t.run((ctx) => ctx.db.get(organizationId));
    expect(await (await deliver(t, accountEvent())).text()).toBe("applied");
    expect(await t.run((ctx) => ctx.db.get(bandId))).toMatchObject({
      chargesEnabled: true,
    });
    expect(await t.run((ctx) => ctx.db.get(organizationId))).toEqual(organization);
  });

  test.each([
    ["missing created", { created: undefined }],
    ["nonnumeric created", { created: "123" }],
    ["missing data", { data: undefined }],
    ["null data", { data: null }],
    ["nonobject data", { data: "account" }],
    ["missing data.object", { data: {} }],
    ["null data.object", { data: { object: null } }],
    ["nonobject data.object", { data: { object: "acct_test" } }],
  ])("rejects a signed event with %s", async (_label, fields) => {
    const t = convexTest(schema, modules);
    const event = { ...accountEvent(), ...fields };
    const response = await deliver(t, event);
    expect(response.status).toBe(400);
    expect(await response.text()).toBe("invalid event");
    expect(await eventRows(t, event.id)).toEqual([]);
  });
});
