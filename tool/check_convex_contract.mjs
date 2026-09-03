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
  "organizationMembers.js:resolveInvite": "Query",
  "organizationMembers.js:acceptInvite": "Mutation",
  "venues.js:resolvePublic": "Query",
  "venues.js:privateDetail": "Query",
  "admin.js:me": "Query",
});

export const requiredClientFields = Object.freeze([
  ["media.js:addMedia", "args", "thumbnailStorageId", true],
  ["interactions.js:toggleRsvp", "args", "on", true],
  ["media.js:forBand", "arrayReturn", "thumbnailUrl", false],
  ["media.js:forBand", "arrayReturn", "isAvatar", false],
  ["media.js:forBand", "arrayReturn", "isBanner", false],
  ["bands.js:bySlug", "return", "avatarUrl", false],
  ["bands.js:bySlug", "return", "bannerUrl", false],
  ["bands.js:archive", "return", "bandId", false],
  ["bands.js:archive", "return", "archivedAt", false],
  ["bands.js:archive", "return", "alreadyArchived", false],
  ["bands.js:archiveStatus", "return", "bandId", false],
  ["bands.js:archiveStatus", "return", "archivedAt", false],
  ["gigs.js:feedV2", "return", "bands", false],
  ["venues.js:detail", "return", "approxLocation", false],
  ["venues.js:list", "arrayReturn", "approxLocation", false],
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
