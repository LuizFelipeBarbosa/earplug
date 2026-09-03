import assert from "node:assert/strict";
import test from "node:test";

import {
  argsFor,
  parseStatus,
  statusArgsFor,
} from "./run_release_backfills.mjs";

test("parseStatus reports a fully completed release", () => {
  assert.deepEqual(
    parseStatus([
      { name: "migrations:first", isDone: true, state: "success" },
      { name: "migrations:second", isDone: true, state: "success" },
    ]),
    { done: true, failed: [], pending: [] },
  );
});

test("parseStatus reports an in-progress migration as pending", () => {
  assert.deepEqual(
    parseStatus([
      { name: "migrations:first", isDone: true, state: "success" },
      { name: "migrations:second", isDone: false, state: "inProgress" },
    ]),
    {
      done: false,
      failed: [],
      pending: ["migrations:second"],
    },
  );
});

test("parseStatus reports a failed migration outside pending", () => {
  assert.deepEqual(
    parseStatus([
      { name: "migrations:first", isDone: true, state: "success" },
      { name: "migrations:second", isDone: false, state: "failed" },
    ]),
    {
      done: false,
      failed: ["migrations:second"],
      pending: [],
    },
  );
});

test("builds runner and status arguments with and without production", () => {
  assert.deepEqual(argsFor(), [
    "convex",
    "run",
    "migrations:runReleaseBackfills",
    "{}",
  ]);
  assert.deepEqual(argsFor({ prod: true }), [
    "convex",
    "run",
    "migrations:runReleaseBackfills",
    "{}",
    "--prod",
  ]);
  assert.deepEqual(statusArgsFor(), [
    "convex",
    "run",
    "migrations:releaseBackfillStatus",
    "{}",
  ]);
  assert.deepEqual(statusArgsFor({ prod: true }), [
    "convex",
    "run",
    "migrations:releaseBackfillStatus",
    "{}",
    "--prod",
  ]);
});
