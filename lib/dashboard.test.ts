import { test } from "node:test";
import assert from "node:assert/strict";
import { band, getSubject, runningGrade, stillToCome, thisWeek } from "./dashboard.ts";

test("running grade = weighted average of completed assessments only", () => {
  assert.equal(runningGrade(getSubject("linear-algebra")!), 80.6); // (4*85+4*72+10*90+30*78)/48
  assert.equal(runningGrade(getSubject("intro-to-ai")!), 85.9);
  assert.equal(runningGrade(getSubject("advanced-python")!), 83);
});

test("still to come = weight of upcoming assessments", () => {
  assert.deepEqual(["linear-algebra", "intro-to-ai", "advanced-python"].map((id) => stillToCome(getSubject(id)!)), [52, 60, 77]);
});

test("shade bands", () => {
  assert.deepEqual([3, 4, 5, 12, 15, 20, 30, 35, 40].map(band), [0, 0, 1, 1, 1, 2, 2, 3, 3]);
});

test("this week = next 3 upcoming across courses, soonest first", () => {
  assert.deepEqual(thisWeek().map((x) => `${x.subject.id}/${x.assessment.id}`), ["linear-algebra/a2", "intro-to-ai/mid", "advanced-python/a2"]);
});
