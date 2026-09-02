import assert from "node:assert/strict";
import test from "node:test";

import {
  contractProblems,
  deploymentNameFromUrl,
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
    } else if (identifier === "bands.js:bySlug") {
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

test("accepts a deployment with every required client invitation function", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => completeFunction(identifier, functionType),
  );

  assert.deepEqual(contractProblems(url, { url, functions }), []);
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
