import { v } from "convex/values";
import { internal } from "./_generated/api";
import { Doc, Id } from "./_generated/dataModel";
import {
  MutationCtx,
  QueryCtx,
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import {
  MAX_FEED_GIGS,
  MAX_PAST_GIGS,
  MAX_UPCOMING_GIGS_PER_BAND,
  assertGigPublishable,
  bandPayloadValidator,
  feedCutoff,
  gigPayloadValidator,
  gigPublishFieldsValidator,
  insertPublishedGig,
  pastGigsForBand,
  requireBandAdmin,
  requireBandAdminQuery,
  toBandPayload,
  toGigPayload,
  toVenuePayload,
  upcomingGigsForBand,
  venuePayloadValidator,
} from "./lib/helpers";
import {
  ageRequirementValidator,
  gigPerformerRoleValidator,
  gigProjectStatusValidator,
} from "./schema";

const MAX_PERFORMERS = 20;
const INVITE_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;

const performerPayloadValidator = v.object({
  _id: v.id("gigProjectPerformers"),
  kind: v.union(v.literal("band"), v.literal("invited"), v.literal("text")),
  name: v.string(),
  role: gigPerformerRoleValidator,
  bandId: v.union(v.id("bands"), v.null()),
  inviteUrl: v.union(v.string(), v.null()),
});

const projectPayloadValidator = v.object({
  _id: v.id("gigProjects"),
  bandId: v.id("bands"),
  publicGigId: v.union(v.id("gigs"), v.null()),
  status: gigProjectStatusValidator,
  revision: v.number(),
  publishedRevision: v.union(v.number(), v.null()),
  title: v.union(v.string(), v.null()),
  doorsAt: v.union(v.number(), v.null()),
  startsAt: v.union(v.number(), v.null()),
  venueId: v.union(v.id("venues"), v.null()),
  price: v.number(),
  flyKey: v.string(),
  flyStorageId: v.union(v.id("_storage"), v.null()),
  flyerUrl: v.union(v.string(), v.null()),
  overlay: v.boolean(),
  desc: v.string(),
  ticketing: v.union(v.literal("rsvp"), v.literal("external")),
  ageRequirement: ageRequirementValidator,
  externalUrl: v.union(v.string(), v.null()),
  cap: v.string(),
  updatedAt: v.number(),
  performers: v.array(performerPayloadValidator),
});

function lifecycle(gig: Doc<"gigs">) {
  return gig.lifecycle ?? "published";
}

function assertActiveProject(project: Doc<"gigProjects">) {
  if (project.status === "deleted") throw new Error("Gig has been deleted");
}

async function projectPerformers(
  ctx: QueryCtx | MutationCtx,
  projectId: Id<"gigProjects">,
) {
  return await ctx.db
    .query("gigProjectPerformers")
    .withIndex("by_project_and_order", (q) => q.eq("projectId", projectId))
    .order("asc")
    .take(MAX_PERFORMERS + 1);
}

async function toProjectPayload(
  ctx: QueryCtx | MutationCtx,
  project: Doc<"gigProjects">,
) {
  const performers = await projectPerformers(ctx, project._id);
  return {
    _id: project._id,
    bandId: project.bandId,
    publicGigId: project.publicGigId ?? null,
    status: project.status,
    revision: project.revision,
    publishedRevision: project.publishedRevision ?? null,
    title: project.title ?? null,
    doorsAt: project.doorsAt ?? null,
    startsAt: project.startsAt ?? null,
    venueId: project.venueId ?? null,
    price: project.price,
    flyKey: project.flyKey,
    flyStorageId: project.flyStorageId ?? null,
    flyerUrl: project.flyStorageId
      ? await ctx.storage.getUrl(project.flyStorageId)
      : null,
    overlay: project.overlay,
    desc: project.desc,
    ticketing: project.ticketing,
    ageRequirement: project.ageRequirement,
    externalUrl: project.externalUrl ?? null,
    cap: project.cap,
    updatedAt: project.updatedAt,
    performers: performers.slice(0, MAX_PERFORMERS).map((performer) => ({
      _id: performer._id,
      kind: performer.kind,
      name: performer.name,
      role: performer.role,
      bandId: performer.bandId ?? null,
      inviteUrl:
        performer.kind === "invited" &&
        performer.inviteToken &&
        performer.inviteRevoked !== true
          ? `https://earplug.app/gig-invite/${performer.inviteToken}`
          : null,
    })),
  };
}

async function requireProjectAdmin(
  ctx: MutationCtx,
  projectId: Id<"gigProjects">,
) {
  const project = await ctx.db.get(projectId);
  if (!project) throw new Error("Gig draft not found");
  await requireBandAdmin(ctx, project.bandId);
  assertActiveProject(project);
  return project;
}

async function requireProjectAdminQuery(
  ctx: QueryCtx,
  projectId: Id<"gigProjects">,
) {
  const project = await ctx.db.get(projectId);
  if (!project) throw new Error("Gig draft not found");
  await requireBandAdminQuery(ctx, project.bandId);
  assertActiveProject(project);
  return project;
}

function formattedTime(timestamp: number) {
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/Los_Angeles",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })
    .format(new Date(timestamp))
    .replace(" ", "")
    .replace(":00", "")
    .toUpperCase();
}

async function replaceGigBandIndex(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
  bandIds: Id<"bands">[],
  startsAt: number,
) {
  const existing = await ctx.db
    .query("gigBands")
    .withIndex("by_gig", (q) => q.eq("gigId", gigId))
    .take(MAX_PERFORMERS + 5);
  for (const row of existing) await ctx.db.delete(row._id);
  for (const bandId of new Set(bandIds)) {
    await ctx.db.insert("gigBands", { gigId, bandId, startsAt });
  }
}

async function publicLineup(ctx: MutationCtx, projectId: Id<"gigProjects">) {
  const performers = await projectPerformers(ctx, projectId);
  if (performers.length === 0) throw new Error("Add at least one performer");
  if (performers.length > MAX_PERFORMERS) {
    throw new Error(`A gig can have at most ${MAX_PERFORMERS} performers`);
  }
  const lineup = performers.flatMap((performer) =>
    performer.bandId ? [performer.bandId] : [],
  );
  const genres = new Set<string>();
  for (const bandId of new Set(lineup)) {
    const band = await ctx.db.get(bandId);
    if (band) for (const genre of band.genres) genres.add(genre);
  }
  return {
    lineup: [...new Set(lineup)],
    genres: [...genres],
    performers: performers.map((performer) => ({
      name: performer.name,
      role: performer.role,
      ...(performer.bandId ? { bandId: performer.bandId } : {}),
    })),
  };
}

async function publishProject(ctx: MutationCtx, project: Doc<"gigProjects">) {
  if (!project.title?.trim()) throw new Error("Gig name is required");
  if (project.doorsAt === undefined || project.startsAt === undefined) {
    throw new Error("Doors and start time are required");
  }
  if (project.venueId === undefined) throw new Error("Venue is required");
  if (project.startsAt < project.doorsAt) {
    throw new Error("Start time must be after doors");
  }
  await assertGigPublishable(ctx, {
    bandId: project.bandId,
    startsAt: project.startsAt,
    venueId: project.venueId,
    price: project.price,
    flyKey: project.flyKey,
    flyStorageId: project.flyStorageId,
    ticketing: project.ticketing,
    externalUrl: project.externalUrl,
  });

  const lineup = await publicLineup(ctx, project._id);
  const doorsTime = `${formattedTime(project.doorsAt)} / ${formattedTime(project.startsAt)}`;
  const publicFields = {
    title: project.title.trim(),
    venueId: project.venueId,
    price: project.price,
    startsAt: project.startsAt,
    doorsAt: project.doorsAt,
    doorsTime,
    flyKey: project.flyKey,
    lineup: lineup.lineup,
    performers: lineup.performers,
    genres: lineup.genres,
    desc: project.desc.trim(),
    ticketing: project.ticketing,
    ageRequirement: project.ageRequirement,
    ...(project.ticketing === "external" && project.externalUrl
      ? { externalUrl: project.externalUrl }
      : { externalUrl: undefined }),
    ...(project.flyKey === "custom" && project.flyStorageId
      ? { flyStorageId: project.flyStorageId }
      : { flyStorageId: undefined }),
    cap: project.cap,
    createdByBand: project.bandId,
    lifecycle: "published" as const,
  };

  let publicGigId = project.publicGigId;
  if (publicGigId) {
    const gig = await ctx.db.get(publicGigId);
    if (!gig) publicGigId = undefined;
    else {
      await ctx.db.patch(publicGigId, publicFields);
      await replaceGigBandIndex(
        ctx,
        publicGigId,
        lineup.lineup,
        project.startsAt,
      );
    }
  }
  if (!publicGigId) {
    publicGigId = await ctx.db.insert("gigs", {
      ...publicFields,
      goingCount: 0,
    });
    await replaceGigBandIndex(
      ctx,
      publicGigId,
      lineup.lineup,
      project.startsAt,
    );
  }
  await ctx.db.patch(project._id, {
    publicGigId,
    status: "published",
    publishedRevision: project.revision,
    updatedAt: Date.now(),
  });
  return publicGigId;
}

export async function createProjectForGig(
  ctx: MutationCtx,
  gig: Doc<"gigs">,
  bandId: Id<"bands">,
) {
  const existing = await ctx.db
    .query("gigProjects")
    .withIndex("by_public_gig", (q) => q.eq("publicGigId", gig._id))
    .first();
  if (existing) return existing._id;
  const now = Date.now();
  const projectId = await ctx.db.insert("gigProjects", {
    bandId,
    publicGigId: gig._id,
    status: lifecycle(gig) === "cancelled" ? "cancelled" : "published",
    revision: 1,
    publishedRevision: 1,
    title: gig.title,
    doorsAt: gig.doorsAt ?? gig.startsAt,
    startsAt: gig.startsAt,
    venueId: gig.venueId,
    price: gig.price,
    flyKey: gig.flyKey,
    flyStorageId: gig.flyStorageId,
    overlay: true,
    desc: gig.desc,
    ticketing: gig.ticketing,
    ageRequirement: gig.ageRequirement ?? "allAges",
    externalUrl: gig.externalUrl,
    cap: gig.cap,
    createdAt: now,
    updatedAt: now,
  });
  for (let index = 0; index < gig.lineup.length; index++) {
    const lineupBandId = gig.lineup[index];
    const band = await ctx.db.get(lineupBandId);
    if (!band) continue;
    await ctx.db.insert("gigProjectPerformers", {
      projectId,
      order: index,
      kind: "band",
      name: band.name,
      role: index === 0 ? "headliner" : "support",
      bandId: lineupBandId,
    });
  }
  return projectId;
}

type UpcomingGigs = { gigs: Doc<"gigs">[]; nextStartsAt: number | null };

async function upcomingGigs(ctx: QueryCtx): Promise<UpcomingGigs> {
  const published = await ctx.db
    .query("gigs")
    .withIndex("by_lifecycle_and_startsAt", (q) =>
      q.eq("lifecycle", "published").gte("startsAt", feedCutoff()),
    )
    .order("asc")
    .take(MAX_FEED_GIGS + 1);
  // Legacy rows have no lifecycle value and are treated as published until the
  // lifecycle migration has finished everywhere.
  const legacy = await ctx.db
    .query("gigs")
    .withIndex("by_lifecycle_and_startsAt", (q) =>
      q.eq("lifecycle", undefined).gte("startsAt", feedCutoff()),
    )
    .order("asc")
    .take(MAX_FEED_GIGS + 1);
  const visible = [...published, ...legacy].sort(
    (left, right) => left.startsAt - right.startsAt,
  );
  return {
    gigs: visible.slice(0, MAX_FEED_GIGS),
    nextStartsAt: visible[MAX_FEED_GIGS]?.startsAt ?? null,
  };
}

async function hydrateVenues(ctx: QueryCtx, venueIds: Set<Id<"venues">>) {
  const venues = [];
  for (const venueId of venueIds) {
    const venue = await ctx.db.get(venueId);
    if (venue) venues.push(toVenuePayload(venue));
  }
  return venues;
}

export const feed = query({
  args: {},
  returns: v.object({
    gigs: v.array(gigPayloadValidator),
    venues: v.array(venuePayloadValidator),
    bands: v.array(bandPayloadValidator),
    nextStartsAt: v.union(v.number(), v.null()),
  }),
  handler: async (ctx) => {
    const { gigs, nextStartsAt } = await upcomingGigs(ctx);
    const venueIds = new Set<Id<"venues">>();
    const bandIds = new Set<Id<"bands">>();
    for (const gig of gigs) {
      venueIds.add(gig.venueId);
      for (const bandId of gig.lineup) bandIds.add(bandId);
      if (gig.createdByBand) bandIds.add(gig.createdByBand);
    }
    const bands = [];
    for (const bandId of bandIds) {
      const band = await ctx.db.get(bandId);
      if (band) bands.push(await toBandPayload(ctx, band));
    }
    const gigPayloads = [];
    for (const gig of gigs) gigPayloads.push(await toGigPayload(ctx, gig));
    return {
      gigs: gigPayloads,
      venues: await hydrateVenues(ctx, venueIds),
      bands,
      nextStartsAt,
    };
  },
});

/** Direct public-page lookup. Cancelled gigs remain resolvable so an old share
 * link explains what happened; unpublished and deleted gigs stay private. */
export const getPublic = query({
  args: { gigId: v.id("gigs") },
  returns: v.union(gigPayloadValidator, v.null()),
  handler: async (ctx, args) => {
    const gig = await ctx.db.get(args.gigId);
    if (!gig || !["published", "cancelled"].includes(lifecycle(gig)))
      return null;
    return await toGigPayload(ctx, gig);
  },
});

export const forBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(gigPayloadValidator),
  handler: async (ctx, args) => {
    const rows = await upcomingGigsForBand(
      ctx,
      args.bandId,
      MAX_UPCOMING_GIGS_PER_BAND * 2,
    );
    const out = [];
    for (const gig of rows) {
      if (lifecycle(gig) === "published")
        out.push(await toGigPayload(ctx, gig));
      if (out.length === MAX_UPCOMING_GIGS_PER_BAND) break;
    }
    return out;
  },
});

