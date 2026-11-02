import type { Connector } from "../types.ts";

// Demo: fails on purpose to show the broken-connection banner (the likely real-world case without IT approval).
export const teams: Connector = {
  source: "teams",
  async fetch() {
    throw new Error("Your university requires admin approval to read Teams channel messages.");
  },
};
