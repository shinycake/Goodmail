import { connect } from "cloudflare:sockets";
import { type Arrival, decodeEncodedWords, newestOf, RETRY, senderAddress, senderName } from "./new-mail";

/** How the relay reaches an account's IMAP server. Never without TLS: the password goes over it. */
export interface ImapLogin {
  host: string;
  port: number;
  /** `tls` from the first byte (993), or `startTLS` on a plain connection that turns TLS on (143). */
  security: "tls" | "startTLS";
  username: string;
  password: string;
}

/** The Inbox's UIDs: new mail always takes a UID at or above `uidNext`, unless `uidValidity` changes. */
export interface InboxStatus {
  uidValidity: number;
  uidNext: number;
}

/**
 * The newest mail at or above UID `since` that the app alerts for (unread, not deleted, not sent by the account
 * itself), read as it is now, as `new-mail.ts` wants it. `retry` when the server couldn't answer.
 */
export type FreshMail = (since: number) => Promise<Arrival>;

/** The server refused the login. The relay stops logging in with it, so it never locks the account. */
export class LoginRefused extends Error {}

/** Opens a TCP connection, as `cloudflare:sockets` does; tests pass a scripted server. */
export type Connect = (login: ImapLogin) => Socket;

export const connectToServer: Connect = (login) =>
  connect(
    { hostname: login.host, port: login.port },
    { secureTransport: login.security === "tls" ? "on" : "starttls", allowHalfOpen: false },
  );

/** Setting up, from the greeting to the first STATUS, gets this long; so does logging out after watching. */
const TIMEOUT_MS = 20_000;
/** Watching stops this long before its deadline, to leave time to log out before the next check starts. */
const IDLE_MARGIN_MS = 3_000;
/**
 * IDLE is ended and started again this often. A connection with no traffic for about 4.5 minutes was closed on every
 * run (seen on iCloud from Workers, 2026-11-16), so the watch renews well before that.
 */
const IDLE_RENEW_MS = 120_000;

/**
 * Logs in and reads the Inbox's STATUS: one short conversation, so the relay holds no connection between checks.
 * Throws `LoginRefused` when the server refuses the login for good, and anything else (network, timeout, a server
 * saying it is unavailable) for a failure worth trying again.
 */
export async function inboxStatus(login: ImapLogin, open: Connect = connectToServer): Promise<InboxStatus> {
  let first: InboxStatus | undefined;
  await watchInbox(
    login,
    0,
    async (status) => {
      first = status;
    },
    open,
  );
  if (!first) throw new Error("IMAP server sent no STATUS");
  return first;
}

/**
 * Logs in, hands `onStatus` the Inbox's STATUS, then keeps watching the Inbox with IDLE (RFC 2177) until `until`
 * (ms since 1970):
 * each time the server announces new mail, it reads the STATUS again and hands it over at once, so an alert goes out
 * within seconds. One login covers the whole time, and waiting costs the Worker no CPU. A server without IDLE gets the
 * first STATUS only. Throws as `inboxStatus` does, for the login or the first STATUS; a connection lost while
 * watching just ends the watch, since the next check logs in again.
 */
