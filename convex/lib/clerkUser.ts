import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";

export type ClerkUserFacts = {
  clerkId: string;
  email: string;
  emailVerified: boolean;
  name?: string;
};

type PrimaryEmailFacts = {
  email: string;
  verified: boolean;
};

/** Pure. Returns only the explicitly selected primary address. */
function primaryEmailFacts(user: unknown): PrimaryEmailFacts | null {
  if (typeof user !== "object" || user === null) return null;

  const data = user as Record<string, unknown>;
  if (typeof data.primary_email_address_id !== "string") return null;
  if (!Array.isArray(data.email_addresses)) return null;

  for (const candidate of data.email_addresses) {
    if (typeof candidate !== "object" || candidate === null) continue;
    const address = candidate as Record<string, unknown>;
    if (address.id !== data.primary_email_address_id) continue;

    const verification = address.verification;
    return {
      email:
        typeof address.email_address === "string" ? address.email_address : "",
      verified:
        typeof verification === "object" &&
        verification !== null &&
        (verification as Record<string, unknown>).status === "verified",
    };
  }
  return null;
}

/** Pure. Narrows an unknown-shaped Clerk webhook/API user payload. */
export function clerkUserFacts(data: unknown): ClerkUserFacts | null {
  if (typeof data !== "object" || data === null) return null;

  const user = data as Record<string, unknown>;
  if (typeof user.id !== "string" || user.id === "") return null;

  const primaryEmail = primaryEmailFacts(user);
  const firstName = typeof user.first_name === "string" ? user.first_name : "";
  const lastName = typeof user.last_name === "string" ? user.last_name : "";
  const name = `${firstName} ${lastName}`.trim();

  return {
    clerkId: user.id,
    email: primaryEmail?.email ?? "",
    emailVerified: primaryEmail?.verified ?? false,
    ...(name === "" ? {} : { name }),
  };
}

/** Pure. The only email this repo trusts from Clerk. */
export function verifiedPrimaryEmail(user: unknown): string | null {
  const primaryEmail = primaryEmailFacts(user);
  return primaryEmail !== null &&
    primaryEmail.verified &&
    primaryEmail.email !== ""
    ? primaryEmail.email
    : null;
}

/**
 * Writes an email only when no other users row already holds it.
 * A collision is left for manual resolution because creating another matching
 * row would make ensureUser's unique-email adoption permanently ambiguous.
 */
export async function safeSetEmail(
  ctx: MutationCtx,
  userId: Id<"users">,
  email: string,
): Promise<boolean> {
  const matches = await ctx.db
    .query("users")
    .withIndex("by_email", (q) => q.eq("email", email))
    .take(2);
  const collision = matches.find((match) => match._id !== userId);
  if (collision !== undefined) {
    console.warn(
      `Refusing email collision: ${userId} <- ${email} (already on ${collision._id})`,
    );
    return false;
  }

  await ctx.db.patch(userId, { email });
  return true;
}

/**
 * The shared Clerk identity adoption ladder. Keep every Clerk-driven user
 * writer inside this one mutation transaction so concurrent inserts conflict,
 * retry, and re-read the winning row.
 */
export async function upsertUserFromClerk(
  ctx: MutationCtx,
  facts: ClerkUserFacts,
  opts: { emailIsAuthoritative?: boolean } = {},
): Promise<{
  userId: Id<"users">;
  outcome: "created" | "adopted_by_clerk_id" | "adopted_by_email";
}> {
  const byClerkId = await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", facts.clerkId))
    .unique();
  if (byClerkId !== null) {
    if (
      (byClerkId.email === "" && facts.email !== "") ||
      (opts.emailIsAuthoritative === true &&
        facts.email !== "" &&
        facts.email !== byClerkId.email)
    ) {
      await safeSetEmail(ctx, byClerkId._id, facts.email);
    }

    const patch: { name?: string; deletedAt?: undefined } = {};
    if (byClerkId.name === "" && facts.name !== undefined) {
      patch.name = facts.name;
    }
    if (byClerkId.deletedAt !== undefined) {
      patch.deletedAt = undefined;
    }
    if (Object.keys(patch).length > 0) {
      await ctx.db.patch(byClerkId._id, patch);
    }
    return { userId: byClerkId._id, outcome: "adopted_by_clerk_id" };
  }

  if (facts.email !== "" && facts.emailVerified) {
    const byEmail = await ctx.db
      .query("users")
      .withIndex("by_email", (q) => q.eq("email", facts.email))
      .take(2);
    if (byEmail.length === 1 && byEmail[0].deletedAt === undefined) {
      const adopted = byEmail[0];
      await ctx.db.patch(adopted._id, {
        clerkId: facts.clerkId,
        ...(adopted.name === "" && facts.name !== undefined
          ? { name: facts.name }
          : {}),
      });
      return { userId: adopted._id, outcome: "adopted_by_email" };
    }
  }

  const userId = await ctx.db.insert("users", {
    clerkId: facts.clerkId,
    name:
      facts.name ??
      (facts.email !== "" ? facts.email.split("@")[0] : "Music fan"),
    email: facts.email,
    genres: [],
    attendedCount: 0,
  });
  return { userId, outcome: "created" };
}
