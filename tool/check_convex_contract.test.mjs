import assert from "node:assert/strict";
import test from "node:test";

import {
  contractProblems,
  deploymentNameFromUrl,
  functionSpecArgs,
  requiredClientFields,
  requiredClientFunctions,
} from "./check_convex_contract.mjs";

function completeFunction(identifier, functionType) {
  const entry = { identifier, functionType };
  for (const [
    requiredIdentifier,
    surface,
    fieldName,
    optional,
  ] of requiredClientFields) {
    if (requiredIdentifier !== identifier) continue;
    const field = { fieldType: { type: "string" }, optional };
    if (surface === "args") {
      entry.args ??= { type: "object", value: {} };
      entry.args.value[fieldName] = field;
    } else if (surface === "arrayReturn") {
      entry.returns ??= { type: "array", value: { type: "object", value: {} } };
      entry.returns.value.value[fieldName] = field;
    } else if (
      identifier === "bands.js:bySlug" || identifier === "bookingsRead.js:get"
    ) {
      entry.returns ??= {
        type: "union",
        value: [
          { type: "object", value: {} },
          { type: "null" },
        ],
      };
      entry.returns.value[0].value[fieldName] = field;
    } else {
      entry.returns ??= { type: "object", value: {} };
      entry.returns.value[fieldName] = field;
    }
  }
  return entry;
}

test("extracts a Convex deployment name from its configured URL", () => {
  assert.equal(
    deploymentNameFromUrl("https://brilliant-cardinal-773.convex.cloud"),
    "brilliant-cardinal-773",
  );
  assert.throws(
    () => deploymentNameFromUrl("https://example.com"),
    /Invalid Convex deployment URL/,
  );
});

test("lets a CI deploy key select its own deployment", () => {
  assert.deepEqual(functionSpecArgs("decisive-iguana-759", undefined), [
    "convex",
    "function-spec",
    "--deployment",
    "decisive-iguana-759",
  ]);
  assert.deepEqual(functionSpecArgs("decisive-iguana-759", "prod:key"), [
    "convex",
    "function-spec",
  ]);
});

test("accepts a deployment with every required client invitation function", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => completeFunction(identifier, functionType),
  );

  assert.deepEqual(contractProblems(url, { url, functions }), []);
});

test("reports a deployment missing gigs:feedV2", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions)
    .map(([identifier, functionType]) =>
      completeFunction(identifier, functionType),
    )
    .filter((entry) => entry.identifier !== "gigs.js:feedV2");

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "missing gigs.js:feedV2",
  ]);
});

test("reports a deployment missing venues:resolvePublic", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions)
    .map(([identifier, functionType]) =>
      completeFunction(identifier, functionType),
    )
    .filter((entry) => entry.identifier !== "venues.js:resolvePublic");

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "missing venues.js:resolvePublic",
  ]);
});

test("reports a deployment missing organizations:addPhoto", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions)
    .map(([identifier, functionType]) =>
      completeFunction(identifier, functionType),
    )
    .filter((entry) => entry.identifier !== "organizations.js:addPhoto");

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "missing organizations.js:addPhoto",
  ]);
});

test("reports a deployment missing talentOpportunitiesRead:browse", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions)
    .map(([identifier, functionType]) =>
      completeFunction(identifier, functionType),
    )
    .filter((entry) => entry.identifier !== "talentOpportunitiesRead.js:browse");

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "missing talentOpportunitiesRead.js:browse",
  ]);
});