export async function watchInbox(
  login: ImapLogin,
  until: number,
  onStatus: (status: InboxStatus, fresh: FreshMail) => Promise<void>,
  open: Connect = connectToServer,
  renewMs = IDLE_RENEW_MS,
): Promise<void> {
  const deadline = until - IDLE_MARGIN_MS;
  let socket = open(login);
  const timers: ReturnType<typeof setTimeout>[] = [];
  const timeout = (ms: number) =>
    new Promise<never>((_, reject) => {
      timers.push(setTimeout(() => reject(new Error("IMAP server timed out")), ms));
    });
  try {
    const inbox = await Promise.race([
      (async () => {
        let conversation = new Conversation(socket);
        const greeting = await conversation.line();
        if (!/^\* (OK|PREAUTH)\b/i.test(greeting)) throw new Error("IMAP server didn't greet");
        if (login.security === "startTLS") {
          await conversation.command("STARTTLS");
          conversation.release();
          socket = socket.startTls();
          conversation = new Conversation(socket, conversation.tagsSent);
        }
        if (!/^\* PREAUTH\b/i.test(greeting)) await logIn(conversation, login);
        const inbox = new Inbox(conversation, login.username);
        await onStatus(await status(conversation), inbox.fresh);
        return inbox;
      })(),
      timeout(TIMEOUT_MS),
    ]);
    if (Date.now() < deadline) {
      await Promise.race([idle(inbox, deadline, renewMs, onStatus), timeout(deadline - Date.now() + TIMEOUT_MS)]).catch(
        (error: unknown) => {
          if (error instanceof LoginRefused) throw error;
          console.warn(`IMAP watch ended early: ${error instanceof Error ? error.message : String(error)}`);
        },
      );
    }
    await Promise.race([inbox.conversation.command("LOGOUT"), timeout(TIMEOUT_MS)]).catch(() => undefined);
  } finally {
    for (const timer of timers) clearTimeout(timer);
    await socket.close().catch(() => undefined);
  }
}

async function status(conversation: Conversation): Promise<InboxStatus> {
  const untagged = await conversation.command("STATUS INBOX (UIDNEXT UIDVALIDITY)");
  const found = untagged.map(parseStatus).find((parsed) => parsed !== undefined);
  if (!found) throw new Error("IMAP server sent no STATUS");
  return found;
}

/**
 * Selects the Inbox read-only and idles in it until `deadline`, starting IDLE again every `renewMs`, reading the STATUS again whenever the server says the
 * Inbox grew (`* n EXISTS`). Returns at once when the server doesn't take IDLE.
 */
async function idle(
  inbox: Inbox,
  deadline: number,
  renewMs: number,
  onStatus: (status: InboxStatus, fresh: FreshMail) => Promise<void>,
): Promise<void> {
  await inbox.examine();
  const { conversation } = inbox;
  while (Date.now() < deadline) {
    let tag;
    try {
      tag = await conversation.begin("IDLE");
    } catch (error) {
      if (error instanceof CommandFailed) return;
      throw error;
    }
    let arrived = false;
    const renewal = Math.min(deadline, Date.now() + renewMs);
    for (let line = await conversation.lineBy(renewal); line !== undefined; line = await conversation.lineBy(renewal)) {
      if (/^\* \d+ EXISTS\b/i.test(line)) {
        arrived = true;
        break;
      }
    }
    await conversation.finish(tag, "DONE");
    if (arrived) await onStatus(await status(conversation), inbox.fresh);
  }
}

/** The Inbox on one logged-in conversation, selected read-only once something needs it selected. */
class Inbox {
  private selection: "none" | "examined" = "none";

  constructor(
    readonly conversation: Conversation,
    private readonly ownAddress: string,
  ) {}

  async examine(): Promise<void> {
    if (this.selection === "examined") return;
    await this.conversation.command("EXAMINE INBOX");
    this.selection = "examined";
  }

  readonly fresh: FreshMail = async (since) => {
    try {
      await this.examine();
      const untagged = await this.conversation.command(
        `UID FETCH ${since}:* (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])`,
      );
      const own = this.ownAddress.toLowerCase();
      // `since:*` always matches the newest message, even one below `since`.
      const found = parseFetch(untagged).filter(
        (message) =>
          message.uid >= since &&
          !message.flags.some((flag) => /^\\(Seen|Deleted)$/i.test(flag)) &&
          senderAddress(message.from) !== own,
      );
      return newestOf(found.map((message) => ({ mail: { sender: senderName(message.from), subject: message.subject }, at: message.uid })));
    } catch (error) {
      console.warn(`IMAP new-mail check failed: ${error instanceof Error ? error.message : String(error)}`);
      return RETRY;
    }
  };
}

/** One message from a `UID FETCH (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])`, its headers decoded. */
export interface FetchedHeaders {
  uid: number;
  flags: string[];
  from: string;
  subject: string;
}