export const pastForBand = query({
  args: { bandId: v.id("bands") },
  returns: v.object({
    gigs: v.array(gigPayloadValidator),
    venues: v.array(venuePayloadValidator),
  }),
  handler: async (ctx, args) => {
    const rows = await pastGigsForBand(ctx, args.bandId, MAX_PAST_GIGS * 2);
    const gigs = [];
    const venueIds = new Set<Id<"venues">>();
    for (const gig of rows) {
      if (lifecycle(gig) !== "published") continue;
      gigs.push(await toGigPayload(ctx, gig));
      venueIds.add(gig.venueId);
      if (gigs.length === MAX_PAST_GIGS) break;
    }
    return { gigs, venues: await hydrateVenues(ctx, venueIds) };
  },
});

/** Compatibility endpoint for released clients. New clients use projects. */
export const publishGig = mutation({
  args: gigPublishFieldsValidator.fields,
  returns: v.object({ gigId: v.id("gigs") }),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const { band } = await assertGigPublishable(ctx, args);
    const gigId = await insertPublishedGig(ctx, args, band);
    const gig = await ctx.db.get(gigId);
    if (gig) {
      await ctx.db.patch(gigId, {
        lifecycle: "published",
        doorsAt: gig.doorsAt ?? gig.startsAt,
        performers: [{ name: band.name, role: "headliner", bandId: band._id }],
      });
      await createProjectForGig(
        ctx,
        { ...gig, lifecycle: "published" },
        band._id,
      );
    }
    return { gigId };
  },
});

