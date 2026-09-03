import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

// The non-Instagram links carried over from the legacy `socialLinks` bag
// (instagram was promoted to `linkIg` as an @handle). Preserved because v1 has
// nowhere to show them yet, not because anything reads them.
const legacySocialLinksValidator = v.object({
  spotify: v.optional(v.string()),
  appleMusic: v.optional(v.string()),
  tiktok: v.optional(v.string()),
  youtube: v.optional(v.string()),
  website: v.optional(v.string()),
});

export const pastShowValidator = v.object({
  title: v.string(),
  meta: v.string(),
});

export const ageRequirementValidator = v.union(
  v.literal("allAges"),
  v.literal("18Plus"),
  v.literal("21Plus"),
);

export const gigLifecycleValidator = v.union(
  v.literal("published"),
  v.literal("cancelled"),
  v.literal("unpublished"),
  v.literal("deleted"),
);

export const gigProjectStatusValidator = v.union(
  v.literal("draft"),
  v.literal("published"),
  v.literal("cancelled"),
  v.literal("deleted"),
);

export const gigPerformerRoleValidator = v.union(
  v.literal("headliner"),
  v.literal("support"),
  v.literal("opener"),
);

export const gigPublicPerformerValidator = v.object({
  name: v.string(),
  role: gigPerformerRoleValidator,
  bandId: v.optional(v.id("bands")),
});

export const organizationRoleValidator = v.union(
  v.literal("owner"),
  v.literal("manager"),
  v.literal("finance"),
  v.literal("door"),
);

export const organizationTypeValidator = v.union(
  v.literal("venueOperator"),
  v.literal("promoter"),
  v.literal("studentOrg"),
  v.literal("other"),
);

export const organizationStatusValidator = v.union(
  v.literal("pending"),
  v.literal("verified"),
  v.literal("suspended"),
);

export const organizationApplicationStatusValidator = v.union(
  v.literal("submitted"),
  v.literal("under_review"),
  v.literal("needs_info"),
  v.literal("approved"),
  v.literal("rejected"),
  v.literal("withdrawn"),
);

export const venueStatusValidator = v.union(
  v.literal("legacy"),
  v.literal("pending"),
  v.literal("verified"),
  v.literal("suspended"),
);

export const addressDisclosureValidator = v.union(
  v.literal("onTicket"),
  v.literal("public"),
);

export const venueTypeValidator = v.union(
  v.literal("bar"),
  v.literal("club"),
  v.literal("hall"),
  v.literal("house"),
  v.literal("outdoor"),
  v.literal("other"),
);

export const fanCityValidator = v.union(
  v.literal("sf"),
  v.literal("oak"),
  v.literal("berkeley"),
  v.literal("alameda"),
  v.literal("emeryville"),
  v.literal("richmond"),
  v.literal("dalyCity"),
  v.literal("sanMateo"),
  v.literal("paloAlto"),
  v.literal("sanJose"),
  v.literal("hayward"),
  v.literal("fremont"),
  v.literal("walnutCreek"),
  v.literal("sanRafael"),
);

export const fanGenreChoiceValidator = v.union(
  v.literal("pending"),
  v.literal("selected"),
  v.literal("open"),
);

export const fanOnboardingValidator = v.object({
  preferredCity: v.optional(fanCityValidator),
  genreChoice: fanGenreChoiceValidator,
  collapsed: v.boolean(),
});

