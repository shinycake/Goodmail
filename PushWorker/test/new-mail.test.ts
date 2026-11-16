import { describe, expect, it } from "vitest";
import { alertPayload, decodeEncodedWords, newestOf, senderAddress, senderName } from "../src/new-mail";

describe("the alert gate", () => {
  it("titles the alert with the sender and shows the subject", () => {
    expect(alertPayload({ sender: "Dana", subject: "Lunch?" }, { accountID: "a1" })).toEqual({
      aps: { alert: { title: "Dana", body: "Lunch?" }, sound: "default", "mutable-content": 1 },
      accountID: "a1",
    });
  });

  it("shows the sender alone for an email without a subject, and clips long text", () => {
    const payload = alertPayload({ sender: "x".repeat(300), subject: "  " }, { account: "a@b", historyId: "1" }) as {
      aps: { alert: Record<string, string> };
    };
    expect(Object.keys(payload.aps.alert)).toEqual(["title"]);
    expect(payload.aps.alert.title).toHaveLength(100);
  });

  it("picks the newest, and none from nothing", () => {
    const older = { mail: { sender: "A", subject: "" }, at: 1 };
    const newer = { mail: { sender: "B", subject: "" }, at: 2 };
    expect(newestOf([newer, older])).toEqual({ kind: "mail", newest: newer.mail });
    expect(newestOf([])).toEqual({ kind: "none" });
  });
});

describe("From headers", () => {
  it("names the sender by display name, or by address when there is none", () => {
    expect(senderName('"Levi, Dana" <dana@example.com>')).toBe("Levi, Dana");
    expect(senderName("<dana@example.com>")).toBe("dana@example.com");
    expect(senderName("dana@example.com")).toBe("dana@example.com");
    expect(senderAddress("Dana <Dana@Example.com>")).toBe("dana@example.com");
  });

  it("decodes encoded words, joining adjacent ones, and leaves broken ones alone", () => {
    expect(decodeEncodedWords("=?UTF-8?B?16nXnA==?= =?UTF-8?B?15XXnQ==?= there")).toBe("שלום there");
    expect(decodeEncodedWords("=?ISO-8859-1?Q?Caf=E9_time?=")).toBe("Café time");
    expect(decodeEncodedWords("=?bogus-charset?B?QQ==?=")).toBe("=?bogus-charset?B?QQ==?=");
  });
});
