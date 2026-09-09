import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import {
  resolveTicketSeller,
  sellerRefFields,
  type TicketSeller,
} from "./ticketSeller";

export async function ensureInventory(
  ctx: MutationCtx,
  gig: Doc<"gigs">,
): Promise<Doc<"gigTicketInventory">> {
  const inventory = await ctx.db
    .query("gigTicketInventory")
    .withIndex("by_gigId", (q) => q.eq("gigId", gig._id))
    .unique();
  const seller = await resolveTicketSeller(ctx, gig);
  if (
    gig.ticketing !== "paid" ||
    gig.ticketCapacity === undefined ||
    seller === null
  ) {
    throw new Error("This event is not selling tickets");
  }
  if (inventory) {
    if (
      inventory.organizationId !== seller.organizationId ||
      inventory.bandId !== seller.bandId
    ) {
      throw new Error("This event is not selling tickets");
    }
    return inventory;
  }

  const inventoryId = await ctx.db.insert("gigTicketInventory", {
    gigId: gig._id,
    ...sellerRefFields(seller),
    capacity: gig.ticketCapacity,
    sold: 0,
    reserved: 0,
    updatedAt: Date.now(),
  });
  const inserted = await ctx.db.get(inventoryId);
  if (!inserted) throw new Error("Ticket inventory not found");
  return inserted;
}

export async function applyTicketInventoryCapacity(
  ctx: MutationCtx,
  gigId: Id<"gigs">,
  seller: TicketSeller,
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
      ...sellerRefFields(seller),
      capacity,
      sold: 0,
      reserved: 0,
      updatedAt: Date.now(),
    });
  }
}

export function availableCount(inventory: Doc<"gigTicketInventory">): number {
  return inventory.capacity - inventory.sold - inventory.reserved;
}

export async function reserveInventory(
  ctx: MutationCtx,
  inventory: Doc<"gigTicketInventory">,
  quantity: number,
): Promise<void> {
  const current = await ctx.db.get(inventory._id);
  if (!current) throw new Error("Ticket inventory not found");
  if (current.sold + current.reserved + quantity > current.capacity) {
    throw new Error("Not enough tickets left");
  }
  await ctx.db.patch(current._id, {
    reserved: current.reserved + quantity,
    updatedAt: Date.now(),
  });
}

export async function releaseInventory(
  ctx: MutationCtx,
  inventory: Doc<"gigTicketInventory">,
  quantity: number,
): Promise<void> {
  const current = await ctx.db.get(inventory._id);
  if (!current) throw new Error("Ticket inventory not found");
  await ctx.db.patch(current._id, {
    reserved: Math.max(0, current.reserved - quantity),
    updatedAt: Date.now(),
  });
}

export async function commitInventory(
  ctx: MutationCtx,
  inventory: Doc<"gigTicketInventory">,
  quantity: number,
): Promise<void> {
  const current = await ctx.db.get(inventory._id);
  if (!current) throw new Error("Ticket inventory not found");
  await ctx.db.patch(current._id, {
    reserved: Math.max(0, current.reserved - quantity),
    sold: current.sold + quantity,
    updatedAt: Date.now(),
  });
}
