import {
  APPLICATION_TRANSITIONS,
  OPPORTUNITY_TRANSITIONS,
  SLOT_TRANSITIONS,
  assertApplicationTransition,
  assertOpportunityTransition,
  assertSlotTransition,
  canTransition,
} from "./lib/opportunityStatus";
import { expectStatusTransitions } from "./statusTransitions.test-helpers";

expectStatusTransitions({
  entity: "Opportunity",
  table: OPPORTUNITY_TRANSITIONS,
  canTransition,
  assertTransition: assertOpportunityTransition,
  expected: {
    draft: ["open", "cancelled"],
    open: ["applications_closed", "cancelled", "confirmed"],
    applications_closed: ["open", "booking", "cancelled", "confirmed"],
    booking: ["confirmed", "applications_closed", "open", "cancelled"],
    confirmed: ["completed", "cancelled", "booking"],
    completed: [],
    cancelled: [],
  },
});

expectStatusTransitions({
  entity: "Application",
  table: APPLICATION_TRANSITIONS,
  canTransition,
  assertTransition: assertApplicationTransition,
  expected: {
    submitted: ["under_review", "shortlisted", "declined", "withdrawn", "expired"],
    under_review: ["shortlisted", "declined", "withdrawn", "expired"],
    shortlisted: ["offered", "declined", "withdrawn", "expired"],
    offered: ["booked", "declined", "withdrawn", "expired", "shortlisted"],
    booked: ["declined", "withdrawn"],
    declined: [],
    withdrawn: [],
    expired: [],
  },
});

expectStatusTransitions({
  entity: "Slot",
  table: SLOT_TRANSITIONS,
  canTransition,
  assertTransition: assertSlotTransition,
  expected: {
    open: ["booked", "cancelled"],
    booked: ["open", "cancelled"],
    cancelled: [],
  },
});
