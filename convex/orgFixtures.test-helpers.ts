/** Test-only fixtures. The multi-dot filename keeps this module out of the
 * Convex bundle (the CLI skips `*.x.ts` files) while vitest's default include
 * pattern (`*.test.ts`) keeps it from being collected as a suite. */
import type { TestConvexForDataModelAndIdentity } from "convex-test";
import { api } from "./_generated/api";
import type { DataModel, Doc, Id } from "./_generated/dataModel";
import type { OrganizationRole } from "./lib/authz";

export type OrganizationActor = {
  label: string;
  role: OrganizationRole | null;
  email?: string;
  name?: string;
  createdAt?: number;
  /** Label of another actor in this fixture. */
  addedBy?: string;
};

export type OrganizationOptions = {
  prefix: string;
  orgType?: "venueOperator" | "privateHost";
  /** Defaults to ["owner"]. Null creates a user without a membership.
   * Use labeled actors for strangers, repeated roles, or custom identities.
   * A lone null is labeled "user"; other null entries use "user_<index>". */
  roles?: readonly (OrganizationRole | null | OrganizationActor)[];
  /** Defaults to direct inserts. The dashboard, membership, payout-account,
   * and Stripe-action suites should set this to true to preserve ensureUser. */
  viaEnsureUser?: boolean;
  withPrivateDetails?: boolean;
  /** Defaults to 1, matching the simple organization suites. */
  now?: number;
  /** Defaults to the first actor, even when that actor has no membership. */
  ownerLabel?: string;
  organization?: Partial<
    Omit<Doc<"organizations">, "_id" | "_creationTime" | "ownerUserId">
  >;
  /** Applied only when withPrivateDetails is true. */
  privateDetails?: Partial<
    Omit<Doc<"organizationPrivateDetails">, "_id" | "_creationTime" | "organizationId">
  >;
};

export type OrganizationFixture = {
  t: TestConvexForDataModelAndIdentity<DataModel>;
  as: (roleOrLabel: string) =>
    ReturnType<TestConvexForDataModelAndIdentity<DataModel>["withIdentity"]>;
  users: Record<string, Id<"users">>;
  organizationId: Id<"organizations">;
  detailsId?: Id<"organizationPrivateDetails">;
};

/** Seeds one organization with users and optional memberships/private details.
 * For example, roles: ["owner", { label: "invitee", role: null }] creates an
 * owner and a non-member. roles: [{ label: "user", role: null }] supports an
 * organization owner with no membership row.
 *
 * Names, emails, timestamps and organization/private fields are overridable
 * for suites that assert their exact values. Opportunity suites can use direct
 * inserts and add their venues, bands and second organization locally. */
export async function setupOrganization(
  t: TestConvexForDataModelAndIdentity<DataModel>,
  opts: OrganizationOptions,
): Promise<OrganizationFixture> {
  const roles = opts.roles ?? ["owner"];
  const actors: OrganizationActor[] = roles.map((entry, index) =>
    typeof entry === "object" && entry !== null
      ? entry
      : {
          label: entry ?? (roles.length === 1 ? "user" : `user_${index}`),
          role: entry,
        },
  );
  const labels = new Set(actors.map((actor) => actor.label));
  if (actors.length === 0 || labels.size !== actors.length) {
    throw new Error("Organization fixtures need at least one actor with unique labels");
  }
  const ownerLabel = opts.ownerLabel ?? actors[0].label;
  if (
    !labels.has(ownerLabel) ||
    actors.some((actor) => actor.addedBy !== undefined && !labels.has(actor.addedBy))
  ) {
    throw new Error("Organization owner and addedBy must reference fixture actors");
  }
  const identities = new Map(actors.map((actor) => [actor.label, {
    subject: `${opts.prefix}_${actor.label}`,
    email: actor.email ?? `${actor.label}@${opts.prefix}.test`,
    name: actor.name ?? actor.label,
  }]));
  const as = (label: string) => {
    const identity = identities.get(label);
    if (!identity) throw new Error(`Unknown organization fixture actor: ${label}`);
    return t.withIdentity(identity);
  };
  const users: Record<string, Id<"users">> = {};
  if (opts.viaEnsureUser) {
    for (const actor of actors) {
      const { userId } = await as(actor.label).mutation(api.users.ensureUser, {});
      users[actor.label] = userId;
    }
  }
  const now = opts.now ?? 1;
  const ids = await t.run(async (ctx) => {
    if (!opts.viaEnsureUser) {
      for (const [label, identity] of identities) {
        users[label] = await ctx.db.insert("users", {
          clerkId: identity.subject,
          email: identity.email,
          name: identity.name,
          genres: [],
          attendedCount: 0,
        });
      }
    }
    const organizationId = await ctx.db.insert("organizations", {
      name: "Neighborhood Venues",
      slug: "neighborhood-venues",
      orgType: opts.orgType ?? "venueOperator",
      status: "verified",
      ownerUserId: users[ownerLabel],
      createdAt: now,
      updatedAt: now,
      ...opts.organization,
    });
    for (const actor of actors) {
      if (actor.role === null) continue;
      await ctx.db.insert("organizationMembers", {
        organizationId,
        userId: users[actor.label],
        role: actor.role,
        createdAt: actor.createdAt ?? now,
        ...(actor.addedBy === undefined ? {} : { addedBy: users[actor.addedBy] }),
      });
    }
    const detailsId = opts.withPrivateDetails
      ? await ctx.db.insert("organizationPrivateDetails", {
          organizationId,
          legalName: "Neighborhood Venues LLC",
          businessEmail: `office@${opts.prefix}.test`,
          contactName: identities.get(ownerLabel)!.name,
          stripeChargesEnabled: false,
          stripePayoutsEnabled: false,
          stripeDetailsSubmitted: false,
          verificationDocStorageIds: [],
          updatedAt: now,
          ...opts.privateDetails,
        })
      : undefined;
    return { organizationId, detailsId };
  });
  return { t, as, users, ...ids };
}
