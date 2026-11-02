import { days, type Connector } from "../types.ts";

// Demo: sample data. Real version reads personal Gmail over IMAP with an app password.
export const gmail: Connector = {
  source: "gmail",
  async fetch() {
    return {
      items: [
        { source: "gmail", externalId: "m1", kind: "message", title: "Fwd: BIO150 field trip consent form", from: "Student Affairs", occurredAt: days(-2) },
      ],
    };
  },
};