export const manageForBand = query({
  args: { bandId: v.id("bands") },
  returns: v.array(projectPayloadValidator),
  handler: async (ctx, args) => {
    await requireBandAdminQuery(ctx, args.bandId);
    const projects = await ctx.db
      .query("gigProjects")
      .withIndex("by_band_and_status", (q) => q.eq("bandId", args.bandId))
      .order("desc")
      .take(100);
    const out = [];
    for (const project of projects) {
      if (project.status !== "deleted")
        out.push(await toProjectPayload(ctx, project));
    }
    return out;
  },
});

export const getProject = query({
  args: { projectId: v.id("gigProjects") },
  returns: projectPayloadValidator,
  handler: async (ctx, args) =>
    await toProjectPayload(
      ctx,
      await requireProjectAdminQuery(ctx, args.projectId),
    ),
});

export const createDraft = mutation({
  args: { bandId: v.id("bands") },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const band = await ctx.db.get(args.bandId);
    if (!band) throw new Error("Band not found");
    const now = Date.now();
    const projectId = await ctx.db.insert("gigProjects", {
      bandId: args.bandId,
      status: "draft",
      revision: 1,
      price: 0,
      flyKey: "xerox",
      overlay: true,
      desc: "",
      ticketing: "rsvp",
      ageRequirement: "allAges",
      cap: "No cap",
      createdAt: now,
      updatedAt: now,
    });
    await ctx.db.insert("gigProjectPerformers", {
      projectId,
      order: 0,
      kind: "band",
      name: band.name,
      role: "headliner",
      bandId: band._id,
    });
    const project = await ctx.db.get(projectId);
    if (!project) throw new Error("Draft not found after creation");
    return await toProjectPayload(ctx, project);
  },
});

