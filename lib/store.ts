import type { Connection, Connector, Course, Item, Kind, Source } from "./types.ts";
import { moodle } from "./connectors/moodle.ts";
import { outlook } from "./connectors/outlook.ts";
import { teams } from "./connectors/teams.ts";
import { gmail } from "./connectors/gmail.ts";

// ponytail: in-memory store for the demo; becomes Supabase tables (items, courses, connections) in the real build.
export const courses = new Map<string, Course>();
export const items = new Map<string, Item>();
export const connections = new Map<Source, Connection>();

// Moodle first: it supplies the courses that mail and Teams items get matched to.
const connectors: Connector[] = [moodle, outlook, teams, gmail];

export const keyOf = (i: Item) => `${i.source}:${i.externalId}`;

export function matchCourse(text: string, list: Iterable<Course>) {
  const t = text.toLowerCase();
  for (const c of list) if (t.includes(c.code.toLowerCase())) return c.id;
}

// Upsert on (source, externalId): re-syncing never duplicates and keeps what the user already saw.
function upsert(item: Item) {
  const prev = items.get(keyOf(item));
  items.set(keyOf(item), {
    ...item,
    courseId: item.courseId ?? matchCourse(item.title, courses.values()),
    seenAt: prev?.seenAt ?? item.seenAt,
  });
}

export async function sync() {
  for (const c of connectors) {
    try {
      const r = await c.fetch();
      r.courses?.forEach((x) => courses.set(x.id, x));
      r.items.forEach(upsert);
      connections.set(c.source, { source: c.source, status: "ok", lastSyncedAt: new Date().toISOString() });
    } catch (e) {
      connections.set(c.source, { ...connections.get(c.source), source: c.source, status: "error", lastError: (e as Error).message });
    }
  }
}

let first: Promise<void> | undefined;
export const ensureSynced = () => (first ??= sync());

const byDate = (a: Item, b: Item) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt);
const ofKind = (kind: Kind) => [...items.values()].filter((i) => i.kind === kind);

export function needsAttention(now = Date.now()) {
  const soon = now + 14 * 864e5;
  const unseen = (k: Kind) => ofKind(k).filter((i) => !i.seenAt).sort(byDate);
  return {
    deadlines: ofKind("deadline")
      .filter((i) => !i.seenAt && Date.parse(i.dueAt!) >= now && Date.parse(i.dueAt!) <= soon)
      .sort((a, b) => Date.parse(a.dueAt!) - Date.parse(b.dueAt!)),
    grades: unseen("grade"),
    announcements: unseen("announcement"),
    messages: unseen("message"),
  };
}

export const courseItems = (courseId: string) => [...items.values()].filter((i) => i.courseId === courseId).sort(byDate);
export const allGrades = () => ofKind("grade").sort(byDate);
