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

export default defineSchema({
  users: defineTable({
    clerkId: v.string(),
    name: v.string(),
    email: v.string(),
    genres: v.array(v.string()),
    attendedCount: v.number(),
    // Storage references with no home in the v1 UI, kept rather than swept.
    avatarUrl: v.optional(v.string()),
    avatarStorageId: v.optional(v.id("_storage")),
  })
    .index("by_clerk_id", ["clerkId"])
    .index("by_email", ["email"]),

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
    // From createBand's links sheet (stored, not surfaced in v1).
    linkYt: v.optional(v.string()),
    // Storage / link content with no home in the v1 UI, kept rather than swept.
    imageStorageId: v.optional(v.id("_storage")),
    legacySocialLinks: v.optional(legacySocialLinksValidator),
    legacyImageSlotIds: v.optional(v.array(v.id("_storage"))),
    // Invite handles from createBand (stored, unused in v1).
    inviteHandles: v.optional(v.array(v.string())),
  })
    .index("by_name", ["name"])
    .index("by_slug", ["slug"])
    .searchIndex("search_name", { searchField: "name" }),

  venues: defineTable({
    name: v.string(),
    area: v.string(),
    addr: v.string(),
    distSF: v.string(),
    distOak: v.string(),
    lat: v.number(),
    lng: v.number(),
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

  videos: defineTable({
    bandId: v.id("bands"),
    title: v.string(),
    views: v.number(),
    lengthSec: v.number(),
    pinned: v.boolean(),
    order: v.number(),
    // Storage reference for videos synthesized from legacy bandMediaSlots.
    storageId: v.optional(v.id("_storage")),
  }).index("by_band_order", ["bandId", "order"]),
});