export const saveDraft = mutation({
  args: {
    projectId: v.id("gigProjects"),
    revision: v.number(),
    title: v.union(v.string(), v.null()),
    doorsAt: v.union(v.number(), v.null()),
    startsAt: v.union(v.number(), v.null()),
    venueId: v.union(v.id("venues"), v.null()),
    price: v.number(),
    flyKey: v.string(),
    flyStorageId: v.union(v.id("_storage"), v.null()),
    overlay: v.boolean(),
    desc: v.string(),
    ticketing: v.union(v.literal("rsvp"), v.literal("external")),
    ageRequirement: ageRequirementValidator,
    externalUrl: v.union(v.string(), v.null()),
    cap: v.string(),
  },
  returns: v.object({ revision: v.number() }),
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    if (project.revision !== args.revision)
      throw new Error("Draft changed elsewhere");
    if (!Number.isFinite(args.price) || args.price < 0)
      throw new Error("Invalid price");
    const revision = project.revision + 1;
    await ctx.db.patch(project._id, {
      revision,
      title: args.title?.trim() || undefined,
      doorsAt: args.doorsAt ?? undefined,
      startsAt: args.startsAt ?? undefined,
      venueId: args.venueId ?? undefined,
      price: args.price,
      flyKey: args.flyKey,
      flyStorageId: args.flyStorageId ?? undefined,
      overlay: args.overlay,
      desc: args.desc,
      ticketing: args.ticketing,
      ageRequirement: args.ageRequirement,
      externalUrl: args.externalUrl?.trim() || undefined,
      cap: args.cap,
      updatedAt: Date.now(),
    });
    return { revision };
  },
});

