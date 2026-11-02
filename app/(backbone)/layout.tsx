import "./backbone.css";
import Link from "next/link";
import { connection } from "next/server";
import { courses, ensureSynced } from "../../lib/store.ts";

export default async function BackboneLayout({ children }: { children: React.ReactNode }) {
  await connection();
  await ensureSynced();
  return (
    <>
      <div className="demo">Demo: sample data, no real accounts connected</div>
      <header>
        <nav>
          <Link href="/inbox">Needs attention</Link>
          <Link href="/grades">Grades</Link>
          {[...courses.values()].map((c) => (
            <Link key={c.id} href={`/courses/${c.id}`}>{c.code}</Link>
          ))}
        </nav>
      </header>
      <main>{children}</main>
    </>
  );
}
