import Link from "next/link";
import { connection } from "next/server";
import { allGrades, courses, ensureSynced } from "../../../lib/store.ts";

const pct = (s: number, m: number) => Math.round((s / m) * 100);

export default async function GradesPage() {
  await connection();
  await ensureSynced();
  const grades = allGrades();
  return (
    <>
      <h1>Grades</h1>
      {[...courses.values()].map((c) => {
        const mine = grades.filter((g) => g.courseId === c.id);
        if (!mine.length) return null;
        const avg = pct(mine.reduce((s, g) => s + g.grade!.score, 0), mine.reduce((s, g) => s + g.grade!.max, 0));
        return (
          <section key={c.id}>
            <h2><Link href={`/courses/${c.id}`}>{c.code} · {c.name}</Link> <span className="muted">overall {avg}%</span></h2>
            <table>
              <tbody>
                {mine.map((g) => (
                  <tr key={g.externalId}>
                    <td>{g.title}</td>
                    <td className="num">{g.grade!.score}/{g.grade!.max}</td>
                    <td className="num">{pct(g.grade!.score, g.grade!.max)}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </section>
        );
      })}
    </>
  );
}