export const addPerformer = mutation({
  args: {
    projectId: v.id("gigProjects"),
    kind: v.union(v.literal("band"), v.literal("invited"), v.literal("text")),
    name: v.optional(v.string()),
    bandId: v.optional(v.id("bands")),
    role: gigPerformerRoleValidator,
  },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    const performers = await projectPerformers(ctx, project._id);
    if (performers.length >= MAX_PERFORMERS) throw new Error("Lineup is full");
    let name = args.name?.trim() ?? "";
    let bandId: Id<"bands"> | undefined;
    if (args.kind === "band") {
      if (!args.bandId) throw new Error("Band is required");
      const band = await ctx.db.get(args.bandId);
      if (!band) throw new Error("Band not found");
      if (performers.some((performer) => performer.bandId === band._id)) {
        throw new Error("Band is already in the lineup");
      }
      name = band.name;
      bandId = band._id;
    } else if (!name) {
      throw new Error("Performer name is required");
    }
    const inviteToken =
      args.kind === "invited" ? await uniqueInviteToken(ctx) : undefined;
    const inviteExpiresAt = inviteToken
      ? Date.now() + INVITE_LIFETIME_MS
      : undefined;
    await ctx.db.insert("gigProjectPerformers", {
      projectId: project._id,
      order: performers.length,
      kind: args.kind,
      name,
      role: args.role,
      bandId,
      inviteToken,
      inviteExpiresAt,
      inviteRevoked: inviteToken ? false : undefined,
    });
    if (inviteToken && inviteExpiresAt) {
      await ctx.scheduler.runAt(inviteExpiresAt, internal.gigs.expireInvite, {
        token: inviteToken,
      });
    }
    await ctx.db.patch(project._id, {
      revision: project.revision + 1,
      updatedAt: Date.now(),
    });
    const updated = await ctx.db.get(project._id);
    if (!updated) throw new Error("Draft not found");
    return await toProjectPayload(ctx, updated);
  },
});

