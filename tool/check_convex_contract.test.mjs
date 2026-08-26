import assert from "node:assert/strict";
import test from "node:test";

import {
  contractProblems,
  deploymentNameFromUrl,
  requiredClientFunctions,
} from "./check_convex_contract.mjs";

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

test("accepts a deployment with every required client mutation", () => {
  const url = "https://brilliant-cardinal-773.convex.cloud";
  const functions = Object.entries(requiredClientFunctions).map(
    ([identifier, functionType]) => ({ identifier, functionType }),
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
  ]);
});
