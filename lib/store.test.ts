import { test } from "node:test";
import assert from "node:assert/strict";
import { connections, courses, items, keyOf, matchCourse, needsAttention, sync } from "./store.ts";

test("syncing twice creates no duplicates and keeps seen state", async () => {
  await sync();
  const n = items.size;
  const first = items.get("moodle:a1")!;
  first.seenAt = "2026-01-01T00:00:00Z";
  await sync();
  assert.equal(items.size, n);
  assert.equal(items.get(keyOf(first))?.seenAt, "2026-01-01T00:00:00Z");
});

test("mail is matched to a course by its code", async () => {
  await sync();
  assert.equal(matchCourse("Re: math210 homework", courses.values()), "math210");
  assert.equal(items.get("outlook:o1")?.courseId, "cs201");
  assert.equal(items.get("outlook:o2")?.courseId, undefined);
});

test("broken connector is reported, others still sync", async () => {
  await sync();
  assert.equal(connections.get("teams")?.status, "error");
  assert.equal(connections.get("gmail")?.status, "ok");
});

test("needs attention: only deadlines within 14 days", async () => {
  await sync();
  const ids = needsAttention().deadlines.map((d) => d.externalId);
  assert.ok(!ids.includes("a4"));
  assert.ok(ids.includes("a2"));
});