export const updatePerformer = mutation({
  args: {
    performerId: v.id("gigProjectPerformers"),
    name: v.optional(v.string()),
    role: v.optional(gigPerformerRoleValidator),
  },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    const performer = await ctx.db.get(args.performerId);
    if (!performer) throw new Error("Performer not found");
    const project = await requireProjectAdmin(ctx, performer.projectId);
    const patch: { name?: string; role?: "headliner" | "support" | "opener" } =
      {};
    if (args.name !== undefined && performer.kind !== "band") {
      const name = args.name.trim();
      if (!name) throw new Error("Performer name is required");
      patch.name = name;
    }
    if (args.role !== undefined) patch.role = args.role;
    if (Object.keys(patch).length > 0) await ctx.db.patch(performer._id, patch);
    await ctx.db.patch(project._id, {
      revision: project.revision + 1,
      updatedAt: Date.now(),
    });
    const updated = await ctx.db.get(project._id);
    if (!updated) throw new Error("Draft not found");
    return await toProjectPayload(ctx, updated);
  },
});

export const removePerformer = mutation({
  args: { performerId: v.id("gigProjectPerformers") },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    const performer = await ctx.db.get(args.performerId);
    if (!performer) throw new Error("Performer not found");
    const project = await requireProjectAdmin(ctx, performer.projectId);
    await ctx.db.delete(performer._id);
    const remaining = await projectPerformers(ctx, project._id);
    for (let index = 0; index < remaining.length; index++) {
      if (remaining[index].order !== index)
        await ctx.db.patch(remaining[index]._id, { order: index });
    }
    await ctx.db.patch(project._id, {
      revision: project.revision + 1,
      updatedAt: Date.now(),
    });
    const updated = await ctx.db.get(project._id);
    if (!updated) throw new Error("Draft not found");
    return await toProjectPayload(ctx, updated);
  },
});

export const reorderPerformers = mutation({
  args: {
    projectId: v.id("gigProjects"),
    performerIds: v.array(v.id("gigProjectPerformers")),
  },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    const current = await projectPerformers(ctx, project._id);
    if (
      args.performerIds.length !== current.length ||
      args.performerIds.length > MAX_PERFORMERS
    ) {
      throw new Error("Lineup changed; reload and try again");
    }
    const currentIds = new Set(current.map((performer) => performer._id));
    if (
      new Set(args.performerIds).size !== current.length ||
      args.performerIds.some((id) => !currentIds.has(id))
    ) {
      throw new Error("Invalid lineup order");
    }
    for (let index = 0; index < args.performerIds.length; index++) {
      await ctx.db.patch(args.performerIds[index], { order: index });
    }
    await ctx.db.patch(project._id, {
      revision: project.revision + 1,
      updatedAt: Date.now(),
    });
    const updated = await ctx.db.get(project._id);
    if (!updated) throw new Error("Draft not found");
    return await toProjectPayload(ctx, updated);
  },
});

export const publishDraft = mutation({
  args: { projectId: v.id("gigProjects") },
  returns: v.object({ gigId: v.id("gigs") }),
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    return { gigId: await publishProject(ctx, project) };
  },
});

