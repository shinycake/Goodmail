import { describe, expect, it, vi } from "vitest";
import {
  type ImapLogin,
  type InboxStatus,
  inboxStatus,
  LoginRefused,
  parseFetch,
  parseStatus,
  watchInbox,
} from "../src/imap";
import { fakeImap, inboxServer } from "./fake-imap";

const ICLOUD: ImapLogin = {
  host: "imap.mail.me.com",
  port: 993,
  security: "tls",
  username: "someone@icloud.com",
  password: 'abcd-efgh-"ij\\kl',
};

describe("parseStatus", () => {
  it("reads UIDNEXT and UIDVALIDITY in either order, with the name quoted or not", () => {
    expect(parseStatus("* STATUS INBOX (UIDNEXT 12 UIDVALIDITY 34)")).toEqual({ uidNext: 12, uidValidity: 34 });
    expect(parseStatus('* STATUS "INBOX" (UIDVALIDITY 34 UIDNEXT 12)')).toEqual({ uidNext: 12, uidValidity: 34 });
  });

  it("ignores other lines and missing items", () => {
    expect(parseStatus("* CAPABILITY IMAP4rev1")).toBeUndefined();
    expect(parseStatus("* STATUS INBOX (UIDNEXT 12)")).toBeUndefined();
  });
});

describe("parseFetch", () => {
  it("reads UID, flags and the decoded headers, wherever the server puts UID and FLAGS", () => {
    expect(
      parseFetch([
        "* 1 FETCH (UID 12 FLAGS (\\Seen) BODY[HEADER.FIELDS (FROM SUBJECT)] {60}",
        "From: Dana <dana@example.com>",
        "Subject: =?UTF-8?B?16nXnNeV150=?=",
        " continued",
        "",
        ")",
        "* 2 FETCH (BODY[HEADER.FIELDS (FROM SUBJECT)] {40}",
        "Subject: Hi",
        "From: noa@example.com",
        "",
        " UID 13 FLAGS ())",
      ]),
    ).toEqual([
      { uid: 12, flags: ["\\Seen"], from: "Dana <dana@example.com>", subject: "שלום continued" },
      { uid: 13, flags: [], from: "noa@example.com", subject: "Hi" },
    ]);
  });

  it("leaves out a message without a From header", () => {
    expect(parseFetch(["* 1 FETCH (UID 12 FLAGS () BODY[HEADER.FIELDS (FROM SUBJECT)] {2}", "", ")"])).toEqual([]);
  });
});

describe("inboxStatus", () => {
  it("logs in with quoted strings, reads the Inbox's STATUS and logs out", async () => {
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    expect(await inboxStatus(ICLOUD, server.connect)).toEqual({ uidValidity: 7, uidNext: 100 });
    expect(server.sessions[0]?.lines).toEqual([
      'g1 LOGIN "someone@icloud.com" "abcd-efgh-\\"ij\\\\kl"',
      "g2 STATUS INBOX (UIDNEXT UIDVALIDITY)",
      "g3 LOGOUT",
    ]);
  });

  it("turns TLS on before logging in over STARTTLS", async () => {
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    await inboxStatus({ ...ICLOUD, port: 143, security: "startTLS" }, server.connect);
    expect(server.sessions[0]?.lines.slice(0, 3)).toEqual(["g1 STARTTLS", "[TLS]", expect.stringMatching(/^g2 LOGIN /)]);
  });

  it("calls a refused login refused", async () => {
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }, "refused"));
    await expect(inboxStatus(ICLOUD, server.connect)).rejects.toBeInstanceOf(LoginRefused);
  });

  it("doesn't call a login refused when the server says to try later", async () => {
    const server = fakeImap(() => (tag) => [`${tag} NO [UNAVAILABLE] Try again later`]);
    const failure = await inboxStatus(ICLOUD, server.connect).catch((error: unknown) => error);
    expect(failure).toBeInstanceOf(Error);
    expect(failure).not.toBeInstanceOf(LoginRefused);
  });

  it("gives up on a server that doesn't greet", async () => {
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }), "* BYE go away");
    await expect(inboxStatus(ICLOUD, server.connect)).rejects.toThrow("didn't greet");
  });
});

describe("watchInbox", () => {
  const statuses: InboxStatus[] = [];
  const record = async (status: InboxStatus) => {
    statuses.push(status);
  };

  it("idles in the Inbox and reads the STATUS again when the server announces new mail", async () => {
    statuses.length = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const server = fakeImap(() => inboxServer(inbox));
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, record, server.connect);
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    inbox.uidNext = 101;
    server.announce("* 4 EXISTS");
    await watching;
    expect(statuses).toEqual([
      { uidValidity: 7, uidNext: 100 },
      { uidValidity: 7, uidNext: 101 },
    ]);
    const lines = server.sessions[0]?.lines ?? [];
    expect(lines.slice(1, 6)).toEqual([
      "g2 STATUS INBOX (UIDNEXT UIDVALIDITY)",
      "g3 EXAMINE INBOX",
      "g4 IDLE",
      "DONE",
      "g5 STATUS INBOX (UIDNEXT UIDVALIDITY)",
    ]);
    expect(lines.at(-2)).toBe("DONE");
    expect(lines.at(-1)).toMatch(/^g\d+ LOGOUT$/);
    expect(server.sessions).toHaveLength(1);
  });

  it("starts IDLE again every renewal, so the connection never goes quiet for long", async () => {
    statuses.length = 0;
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    await watchInbox(ICLOUD, Date.now() + 5_500, record, server.connect, 1_000);
    const lines = server.sessions[0]?.lines ?? [];
    expect(lines.filter((line) => line.endsWith(" IDLE")).length).toBeGreaterThanOrEqual(2);
    expect(lines.filter((line) => line === "DONE").length).toBe(lines.filter((line) => line.endsWith(" IDLE")).length);
    expect(statuses).toHaveLength(1);
  });

  it("gives only the first STATUS for a server without IDLE", async () => {
    statuses.length = 0;
    const plain = inboxServer({ uidValidity: 7, uidNext: 100 });
    const server = fakeImap(() => (tag, command) => (command === "IDLE" ? [`${tag} BAD no IDLE`] : plain(tag, command)));
    const started = Date.now();
    await watchInbox(ICLOUD, Date.now() + 60_000, record, server.connect);
    expect(Date.now() - started).toBeLessThan(1_000);
    expect(statuses).toHaveLength(1);
  });
});
