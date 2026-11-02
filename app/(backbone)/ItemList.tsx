import Link from "next/link";
import { courses, keyOf } from "../../lib/store.ts";
import type { Item } from "../../lib/types.ts";
import { markSeen } from "./actions.ts";

const fmt = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });
const daysLeft = (iso: string) => Math.ceil((Date.parse(iso) - Date.now()) / 864e5);

export function ItemList({ items, empty = "Nothing here.", seenButton = false }: { items: Item[]; empty?: string; seenButton?: boolean }) {
  if (!items.length) return <p className="muted">{empty}</p>;
  return (
    <ul className="items">
      {items.map((i) => {
        const course = i.courseId ? courses.get(i.courseId) : undefined;
        return (
          <li key={keyOf(i)} className={i.seenAt ? "seen" : ""}>
            <div>
              <span className={`badge ${i.kind}`}>{i.kind}</span>
              <strong>{i.title}</strong>
              {i.grade && <span className="score"> {i.grade.score}/{i.grade.max}</span>}
            </div>
            <div className="meta">
              {course ? <Link href={`/courses/${course.id}`}>{course.code}</Link> : <span>General</span>}
              {i.from && <span>{i.from}</span>}
              <span>{i.dueAt ? `due ${fmt(i.dueAt)} · ${daysLeft(i.dueAt)}d left` : fmt(i.occurredAt)}</span>
              <span className="src">via {i.source}</span>
            </div>
            {seenButton && !i.seenAt && (
              <form action={markSeen.bind(null, keyOf(i))}>
                <button>{i.kind === "deadline" ? "Dismiss" : "Mark seen"}</button>
              </form>
            )}
          </li>
        );
      })}
    </ul>
  );
}