export const duplicate = mutation({
  args: { projectId: v.id("gigProjects") },
  returns: projectPayloadValidator,
  handler: async (ctx, args) => {
    const source = await requireProjectAdmin(ctx, args.projectId);
    const now = Date.now();
    const projectId = await ctx.db.insert("gigProjects", {
      bandId: source.bandId,
      status: "draft",
      revision: 1,
      title: source.title ? `Copy of ${source.title}` : undefined,
      doorsAt: source.doorsAt,
      startsAt: source.startsAt,
      venueId: source.venueId,
      price: source.price,
      flyKey: source.flyKey,
      flyStorageId: source.flyStorageId,
      overlay: source.overlay,
      desc: source.desc,
      ticketing: source.ticketing,
      ageRequirement: source.ageRequirement,
      externalUrl: source.externalUrl,
      cap: source.cap,
      createdAt: now,
      updatedAt: now,
    });
    for (const performer of await projectPerformers(ctx, source._id)) {
      await ctx.db.insert("gigProjectPerformers", {
        projectId,
        order: performer.order,
        kind: performer.kind === "invited" ? "text" : performer.kind,
        name: performer.name,
        role: performer.role,
        bandId: performer.bandId,
      });
    }
    const project = await ctx.db.get(projectId);
    if (!project) throw new Error("Duplicate not found");
    return await toProjectPayload(ctx, project);
  },
});

export const unpublish = mutation({
  args: { projectId: v.id("gigProjects") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    if (project.publicGigId)
      await ctx.db.patch(project.publicGigId, { lifecycle: "unpublished" });
    await ctx.db.patch(project._id, { status: "draft", updatedAt: Date.now() });
    return null;
  },
});

export const cancel = mutation({
  args: { projectId: v.id("gigProjects") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    if (!project.publicGigId)
      throw new Error("Publish the gig before cancelling it");
    await ctx.db.patch(project.publicGigId, { lifecycle: "cancelled" });
    await ctx.db.patch(project._id, {
      status: "cancelled",
      updatedAt: Date.now(),
    });
    return null;
  },
});

export const deleteGig = mutation({
  args: { projectId: v.id("gigProjects") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const project = await requireProjectAdmin(ctx, args.projectId);
    if (project.publicGigId)
      await ctx.db.patch(project.publicGigId, { lifecycle: "deleted" });
    for (const performer of await projectPerformers(ctx, project._id)) {
      if (performer.inviteToken)
        await ctx.db.patch(performer._id, { inviteRevoked: true });
    }
    await ctx.db.patch(project._id, {
      status: "deleted",
      updatedAt: Date.now(),
    });
    await ctx.scheduler.runAfter(0, internal.gigs.purgeDeletedGig, {
      projectId: project._id,
    });
    return null;
  },
});

export const expireInvite = internalMutation({
  args: { token: v.string() },
  returns: v.null(),
  handler: async (ctx, args) => {
    const performer = await ctx.db
      .query("gigProjectPerformers")
      .withIndex("by_invite_token", (q) => q.eq("inviteToken", args.token))
      .first();
    if (
      performer?.inviteToken === args.token &&
      performer.inviteRevoked !== true
    ) {
      await ctx.db.patch(performer._id, { inviteRevoked: true });
    }
    return null;
  },
});

export const resolvePerformerInvite = query({
  args: { token: v.string() },
  returns: v.union(
    v.object({ performerName: v.string(), gigTitle: v.string() }),
    v.null(),
  ),
  handler: async (ctx, args) => {
    if (args.token.length > 200) return null;
    const performer = await ctx.db
      .query("gigProjectPerformers")
      .withIndex("by_invite_token", (q) => q.eq("inviteToken", args.token))
      .first();
    if (
      !performer ||
      performer.inviteRevoked === true ||
      performer.kind !== "invited"
    ) {
      return null;
    }
    const project = await ctx.db.get(performer.projectId);
    if (!project || project.status === "deleted") return null;
    return {
      performerName: performer.name,
      gigTitle: project.title ?? "Untitled gig",
    };
  },
});

