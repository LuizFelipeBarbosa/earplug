import { v } from "convex/values";
import { Doc, Id } from "./_generated/dataModel";
import { MutationCtx, internalMutation } from "./_generated/server";
import { DEMO_BAND_NAMES, DEMO_GIG_TITLES, DEMO_VENUE_NAMES } from "./seed";

// Phase 2 of the legacy migration: `migrations:migrateAll` reshaped the data
// into the v1 contract but left the legacy tables populated and the seeded
// demo rows in place. This module recovers the last real data still trapped in
// legacy tables, then deletes everything dead, so `schema.ts` can drop the
// legacy declarations and tighten its optional fields.
//
// Every step is idempotent: re-running is a no-op. Order matters — the
// recovery steps must run before the purges, and the purges before the schema
// is tightened (Convex refuses to drop a table that still has rows).
//
// Table scans are `.take(1000)`, matching `migrations.ts`. The whole dataset is
// a few hundred rows; this is not built for a large deployment.

const LAUNCH_NIGHT = "EARPLUG LAUNCH NIGHT";
const E2E_USER_EMAIL = "e2e+clerk_test@example.com";
const TEST_BAND_NAME = "test band";

/** Populated legacy tables, superseded by contract tables. Emptied wholesale by
 * `purgeLegacyTables` once the recovery steps have taken what they need. */
const LEGACY_TABLES = [
  "rsvps",
  "eventTickets",
  "bandProfileEngagements",
  "bandMemberships",
  "bandInvites",
  "savedArtists",
  "bandMediaSlots",
  "eventCohostInvites",
  "events",
  "notifications",
  "spotifyProfiles",
] as const;

// ─── step 1: recover launch-night RSVPs ─────────────────────────────────────
// The 25 real RSVPs to EARPLUG LAUNCH NIGHT stayed in the legacy `rsvps` table
// when the event became a `gigs` row, so `interactions:history` shows nothing
// for the fans who were there. Carry them across before the table is dropped.
//
// Attendance is deliberately NOT synthesized: all 25 rows are
// `attendanceStatus: "on_list"`, none has `attendedAt`, and no ticket was ever
// scanned — nobody is recorded as having actually walked in. `attendedCount`
// stays 0 and `history` (derived from these rsvp rows) does the talking.

async function backfillLaunchNightRsvps(ctx: MutationCtx): Promise<number> {
  const gig = await ctx.db
    .query("gigs")
    .withIndex("by_title", (q) => q.eq("title", LAUNCH_NIGHT))
    .unique();
  if (gig === null) return 0;

  let inserted = 0;
  for (const rsvp of await ctx.db.query("rsvps").take(1000)) {
    const { userId, eventId } = rsvp;
    if (!userId || !eventId) continue;

    const event = await ctx.db.get(eventId);
    if (event === null || event.title !== LAUNCH_NIGHT) continue;
    if ((await ctx.db.get(userId)) === null) continue;

    const existing = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user_gig", (q) => q.eq("userId", userId).eq("gigId", gig._id))
      .unique();
    if (existing) continue;

    await ctx.db.insert("gigRsvps", { userId, gigId: gig._id });
    inserted++;
  }

  // `goingCount` is left alone: the migration already carried the legacy
  // rsvpCount of 25 onto the gig, so recomputing it here would double-count.
  return inserted;
}

// ─── step 2: merge duplicate accounts ───────────────────────────────────────
// Repeated sign-ins across Clerk identities left one person with several user
// rows on the same email. That also wedges `users:ensureUser`, which adopts by
// email only when exactly one non-empty match exists — so today a returning
// user with a new clerkId gets a fresh empty account instead of their bands.
// Collapsing each email to a single row repairs adoption for good.