export default defineSchema({
  users: defineTable({
    clerkId: v.string(),
    name: v.string(),
    email: v.string(),
    genres: v.array(v.string()),
    attendedCount: v.number(),
    // Present only for accounts first inserted after fan onboarding launched.
    // Legacy rows adopted by Clerk deliberately remain unenrolled.
    fanOnboarding: v.optional(fanOnboardingValidator),
    // Fan avatar storage. Legacy URL rows remain readable until rewritten.
    avatarUrl: v.optional(v.string()),
    avatarStorageId: v.optional(v.id("_storage")),
    bio: v.optional(v.string()),
    homeLocation: v.optional(fanCityValidator),
    locationPersonalizationEnabled: v.optional(v.boolean()),
    followedBandUpdatesEnabled: v.optional(v.boolean()),
    profileTutorialCompleted: v.optional(v.boolean()),
    // Clerk user.deleted tombstone; milliseconds since epoch.
    deletedAt: v.optional(v.number()),
    // Clerk's updated_at (ms epoch) from the last applied webhook guards
    // authoritative email overwrites against out-of-order Svix delivery.
    clerkUpdatedAt: v.optional(v.number()),
  })
    .index("by_clerk_id", ["clerkId"])
    .index("by_email", ["email"]),

  platformAdmins: defineTable({
    userId: v.id("users"),
    grantedBy: v.optional(v.id("users")),
    grantedAt: v.number(),
    revokedAt: v.optional(v.number()),
    note: v.optional(v.string()),
  }).index("by_userId", ["userId"]),

  organizations: defineTable({
    name: v.string(),
    slug: v.string(),
    orgType: organizationTypeValidator,
    status: organizationStatusValidator,
    ownerUserId: v.id("users"),
    applicationId: v.optional(v.id("organizationApplications")),
    description: v.optional(v.string()),
    website: v.optional(v.string()),
    photoStorageIds: v.optional(v.array(v.id("_storage"))),
    bookingCommissionBps: v.optional(v.number()),
    verifiedAt: v.optional(v.number()),
    suspendedAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_slug", ["slug"])
    .index("by_status_and_name", ["status", "name"]),

  organizationPrivateDetails: defineTable({
    organizationId: v.id("organizations"),
    legalName: v.optional(v.string()),
    businessEmail: v.string(),
    contactName: v.string(),
    phone: v.optional(v.string()),
    stripeAccountId: v.optional(v.string()),
    stripeChargesEnabled: v.boolean(),
    stripePayoutsEnabled: v.boolean(),
    stripeDetailsSubmitted: v.boolean(),
    stripeRequirementsDue: v.optional(v.array(v.string())),
    verificationDocStorageIds: v.array(v.id("_storage")),
    updatedAt: v.number(),
  })
    .index("by_organizationId", ["organizationId"])
    .index("by_stripeAccountId", ["stripeAccountId"]),

  organizationMembers: defineTable({
    organizationId: v.id("organizations"),
    userId: v.id("users"),
    role: organizationRoleValidator,
    addedBy: v.optional(v.id("users")),
    createdAt: v.number(),
  })
    .index("by_organizationId_and_userId", ["organizationId", "userId"])
    .index("by_userId", ["userId"])
    .index("by_organizationId", ["organizationId"]),

  organizationMemberInvites: defineTable({
    organizationId: v.id("organizations"),
    token: v.string(),
    role: organizationRoleValidator,
    createdBy: v.id("users"),
    expiresAt: v.number(),
    revoked: v.boolean(),
    expired: v.optional(v.boolean()),
  })
    .index("by_token", ["token"])
    .index("by_organizationId", ["organizationId"]),

  organizationApplications: defineTable({
    applicantUserId: v.id("users"),
    orgName: v.string(),
    orgType: organizationTypeValidator,
    website: v.optional(v.string()),
    contactName: v.string(),
    businessEmail: v.string(),
    phone: v.optional(v.string()),
    venue: v.optional(
      v.object({
        name: v.string(),
        addr: v.string(),
        lat: v.number(),
        lng: v.number(),
        area: v.string(),
        neighborhood: v.optional(v.string()),
        city: v.optional(v.string()),
        capacity: v.optional(v.number()),
        venueType: v.optional(venueTypeValidator),
      }),
    ),
    verificationDocStorageIds: v.array(v.id("_storage")),
    status: organizationApplicationStatusValidator,
    reviewerUserId: v.optional(v.id("users")),
    reviewNote: v.optional(v.string()),
    decidedAt: v.optional(v.number()),
    resultingOrganizationId: v.optional(v.id("organizations")),
    resultingVenueId: v.optional(v.id("venues")),
    revision: v.number(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_applicantUserId_and_status", ["applicantUserId", "status"])
    .index("by_status_and_createdAt", ["status", "createdAt"]),

  bands: defineTable({
    name: v.string(),
    genres: v.array(v.string()),
    bio: v.optional(v.string()),
    area: v.string(),
    colorHex: v.string(),
    initials: v.string(),
    followerCount: v.number(),
    pastShows: v.array(pastShowValidator),
    // Server-issued unique profile handle; stable once shared, so renames
    // don't break links.
    slug: v.string(),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    // From createBand's links sheet; now exposed on public profiles.
    linkYt: v.optional(v.string()),
    credits: v.optional(v.string()),
    // First managed public-profile preview. Its presence completes the setup
    // task; later previews deliberately do not churn this otherwise stable row.
    publicProfilePreviewedAt: v.optional(v.number()),
    // Widen-phase discovery projection. Every live media write maintains this
    // transactionally; an absent legacy value is deliberately read as false
    // until migrations:backfillBandHasClip has visited the row.
    hasClip: v.optional(v.boolean()),
    // Independent public-profile artwork. `null` is intentional: it records an
    // explicit removal, while `undefined` lets legacy rows fall back to the
    // original shared image below.
    avatarStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    bannerStorageId: v.optional(v.union(v.id("_storage"), v.null())),
    // Legacy shared avatar/banner image. Older clients still write this field;
    // current reads use it only when the corresponding new role is undefined.
    imageStorageId: v.optional(v.id("_storage")),
    legacySocialLinks: v.optional(legacySocialLinksValidator),
    // Legacy fake invite handles remain readable but no live path writes them.
    inviteHandles: v.optional(v.array(v.string())),
    // User-facing deletion is a reversible archive. Historical gig and
    // membership references intentionally continue to point at this row.
    archivedAt: v.optional(v.number()),
    archivedBy: v.optional(v.id("users")),
  })
    .index("by_name", ["name"])
    .index("by_slug", ["slug"])
    .searchIndex("search_name", { searchField: "name" }),

  // Exact address and coordinates are moving to `venuePrivateDetails`.
  // `addr`, `lat`, and `lng` remain required during this widen phase and will
  // be deprecated once every venue has a private-detail row.
  venues: defineTable({
    name: v.string(),
    area: v.string(),
    addr: v.string(),
    // Optional during the venue-creation rollout. Live writes maintain both
    // keys and migrations backfill the curated legacy directory.
    normalizedName: v.optional(v.string()),
    normalizedAddr: v.optional(v.string()),
    createdBy: v.optional(v.id("users")),
    createdByBand: v.optional(v.id("bands")),
    distSF: v.string(),
    distOak: v.string(),
    lat: v.number(),
    lng: v.number(),
    slug: v.optional(v.string()),
    status: v.optional(venueStatusValidator),
    managedByOrganizationId: v.optional(v.id("organizations")),
    venueType: v.optional(venueTypeValidator),
    addressDisclosure: v.optional(addressDisclosureValidator),
    approxLabel: v.optional(v.string()),
    approxLat: v.optional(v.number()),
    approxLng: v.optional(v.number()),
    neighborhood: v.optional(v.string()),
    city: v.optional(v.string()),
    capacityPublic: v.optional(v.number()),
    photoStorageIds: v.optional(v.array(v.id("_storage"))),
    description: v.optional(v.string()),
  })
    .index("by_name", ["name"])
    .index("by_normalizedName", ["normalizedName"])
    .index("by_normalizedAddr", ["normalizedAddr"])
    .index("by_status_and_name", ["status", "name"])
    .index("by_slug", ["slug"])
    .index("by_managedByOrganizationId", ["managedByOrganizationId"]),

  venuePrivateDetails: defineTable({
    venueId: v.id("venues"),
    addr: v.string(),
    lat: v.number(),
    lng: v.number(),
    normalizedAddr: v.string(),
    loadInNotes: v.optional(v.string()),
    capacity: v.optional(v.number()),
    verificationDocStorageIds: v.optional(v.array(v.id("_storage"))),
    updatedAt: v.number(),
  })
    .index("by_venueId", ["venueId"])
    .index("by_normalizedAddr", ["normalizedAddr"]),

  stripeEvents: defineTable({
    eventId: v.string(),
    type: v.string(),
    account: v.optional(v.string()),
    livemode: v.boolean(),
    receivedAt: v.number(),
    appliedAt: v.optional(v.number()),
    status: v.union(
      v.literal("applied"),
      v.literal("ignored"),
      v.literal("failed"),
    ),
    error: v.optional(v.string()),
  }).index("by_eventId", ["eventId"]),

  gigs: defineTable({
    title: v.string(),
    // Optional during widen/backfill. Public payloads fall back to the id
    // until every legacy listing has a stable canonical slug.
    slug: v.optional(v.string()),
    venueId: v.id("venues"),
    price: v.number(),
    startsAt: v.number(),
    doorsTime: v.string(),
    flyKey: v.string(),
    lineup: v.array(v.id("bands")),
    genres: v.array(v.string()),
    desc: v.string(),
    ticketing: v.union(v.literal("rsvp"), v.literal("external")),
    // Optional only while legacy rows remain in deployed data. Every supported
    // write path supplies this explicitly; readers normalize absence to
    // "allAges" until the compatibility rollout can be tightened.
    ageRequirement: v.optional(ageRequirementValidator),
    externalUrl: v.optional(v.string()),
    cap: v.string(),
    goingCount: v.number(),
    createdByBand: v.optional(v.id("bands")),
    // Band-supplied flyer art, set when flyKey is "custom". The gig owns this
    // blob outright — it is never a bandMedia row, because `lineup` is an array
    // so "whose media is it" would be ambiguous.
    flyStorageId: v.optional(v.id("_storage")),
    // Optional during the widen/backfill phase. Readers treat absence as the
    // legacy published state until migrations:backfillGigProjects completes.
    lifecycle: v.optional(gigLifecycleValidator),
    doorsAt: v.optional(v.number()),
    performers: v.optional(v.array(gigPublicPerformerValidator)),
    // Widen-phase publish projection. Saved project/lineup edits clear it and
    // publishing recalculates it. Missing legacy values are never eligible for
    // a discovery boost.
    discoveryListingReady: v.optional(v.boolean()),
  })
    .index("by_startsAt", ["startsAt"])
    .index("by_lifecycle_and_startsAt", ["lifecycle", "startsAt"])
    .index("by_venueId_and_startsAt", ["venueId", "startsAt"])
    .index("by_slug", ["slug"])
    .index("by_title", ["title"]),

  // Private editorial source for both incomplete drafts and published gigs.
  // Public readers never consume this table directly; publish copies a
  // validated snapshot into `gigs` in the same transaction.
  gigProjects: defineTable({
    bandId: v.id("bands"),
    publicGigId: v.optional(v.id("gigs")),
    publicSlug: v.optional(v.string()),
    status: gigProjectStatusValidator,
    revision: v.number(),
    publishedRevision: v.optional(v.number()),
    title: v.optional(v.string()),
    doorsAt: v.optional(v.number()),
    startsAt: v.optional(v.number()),
    venueId: v.optional(v.id("venues")),
    price: v.number(),
    flyKey: v.string(),
    flyStorageId: v.optional(v.id("_storage")),
    overlay: v.boolean(),
    desc: v.string(),
    ticketing: v.union(v.literal("rsvp"), v.literal("external")),
    ageRequirement: ageRequirementValidator,
    externalUrl: v.optional(v.string()),
    cap: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_band_and_status", ["bandId", "status"])
    .index("by_bandId_and_status_and_startsAt", [
      "bandId",
      "status",
      "startsAt",
    ])
    .index("by_public_gig", ["publicGigId"]),

  // A gig has a deliberately bounded lineup (20 performers), but performer
  // rows still live separately so invitations and reordering do not rewrite
  // the entire project record on every edit.
  gigProjectPerformers: defineTable({
    projectId: v.id("gigProjects"),
    order: v.number(),
    kind: v.union(v.literal("band"), v.literal("invited"), v.literal("text")),
    name: v.string(),
    role: gigPerformerRoleValidator,
    bandId: v.optional(v.id("bands")),
    inviteToken: v.optional(v.string()),
    inviteExpiresAt: v.optional(v.number()),
    inviteRevoked: v.optional(v.boolean()),
    claimedAt: v.optional(v.number()),
  })
    .index("by_project_and_order", ["projectId", "order"])
    .index("by_invite_token", ["inviteToken"]),

  /** One row per (gig, band in its lineup). `gigs.lineup` is an array and
   * Convex cannot index array containment, so without this join table the only
   * way to find a band's own gigs is to scan the global `by_startsAt` range and
   * filter in memory — which silently truncates a band's history once other
   * bands' gigs crowd it out of the scan window. `startsAt` is denormalized so
   * the range and the ordering both come from the index.
   *
   * Every write path into `gigs` must also write here; `indexGigForBands` in
   * `lib/helpers.ts` is the single place that does it. */
  gigBands: defineTable({
    gigId: v.id("gigs"),
    bandId: v.id("bands"),
    startsAt: v.number(),
  })
    .index("by_band_startsAt", ["bandId", "startsAt"])
    .index("by_gig", ["gigId"]),

  bandMembers: defineTable({
    bandId: v.id("bands"),
    userId: v.id("users"),
    role: v.union(v.literal("admin"), v.literal("member")),
  })
    .index("by_band_user", ["bandId", "userId"])
    .index("by_band", ["bandId"])
    .index("by_user", ["userId"]),

  // One reusable, seven-day link is managed per band. Rotation replaces its
  // token in place so already-shared links stop resolving without growing
  // unbounded invitation history.
  bandInvites: defineTable({
    bandId: v.id("bands"),
    token: v.string(),
    createdBy: v.id("users"),
    expiresAt: v.number(),
    revoked: v.boolean(),
    // Optional while rows created before server-authoritative expiry remain.
    expired: v.optional(v.boolean()),
  })
    .index("by_token", ["token"])
    .index("by_band", ["bandId"]),

  follows: defineTable({
    userId: v.id("users"),
    bandId: v.id("bands"),
  })
    .index("by_user_band", ["userId", "bandId"])
    .index("by_user", ["userId"])
    .index("by_band", ["bandId"]),

  gigRsvps: defineTable({
    userId: v.id("users"),
    gigId: v.id("gigs"),
    // Existing rows receive a token lazily when the fan first opens a ticket.
    ticketToken: v.optional(v.string()),
    checkedInAt: v.optional(v.number()),
    checkedInBy: v.optional(v.id("users")),
  })
    .index("by_user_gig", ["userId", "gigId"])
    .index("by_user", ["userId"])
    .index("by_gig", ["gigId"])
    .index("by_ticketToken", ["ticketToken"]),

  gigSaves: defineTable({
    userId: v.id("users"),
    gigId: v.id("gigs"),
  })
    .index("by_user_gig", ["userId", "gigId"])
    .index("by_user", ["userId"])
    .index("by_gig", ["gigId"]),

  // One ordered list per band holding both clips and photos, so ordering and
  // the pin are a single concept rather than two.
  //
  // `storageId` is required — a media row with no bytes behind it is exactly
  // the broken state this table exists to fix. `contentType`/`sizeBytes` are
  // optional because convex-test records `_storage` docs as `{size, sha256}`
  // only.
  //
  // No `url` column: Convex storage URLs embed the deployment hostname and go
  // stale when a blob is deleted, so they are resolved per read via
  // `ctx.storage.getUrl`, which returns null for a missing file.
  bandMedia: defineTable({
    bandId: v.id("bands"),
    kind: v.union(v.literal("video"), v.literal("photo")),
    storageId: v.id("_storage"),
    // Generated poster for video rows. Optional during the additive rollout
    // and for legacy clips, which the client can preview from their first
    // decoded frame until they are replaced.
    thumbnailStorageId: v.optional(v.id("_storage")),
    contentType: v.optional(v.string()),
    sizeBytes: v.optional(v.number()),
    title: v.string(),
    // Separate from `title`: a clip's title is a name, a photo wants a credit
    // ("shot by Mara, Aug '25"). Overloading one field makes a later split a
    // migration.
    caption: v.optional(v.string()),
    order: v.number(),
    pinned: v.boolean(),
    // Video-only. Carried over for display; nothing increments `views`.
    views: v.optional(v.number()),
    lengthSec: v.optional(v.number()),
    uploadedBy: v.optional(v.id("users")),
  })
    .index("by_band_order", ["bandId", "order"])
    .index("by_band_kind_order", ["bandId", "kind", "order"]),
});
