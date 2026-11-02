import Link from "next/link";
import { notFound } from "next/navigation";
import { connection } from "next/server";
import { getSubject } from "../../../../lib/dashboard.ts";
import { ScoreChart } from "./ScoreChart.tsx";
import s from "./subject.module.css";

const tabs = [
  ["scores", "Scores"],
  ["assignments", "Assignments"],
  ["materials", "Lectures & Material"],
  ["announcements", "Announcements"],
] as const;

const fmt = (iso: string) => new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" });

export default async function SubjectPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<{ tab?: string }> }) {
  await connection();
  const subject = getSubject((await params).id);
  if (!subject) notFound();
  const q = (await searchParams).tab;
  const tab = tabs.find(([id]) => id === q)?.[0] ?? "scores";

  return (
    <div className={`hue-${subject.hue}`}>
      <Link href="/" className={s.back}>← Courses</Link>
      <header className={s.header}>
        <h1 className={s.title}>{subject.name}</h1>
        <p className={s.code}>{subject.code}</p>
      </header>

      <nav className={s.tabs} aria-label="Course sections">
        {tabs.map(([id, label]) => (
          <Link key={id} href={`?tab=${id}`} scroll={false} replace className={s.tab} aria-current={id === tab ? "page" : undefined}>
            {label}
          </Link>
        ))}
      </nav>

      {tab === "scores" && <ScoreChart subject={subject} />}

      {tab === "assignments" && (
        <ul className={s.list}>
          {subject.assignments.map((x) => (
            <li key={x.title} className={s.row}>
              <div className={s.main}>
                <p className={s.name}>{x.title}</p>
                <p className={s.meta}>Due {fmt(x.due)}</p>
              </div>
              <span className={`${s.pill} ${x.status === "Open" ? s.open : ""}`}>{x.status}</span>
            </li>
          ))}
        </ul>
      )}

      {tab === "materials" && (
        <ul className={s.list}>
          {subject.materials.map((x) => (
            <li key={x.title} className={s.row}>
              <div className={s.main}>
                <p className={s.name}>{x.title}</p>
                <p className={s.meta}>{fmt(x.date)}</p>
              </div>
              <span className={s.tag}>{x.kind}</span>
            </li>
          ))}
        </ul>
      )}

      {tab === "announcements" && (
        <ul className={s.list}>
          {subject.announcements.map((x) => (
            <li key={x.title} className={s.row}>
              <div className={s.main}>
                <p className={s.name}>{x.title}</p>
                <p className={s.meta}>{x.from} · {fmt(x.date)}</p>
              </div>
              <span className={`${s.tag} ${s.source}`} data-source={x.source}>{x.source}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
