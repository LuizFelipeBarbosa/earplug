import { MutationCtx, QueryCtx } from "../_generated/server";
import { isReservedPublicSlug, slugify } from "./helpers";

/** Issues the base venue slug, or a numeric suffix when it is taken.
 *
 * Reads with `.first()`, not `.unique()`: the schema does not enforce slug
 * uniqueness, so a duplicate from another writer must never wedge issuance. */
export async function uniqueVenueSlug(
  ctx: MutationCtx,
  name: string,
): Promise<string> {
  const base = slugify(name);
  for (let n = 1; ; n++) {
    const candidate = n === 1 ? base : `${base}-${n}`;
    if (isReservedPublicSlug(candidate)) continue;
    const taken = await ctx.db
      .query("venues")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (taken === null) return candidate;
  }
}

export async function isVenueSlugAvailable(
  ctx: MutationCtx | QueryCtx,
  slug: string,
): Promise<boolean> {
  const existing = await ctx.db
    .query("venues")
    .withIndex("by_slug", (q) => q.eq("slug", slug))
    .first();
  return existing === null;
}
