import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";

export async function ensureInventory(
  ctx: MutationCtx,
  gig: Doc<"gigs">,
): Promise<Doc<"gigTicketInventory">> {
  const inventory = await ctx.db
    .query("gigTicketInventory")
    .withIndex("by_gigId", (q) => q.eq("gigId", gig._id))
    .unique();
  if (
    gig.ticketing !== "paid" ||
    gig.ticketCapacity === undefined ||
    !gig.createdByOrganization
  ) {
    throw new Error("This event is not selling tickets");
  }
  if (inventory) return inventory;

  const inventoryId = await ctx.db.insert("gigTicketInventory", {
    gigId: gig._id,
    organizationId: gig.createdByOrganization,
    capacity: gig.ticketCapacity,
    sold: 0,
    reserved: 0,
    updatedAt: Date.now(),
  });
  const inserted = await ctx.db.get(inventoryId);
  if (!inserted) throw new Error("Ticket inventory not found");
  return inserted;
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
