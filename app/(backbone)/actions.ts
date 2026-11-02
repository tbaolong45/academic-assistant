"use server";
import { revalidatePath } from "next/cache";
import { items, sync } from "../../lib/store.ts";

export async function markSeen(key: string) {
  const item = items.get(key);
  if (item) item.seenAt = new Date().toISOString();
  revalidatePath("/", "layout");
}

export async function syncNow() {
  await sync();
  revalidatePath("/", "layout");
}
