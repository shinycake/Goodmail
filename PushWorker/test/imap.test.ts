import { describe, expect, it } from "vitest";
import { type ImapLogin, inboxStatus, LoginRefused, parseStatus } from "../src/imap";
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
