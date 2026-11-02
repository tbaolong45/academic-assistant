import { notFound } from "next/navigation";
import { connection } from "next/server";
import { courseItems, courses, ensureSynced } from "../../../../lib/store.ts";
import type { Kind } from "../../../../lib/types.ts";
import { ItemList } from "../../ItemList.tsx";

const sections: [Kind, string][] = [
  ["deadline", "Deadlines"],
  ["grade", "Grades"],
  ["announcement", "Announcements"],
  ["message", "Messages"],
  ["file", "Materials"],
];

export default async function CoursePage({ params }: { params: Promise<{ id: string }> }) {
  await connection();
  await ensureSynced();
  const course = courses.get((await params).id);
  if (!course) notFound();
  const all = courseItems(course.id);
  return (
    <>
      <h1>{course.code} · {course.name}</h1>
      {sections.map(([kind, label]) => (
        <section key={kind}>
          <h2>{label}</h2>
          <ItemList items={all.filter((i) => i.kind === kind)} />
        </section>
      ))}
    </>
  );
}
