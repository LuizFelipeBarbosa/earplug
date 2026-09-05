import {
  Migrations,
  type MigrationFunctionReference,
} from "@convex-dev/migrations";
import { v } from "convex/values";
import { components, internal } from "./_generated/api";
import { DataModel, Doc } from "./_generated/dataModel";
import { MutationCtx, internalQuery } from "./_generated/server";
import { createProjectForGig } from "./gigs";
import {
  discoveryListingFlags,
  isDiscoveryListingReady,
} from "./lib/discovery";
import { approximateLocation } from "./lib/geo";
import {
  MAX_MEDIA_PER_BAND,
  assertUploadAcceptable,
  effectiveAddressDisclosure,
  isReservedPublicSlug,
  slugify,
} from "./lib/helpers";
import { normalizeVenueText } from "./venues";

export const migrations = new Migrations<DataModel>(components.migrations);

// Duplicated from bands' uniqueSlug pattern; convex/lib/venueSlug.ts (a sibling lane, in progress) will likely absorb this — de-duplicate then.
async function uniqueLegacyVenueSlug(ctx: MutationCtx, name: string) {
  const base = slugify(name);
  for (let suffix = 1; ; suffix++) {
    const candidate = suffix === 1 ? base : `${base}-${suffix}`;
    if (isReservedPublicSlug(candidate)) continue;
    const existing = await ctx.db
      .query("venues")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (!existing) return candidate;
  }
}

type VenueLocationPrivacyPatch = Partial<
  Omit<Doc<"venues">, "_id" | "_creationTime">
>;

export async function migrateVenueLocationPrivacy(
  ctx: MutationCtx,
  venue: Doc<"venues">,
): Promise<VenueLocationPrivacyPatch | undefined> {
  const privateDetail = await ctx.db
    .query("venuePrivateDetails")
    .withIndex("by_venueId", (q) => q.eq("venueId", venue._id))
    .first();
  if (!privateDetail && venue.addr.trim() !== "") {
    await ctx.db.insert("venuePrivateDetails", {
      venueId: venue._id,
      addr: venue.addr,
      lat: venue.lat,
      lng: venue.lng,
      normalizedAddr: normalizeVenueText(venue.addr),
      updatedAt: Date.now(),
    });
  }

  const patch: VenueLocationPrivacyPatch = {};
  if (venue.status === undefined) patch.status = "legacy";
  if (venue.slug === undefined) {
    patch.slug = await uniqueLegacyVenueSlug(ctx, venue.name);
  }
  if (venue.approxLat === undefined) {
    const approximate = approximateLocation(
      { lat: venue.lat, lng: venue.lng },
      venue.area,
    );
    patch.approxLabel = approximate.label;
    patch.approxLat = approximate.lat;
    patch.approxLng = approximate.lng;
    patch.neighborhood = approximate.neighborhood ?? undefined;
    patch.city = approximate.city ?? undefined;
  }
  if (venue.normalizedName === undefined) {
    patch.normalizedName = normalizeVenueText(venue.name);
  }
  if (
    venue.normalizedAddr === undefined &&
    effectiveAddressDisclosure({ ...venue, ...patch }) === "public"
  ) {
    patch.normalizedAddr = normalizeVenueText(venue.addr);
  }

  if (Object.keys(patch).length > 0) return patch;
}

export const backfillVenueLocationPrivacy = migrations.define({
  table: "venues",
  batchSize: 50,
  migrateOne: migrateVenueLocationPrivacy,
});

/** Widen-phase backfill. Safe to restart: the project lookup is unique by the
 * public gig id, and already-populated public compatibility fields are left
 * intact. Legacy timing is intentionally preserved when the old display string
 * cannot prove a distinct show time. */
