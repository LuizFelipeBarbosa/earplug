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

const legacyRawSocialLinksValidator = v.object({
  instagram: v.optional(v.string()),
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

export default defineSchema({
  // ─────────────────────────────────────────────────────────────────────────
  // Contract tables (WIDENED for in-place migration: every new field that
  // legacy rows lack is v.optional for now; legacy fields still on rows are
  // declared optional and removed by migrations:migrateAll. Tighten after the
  // migration is verified.)
  // ─────────────────────────────────────────────────────────────────────────

  users: defineTable({
    clerkId: v.string(),
    name: v.string(),
    email: v.string(),
    // New fields (backfilled by migration; required post-tighten).
    genres: v.optional(v.array(v.string())),
    attendedCount: v.optional(v.number()),
    // Kept storage references (user decision — optional, not dropped).
    avatarUrl: v.optional(v.string()),
    avatarStorageId: v.optional(v.id("_storage")),
    // Legacy fields removed by migrateAll.
    avatar: v.optional(v.string()),
    location: v.optional(v.string()),
    memberSince: v.optional(v.number()),
    phoneNumber: v.optional(v.string()),
    role: v.optional(v.string()),
    showsAttended: v.optional(v.number()),
    topGenres: v.optional(v.array(v.string())),
  })
    .index("by_clerk_id", ["clerkId"])
    .index("by_email", ["email"]),

  bands: defineTable({
    name: v.string(),
    genres: v.array(v.string()),
    bio: v.optional(v.string()),
    // New fields (backfilled by migration; required post-tighten).
    area: v.optional(v.string()),
    colorHex: v.optional(v.string()),
    initials: v.optional(v.string()),
    followerCount: v.optional(v.number()),
    linkIg: v.optional(v.string()),
    linkBc: v.optional(v.string()),
    // From createBand's links sheet (stored, not surfaced in v1).
    linkYt: v.optional(v.string()),
    // Server-issued unique profile handle; stable once shared, so renames
    // don't break links.
    slug: v.optional(v.string()),
    pastShows: v.optional(v.array(pastShowValidator)),
    // Kept storage / legacy-preservation fields (user decision).
    imageStorageId: v.optional(v.id("_storage")),
    legacySocialLinks: v.optional(legacySocialLinksValidator),
    // Invite handles from createBand (stored, unused in v1).
    inviteHandles: v.optional(v.array(v.string())),
    // Legacy fields removed by migrateAll.
    createdAt: v.optional(v.number()),
    genre: v.optional(v.string()),
    image: v.optional(v.string()),
    location: v.optional(v.string()),
    memberCount: v.optional(v.number()),
    socialLinks: v.optional(legacyRawSocialLinksValidator),
    userId: v.optional(v.id("users")),
  })
    .index("by_name", ["name"])
    .index("by_slug", ["slug"])
    .searchIndex("search_name", { searchField: "name" }),

  venues: defineTable({
    name: v.string(),
    // New fields (backfilled by migration; required post-tighten).
    area: v.optional(v.string()),
    addr: v.optional(v.string()),
    distSF: v.optional(v.string()),
    distOak: v.optional(v.string()),
    lat: v.optional(v.number()),
    lng: v.optional(v.number()),
    // Legacy fields removed by migrateAll.
    address: v.optional(v.string()),
    capacity: v.optional(v.number()),
    city: v.optional(v.string()),
    coordinates: v.optional(v.object({ lat: v.number(), lng: v.number() })),
    description: v.optional(v.string()),
    genres: v.optional(v.array(v.string())),
    images: v.optional(v.array(v.string())),
  }).index("by_name", ["name"]),

  gigs: defineTable({
    title: v.string(),
    venueId: v.id("venues"),
    price: v.number(),
    startsAt: v.number(),
    doorsTime: v.string(),
    flyKey: v.string(),
    lineup: v.array(v.id("bands")),
    genres: v.array(v.string()),
    desc: v.string(),
    ticketing: v.union(v.literal("rsvp"), v.literal("external")),
    externalUrl: v.optional(v.string()),
    cap: v.string(),
    goingCount: v.number(),
    createdByBand: v.optional(v.id("bands")),
    // Band-supplied flyer art, set when flyKey is "custom". The gig owns this
    // blob outright — it is never a bandMedia row, because `lineup` is an array
    // so "whose media is it" would be ambiguous.
    flyStorageId: v.optional(v.id("_storage")),
  })
    .index("by_startsAt", ["startsAt"])
    .index("by_title", ["title"]),

  bandMembers: defineTable({
    bandId: v.id("bands"),
    userId: v.id("users"),
    role: v.union(v.literal("admin"), v.literal("member")),
  })
    .index("by_band_user", ["bandId", "userId"])
    .index("by_band", ["bandId"])
    .index("by_user", ["userId"]),

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
  })
    .index("by_user_gig", ["userId", "gigId"])
    .index("by_user", ["userId"])
    .index("by_gig", ["gigId"]),

  gigSaves: defineTable({
    userId: v.id("users"),
    gigId: v.id("gigs"),
  })
    .index("by_user_gig", ["userId", "gigId"])
    .index("by_user", ["userId"]),

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

  // ─────────────────────────────────────────────────────────────────────────
  // LEGACY TABLES — pending post-verification cleanup. Declared minimally
  // (every field optional, shapes from the legacy declared schema) so the
  // schema push validates their surviving rows. No new function reads them
  // except migrations:migrateAll. Do not build on these.
  // ─────────────────────────────────────────────────────────────────────────

  bandMemberships: defineTable({
    bandId: v.optional(v.id("bands")),
    invitedBy: v.optional(v.id("users")),
    joinedAt: v.optional(v.number()),
    role: v.optional(v.string()),
    userId: v.optional(v.id("users")),
  }),

  savedArtists: defineTable({
    bandId: v.optional(v.id("bands")),
    createdAt: v.optional(v.number()),
    userId: v.optional(v.id("users")),
  }),

  events: defineTable({
    addressVisibility: v.optional(v.string()),
    bandId: v.optional(v.id("bands")),
    capacity: v.optional(v.number()),
    dateTime: v.optional(v.number()),
    description: v.optional(v.string()),
    genre: v.optional(v.string()),
    genres: v.optional(v.array(v.string())),
    image: v.optional(v.string()),
    imageStorageId: v.optional(v.id("_storage")),
    poll: v.optional(v.any()),
    price: v.optional(v.number()),
    rsvpCount: v.optional(v.number()),
    status: v.optional(v.string()),
    title: v.optional(v.string()),
    venueId: v.optional(v.id("venues")),
  }),

  rsvps: defineTable({
    attendanceStatus: v.optional(v.string()),
    attendedAt: v.optional(v.number()),
    createdAt: v.optional(v.number()),
    eventId: v.optional(v.id("events")),
    pollAnsweredAt: v.optional(v.number()),
    pollAnswers: v.optional(v.any()),
    userId: v.optional(v.id("users")),
  }),

  eventTickets: defineTable({
    eventId: v.optional(v.id("events")),
    issuedAt: v.optional(v.number()),
    revokedAt: v.optional(v.number()),
    revokedReason: v.optional(v.string()),
    rsvpId: v.optional(v.id("rsvps")),
    status: v.optional(v.string()),
    token: v.optional(v.string()),
    usedAt: v.optional(v.number()),
    usedByUserId: v.optional(v.id("users")),
    userId: v.optional(v.id("users")),
  }),

  bandInvites: defineTable({
    bandId: v.optional(v.id("bands")),
    createdAt: v.optional(v.number()),
    email: v.optional(v.string()),
    expiresAt: v.optional(v.number()),
    invitedBy: v.optional(v.id("users")),
    phoneNumber: v.optional(v.string()),
    respondedAt: v.optional(v.number()),
    role: v.optional(v.string()),
    status: v.optional(v.string()),
    targetUserId: v.optional(v.id("users")),
  }),

  bandProfileEngagements: defineTable({
    bandId: v.optional(v.id("bands")),
    firstViewedAt: v.optional(v.number()),
    lastViewedAt: v.optional(v.number()),
    userId: v.optional(v.id("users")),
    viewCount: v.optional(v.number()),
  }),

  eventCohostInvites: defineTable({
    createdAt: v.optional(v.number()),
    eventId: v.optional(v.id("events")),
    expiresAt: v.optional(v.number()),
    hostBandId: v.optional(v.id("bands")),
    invitedBandId: v.optional(v.id("bands")),
    invitedByBandId: v.optional(v.id("bands")),
    invitedByUserId: v.optional(v.id("users")),
    respondedAt: v.optional(v.number()),
    status: v.optional(v.string()),
  }),

  bandMediaSlots: defineTable({
    bandId: v.optional(v.id("bands")),
    caption: v.optional(v.string()),
    createdAt: v.optional(v.number()),
    durationSeconds: v.optional(v.number()),
    fileSizeBytes: v.optional(v.number()),
    location: v.optional(v.string()),
    mediaStorageId: v.optional(v.id("_storage")),
    mediaType: v.optional(v.string()),
    mimeType: v.optional(v.string()),
    slotIndex: v.optional(v.number()),
    updatedAt: v.optional(v.number()),
  }),

  notifications: defineTable({
    bandId: v.optional(v.id("bands")),
    content: v.optional(v.string()),
    eventId: v.optional(v.id("events")),
    friendUserId: v.optional(v.string()),
    friendshipId: v.optional(v.string()),
    read: v.optional(v.boolean()),
    timestamp: v.optional(v.number()),
    title: v.optional(v.string()),
    type: v.optional(v.string()),
    userId: v.optional(v.id("users")),
    venueId: v.optional(v.id("venues")),
  }),

  spotifyProfiles: defineTable({
    lastSyncedAt: v.optional(v.number()),
    matchedBandIds: v.optional(v.array(v.id("bands"))),
    topArtists: v.optional(v.any()),
    topGenres: v.optional(v.array(v.string())),
    userId: v.optional(v.id("users")),
  }),

  likes: defineTable({
    createdAt: v.optional(v.number()),
    eventId: v.optional(v.id("events")),
    userId: v.optional(v.id("users")),
  }),
});
