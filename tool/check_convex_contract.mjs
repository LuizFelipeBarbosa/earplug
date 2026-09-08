import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Values are "Query" | "Mutation" | "Action", as reported by npx convex function-spec.
export const requiredClientFunctions = Object.freeze({
  "users.js:setProfileTutorialCompleted": "Mutation",
  "users.js:updateFanOnboarding": "Mutation",
  "bandInvites.js:manage": "Query",
  "bandInvites.js:resolve": "Query",
  "bandInvites.js:create": "Mutation",
  "bandInvites.js:rotate": "Mutation",
  "bandInvites.js:revoke": "Mutation",
  "bandInvites.js:accept": "Mutation",
  "gigs.js:resolvePerformerInvite": "Query",
  "gigs.js:claimPerformerInvite": "Mutation",
  "gigs.js:resolvePublic": "Query",
  "gigs.js:feedV2": "Query",
  "gigs.js:goingCounts": "Query",
  "gigs.js:doorRoster": "Query",
  "gigs.js:checkInTicket": "Mutation",
  "venues.js:create": "Mutation",
  "bands.js:bySlug": "Query",
  "bands.js:archive": "Mutation",
  "bands.js:archiveStatus": "Query",
  "bands.js:setBandAvatar": "Mutation",
  "bands.js:clearBandAvatar": "Mutation",
  "bands.js:setBandBanner": "Mutation",
  "bands.js:clearBandBanner": "Mutation",
  "media.js:addMedia": "Mutation",
  "media.js:forBand": "Query",
  "media.js:moveWithinKind": "Mutation",
  "interactions.js:ticketForGig": "Mutation",
  "organizationApplications.js:mine": "Query",
  "organizationApplications.js:saveDraft": "Mutation",
  "organizationApplications.js:submit": "Mutation",
  "organizationApplications.js:attachDocument": "Mutation",
  "organizationApplications.js:generateDocumentUploadUrl": "Mutation",
  "organizations.js:mine": "Query",
  "organizations.js:bySlug": "Query",
  "organizations.js:dashboard": "Query",
  "organizations.js:addPhoto": "Mutation",
  "organizationMembers.js:resolveInvite": "Query",
  "organizationMembers.js:acceptInvite": "Mutation",
  "venues.js:resolvePublic": "Query",
  "venues.js:privateDetail": "Query",
  "admin.js:me": "Query",
  "admin.js:bookings": "Query",
  "admin.js:suspendOrganization": "Mutation",
  "talentOpportunities.js:create": "Mutation",
  "talentOpportunities.js:update": "Mutation",
  "talentOpportunities.js:open": "Mutation",
  "talentOpportunities.js:closeApplications": "Mutation",
  "talentOpportunities.js:reopen": "Mutation",
  "talentOpportunities.js:cancel": "Mutation",
  "talentOpportunities.js:deleteDraft": "Mutation",
  "talentOpportunities.js:duplicate": "Mutation",
  "talentOpportunities.js:inviteBand": "Mutation",
  "talentOpportunities.js:uninviteBand": "Mutation",
  "talentOpportunitiesRead.js:browse": "Query",
  "talentOpportunitiesRead.js:invitedFor": "Query",
  "talentOpportunitiesRead.js:resolvePublic": "Query",
  "talentOpportunitiesRead.js:manageForOrganization": "Query",
  "talentOpportunitiesRead.js:get": "Query",
  "artistApplications.js:apply": "Mutation",
  "artistApplications.js:withdraw": "Mutation",
  "artistApplications.js:review": "Mutation",
  "artistApplications.js:forOpportunity": "Query",
  "artistApplications.js:forBand": "Query",
  "artistApplications.js:mine": "Query",
  "gigs.js:writePolicy": "Query",
  "bookings.js:sendOffer": "Mutation",
  "bookings.js:withdrawOffer": "Mutation",
  "bookings.js:respond": "Mutation",
  "bookings.js:cancel": "Mutation",
  "bookingsRead.js:get": "Query",
  "bookingsRead.js:forOrganization": "Query",
  "bookingsRead.js:forBand": "Query",
  "reviews.js:submit": "Mutation",
  "reviews.js:forBooking": "Query",
  "reviews.js:forBand": "Query",
  "reviews.js:forOrganization": "Query",
  "stripeActions.js:startBandOnboarding": "Action",
  "stripeActions.js:startOrganizationOnboarding": "Action",
  "stripeActions.js:refreshBandAccountStatus": "Action",
  "stripeActions.js:refreshOrganizationAccountStatus": "Action",
  "stripeActions.js:bandExpressDashboardLink": "Action",
  "stripeActions.js:organizationExpressDashboardLink": "Action",
  "payoutAccounts.js:bandPayoutStatus": "Query",
  "payoutAccounts.js:organizationStripeStatus": "Query",
  "payments.js:startInstallmentCheckout": "Action",
  "payments.js:paymentsForBooking": "Query",
  "payments.js:checkoutStatus": "Query",
  "payouts.js:payoutsForBooking": "Query",
  "payouts.js:payoutsForBand": "Query",
  "refunds.js:previewCancellation": "Query",
  "refunds.js:refundsForBooking": "Query",
  "tickets.js:reserve": "Mutation",
  "tickets.js:cancelReservation": "Mutation",
  "tickets.js:myTickets": "Query",
  "tickets.js:get": "Query",
  "tickets.js:orderStatus": "Query",
  "tickets.js:salesForGig": "Query",
  "ticketCheckout.js:startCheckout": "Action",
  "ticketCheckout.js:cancelOrder": "Action",
  "ticketsDoor.js:checkIn": "Mutation",
  "ticketsDoor.js:doorRoster": "Query",
  "finance.js:overview": "Query",
  "finance.js:transactions": "Query",
  "financeActions.js:refreshBalance": "Action",
  "financeActions.js:exportStatement": "Action",
  "analytics.js:artistInsights": "Query",
  "analytics.js:myBandInsights": "Query",
  "talentOpportunities.js:updateTicketing": "Mutation",
  "features.js:flags": "Query",
  "privateLocations.js:create": "Mutation",
  "privateLocations.js:update": "Mutation",
  "privateLocations.js:remove": "Mutation",
  "privateLocations.js:forOrganization": "Query",
  "disputes.js:open": "Mutation",
  "disputes.js:forBooking": "Query",
  "disputes.js:listOpen": "Query",
  "disputes.js:startReview": "Mutation",
  "disputes.js:resolve": "Mutation",
  "safety.js:report": "Mutation",
  "safety.js:mine": "Query",
  "safety.js:listOpen": "Query",
  "safety.js:resolve": "Mutation",
  "safety.js:forBookingAdmin": "Query",
  "venueConsents.js:request": "Mutation",
  "venueConsents.js:withdraw": "Mutation",
  "venueConsents.js:decide": "Mutation",
  "venueConsents.js:revoke": "Mutation",
  "venueConsents.js:forOpportunity": "Query",
  "venueConsents.js:forVenueOrganization": "Query",
  "payouts.js:statementForBand": "Query",
});