async function mergeDuplicateUsers(ctx: MutationCtx): Promise<number> {
  const byEmail = new Map<string, Doc<"users">[]>();
  for (const user of await ctx.db.query("users").take(1000)) {
    if (user.email === "") continue; // empty emails are not an identity
    const group = byEmail.get(user.email) ?? [];
    group.push(user);
    byEmail.set(user.email, group);
  }

  let mergedAway = 0;
  for (const group of byEmail.values()) {
    if (group.length < 2) continue;
    // Oldest wins. Which row survives only decides the surviving _id and
    // clerkId — every attached row is moved across either way, so the choice
    // can't lose data, and the next sign-in repoints clerkId via ensureUser.
    group.sort((a, b) => a._creationTime - b._creationTime);
    const survivor = group[0];
    for (const duplicate of group.slice(1)) {
      await moveUserRows(ctx, duplicate._id, survivor._id);
      await ctx.db.delete(duplicate._id);
      mergedAway++;
    }
  }
  return mergedAway;
}

/** Repoint one user's memberships, follows, rsvps and saves onto another,
 * dropping rather than duplicating any pair the survivor already has. */
async function moveUserRows(
  ctx: MutationCtx,
  fromId: Id<"users">,
  toId: Id<"users">,
): Promise<void> {
  for (const membership of await ctx.db
    .query("bandMembers")
    .withIndex("by_user", (q) => q.eq("userId", fromId))
    .collect()) {
    const existing = await ctx.db
      .query("bandMembers")
      .withIndex("by_band_user", (q) =>
        q.eq("bandId", membership.bandId).eq("userId", toId),
      )
      .unique();
    if (existing === null) {
      await ctx.db.patch(membership._id, { userId: toId });
    } else {
      // Keep the more privileged of the two roles.
      if (membership.role === "admin" && existing.role !== "admin") {
        await ctx.db.patch(existing._id, { role: "admin" });
      }
      await ctx.db.delete(membership._id);
    }
  }

  for (const follow of await ctx.db
    .query("follows")
    .withIndex("by_user", (q) => q.eq("userId", fromId))
    .collect()) {
    const existing = await ctx.db
      .query("follows")
      .withIndex("by_user_band", (q) =>
        q.eq("userId", toId).eq("bandId", follow.bandId),
      )
      .unique();
    if (existing === null) {
      await ctx.db.patch(follow._id, { userId: toId });
    } else {
      await ctx.db.delete(follow._id);
    }
  }

  for (const rsvp of await ctx.db
    .query("gigRsvps")
    .withIndex("by_user", (q) => q.eq("userId", fromId))
    .collect()) {
    const existing = await ctx.db
      .query("gigRsvps")
      .withIndex("by_user_gig", (q) => q.eq("userId", toId).eq("gigId", rsvp.gigId))
      .unique();
    if (existing === null) {
      await ctx.db.patch(rsvp._id, { userId: toId });
    } else {
      await ctx.db.delete(rsvp._id);
    }
  }

  for (const save of await ctx.db
    .query("gigSaves")
    .withIndex("by_user", (q) => q.eq("userId", fromId))
    .collect()) {
    const existing = await ctx.db
      .query("gigSaves")
      .withIndex("by_user_gig", (q) => q.eq("userId", toId).eq("gigId", save.gigId))
      .unique();
    if (existing === null) {
      await ctx.db.patch(save._id, { userId: toId });
    } else {
      await ctx.db.delete(save._id);
    }
  }
}

// ─── cascading deletes ──────────────────────────────────────────────────────

/** `gigSaves` has no `by_gig` index (nothing in the contract needs one), so
 * finding a gig's saves means a scan. The table is tiny. */
async function deleteGigCascade(ctx: MutationCtx, gigId: Id<"gigs">): Promise<void> {
  for (const rsvp of await ctx.db
    .query("gigRsvps")
    .withIndex("by_gig", (q) => q.eq("gigId", gigId))
    .collect()) {
    await ctx.db.delete(rsvp._id);
  }
  for (const save of await ctx.db.query("gigSaves").take(1000)) {
    if (save.gigId === gigId) await ctx.db.delete(save._id);
  }
  await ctx.db.delete(gigId);
}