/**
 * Reads a FETCH response's untagged lines. The headers come as a literal (`{n}` then the lines), which ends at its
 * blank line; UID and FLAGS may come before or after it. A message without a UID or a From header is left out.
 */
export function parseFetch(lines: string[]): FetchedHeaders[] {
  const messages: FetchedHeaders[] = [];
  let current: { items: string; headers: string[] } | undefined;
  let inLiteral = false;
  const close = () => {
    if (!current) return;
    const uid = Number(/\bUID (\d+)/i.exec(current.items)?.[1]);
    const flags = /\bFLAGS \(([^)]*)\)/i.exec(current.items)?.[1]?.trim().split(/\s+/).filter(Boolean) ?? [];
    const headers = unfold(current.headers);
    const from = headers.get("from");
    if (Number.isSafeInteger(uid) && from) {
      messages.push({ uid, flags, from: decodeEncodedWords(from), subject: decodeEncodedWords(headers.get("subject") ?? "") });
    }
    current = undefined;
  };
  for (const line of lines) {
    if (inLiteral) {
      if (line === "") inLiteral = false;
      else current?.headers.push(line);
      continue;
    }
    if (/^\* \d+ FETCH /i.test(line)) {
      close();
      current = { items: "", headers: [] };
    }
    if (!current) continue;
    const literal = /\{\d+\}$/.exec(line);
    current.items += ` ${literal ? line.slice(0, literal.index) : line}`;
    if (literal) inLiteral = true;
  }
  close();
  return messages;
}

/** Header lines, with continuation lines joined, by lowercased name; the first of a repeated name wins. */
function unfold(lines: string[]): Map<string, string> {
  const headers = new Map<string, string>();
  let last: string | undefined;
  for (const line of lines) {
    if (/^[ \t]/.test(line) && last !== undefined) {
      headers.set(last, `${headers.get(last)} ${line.trim()}`);
      continue;
    }
    const colon = line.indexOf(":");
    if (colon <= 0) continue;
    const name = line.slice(0, colon).trim().toLowerCase();
    last = headers.has(name) ? undefined : name;
    if (last !== undefined) headers.set(name, line.slice(colon + 1).trim());
  }
  return headers;
}

/** Response codes that say the login may work later (RFC 5530), so it isn't refused for good. */
const TRANSIENT_CODES = /\[(UNAVAILABLE|INUSE|SERVERBUG|LIMIT)\]/i;

async function logIn(conversation: Conversation, login: ImapLogin): Promise<void> {
  try {
    await conversation.command(`LOGIN ${quoted(login.username)} ${quoted(login.password)}`);
  } catch (error) {
    if (error instanceof CommandFailed && error.status === "NO" && !TRANSIENT_CODES.test(error.text)) {
      throw new LoginRefused(error.text);
    }
    throw error;
  }
}

/** Whether `text` can be sent as an IMAP quoted string: printable ASCII only. */
export function isQuotable(text: string): boolean {
  return /^[\x20-\x7e]*$/.test(text);
}

