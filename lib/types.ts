export type Source = "moodle" | "outlook" | "teams" | "gmail";
export type Kind = "deadline" | "grade" | "announcement" | "message" | "file";

export type Course = { id: string; code: string; name: string };

// One shape for everything the app shows; becomes the `items` table later.
export type Item = {
  source: Source;
  externalId: string;
  kind: Kind;
  courseId?: string;
  title: string;
  from?: string;
  url?: string;
  dueAt?: string;
  occurredAt: string;
  grade?: { score: number; max: number };
  seenAt?: string;
};

export type Connection = {
  source: Source;
  status: "ok" | "error";
  lastSyncedAt?: string;
  lastError?: string;
};

// Every source (Moodle, Outlook, Teams, Gmail, later other sites) implements this.
export type Connector = {
  source: Source;
  fetch(): Promise<{ courses?: Course[]; items: Item[] }>;
};

export const days = (n: number) => new Date(Date.now() + n * 864e5).toISOString();
