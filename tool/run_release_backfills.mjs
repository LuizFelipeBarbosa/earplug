import { spawnSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const DEFAULT_TIMEOUT_SECONDS = 1200;
const POLL_INTERVAL_MS = 5000;

function convexRunArgs(functionName, { prod = false } = {}) {
  const args = ["convex", "run", functionName, "{}"];
  if (prod) args.push("--prod");
  return args;
}

export function argsFor(flags = {}) {
  return convexRunArgs("migrations:runReleaseBackfills", flags);
}

export function statusArgsFor(flags = {}) {
  return convexRunArgs("migrations:releaseBackfillStatus", flags);
}

export function parseStatus(json) {
  if (!Array.isArray(json)) {
    throw new Error("Release backfill status must be a JSON array");
  }
  const failed = json
    .filter((entry) => entry.state === "failed")
    .map((entry) => entry.name);
  const pending = json
    .filter((entry) => entry.isDone !== true && entry.state !== "failed")
    .map((entry) => entry.name);
  return {
    done: json.every((entry) => entry.isDone === true),
    failed,
    pending,
  };
}

function parseFlags(argv) {
  let prod = false;
  let timeoutSeconds = DEFAULT_TIMEOUT_SECONDS;
  for (let index = 0; index < argv.length; index++) {
    const arg = argv[index];
    if (arg === "--prod") {
      prod = true;
      continue;
    }
    if (arg === "--timeout-seconds") {
      const value = argv[++index];
      timeoutSeconds = Number(value);
      if (!Number.isFinite(timeoutSeconds) || timeoutSeconds <= 0) {
        throw new Error("--timeout-seconds must be a positive number");
      }
      continue;
    }
    throw new Error(
      `Unknown argument: ${arg}\nUsage: node tool/run_release_backfills.mjs [--prod] [--timeout-seconds N]`,
    );
  }
  return { prod, timeoutSeconds };
}

function sleep(ms) {
  return new Promise((resolvePromise) => setTimeout(resolvePromise, ms));
}

async function run(argv) {
  const flags = parseFlags(argv);
  const toolDirectory = dirname(fileURLToPath(import.meta.url));
  const repositoryRoot = resolve(toolDirectory, "..");
  const executable = process.platform === "win32" ? "npx.cmd" : "npx";
  const kickoff = spawnSync(executable, argsFor(flags), {
    cwd: repositoryRoot,
    stdio: "inherit",
  });
  if (kickoff.error) throw kickoff.error;
  if (kickoff.status !== 0) {
    throw new Error("Could not start the release backfill runner");
  }

  const deadline = Date.now() + flags.timeoutSeconds * 1000;
  let pending = [];
  while (true) {
    const statusResult = spawnSync(executable, statusArgsFor(flags), {
      cwd: repositoryRoot,
      encoding: "utf8",
      maxBuffer: 10 * 1024 * 1024,
      stdio: ["ignore", "pipe", "pipe"],
    });
    if (statusResult.error) throw statusResult.error;
    if (statusResult.status !== 0) {
      throw new Error(
        statusResult.stderr.trim() || "Could not read release backfill status",
      );
    }

    const statuses = JSON.parse(statusResult.stdout);
    const parsed = parseStatus(statuses);
    if (parsed.failed.length > 0) {
      const details = statuses
        .filter((entry) => entry.state === "failed")
        .map((entry) =>
          entry.error ? `${entry.name}: ${entry.error}` : entry.name,
        );
      throw new Error(`Release backfills failed:\n${details.join("\n")}`);
    }
    if (parsed.done) {
      console.log("Release backfills completed successfully.");
      return;
    }

    pending = parsed.pending;
    const remainingMs = deadline - Date.now();
    if (remainingMs <= 0) {
      throw new Error(
        `Release backfills timed out; still pending: ${pending.join(", ")}`,
      );
    }
    await sleep(Math.min(POLL_INTERVAL_MS, remainingMs));
  }
}

const invokedPath = process.argv[1]
  ? pathToFileURL(resolve(process.argv[1])).href
  : null;
if (invokedPath === import.meta.url) {
  run(process.argv.slice(2)).catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