test("reports missing, mistyped, and wrong-deployment functions", () => {
  const problems = contractProblems(
    "https://decisive-iguana-759.convex.cloud",
    {
      url: "https://brilliant-cardinal-773.convex.cloud",
      functions: [
        {
          identifier: "users.js:setProfileTutorialCompleted",
          functionType: "Query",
        },
      ],
    },
  );

  assert.deepEqual(problems, [
    "function metadata came from https://brilliant-cardinal-773.convex.cloud, expected https://decisive-iguana-759.convex.cloud",
    "users.js:setProfileTutorialCompleted is Query, expected Mutation",
    "missing users.js:updateFanOnboarding",
    "missing bandInvites.js:manage",
    "missing bandInvites.js:resolve",
    "missing bandInvites.js:create",
    "missing bandInvites.js:rotate",
    "missing bandInvites.js:revoke",
    "missing bandInvites.js:accept",
    "missing gigs.js:resolvePerformerInvite",
    "missing gigs.js:claimPerformerInvite",
    "missing gigs.js:resolvePublic",
    "missing gigs.js:feedV2",
    "missing gigs.js:goingCounts",
    "missing gigs.js:doorRoster",
    "missing gigs.js:checkInTicket",
    "missing venues.js:create",
    "missing bands.js:bySlug",
    "missing bands.js:archive",
    "missing bands.js:archiveStatus",
    "missing bands.js:setBandAvatar",
    "missing bands.js:clearBandAvatar",
    "missing bands.js:setBandBanner",
    "missing bands.js:clearBandBanner",
    "missing media.js:addMedia",
    "missing media.js:forBand",
    "missing media.js:moveWithinKind",
    "missing interactions.js:ticketForGig",
    "missing organizationApplications.js:mine",
    "missing organizationApplications.js:saveDraft",
    "missing organizationApplications.js:submit",
    "missing organizationApplications.js:attachDocument",
    "missing organizationApplications.js:generateDocumentUploadUrl",
    "missing organizations.js:mine",
    "missing organizations.js:bySlug",
    "missing organizations.js:dashboard",
    "missing organizations.js:addPhoto",
    "missing organizationMembers.js:resolveInvite",
    "missing organizationMembers.js:acceptInvite",
    "missing venues.js:resolvePublic",
    "missing venues.js:privateDetail",
    "missing admin.js:me",
    "missing talentOpportunities.js:create",
    "missing talentOpportunities.js:update",
    "missing talentOpportunities.js:open",
    "missing talentOpportunities.js:closeApplications",
    "missing talentOpportunities.js:reopen",
    "missing talentOpportunities.js:cancel",
    "missing talentOpportunities.js:deleteDraft",
    "missing talentOpportunities.js:duplicate",
    "missing talentOpportunities.js:inviteBand",
    "missing talentOpportunities.js:uninviteBand",
    "missing talentOpportunitiesRead.js:browse",
    "missing talentOpportunitiesRead.js:invitedFor",
    "missing talentOpportunitiesRead.js:resolvePublic",
    "missing talentOpportunitiesRead.js:manageForOrganization",
    "missing talentOpportunitiesRead.js:get",
    "missing artistApplications.js:apply",
    "missing artistApplications.js:withdraw",
    "missing artistApplications.js:review",
    "missing artistApplications.js:forOpportunity",
    "missing artistApplications.js:forBand",
    "missing artistApplications.js:mine",
    "missing gigs.js:writePolicy",
    "missing bookings.js:sendOffer",
    "missing bookings.js:withdrawOffer",
    "missing bookings.js:respond",
    "missing bookings.js:cancel",
    "missing bookingsRead.js:get",
    "missing bookingsRead.js:forOrganization",
    "missing bookingsRead.js:forBand",
    "missing reviews.js:submit",
    "missing reviews.js:forBooking",
    "missing reviews.js:forBand",
    "missing reviews.js:forOrganization",
  ]);
});

test("reports missing client fields on otherwise present functions", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => completeFunction(identifier, functionType),
  );
  const media = functions.find(
    (entry) => entry.identifier === "media.js:forBand",
  );
  delete media.returns.value.value.thumbnailUrl;

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "media.js:forBand is missing arrayReturn.thumbnailUrl",
  ]);
});

test("reports missing client fields on nullable union returns", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => completeFunction(identifier, functionType),
  );
  const bySlug = functions.find(
    (entry) => entry.identifier === "bands.js:bySlug",
  );
  delete bySlug.returns.value[0].value.avatarUrl;

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "bands.js:bySlug is missing return.avatarUrl",
  ]);
});

test("reports missing booking fields on nullable union returns", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => completeFunction(identifier, functionType),
  );
  const booking = functions.find(
    (entry) => entry.identifier === "bookingsRead.js:get",
  );
  delete booking.returns.value[0].value.currentOffer;

  assert.deepEqual(contractProblems(url, { url, functions }), [
    "bookingsRead.js:get is missing return.currentOffer",
  ]);
});