/** Refuses to delete a band still booked on a surviving gig — a dangling id in
 * `gigs.lineup` would break the feed for everyone. */
async function deleteBandCascade(ctx: MutationCtx, bandId: Id<"bands">): Promise<void> {
  for (const gig of await ctx.db.query("gigs").take(1000)) {
    if (gig.lineup.includes(bandId)) {
      throw new Error(
        `Refusing to delete band ${bandId}: still in the lineup of gig "${gig.title}"`,
      );
    }
  }
  for (const member of await ctx.db
    .query("bandMembers")
    .withIndex("by_band", (q) => q.eq("bandId", bandId))
    .collect()) {
    await ctx.db.delete(member._id);
  }
  for (const follow of await ctx.db
    .query("follows")
    .withIndex("by_band", (q) => q.eq("bandId", bandId))
    .collect()) {
    await ctx.db.delete(follow._id);
  }
  for (const video of await ctx.db
    .query("videos")
    .withIndex("by_band_order", (q) => q.eq("bandId", bandId))
    .collect()) {
    await ctx.db.delete(video._id);
  }
  await ctx.db.delete(bandId);
}

async function deleteUserCascade(ctx: MutationCtx, userId: Id<"users">): Promise<void> {
  for (const member of await ctx.db
    .query("bandMembers")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect()) {
    await ctx.db.delete(member._id);
  }
  for (const follow of await ctx.db
    .query("follows")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect()) {
    await ctx.db.delete(follow._id);
  }
  for (const rsvp of await ctx.db
    .query("gigRsvps")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect()) {
    await ctx.db.delete(rsvp._id);
  }
  for (const save of await ctx.db
    .query("gigSaves")
    .withIndex("by_user", (q) => q.eq("userId", userId))
    .collect()) {
    await ctx.db.delete(save._id);
  }
  await ctx.db.delete(userId);
}

// ─── step 3: purge seeded demo content ──────────────────────────────────────
// `seed:seedDemo` put six invented bands, six venues, seven gigs and five
// videos next to the real Berkeley data. Deleted by name so the step stays
// re-runnable, and in reference order — gigs, then bands, then venues.

async function purgeDemoData(
  ctx: MutationCtx,
): Promise<{ gigs: number; bands: number; venues: number }> {
  const demoBandIds = new Set(
    (await ctx.db.query("bands").take(1000))
      .filter((band) => DEMO_BAND_NAMES.includes(band.name))
      .map((band) => band._id),
  );

  let gigs = 0;
  for (const gig of await ctx.db.query("gigs").take(1000)) {
    if (!DEMO_GIG_TITLES.includes(gig.title)) continue;
    const realBandId = gig.lineup.find((bandId) => !demoBandIds.has(bandId));
    if (realBandId !== undefined) {
      throw new Error(
        `Refusing to delete demo gig "${gig.title}": a real band (${realBandId}) is on the lineup`,
      );
    }
    await deleteGigCascade(ctx, gig._id);
    gigs++;
  }

  let bands = 0;
  for (const bandId of demoBandIds) {
    await deleteBandCascade(ctx, bandId); // throws if still booked
    bands++;
  }

  let venues = 0;
  const survivingVenueIds = new Set(
    (await ctx.db.query("gigs").take(1000)).map((gig) => gig.venueId),
  );
  for (const venue of await ctx.db.query("venues").take(1000)) {
    if (!DEMO_VENUE_NAMES.includes(venue.name)) continue;
    if (survivingVenueIds.has(venue._id)) {
      throw new Error(
        `Refusing to delete demo venue "${venue.name}": a surviving gig is booked there`,
      );
    }
    await ctx.db.delete(venue._id);
    venues++;
  }

  return { gigs, bands, venues };
}

// ─── step 4: purge test rows ────────────────────────────────────────────────

