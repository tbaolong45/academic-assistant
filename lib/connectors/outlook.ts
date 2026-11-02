import { days, type Connector } from "../types.ts";

// Demo: sample data. Real version reads school mail via Microsoft Graph.
export const outlook: Connector = {
  source: "outlook",
  async fetch() {
    return {
      items: [
        { source: "outlook", externalId: "o1", kind: "message", title: "CS201 – project groups announced", from: "Dr. Le", occurredAt: days(-1) },
        { source: "outlook", externalId: "o2", kind: "message", title: "Final exam timetable published", from: "Registrar's Office", occurredAt: days(-2) },
        { source: "outlook", externalId: "o3", kind: "message", title: "MATH210 office hours cancelled tomorrow", from: "Dr. Nguyen", occurredAt: days(-4) },
      ],
    };
  },
};
