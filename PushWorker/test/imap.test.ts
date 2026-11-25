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
    // Selected before the first STATUS, so what the server says after the STATUS starts the first round.
    expect(lines.slice(1, 6)).toEqual([
      "g2 EXAMINE INBOX",
      "g3 STATUS INBOX (UIDNEXT UIDVALIDITY)",
      "g4 IDLE",
      "DONE",
      "g5 STATUS INBOX (UIDNEXT UIDVALIDITY)",
    ]);
    expect(lines.at(-2)).toBe("DONE");
    expect(lines.at(-1)).toMatch(/^g\d+ LOGOUT$/);
    expect(server.sessions).toHaveLength(1);
  });

  it("notices mail the server announces between two IDLE commands", async () => {
    statuses.length = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const plain = inboxServer(inbox);
    let idles = 0;
    const server = fakeImap(() => (tag, command) => {
      if (command !== "IDLE" || ++idles !== 2) return plain(tag, command);
      inbox.uidNext = 101;
      return ["* 4 EXISTS", ...plain(tag, command)];
    });
    await watchInbox(ICLOUD, Date.now() + 5_500, record, server.connect, { renewMs: 1_000 });
    expect(statuses).toEqual([
      { uidValidity: 7, uidNext: 100 },
      { uidValidity: 7, uidNext: 101 },
    ]);
  });

  it("reads the STATUS again only for mail that arrived, not for a count the server repeats", async () => {
    statuses.length = 0;
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, record, server.connect);
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    server.announce("* 3 EXISTS");
    await watching;
    expect(statuses).toHaveLength(1);
  });

  it("counts mail that arrives after another message was removed, though the Inbox is no bigger", async () => {
    statuses.length = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const server = fakeImap(() => inboxServer(inbox));
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, record, server.connect);
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    server.announce("* 1 EXPUNGE");
    inbox.uidNext = 101;
    server.announce("* 3 EXISTS");
    await watching;
    expect(statuses.at(-1)).toEqual({ uidValidity: 7, uidNext: 101 });
  });

  it("reports mail changing or leaving once the burst settles, and reads no STATUS for it", async () => {
    statuses.length = 0;
    let handled = 0;
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, record, server.connect, { settleMs: 500 }, async () => {
      handled++;
    });
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    server.announce("* 2 FETCH (FLAGS (\\Seen))");
    server.announce("* 3 FETCH (FLAGS (\\Seen \\Flagged))");
    server.announce("* 1 EXPUNGE");
    await watching;
    expect(handled).toBe(1);
    expect(statuses).toHaveLength(1);
  });

  it("alerts at once for mail that arrives while a burst of changes settles, then reports the changes too", async () => {
    statuses.length = 0;
    const calls: string[] = [];
    const inbox = { uidValidity: 7, uidNext: 100 };
    const server = fakeImap(() => inboxServer(inbox));
    const noting = async (status: InboxStatus) => {
      statuses.push(status);
      calls.push("status");
    };
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, noting, server.connect, { settleMs: 3_000 }, async () => {
      calls.push("handled");
    });
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    server.announce("* 2 FETCH (FLAGS (\\Seen))");
    inbox.uidNext = 101;
    const announced = Date.now();
    server.announce("* 4 EXISTS");
    await vi.waitUntil(() => statuses.length === 2);
    expect(Date.now() - announced).toBeLessThan(1_000);
    await watching;
    // The new mail may bring no alert (read already, or APNs failed), so the change still gets its push.
    expect(calls).toEqual(["status", "status", "handled"]);
  });

  it("reports another app's change that the server announces during the new-mail check", async () => {
    statuses.length = 0;
    let handled = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const plain = inboxServer(inbox);
    let fetches = 0;
    const server = fakeImap(() => (tag, command) => {
      const reply = plain(tag, command);
      // RFC 3501 lets the server say what changed during any command: here a message read elsewhere, and one gone.
      if (command.startsWith("UID FETCH") && ++fetches === 2) {
        return ["* 1 FETCH (FLAGS (\\Seen))", "* 2 EXPUNGE", ...reply];
      }
      return reply;
    });
    const fetching = async (status: InboxStatus, fresh: (since: number) => Promise<unknown>) => {
      statuses.push(status);
      await fresh(status.uidNext - 1);
    };
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, fetching, server.connect, { settleMs: 300 }, async () => {
      handled++;
    });
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g5 IDLE"));
    inbox.uidNext = 101;
    server.announce("* 4 EXISTS");
    await watching;
    expect(statuses).toHaveLength(2);
    expect(handled).toBe(1);
  });

  /** A watch whose every onStatus runs the new-mail check, as the relay's does, over a server whose FETCH replies `fetchReply` shapes. */
  function fetchingWatch(fetchReply: (fetches: number, reply: string[]) => string[], onStatus?: (status: InboxStatus) => void) {
    const inbox = { uidValidity: 7, uidNext: 100 };
    const plain = inboxServer(inbox);
    let fetches = 0;
    let handled = 0;
    const server = fakeImap(() => (tag, command) => {
      const reply = plain(tag, command);
      return command.startsWith("UID FETCH") ? fetchReply(++fetches, reply) : reply;
    });
    const fetching = async (status: InboxStatus, fresh: (since: number) => Promise<unknown>) => {
      statuses.push(status);
      onStatus?.(status);
      await fresh(status.uidNext - 1);
    };
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, fetching, server.connect, { settleMs: 300 }, async () => {
      handled++;
    });
    return { inbox, server, watching, handled: () => handled };
  }

  it("reports a read elsewhere that the server names by UID during the new-mail check", async () => {
    statuses.length = 0;
    // Dovecot names the UID in an unsolicited FETCH, here one above what the check asked for.
    const watch = fetchingWatch((fetches, reply) => (fetches === 2 ? ["* 2 FETCH (UID 150 FLAGS (\\Seen))", ...reply] : reply));
    await vi.waitUntil(() => watch.server.sessions[0]?.lines.includes("g5 IDLE"));
    watch.inbox.uidNext = 101;
    watch.server.announce("* 4 EXISTS");
    await watch.watching;
    expect(statuses).toHaveLength(2);
    expect(watch.handled()).toBe(1);
  });

  it("takes a reply to its own check as no change, wherever the server puts the UID", async () => {
    statuses.length = 0;
    const headers = "From: Dana <dana@example.com>\r\nSubject: Hi\r\n\r\n";
    const watch = fetchingWatch((fetches, reply) => [
      `* 3 FETCH (FLAGS () BODY[HEADER.FIELDS (FROM SUBJECT)] {${headers.length}}`,
      "From: Dana <dana@example.com>",
      "Subject: Hi",
      "",
      ` UID ${98 + fetches})`,
      reply.at(-1)!,
    ]);
    await vi.waitUntil(() => watch.server.sessions[0]?.lines.includes("g5 IDLE"));
    watch.inbox.uidNext = 101;
    watch.server.announce("* 4 EXISTS");
    await watch.watching;
    expect(statuses).toHaveLength(2);
    expect(watch.handled()).toBe(0);
  });

  it("reports a change the server names during the first new-mail check", async () => {
    statuses.length = 0;
    const watch = fetchingWatch((fetches, reply) => (fetches === 1 ? ["* 1 FETCH (FLAGS (\\Seen))", ...reply] : reply));
    await watch.watching;
    expect(watch.handled()).toBe(1);
  });

  it("reads the STATUS again for mail the server announces just after the first one", async () => {
    statuses.length = 0;
    let announced = false;
    const watch = fetchingWatch(
      (_, reply) => reply,
      () => {
        if (announced) return;
        announced = true;
        // Mail arriving while the relay looks up the devices to alert.
        watch.inbox.uidNext = 101;
        watch.server.announce("* 4 EXISTS");
      },
    );
    await watch.watching;
    expect(statuses.map((status) => status.uidNext)).toEqual([100, 101]);
  });

  it("takes the flags a server sends with new mail as no change", async () => {
    statuses.length = 0;
    let handled = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const server = fakeImap(() => inboxServer(inbox));
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, record, server.connect, { settleMs: 300 }, async () => {
      handled++;
    });
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g4 IDLE"));
    inbox.uidNext = 101;
    server.announce("* 4 EXISTS");
    server.announce("* 4 FETCH (FLAGS (\\Recent))");
    await watching;
    expect(statuses).toHaveLength(2);
    expect(handled).toBe(0);
  });

  it("doesn't take the replies to its own new-mail check for changes", async () => {
    statuses.length = 0;
    let handled = 0;
    const inbox = { uidValidity: 7, uidNext: 100 };
    const server = fakeImap(() => inboxServer(inbox));
    const fetching = async (status: InboxStatus, fresh: (since: number) => Promise<unknown>) => {
      statuses.push(status);
      await fresh(status.uidNext - 1);
    };
    const watching = watchInbox(ICLOUD, Date.now() + 4_500, fetching, server.connect, {}, async () => {
      handled++;
    });
    await vi.waitUntil(() => server.sessions[0]?.lines.includes("g5 IDLE"));
    inbox.uidNext = 101;
    server.announce("* 4 EXISTS");
    await watching;
    expect(statuses).toHaveLength(2);
    expect(handled).toBe(0);
  });

  it("starts IDLE again every renewal, so the connection never goes quiet for long", async () => {
    statuses.length = 0;
    const server = fakeImap(() => inboxServer({ uidValidity: 7, uidNext: 100 }));
    await watchInbox(ICLOUD, Date.now() + 5_500, record, server.connect, { renewMs: 1_000 });
    const lines = server.sessions[0]?.lines ?? [];
    expect(lines.filter((line) => line.endsWith(" IDLE")).length).toBeGreaterThanOrEqual(2);
    expect(lines.filter((line) => line === "DONE").length).toBe(lines.filter((line) => line.endsWith(" IDLE")).length);
    expect(statuses).toHaveLength(1);
  });

  it("gives up on a server that stops answering, long before the watch's time is up", async () => {
    statuses.length = 0;
    const plain = inboxServer({ uidValidity: 7, uidNext: 100 });
    const server = fakeImap(() => (tag, command) => (tag === "DONE" ? [] : plain(tag, command)));
    const started = Date.now();
    await watchInbox(ICLOUD, Date.now() + 60_000, record, server.connect, { renewMs: 500, replyMs: 500 });
    expect(Date.now() - started).toBeLessThan(5_000);
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