export const requiredClientFields = Object.freeze([
  ["media.js:addMedia", "args", "thumbnailStorageId", true],
  ["interactions.js:toggleRsvp", "args", "on", true],
  ["media.js:forBand", "arrayReturn", "thumbnailUrl", false],
  ["media.js:forBand", "arrayReturn", "isAvatar", false],
  ["media.js:forBand", "arrayReturn", "isBanner", false],
  ["bands.js:bySlug", "return", "avatarUrl", false],
  ["bands.js:bySlug", "return", "bannerUrl", false],
  ["bands.js:bySlug", "return", "reviewSummary", false],
  ["organizations.js:bySlug", "return", "reviewSummary", false],
  ["bands.js:archive", "return", "bandId", false],
  ["bands.js:archive", "return", "archivedAt", false],
  ["bands.js:archive", "return", "alreadyArchived", false],
  ["bands.js:archiveStatus", "return", "bandId", false],
  ["bands.js:archiveStatus", "return", "archivedAt", false],
  ["gigs.js:feedV2", "return", "bands", false],
  ["venues.js:list", "arrayReturn", "venueType", false],
  ["venues.js:list", "arrayReturn", "approxLocation", false],
  ["talentOpportunitiesRead.js:resolvePublic", "return", "opportunity", false],
  ["gigs.js:writePolicy", "return", "bandGigWrites", false],
  ["bookings.js:sendOffer", "args", "grossMinor", false],
  ["bookings.js:sendOffer", "args", "cancellationTemplate", false],
  ["bookings.js:respond", "args", "expectedRevision", false],
  ["bookingsRead.js:get", "return", "fee", false],
  ["bookingsRead.js:get", "return", "venue", false],
  ["bookingsRead.js:get", "return", "currentOffer", false],
  ["bookingsRead.js:forBand", "arrayReturn", "status", false],
  ...[
    "paidMinor",
    "refundedMinor",
    "paymentDueAt",
    "payoutHoldReasons",
  ].flatMap((field) => [
    ["bookingsRead.js:get", "return", field, false],
    ["bookingsRead.js:forBand", "arrayReturn", field, false],
    ["bookingsRead.js:forOrganization", "arrayReturn", field, false],
  ]),
  ["reviews.js:forBooking", "return", "canSubmit", false],
  ["reviews.js:forBand", "arrayReturn", "monthLabel", false],
  ["payments.js:paymentsForBooking", "arrayReturn", "canPay", false],
  ["payments.js:startInstallmentCheckout", "return", "url", false],
  ["refunds.js:previewCancellation", "return", "refundMinor", false],
  ["payoutAccounts.js:bandPayoutStatus", "return", "state", false],
  ["tickets.js:reserve", "return", "orderId", false],
  ["tickets.js:reserve", "return", "totalMinor", false],
  ["tickets.js:reserve", "return", "reservedUntil", false],
  ["tickets.js:orderStatus", "return", "status", false],
  ["tickets.js:myTickets", "arrayReturn", "token", false],
  ["tickets.js:myTickets", "arrayReturn", "status", false],
  ["ticketCheckout.js:startCheckout", "return", "url", false],
  ["ticketCheckout.js:startCheckout", "return", "sessionId", false],
  ["ticketsDoor.js:checkIn", "return", "kind", false],
  ["gigs.js:resolvePublic", "return", "ticketPriceMinor", true],
  ["finance.js:overview", "return", "bookings", false],
  ["finance.js:overview", "return", "tickets", false],
  ["finance.js:overview", "return", "currency", false],
  ["finance.js:overview", "return", "snapshot", false],
  ["finance.js:transactions", "return", "page", false],
  ["financeActions.js:exportStatement", "return", "csv", false],
  ["analytics.js:artistInsights", "return", "estimatedDraw", false],
  ["talentOpportunities.js:updateTicketing", "return", "revision", false],
  ["features.js:flags", "return", "privateBookings", false],
  ["privateLocations.js:create", "return", "locationId", false],
  ["safety.js:report", "return", "reportId", false],
  ["bookingsRead.js:get", "return", "privateEvent", false],
  ["bookingsRead.js:get", "return", "privateLocation", false],
  ["talentOpportunitiesRead.js:browse", "args", "mode", true],
  ["bookings.js:cancel", "args", "safety", true],
  ["talentOpportunities.js:create", "args", "privateLocationId", true],
  ["features.js:flags", "return", "disputes", false],
  ["disputes.js:open", "args", "requestedRefundMinor", true],
  ["disputes.js:open", "args", "side", true],
  ["disputes.js:resolve", "args", "refundMinor", true],
  ["disputes.js:forBooking", "arrayReturn", "status", false],
  ["disputes.js:forBooking", "arrayReturn", "resolution", true],
  ["admin.js:bookings", "args", "filter", false],
  ["bookingsRead.js:get", "return", "viewerIsPlatformAdmin", true],
  ["admin.js:suspendOrganization", "args", "note", true],
  ["features.js:flags", "return", "promoters", false],
  ["financeActions.js:exportStatement", "return", "transactions", false],
  ["financeActions.js:exportStatement", "return", "totalsByKind", false],
  ["financeActions.js:exportStatement", "return", "rows", false],
  ["talentOpportunitiesRead.js:manageForOrganization", "arrayReturn", "venueConsentStatus", true],
  ["organizations.js:dashboard", "return", "pendingVenueConsents", true],
]);

