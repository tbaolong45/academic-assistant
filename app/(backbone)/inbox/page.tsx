import { connection } from "next/server";
import { connections, ensureSynced, needsAttention } from "../../../lib/store.ts";
import { syncNow } from "../actions.ts";
import { ItemList } from "../ItemList.tsx";

export default async function Home() {
  await connection();
  await ensureSynced();
  const a = needsAttention();
  return (
    <>
      <section className="health">
        {[...connections.values()].map((c) => (
          <div key={c.source} className={`conn ${c.status}`} title={c.lastError}>
            <strong>{c.source}</strong>{" "}
            {c.status === "ok" ? `synced ${new Date(c.lastSyncedAt!).toLocaleTimeString("en-GB", { timeStyle: "short" })}` : "connection broken"}
            {c.lastError && <div className="err">{c.lastError}</div>}
          </div>
        ))}
        <form action={syncNow}><button>Sync now</button></form>
      </section>

      <h1>Needs attention</h1>
      <h2>Due in the next 14 days</h2>
      <ItemList items={a.deadlines} empty="No deadlines in the next 14 days." seenButton />
      <h2>New grades</h2>
      <ItemList items={a.grades} empty="No new grades." seenButton />
      <h2>Announcements</h2>
      <ItemList items={a.announcements} empty="No new announcements." seenButton />
      <h2>Messages</h2>
      <ItemList items={a.messages} empty="No new messages." seenButton />
    </>
  );
}
