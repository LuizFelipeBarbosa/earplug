import { v, type Infer } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import { mutation, query, type QueryCtx } from "./_generated/server";
import { requireOrganizationRole } from "./lib/authz";
import { requireBandRole } from "./lib/helpers";
import {
  assertTicketTransition,
  TICKET_TOKEN_PREFIX,
} from "./lib/ticketStatus";

const TICKET_TOKEN_PREFIX_V1 = "earplug:ticket:v1:";

function parseTicketPayload(
  payload: string,
): { version: "v1" | "v2"; token: string } | { version: "unrecognized" } {
  for (const [version, prefix] of [
    ["v2", TICKET_TOKEN_PREFIX],
    ["v1", TICKET_TOKEN_PREFIX_V1],
  ] as const) {
    if (payload.startsWith(prefix)) {
      const token = payload.slice(prefix.length);
      if (/^[a-f0-9]{64}$/.test(token)) return { version, token };
    }
  }
  return { version: "unrecognized" };
}

async function requireDoorAccess(
  ctx: QueryCtx,
  gig: Doc<"gigs">,
): Promise<Doc<"users">> {
  if (gig.createdByOrganization) {
    const access = await requireOrganizationRole(
      ctx,
      gig.createdByOrganization,
      ["owner", "manager", "door"],
    );
    return access.user;
  }

  const bandIds = [gig.createdByBand, ...gig.lineup].filter(
    (bandId): bandId is Id<"bands"> => Boolean(bandId),
  );
  for (const bandId of bandIds) {
    try {
      const { user } = await requireBandRole(ctx, bandId, { role: "admin" });
      return user;
    } catch {
      // An admin of any associated band can manage the door.
    }
  }
  throw new Error("Only the band or organizer can check people in");
}

async function holderNameFor(
  ctx: QueryCtx,
  userId: Id<"users">,
): Promise<string> {
  const holder = await ctx.db.get(userId);
  return holder?.name.trim() || "Guest";
}

export const doorCheckInResultValidator = v.union(
  v.object({
    kind: v.literal("checkedIn"),
    holderName: v.string(),
    checkedInAt: v.number(),
    source: v.union(v.literal("ticket"), v.literal("rsvp")),
  }),
  v.object({
    kind: v.literal("alreadyUsed"),
    holderName: v.string(),
    checkedInAt: v.number(),
    source: v.union(v.literal("ticket"), v.literal("rsvp")),
  }),
  v.object({ kind: v.literal("refunded") }),
  v.object({ kind: v.literal("eventCancelled") }),
  v.object({ kind: v.literal("wrongEvent") }),
  v.object({ kind: v.literal("unknown") }),
);

export const checkIn = mutation({
  args: { gigId: v.id("gigs"), payload: v.string() },
  returns: doorCheckInResultValidator,
  handler: async (
    ctx,
    args,
  ): Promise<Infer<typeof doorCheckInResultValidator>> => {
    const gig = await ctx.db.get(args.gigId);
    if (!gig) throw new Error("Gig not found");
    const user = await requireDoorAccess(ctx, gig);
    if ((gig.lifecycle ?? "published") === "cancelled") {
      return { kind: "eventCancelled" };
    }

    const parsed = parseTicketPayload(args.payload.trim());
    if (parsed.version === "unrecognized") return { kind: "unknown" };

    if (parsed.version === "v2") {
      const ticket = await ctx.db
        .query("tickets")
        .withIndex("by_token", (q) =>
          q.eq("token", TICKET_TOKEN_PREFIX + parsed.token),
        )
        .unique();
      if (!ticket) return { kind: "unknown" };
      if (ticket.gigId !== args.gigId) return { kind: "wrongEvent" };
      if (ticket.status === "refunded" || ticket.status === "cancelled") {
        return { kind: "refunded" };
      }
      if (ticket.status === "used") {
        return {
          kind: "alreadyUsed",
          holderName: await holderNameFor(ctx, ticket.holderUserId),
          checkedInAt: ticket.checkedInAt ?? 0,
          source: "ticket",
        };
      }

      assertTicketTransition("valid", "used");
      const now = Date.now();
      await ctx.db.patch(ticket._id, {
        status: "used",
        checkedInAt: now,
        checkedInBy: user._id,
      });
      return {
        kind: "checkedIn",
        holderName: await holderNameFor(ctx, ticket.holderUserId),
        checkedInAt: now,
        source: "ticket",
      };
    }

    const rsvp = await ctx.db
      .query("gigRsvps")
      .withIndex("by_ticketToken", (q) => q.eq("ticketToken", parsed.token))
      .unique();
    if (!rsvp) return { kind: "unknown" };
    if (rsvp.gigId !== args.gigId) return { kind: "wrongEvent" };
    if (rsvp.checkedInAt !== undefined) {
      return {
        kind: "alreadyUsed",
        holderName: await holderNameFor(ctx, rsvp.userId),
        checkedInAt: rsvp.checkedInAt,
        source: "rsvp",
      };
    }

    const now = Date.now();
    await ctx.db.patch(rsvp._id, { checkedInAt: now, checkedInBy: user._id });
    return {
      kind: "checkedIn",
      holderName: await holderNameFor(ctx, rsvp.userId),
      checkedInAt: now,
      source: "rsvp",
    };
  },
});

export const doorRoster = query({
  args: { gigId: v.id("gigs") },
  returns: v.object({
    rsvpTotal: v.number(),
    rsvpCheckedIn: v.number(),
    ticketsSold: v.number(),
    ticketsCheckedIn: v.number(),
    truncated: v.boolean(),
  }),
  handler: async (ctx, args) => {
    const gig = await ctx.db.get(args.gigId);
    if (!gig) throw new Error("Gig not found");
    await requireDoorAccess(ctx, gig);

    const rsvps = await ctx.db
      .query("gigRsvps")
      .withIndex("by_gig", (q) => q.eq("gigId", args.gigId))
      .take(501);
    const tickets = await ctx.db
      .query("tickets")
      .withIndex("by_gigId", (q) => q.eq("gigId", args.gigId))
      .take(501);
    const visibleTickets = tickets.slice(0, 500);
    return {
      rsvpTotal: Math.min(rsvps.length, 500),
      rsvpCheckedIn: rsvps
        .slice(0, 500)
        .filter((rsvp) => rsvp.checkedInAt !== undefined).length,
      ticketsSold: visibleTickets.filter(
        (ticket) => ticket.status === "valid" || ticket.status === "used",
      ).length,
      ticketsCheckedIn: visibleTickets.filter(
        (ticket) => ticket.status === "used",
      ).length,
      truncated: rsvps.length > 500 || tickets.length > 500,
    };
  },
});
