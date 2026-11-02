import Link from "next/link";
import { connection } from "next/server";
import { subjects, runningGrade, stillToCome, thisWeek } from "../../lib/dashboard.ts";
import s from "./home.module.css";

function when(iso: string, now: number) {
  const n = Math.round((Date.parse(iso) - now) / 864e5);
  const rel = n <= 0 ? "today" : n === 1 ? "tomorrow" : `in ${n} days`;
  return `${rel} · ${new Date(iso).toLocaleDateString("en-GB", { weekday: "short", day: "numeric", month: "short" })}`;
}

export default async function Home() {
  await connection();
  const now = Date.now();

  return (
    <>
      <h1 className={s.title}>Academic Assistant</h1>

      <section aria-labelledby="week">
        <h2 id="week" className={s.heading}>This week</h2>
        <ul className={s.list}>
          {thisWeek(3, now).map(({ subject, assessment }) => (
            <li key={subject.id + assessment.id}>
              <Link href={`/subjects/${subject.id}`} className={`${s.row} hue-${subject.hue}`}>
                <span className={s.marker} aria-hidden />
                <span className={s.rowMain}>
                  <span className={s.muted}>{subject.name}</span>
                  <span className={s.strong}>{assessment.name}{assessment.type !== assessment.name && <span className={s.muted}> · {assessment.type}</span>}</span>
                  <span className={s.muted}>{when(assessment.date, now)}</span>
                </span>
                <span className={s.weight}>{assessment.weight}% of grade</span>
              </Link>
            </li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="courses">
        <h2 id="courses" className={s.heading}>Your courses</h2>
        <ul className={s.list}>
          {subjects.map((subject) => {
            const grade = runningGrade(subject);
            const left = stillToCome(subject);
            const gradeText = grade === null ? "No grades yet" : `${grade.toFixed(1)}%`;
            return (
              <li key={subject.id}>
                <Link
                  href={`/subjects/${subject.id}`}
                  className={`${s.card} hue-${subject.hue}`}
                  aria-label={`${subject.name}, running grade ${gradeText}, ${left}% still to come`}
                >
                  <span className={s.cardHead}>
                    <span className={s.strong}>{subject.name}</span>
                    <span className={s.muted}>{subject.code}</span>
                  </span>
                  <span className={s.grade}>{gradeText}</span>
                  <span className={s.muted}>Running grade</span>
                  <span className={s.meter} aria-hidden>
                    <span style={{ width: `${100 - left}%` }} />
                  </span>
                  <span className={s.muted}>{100 - left}% done · {left}% of grade still to come</span>
                  <span className={s.chevron} aria-hidden>›</span>
                </Link>
              </li>
            );
          })}
        </ul>
      </section>
    </>
  );
}