export const backfillGigProjects = migrations.define({
  table: "gigs",
  batchSize: 25,
  migrateOne: async (ctx, gig) => {
    if (gig.ownerKind === "organization") return;
    const ownerBandId = gig.createdByBand ?? gig.lineup[0];
    if (ownerBandId) await createProjectForGig(ctx, gig, ownerBandId);

    const performers = [];
    for (let index = 0; index < gig.lineup.length; index++) {
      const band = await ctx.db.get(gig.lineup[index]);
      if (band) {
        performers.push({
          name: band.name,
          role: index === 0 ? ("headliner" as const) : ("support" as const),
          bandId: band._id,
        });
      }
    }
    await ctx.db.patch(gig._id, {
      lifecycle: gig.lifecycle ?? "published",
      doorsAt: gig.doorsAt ?? gig.startsAt,
      performers: gig.performers ?? performers,
    });
  },
});

/** Denormalizes valid clip existence after all live media writes already
 * maintain the field. Legacy rows with missing or unacceptable blobs fail
 * closed. */
export const backfillBandHasClip = migrations.define({
  table: "bands",
  batchSize: 50,
  migrateOne: async (ctx, band) => {
    const videos = await ctx.db
      .query("bandMedia")
      .withIndex("by_band_kind_order", (q) =>
        q.eq("bandId", band._id).eq("kind", "video"),
      )
      .take(MAX_MEDIA_PER_BAND);
    let hasClip = false;
    for (const video of videos) {
      const upload = await ctx.db.system.get("_storage", video.storageId);
      if (!upload) continue;
      try {
        assertUploadAcceptable(
          { size: upload.size, contentType: upload.contentType },
          "video",
        );
        hasClip = true;
        break;
      } catch {
        // Keep checking: a later legacy video may still be valid.
      }
    }
    if (band.hasClip !== hasClip) return { hasClip };
  },
});

/** Organization gigs are populated directly by opportunity publishing. Band
 * gigs rebuild readiness from their private project, failing closed when the
 * project or creator is missing or legacy state is ambiguous. */
export const backfillGigDiscoveryListingReady = migrations.define({
  table: "gigs",
  batchSize: 25,
  migrateOne: async (ctx, gig) => {
    if (gig.ownerKind === "organization") {
      if (gig.discoveryListingReady !== true) {
        return { discoveryListingReady: true };
      }
      return;
    }
    const project = await ctx.db
      .query("gigProjects")
      .withIndex("by_public_gig", (q) => q.eq("publicGigId", gig._id))
      .first();
    let discoveryListingReady = false;
    if (project) {
      const performers = await ctx.db
        .query("gigProjectPerformers")
        .withIndex("by_project_and_order", (q) =>
          q.eq("projectId", project._id),
        )
        .take(21);
      const flags = await discoveryListingFlags(ctx, project, gig, performers);
      discoveryListingReady = isDiscoveryListingReady(flags);
    }
    if (gig.discoveryListingReady !== discoveryListingReady) {
      return { discoveryListingReady };
    }
  },
});

/** Operational order for the widen-phase rollout. Completed component jobs
 * are skipped, and retries resume from their stored cursor. */
export const runDiscoveryReadinessBackfills = migrations.runner([
  internal.migrations.backfillGigProjects,
  internal.migrations.backfillBandHasClip,
  internal.migrations.backfillGigDiscoveryListingReady,
]);

// Venue privacy is independent, so establish its compatibility data before
// the unrelated discovery-readiness series continues.
export const RELEASE_BACKFILLS: readonly MigrationFunctionReference[] = [
  internal.migrations.backfillVenueLocationPrivacy,
  internal.migrations.backfillGigProjects,
  internal.migrations.backfillBandHasClip,
  internal.migrations.backfillGigDiscoveryListingReady,
] as const;

export const runReleaseBackfills = migrations.runner([...RELEASE_BACKFILLS]);

export const releaseBackfillStatus = internalQuery({
  args: {},
  returns: v.any(),
  handler: async (ctx) =>
    migrations.getStatus(ctx, { migrations: [...RELEASE_BACKFILLS] }),
});

export const run = migrations.runner();