export function deploymentNameFromUrl(value) {
  const url = new URL(value);
  const suffix = ".convex.cloud";
  if (url.protocol !== "https:" || !url.hostname.endsWith(suffix)) {
    throw new Error(`Invalid Convex deployment URL: ${value}`);
  }

  const deploymentName = url.hostname.slice(0, -suffix.length);
  if (deploymentName === "" || deploymentName.includes(".")) {
    throw new Error(`Invalid Convex deployment URL: ${value}`);
  }
  return deploymentName;
}

export function functionSpecArgs(deploymentName, deployKey) {
  const args = ["convex", "function-spec"];
  if (!deployKey) args.push("--deployment", deploymentName);
  return args;
}

function returnObjectFields(validator) {
  if (validator?.type !== "union") return validator?.value;
  if (!Array.isArray(validator.value)) return undefined;
  return validator.value.find((member) => member?.type === "object")?.value;
}

export function contractProblems(expectedUrl, specification) {
  const problems = [];
  if (specification.url !== expectedUrl) {
    problems.push(
      `function metadata came from ${specification.url ?? "an unknown URL"}, ` +
        `expected ${expectedUrl}`,
    );
  }

  const functions = new Map(
    (specification.functions ?? []).map((entry) => [entry.identifier, entry]),
  );
  for (const [identifier, expectedType] of Object.entries(
    requiredClientFunctions,
  )) {
    const entry = functions.get(identifier);
    if (entry === undefined) {
      problems.push(`missing ${identifier}`);
    } else if (entry.functionType !== expectedType) {
      problems.push(
        `${identifier} is ${entry.functionType}, expected ${expectedType}`,
      );
    }
  }
  for (const [
    identifier,
    surface,
    fieldName,
    expectedOptional,
  ] of requiredClientFields) {
    const entry = functions.get(identifier);
    if (entry === undefined) continue;
    const fields =
      surface === "args"
        ? entry.args?.value
        : surface === "arrayReturn"
          ? entry.returns?.value?.value
          : returnObjectFields(entry.returns);
    const field = fields?.[fieldName];
    if (field === undefined) {
      problems.push(`${identifier} is missing ${surface}.${fieldName}`);
    } else if (field.optional !== expectedOptional) {
      problems.push(
        `${identifier} ${surface}.${fieldName} optional=${field.optional}, ` +
          `expected ${expectedOptional}`,
      );
    }
  }
  return problems;
}