function quoted(text: string): string {
  return `"${text.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

/** `* STATUS INBOX (UIDNEXT 12 UIDVALIDITY 34)`, with the mailbox name quoted or not and the items in any order. */
export function parseStatus(line: string): InboxStatus | undefined {
  const items = /^\* STATUS (?:"(?:[^"\\]|\\.)*"|\S+) \(([^)]*)\)/i.exec(line)?.[1];
  if (items === undefined) return undefined;
  const words = items.trim().split(/\s+/);
  const values = new Map<string, number>();
  for (let index = 0; index + 1 < words.length; index += 2) {
    values.set(words[index]!.toUpperCase(), Number(words[index + 1]));
  }
  const uidNext = values.get("UIDNEXT");
  const uidValidity = values.get("UIDVALIDITY");
  if (!Number.isSafeInteger(uidNext) || !Number.isSafeInteger(uidValidity)) return undefined;
  return { uidNext: uidNext!, uidValidity: uidValidity! };
}

/** A tagged NO or BAD as a `CommandFailed`. */
function failure(line: string): CommandFailed {
  const [, status, rest] = /^\S+ (NO|BAD)\b ?(.*)$/i.exec(line) ?? [];
  return new CommandFailed(status?.toUpperCase() === "NO" ? "NO" : "BAD", rest ?? line);
}

class CommandFailed extends Error {
  constructor(
    readonly status: "NO" | "BAD",
    readonly text: string,
  ) {
    super(`IMAP ${status} ${text}`);
  }
}

/** Lines in and commands out over one socket. Commands are tagged in turn; untagged lines come back with the reply. */
class Conversation {
  private readonly reader: ReadableStreamDefaultReader<Uint8Array>;
  private readonly writer: WritableStreamDefaultWriter<Uint8Array>;
  private readonly decoder = new TextDecoder();
  private buffered = "";
  private pending: Promise<ReadableStreamReadResult<Uint8Array>> | undefined;

  /** Tags carry on from `tagsSent` commands, as on the plain connection before STARTTLS. */
  constructor(
    socket: Socket,
    public tagsSent = 0,
  ) {
    this.reader = socket.readable.getReader();
    this.writer = socket.writable.getWriter();
  }

  async line(): Promise<string> {
    const line = await this.lineBy(Infinity);
    if (line === undefined) throw new Error("IMAP server sent no line");
    return line;
  }

  /**
   * The next line, or undefined when none comes by `deadline` (ms since 1970). A read still waiting then is kept for
   * the next call, so no line is lost.
   */
  async lineBy(deadline: number): Promise<string | undefined> {
    for (;;) {
      const end = this.buffered.indexOf("\r\n");
      if (end >= 0) {
        const line = this.buffered.slice(0, end);
        this.buffered = this.buffered.slice(end + 2);
        return line;
      }
      this.pending ??= this.reader.read();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const late = new Promise<"late">((resolve) => {
        if (deadline !== Infinity) timer = setTimeout(() => resolve("late"), Math.max(0, deadline - Date.now()));
      });
      const result = await Promise.race([this.pending, late]);
      if (timer !== undefined) clearTimeout(timer);
      if (result === "late") return undefined;
      this.pending = undefined;
      if (result.done) throw new Error("IMAP server closed the connection");
      this.buffered += this.decoder.decode(result.value, { stream: true });
    }
  }

  /** Sends `text` and reads to its tagged reply. Returns the untagged lines; throws `CommandFailed` for NO or BAD. */
  async command(text: string): Promise<string[]> {
    return this.finish(await this.send(text));
  }

  /**
   * Sends `text` and reads to the server's go-ahead (`+`), as IDLE answers. Returns the tag for `finish`; throws
   * `CommandFailed` when the server answers NO or BAD instead.
   */
  async begin(text: string): Promise<string> {
    const tag = await this.send(text);
    for (;;) {
      const line = await this.line();
      if (line.startsWith("+")) return tag;
      if (line.startsWith(`${tag} `)) throw failure(line);
    }
  }

  private async send(text: string): Promise<string> {
    const tag = `g${++this.tagsSent}`;
    await this.writer.write(new TextEncoder().encode(`${tag} ${text}\r\n`));
    return tag;
  }

  /** Sends `line`, if any, and reads to `tag`'s tagged reply, as `command` does. */
  async finish(tag: string, line?: string): Promise<string[]> {
    if (line !== undefined) await this.writer.write(new TextEncoder().encode(`${line}\r\n`));
    const untagged: string[] = [];
    for (;;) {
      const line = await this.line();
      if (!line.startsWith(`${tag} `)) {
        untagged.push(line);
        continue;
      }
      if (/^\S+ OK\b/i.test(line)) return untagged;
      throw failure(line);
    }
  }

  /** Lets go of the socket's streams, as `startTls` needs. */
  release(): void {
    this.reader.releaseLock();
    this.writer.releaseLock();
  }
}
