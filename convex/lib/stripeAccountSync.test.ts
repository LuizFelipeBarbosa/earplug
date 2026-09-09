import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import schema from "../schema";
import { syncStripeAccount } from "./stripeAccountSync";

async function setupBandAccount() {
  const t = convexTest(schema);
  const accountId = await t.run(async (ctx) => {
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
    return await ctx.db.insert("bandPayoutAccounts", {
      bandId,
      stripeAccountId: "acct_band",
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      requirementsDue: [],
      updatedAt: 1,
    });
  });
  return { t, accountId };
}

describe("syncStripeAccount", () => {
  test("syncs pending and active card payments alongside the existing band account fields", async () => {
    const { t, accountId } = await setupBandAccount();

    expect(
      await t.run((ctx) =>
        syncStripeAccount(ctx, {
          id: "acct_band",
          capabilities: { card_payments: "pending" },
          charges_enabled: false,
          payouts_enabled: true,
          details_submitted: true,
          requirements: {
            currently_due: ["individual.verification.document", "individual.dob"],
            past_due: ["individual.dob", "individual.address"],
          },
        }),
      ),
    ).toBe("band");
    const pendingAccount = await t.run((ctx) => ctx.db.get(accountId));
    expect(pendingAccount).toMatchObject({
      cardPaymentsStatus: "pending",
      chargesEnabled: false,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: [
        "individual.verification.document",
        "individual.dob",
        "individual.address",
      ],
    });
    expect(pendingAccount?.updatedAt).toBeGreaterThan(1);

    expect(
      await t.run((ctx) =>
        syncStripeAccount(ctx, {
          id: "acct_band",
          capabilities: { card_payments: "active" },
          charges_enabled: true,
          payouts_enabled: true,
          details_submitted: true,
          requirements: { currently_due: [], past_due: [] },
        }),
      ),
    ).toBe("band");
    expect(await t.run((ctx) => ctx.db.get(accountId))).toMatchObject({
      cardPaymentsStatus: "active",
      chargesEnabled: true,
      payoutsEnabled: true,
      detailsSubmitted: true,
      requirementsDue: [],
    });
  });

  test.each(["capabilities", "card_payments"] as const)(
    "clears the stored capability status and defaults missing fields when %s is absent",
    async (missingField) => {
      const { t, accountId } = await setupBandAccount();
      await t.run((ctx) =>
        ctx.db.patch("bandPayoutAccounts", accountId, {
          cardPaymentsStatus: "active",
          payoutsEnabled: true,
          detailsSubmitted: true,
          requirementsDue: ["individual.verification.document"],
        }),
      );

      expect(
        await t.run((ctx) =>
          syncStripeAccount(ctx, {
            id: "acct_band",
            charges_enabled: true,
            ...(missingField === "capabilities" ? {} : { capabilities: {} }),
          }),
        ),
      ).toBe("band");
      const account = await t.run((ctx) => ctx.db.get(accountId));
      expect(account).not.toHaveProperty("cardPaymentsStatus");
      expect(account).toMatchObject({
        chargesEnabled: true,
        payoutsEnabled: false,
        detailsSubmitted: false,
        requirementsDue: [],
      });
      expect(account?.updatedAt).toBeGreaterThan(1);
    },
  );
});
