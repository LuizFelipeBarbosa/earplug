/* eslint-disable */
/**
 * Generated `api` utility.
 *
 * THIS CODE IS AUTOMATICALLY GENERATED.
 *
 * To regenerate, run `npx convex dev`.
 * @module
 */

import type * as analytics from "../analytics.js";
import type * as bandInvites from "../bandInvites.js";
import type * as bands from "../bands.js";
import type * as clerkBackfill from "../clerkBackfill.js";
import type * as crons from "../crons.js";
import type * as gigs from "../gigs.js";
import type * as http from "../http.js";
import type * as interactions from "../interactions.js";
import type * as lib_clerkUser from "../lib/clerkUser.js";
import type * as lib_discovery from "../lib/discovery.js";
import type * as lib_helpers from "../lib/helpers.js";
import type * as maintenance from "../maintenance.js";
import type * as media from "../media.js";
import type * as migrations from "../migrations.js";
import type * as seed from "../seed.js";
import type * as users from "../users.js";
import type * as venues from "../venues.js";

import type {
  ApiFromModules,
  FilterApi,
  FunctionReference,
} from "convex/server";

declare const fullApi: ApiFromModules<{
  analytics: typeof analytics;
  bandInvites: typeof bandInvites;
  bands: typeof bands;
  clerkBackfill: typeof clerkBackfill;
  crons: typeof crons;
  gigs: typeof gigs;
  http: typeof http;
  interactions: typeof interactions;
  "lib/clerkUser": typeof lib_clerkUser;
  "lib/discovery": typeof lib_discovery;
  "lib/helpers": typeof lib_helpers;
  maintenance: typeof maintenance;
  media: typeof media;
  migrations: typeof migrations;
  seed: typeof seed;
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
