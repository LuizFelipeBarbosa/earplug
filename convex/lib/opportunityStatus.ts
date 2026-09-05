import type { Infer } from "convex/values";
import {
  opportunityStatusValidator,
  artistApplicationStatusValidator,
  opportunitySlotStatusValidator,
} from "../schema";

export type OpportunityStatus = Infer<typeof opportunityStatusValidator>;
export type ArtistApplicationStatus = Infer<typeof artistApplicationStatusValidator>;
export type OpportunitySlotStatus = Infer<typeof opportunitySlotStatusValidator>;

export const OPPORTUNITY_TRANSITIONS: Record<
  OpportunityStatus,
  readonly OpportunityStatus[]
> = {
  draft: ["open", "cancelled"],
  open: ["applications_closed", "cancelled", "confirmed"],
  applications_closed: ["open", "booking", "cancelled", "confirmed"],
  booking: ["confirmed", "applications_closed", "cancelled"],
  confirmed: ["completed", "cancelled", "booking"],
  completed: [],
  cancelled: [],
};

export const APPLICATION_TRANSITIONS: Record<
  ArtistApplicationStatus,
  readonly ArtistApplicationStatus[]
> = {
  submitted: ["under_review", "shortlisted", "declined", "withdrawn", "expired"],
  under_review: ["shortlisted", "declined", "withdrawn", "expired"],
  shortlisted: ["offered", "declined", "withdrawn", "expired"],
  offered: ["booked", "declined", "withdrawn", "expired", "shortlisted"],
  booked: ["declined", "withdrawn"],
  declined: [],
  withdrawn: [],
  expired: [],
};

export const SLOT_TRANSITIONS: Record<
  OpportunitySlotStatus,
  readonly OpportunitySlotStatus[]
> = {
  open: ["booked", "cancelled"],
  booked: ["open", "cancelled"],
  cancelled: [],
};

export function canTransition<T extends string>(
  table: Record<T, readonly T[]>,
  from: T,
  to: T,
): boolean {
  return table[from]?.includes(to) ?? false;
}

export function assertOpportunityTransition(
  from: OpportunityStatus,
  to: OpportunityStatus,
): void {
  if (!canTransition(OPPORTUNITY_TRANSITIONS, from, to)) {
    throw new Error(`Opportunity cannot go from ${from} to ${to}`);
  }
}

export function assertApplicationTransition(
  from: ArtistApplicationStatus,
  to: ArtistApplicationStatus,
): void {
  if (!canTransition(APPLICATION_TRANSITIONS, from, to)) {
    throw new Error(`Application cannot go from ${from} to ${to}`);
  }
}

export function assertSlotTransition(
  from: OpportunitySlotStatus,
  to: OpportunitySlotStatus,
): void {
  if (!canTransition(SLOT_TRANSITIONS, from, to)) {
    throw new Error(`Slot cannot go from ${from} to ${to}`);
  }
}

export const APPLICATION_ACTIVE_STATUSES: readonly ArtistApplicationStatus[] = [
  "submitted",
  "under_review",
  "shortlisted",
  "offered",
];

export const OPPORTUNITY_ARTIST_VISIBLE_STATUSES: readonly OpportunityStatus[] = [
  "open",
  "applications_closed",
  "booking",
  "confirmed",
];