export const claimPerformerInvite = mutation({
  args: { token: v.string(), bandId: v.id("bands") },
  returns: v.object({ projectId: v.id("gigProjects") }),
  handler: async (ctx, args) => {
    await requireBandAdmin(ctx, args.bandId);
    const band = await ctx.db.get(args.bandId);
    if (!band) throw new Error("Band not found");
    const performer =
      args.token.length <= 200
        ? await ctx.db
            .query("gigProjectPerformers")
            .withIndex("by_invite_token", (q) =>
              q.eq("inviteToken", args.token),
            )
            .first()
        : null;
    if (
      !performer ||
      performer.kind !== "invited" ||
      performer.inviteRevoked === true ||
      !performer.inviteExpiresAt ||
      performer.inviteExpiresAt <= Date.now()
    ) {
      throw new Error("Invitation is invalid or expired");
    }
    const project = await ctx.db.get(performer.projectId);
    if (!project || project.status === "deleted")
      throw new Error("Gig is unavailable");
    const performers = await projectPerformers(ctx, project._id);
    if (
      performers.some(
        (candidate) =>
          candidate._id !== performer._id && candidate.bandId === band._id,
      )
    ) {
      throw new Error("Band is already in the lineup");
    }
    await ctx.db.patch(performer._id, {
      kind: "band",
      name: band.name,
      bandId: band._id,
      inviteRevoked: true,
      claimedAt: Date.now(),
    });
    const revision = project.revision + 1;
    let publishedRevision = project.publishedRevision;
    if (project.status === "published" || project.status === "cancelled") {
      const lineup = await publicLineup(ctx, project._id);
      if (project.publicGigId) {
        await ctx.db.patch(project.publicGigId, {
          lineup: lineup.lineup,
          performers: lineup.performers,
          genres: lineup.genres,
        });
        if (project.startsAt)
          await replaceGigBandIndex(
            ctx,
            project.publicGigId,
            lineup.lineup,
            project.startsAt,
          );
        publishedRevision = revision;
      }
    }
    await ctx.db.patch(project._id, {
      revision,
      publishedRevision,
      updatedAt: Date.now(),
    });
    return { projectId: project._id };
  },
});

export const purgeDeletedGig = internalMutation({
  args: { projectId: v.id("gigProjects") },
  returns: v.null(),
  handler: async (ctx, args) => {
    const project = await ctx.db.get(args.projectId);
    if (!project || project.status !== "deleted") return null;
    const performers = await projectPerformers(ctx, project._id);
    for (const performer of performers) await ctx.db.delete(performer._id);
    const gigId = project.publicGigId;
    if (gigId) {
      const joins = await ctx.db
        .query("gigBands")
        .withIndex("by_gig", (q) => q.eq("gigId", gigId))
        .take(100);
      for (const row of joins) await ctx.db.delete(row._id);
      const rsvps = await ctx.db
        .query("gigRsvps")
        .withIndex("by_gig", (q) => q.eq("gigId", gigId))
        .take(100);
      for (const row of rsvps) await ctx.db.delete(row._id);
      const saves = await ctx.db
        .query("gigSaves")
        .withIndex("by_gig", (q) => q.eq("gigId", gigId))
        .take(100);
      for (const row of saves) await ctx.db.delete(row._id);
      if (rsvps.length === 100 || saves.length === 100) {
        await ctx.scheduler.runAfter(0, internal.gigs.purgeDeletedGig, {
          projectId: project._id,
        });
        return null;
      }
      await ctx.db.delete(gigId);
    }
    await ctx.db.delete(project._id);
    return null;
  },
});

function randomToken() {
  const bytes = new Uint8Array(32);
  for (let index = 0; index < bytes.length; index++)
    bytes[index] = Math.floor(Math.random() * 256);
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}

async function uniqueInviteToken(ctx: MutationCtx) {
  for (let attempt = 0; attempt < 3; attempt++) {
    const token = randomToken();
    const collision = await ctx.db
      .query("gigProjectPerformers")
      .withIndex("by_invite_token", (q) => q.eq("inviteToken", token))
      .first();
    if (!collision) return token;
  }
  throw new Error("Could not create a unique invitation");
}