function checkDeployment(environmentName) {
  if (!/^[a-z0-9_-]+$/.test(environmentName)) {
    throw new Error(`Invalid environment name: ${environmentName}`);
  }

  const toolDirectory = dirname(fileURLToPath(import.meta.url));
  const repositoryRoot = resolve(toolDirectory, "..");
  const configPath = resolve(
    repositoryRoot,
    "config",
    `${environmentName}.json`,
  );
  const config = JSON.parse(readFileSync(configPath, "utf8"));
  const expectedUrl = config.CONVEX_URL;
  if (typeof expectedUrl !== "string") {
    throw new Error(`${configPath} does not define CONVEX_URL`);
  }

  const deploymentName = deploymentNameFromUrl(expectedUrl);
  const executable = process.platform === "win32" ? "npx.cmd" : "npx";
  const result = spawnSync(
    executable,
    functionSpecArgs(deploymentName, process.env.CONVEX_DEPLOY_KEY),
    {
      cwd: repositoryRoot,
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    },
  );
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      result.stderr.trim() ||
        `Could not inspect Convex deployment ${deploymentName}`,
    );
  }

  const specification = JSON.parse(result.stdout);
  const problems = contractProblems(expectedUrl, specification);
  if (problems.length > 0) {
    throw new Error(
      [
        `Convex deployment ${deploymentName} is incompatible with the client:`,
        ...problems.map((problem) => `- ${problem}`),
        "Deploy the backend before publishing this client.",
      ].join("\n"),
    );
  }

  console.log(
    `Convex client contract verified for ${environmentName} (${deploymentName}).`,
  );
}

const invokedPath = process.argv[1]
  ? pathToFileURL(resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) {
  try {
    checkDeployment(process.argv[2] ?? process.env.EARPLUG_ENV ?? "dev");
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  }
}
