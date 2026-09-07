import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { insertGigWithBandIndex, slugify } from "../lib/helpers";
import { assertOpportunityTransition } from "./opportunityStatus";

export function formattedTime(timestamp: number) {
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

export async function uniqueGigSlug(ctx: MutationCtx, title: string) {
  const generated = slugify(title);
  const base = generated === "band" ? "gig" : generated;
  for (let suffix = 1; ; suffix++) {
    const candidate = suffix === 1 ? base : `${base}-${suffix}`;
    const existing = await ctx.db
      .query("gigs")
      .withIndex("by_slug", (q) => q.eq("slug", candidate))
      .first();
    if (!existing) return candidate;
  }
}

export async function replaceGigBandIndex(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
  bandIds: Id<"bands">[],
  startsAt: number,
) {
  const existing = await ctx.db
    .query("gigBands")
    .withIndex("by_gig", (q) => q.eq("gigId", gigId))
    .take(25);
  for (const row of existing) await ctx.db.delete(row._id);
  for (const bandId of new Set(bandIds)) {
    await ctx.db.insert("gigBands", { gigId, bandId, startsAt });
  }
}

export async function bookedLineup(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
) {
  const slots = await ctx.db
    .query("opportunitySlots")
    .withIndex("by_opportunityId_and_order", (q) =>
      q.eq("opportunityId", opportunityId),
    )
    .order("asc")
    .collect();
  const lineup: Id<"bands">[] = [];
  const performers: {
    bandId: Id<"bands">;
    role: Doc<"opportunitySlots">["role"];
    name: string;
  }[] = [];
  let requiredFilled = true;
  for (const slot of slots) {
    const booking = slot.bookingId ? await ctx.db.get(slot.bookingId) : null;
    if (!slot.bandId || booking?.status !== "confirmed") {
      if (slot.required) requiredFilled = false;
      continue;
    }
    const band = await ctx.db.get(slot.bandId);
    if (!band) throw new Error("Booked slot references a missing band");
    lineup.push(slot.bandId);
    performers.push({ bandId: slot.bandId, role: slot.role, name: band.name });
  }
  return { lineup, performers, requiredFilled };
}

function pricedTicketingGigFields(opportunity: Doc<"talentOpportunities">) {
  return {
    ticketPriceMinor: opportunity.ticketPriceMinor,
    ticketCurrency: opportunity.ticketCurrency,
    ticketCapacity: opportunity.ticketCapacity,
    price: Math.round((opportunity.ticketPriceMinor ?? 0) / 100),
  };
}

async function applyTicketInventoryCapacity(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
  organizationId: Id<"organizations">,
  capacity: number | undefined,
): Promise<void> {
  if (capacity === undefined) {
    throw new Error("Paid opportunity is missing a ticket capacity");
  }
  const existing = await ctx.db
    .query("gigTicketInventory")
    .withIndex("by_gigId", (q) => q.eq("gigId", gigId))
    .unique();
  if (existing) {
    await ctx.db.patch(existing._id, {
      capacity: Math.max(capacity, existing.sold + existing.reserved),
      updatedAt: Date.now(),
    });
  } else {
    await ctx.db.insert("gigTicketInventory", {
      gigId,
      organizationId,
      capacity,
      sold: 0,
      reserved: 0,
      updatedAt: Date.now(),
    });
  }
}

export async function publishGigFromOpportunity(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
): Promise<Id<"gigs"> | null> {
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  const { lineup, performers, requiredFilled } = await bookedLineup(
    ctx,
    opportunityId,
  );
  if (!requiredFilled) return null;
  if (opportunity.mode === "privateBooking") {
    assertOpportunityTransition(opportunity.status, "confirmed");
    await ctx.db.patch(opportunityId, {
      status: "confirmed",
      revision: opportunity.revision + 1,
      updatedAt: Date.now(),
    });
    return null;
  }
  if (opportunity.venueId === undefined) {
    throw new Error("Opportunity has no venue");
  }

  const existingGig = opportunity.publicGigId
    ? await ctx.db.get(opportunity.publicGigId)
    : null;
  const ticketing = opportunity.ticketing === "none" ? "rsvp" : opportunity.ticketing;
  const ticketingFields = {
    ticketing,
    ...(ticketing === "external" && opportunity.externalUrl
      ? { externalUrl: opportunity.externalUrl }
      : {}),
    ...(ticketing === "paid"
      ? pricedTicketingGigFields(opportunity)
      : {}),
  };
  let gigId: Id<"gigs">;
  if (existingGig) {
    gigId = existingGig._id;
    await ctx.db.patch(gigId, {
      lifecycle: "published",
      lineup,
      performers,
      discoveryListingReady: true,
      ...ticketingFields,
    });
    await replaceGigBandIndex(ctx, gigId, lineup, opportunity.startsAt);
  } else {
    const doorsAt = opportunity.doorsAt ?? opportunity.startsAt;
    gigId = await insertGigWithBandIndex(ctx, {
      title: opportunity.title,
      slug: await uniqueGigSlug(ctx, opportunity.title),
      venueId: opportunity.venueId,
      price: 0,
      startsAt: opportunity.startsAt,
      doorsAt,
      doorsTime: `${formattedTime(doorsAt)} / ${formattedTime(opportunity.startsAt)}`,
      flyKey: opportunity.flyKey,
      ...(opportunity.flyKey === "custom" && opportunity.flyStorageId
        ? { flyStorageId: opportunity.flyStorageId }
        : {}),
      lineup,
      performers: performers.map(({ name, role, bandId }) => ({ name, role, bandId })),
      genres: opportunity.genres,
      desc: opportunity.desc,
      ...ticketingFields,
      ageRequirement: opportunity.ageRequirement,
      cap: opportunity.expectedAttendance !== undefined
        ? String(opportunity.expectedAttendance)
        : "No cap",
      goingCount: 0,
      createdByBand: undefined,
      ownerKind: "organization",
      createdByOrganization: opportunity.organizationId,
      opportunityId,
      lifecycle: "published",
      discoveryListingReady: true,
    });
  }
  if (ticketing === "paid") {
    await applyTicketInventoryCapacity(
      ctx,
      gigId,
      opportunity.organizationId,
      opportunity.ticketCapacity,
    );
  }
  assertOpportunityTransition(opportunity.status, "confirmed");
  await ctx.db.patch(opportunityId, {
    publicGigId: gigId,
    status: "confirmed",
    revision: opportunity.revision + 1,
    updatedAt: Date.now(),
  });
  return gigId;
}

export async function syncGigTicketing(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
): Promise<void> {
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  if (opportunity.mode === "privateBooking") return;
  if (opportunity.publicGigId === undefined || opportunity.ticketing !== "paid") {
    return;
  }
  const gig = await ctx.db.get(opportunity.publicGigId);
  if (!gig) return;
  await ctx.db.patch(gig._id, pricedTicketingGigFields(opportunity));
  await applyTicketInventoryCapacity(
    ctx,
    gig._id,
    opportunity.organizationId,
    opportunity.ticketCapacity,
  );
}

export async function syncGigLineup(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
): Promise<void> {
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  if (opportunity.mode === "privateBooking") return;
  if (opportunity.publicGigId === undefined) return;
  const gig = await ctx.db.get(opportunity.publicGigId);
  if (!gig) return;
  const { lineup, performers } = await bookedLineup(ctx, opportunityId);
  await ctx.db.patch(gig._id, { lineup, performers });
  await replaceGigBandIndex(ctx, gig._id, lineup, gig.startsAt);
}

export async function unpublishOpportunityGig(
  ctx: MutationCtx,
  opportunityId: Id<"talentOpportunities">,
  reason: "required_slot_cancelled" | "opportunity_cancelled",
): Promise<void> {
  const opportunity = await ctx.db.get(opportunityId);
  if (!opportunity) throw new Error("Opportunity not found");
  if (opportunity.mode !== "privateBooking") {
    if (opportunity.publicGigId === undefined) return;
    await ctx.db.patch(opportunity.publicGigId, {
      lifecycle: reason === "opportunity_cancelled" ? "cancelled" : "unpublished",
      discoveryListingReady: false,
    });
  }
  const status = reason === "required_slot_cancelled" ? "booking" : "cancelled";
  if (opportunity.status !== status) {
    assertOpportunityTransition(opportunity.status, status);
    await ctx.db.patch(opportunityId, {
      status,
      revision: opportunity.revision + 1,
      updatedAt: Date.now(),
    });
  }
}
