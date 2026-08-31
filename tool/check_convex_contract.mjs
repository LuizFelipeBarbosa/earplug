import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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
  "gigs.js:doorRoster": "Query",
  "gigs.js:checkInTicket": "Mutation",
  "venues.js:create": "Mutation",
  "bands.js:bySlug": "Query",
  "bands.js:archive": "Mutation",
  "interactions.js:ticketForGig": "Mutation",
});

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

export function contractProblems(expectedUrl, specification) {
  const problems = [];
  if (specification.url !== expectedUrl) {
    problems.push(
      `function metadata came from ${specification.url ?? "an unknown URL"}, ` +
        `expected ${expectedUrl}`,
    );
  }

  const functions = new Map(
    (specification.functions ?? []).map((entry) => [
      entry.identifier,
      entry.functionType,
    ]),
  );
  for (const [identifier, expectedType] of Object.entries(
    requiredClientFunctions,
  )) {
    const actualType = functions.get(identifier);
    if (actualType === undefined) {
      problems.push(`missing ${identifier}`);
    } else if (actualType !== expectedType) {
      problems.push(`${identifier} is ${actualType}, expected ${expectedType}`);
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
    ["convex", "function-spec", "--deployment", deploymentName],
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
