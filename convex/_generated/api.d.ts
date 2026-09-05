/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as admin from "../admin.js";
import type * as analytics from "../analytics.js";
import type * as artistApplications from "../artistApplications.js";
import type * as bandInvites from "../bandInvites.js";
import type * as bands from "../bands.js";
import type * as bookings from "../bookings.js";
import type * as bookingsRead from "../bookingsRead.js";
import type * as clock from "../clock.js";
import type * as crons from "../crons.js";
import type * as emails from "../emails.js";
import type * as gigs from "../gigs.js";
import type * as http from "../http.js";
import type * as interactions from "../interactions.js";
import type * as lib_authz from "../lib/authz.js";
import type * as lib_bookingConfirm from "../lib/bookingConfirm.js";
import type * as lib_bookingStatus from "../lib/bookingStatus.js";
import type * as lib_cancellationPolicy from "../lib/cancellationPolicy.js";
import type * as lib_clerkUser from "../lib/clerkUser.js";
import type * as lib_discovery from "../lib/discovery.js";
import type * as lib_docCache from "../lib/docCache.js";
import type * as lib_env from "../lib/env.js";
import type * as lib_fees from "../lib/fees.js";
import type * as lib_geo from "../lib/geo.js";
import type * as lib_gigPublish from "../lib/gigPublish.js";
import type * as lib_gigWritePolicy from "../lib/gigWritePolicy.js";
import type * as lib_helpers from "../lib/helpers.js";
import type * as lib_ledger from "../lib/ledger.js";
import type * as lib_opportunityPayload from "../lib/opportunityPayload.js";
import type * as lib_opportunityStatus from "../lib/opportunityStatus.js";
import type * as lib_opportunityVisibility from "../lib/opportunityVisibility.js";
import type * as lib_paymentSchedule from "../lib/paymentSchedule.js";
import type * as lib_paymentStatus from "../lib/paymentStatus.js";
import type * as lib_reviewSummary from "../lib/reviewSummary.js";
import type * as lib_stripeAccountSync from "../lib/stripeAccountSync.js";
import type * as lib_stripeClient from "../lib/stripeClient.js";
import type * as lib_stripeSignature from "../lib/stripeSignature.js";
import type * as lib_venuePrivate from "../lib/venuePrivate.js";
import type * as lib_venueSlug from "../lib/venueSlug.js";
import type * as maintenance from "../maintenance.js";
import type * as media from "../media.js";
import type * as migrations from "../migrations.js";
import type * as organizationApplications from "../organizationApplications.js";
import type * as organizationMembers from "../organizationMembers.js";
import type * as organizations from "../organizations.js";
import type * as payments from "../payments.js";
import type * as payoutAccounts from "../payoutAccounts.js";
import type * as reviews from "../reviews.js";
import type * as seed from "../seed.js";
import type * as stripeActions from "../stripeActions.js";
import type * as stripeHandlers_accounts from "../stripeHandlers/accounts.js";
import type * as stripeHandlers_disputes from "../stripeHandlers/disputes.js";
import type * as stripeHandlers_payments from "../stripeHandlers/payments.js";
import type * as stripeWebhook from "../stripeWebhook.js";
import type * as talentOpportunities from "../talentOpportunities.js";
import type * as talentOpportunitiesRead from "../talentOpportunitiesRead.js";
import type * as users from "../users.js";
import type * as venues from "../venues.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  admin: typeof admin;
  analytics: typeof analytics;
  artistApplications: typeof artistApplications;
  bandInvites: typeof bandInvites;
  bands: typeof bands;
  bookings: typeof bookings;
  bookingsRead: typeof bookingsRead;
  clock: typeof clock;
  crons: typeof crons;
  emails: typeof emails;
  gigs: typeof gigs;
  http: typeof http;
  interactions: typeof interactions;
  "lib/authz": typeof lib_authz;
  "lib/bookingConfirm": typeof lib_bookingConfirm;
  "lib/bookingStatus": typeof lib_bookingStatus;
  "lib/cancellationPolicy": typeof lib_cancellationPolicy;
  "lib/clerkUser": typeof lib_clerkUser;
  "lib/discovery": typeof lib_discovery;
  "lib/docCache": typeof lib_docCache;
  "lib/env": typeof lib_env;
  "lib/fees": typeof lib_fees;
  "lib/geo": typeof lib_geo;
  "lib/gigPublish": typeof lib_gigPublish;
  "lib/gigWritePolicy": typeof lib_gigWritePolicy;
  "lib/helpers": typeof lib_helpers;
  "lib/ledger": typeof lib_ledger;
  "lib/opportunityPayload": typeof lib_opportunityPayload;
  "lib/opportunityStatus": typeof lib_opportunityStatus;
  "lib/opportunityVisibility": typeof lib_opportunityVisibility;
  "lib/paymentSchedule": typeof lib_paymentSchedule;
  "lib/paymentStatus": typeof lib_paymentStatus;
  "lib/reviewSummary": typeof lib_reviewSummary;
  "lib/stripeAccountSync": typeof lib_stripeAccountSync;
  "lib/stripeClient": typeof lib_stripeClient;
  "lib/stripeSignature": typeof lib_stripeSignature;
  "lib/venuePrivate": typeof lib_venuePrivate;
  "lib/venueSlug": typeof lib_venueSlug;
  maintenance: typeof maintenance;
  media: typeof media;
  migrations: typeof migrations;
  organizationApplications: typeof organizationApplications;
  organizationMembers: typeof organizationMembers;
  organizations: typeof organizations;
  payments: typeof payments;
  payoutAccounts: typeof payoutAccounts;
  reviews: typeof reviews;
  seed: typeof seed;
  stripeActions: typeof stripeActions;
  "stripeHandlers/accounts": typeof stripeHandlers_accounts;
  "stripeHandlers/disputes": typeof stripeHandlers_disputes;
  "stripeHandlers/payments": typeof stripeHandlers_payments;
  stripeWebhook: typeof stripeWebhook;
  talentOpportunities: typeof talentOpportunities;
  talentOpportunitiesRead: typeof talentOpportunitiesRead;
  users: typeof users;
  venues: typeof venues;
}>;

/**
 * A utility for referencing Convex functions in your app's public API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = api.myModule.myFunction;
 * ```
 */
export declare const api: FilterApi<
  typeof fullApi,
  FunctionReference<any, "public">
>;

/**
 * A utility for referencing Convex functions in your app's internal API.
 *
 * Usage:
 * ```js
 * const myFunctionReference = internal.myModule.myFunction;
 * ```
 */
export declare const internal: FilterApi<
  typeof fullApi,
  FunctionReference<any, "internal">
>;

export declare const components: {
  migrations: import("@convex-dev/migrations/_generated/component.js").ComponentApi<"migrations">;
};