async function purgeJunkRows(
  ctx: MutationCtx,
): Promise<{ bands: number; users: number }> {
  let bands = 0;
  const testBand = await ctx.db
    .query("bands")
    .withIndex("by_name", (q) => q.eq("name", TEST_BAND_NAME))
    .unique();
  if (testBand) {
    await deleteBandCascade(ctx, testBand._id);
    bands++;
  }

  // Clerk test sign-ins recreate this account on demand; nothing in the repo
  // depends on the row existing.
  let users = 0;
  for (const user of await ctx.db
    .query("users")
    .withIndex("by_email", (q) => q.eq("email", E2E_USER_EMAIL))
    .collect()) {
    await deleteUserCascade(ctx, user._id);
    users++;
  }

  return { bands, users };
}

// ─── step 5: empty the legacy tables ────────────────────────────────────────
// Storage blobs are not touched: the video slots live on in `videos.storageId`
// and the image slot in `bands.legacyImageSlotIds`, so nothing referenced is
// lost. Only `events.imageStorageId` orphans a single blob, which stays in
// storage and in the pre-cleanup snapshot.

async function purgeLegacyTables(ctx: MutationCtx): Promise<number> {
  let deleted = 0;
  for (const table of LEGACY_TABLES) {
    for (const row of await ctx.db.query(table).take(1000)) {
      await ctx.db.delete(row._id);
      deleted++;
    }
  }
  return deleted;
}

// ─── registered functions ───────────────────────────────────────────────────

export const backfillRsvps = internalMutation({
  args: {},
  returns: v.object({ rsvpsRecovered: v.number() }),
  handler: async (ctx) => ({ rsvpsRecovered: await backfillLaunchNightRsvps(ctx) }),
});

export const mergeUsers = internalMutation({
  args: {},
  returns: v.object({ duplicatesMerged: v.number() }),
  handler: async (ctx) => ({ duplicatesMerged: await mergeDuplicateUsers(ctx) }),
});

export const cleanupAll = internalMutation({
  args: {},
  returns: v.object({
    rsvpsRecovered: v.number(),
    duplicatesMerged: v.number(),
    demoGigsDeleted: v.number(),
    demoBandsDeleted: v.number(),
    demoVenuesDeleted: v.number(),
    junkBandsDeleted: v.number(),
    junkUsersDeleted: v.number(),
    legacyRowsDeleted: v.number(),
    users: v.number(),
    bands: v.number(),
    venues: v.number(),
    gigs: v.number(),
    gigRsvps: v.number(),
    follows: v.number(),
    bandMembers: v.number(),
    videos: v.number(),
  }),
  handler: async (ctx) => {
    const rsvpsRecovered = await backfillLaunchNightRsvps(ctx);
    const duplicatesMerged = await mergeDuplicateUsers(ctx);
    const demo = await purgeDemoData(ctx);
    const junk = await purgeJunkRows(ctx);
    const legacyRowsDeleted = await purgeLegacyTables(ctx);

    return {
      // Work counts: zero on a second run, which is how you tell it was a no-op.
      rsvpsRecovered,
      duplicatesMerged,
      demoGigsDeleted: demo.gigs,
      demoBandsDeleted: demo.bands,
      demoVenuesDeleted: demo.venues,
      junkBandsDeleted: junk.bands,
      junkUsersDeleted: junk.users,
      legacyRowsDeleted,
      // State counts: identical on every run.
      users: (await ctx.db.query("users").take(1000)).length,
      bands: (await ctx.db.query("bands").take(1000)).length,
      venues: (await ctx.db.query("venues").take(1000)).length,
      gigs: (await ctx.db.query("gigs").take(1000)).length,
      gigRsvps: (await ctx.db.query("gigRsvps").take(1000)).length,
      follows: (await ctx.db.query("follows").take(1000)).length,
      bandMembers: (await ctx.db.query("bandMembers").take(1000)).length,
      videos: (await ctx.db.query("videos").take(1000)).length,
    };
  },
});
