import { connect } from "cloudflare:sockets";
import { type Arrival, decodeEncodedWords, newestOf, RETRY, senderName } from "./new-mail";

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
 * The newest mail at or above UID `since` that the app alerts for (unread and not deleted), read as it is now, as `new-mail.ts` wants it. `retry` when the server couldn't answer.
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

/**
 * Setting up, from the greeting to the first STATUS, gets this long; so does logging out after watching, and so does
 * the server for each line of a reply.
 */
const TIMEOUT_MS = 20_000;
/** Watching stops this long before its deadline, to leave time to log out before the next check starts. */
const IDLE_MARGIN_MS = 3_000;
/**
 * IDLE is ended and started again this often. A connection with no traffic for about 4.5 minutes was closed on every
 * run (seen on iCloud from Workers, 2026-11-16), so the watch renews well before that.
 */
const IDLE_RENEW_MS = 120_000;
/** After mail changed or left, the watch waits this long for the rest of the burst before it sends one push. */
const SETTLE_MS = 2_000;

/** How a watch paces itself. Tests pass shorter times. */
export interface Pace {
  /** How often IDLE is ended and started again. */
  renewMs: number;
  /** How long the server gets for each line of a reply before the connection is given up. */
  replyMs: number;
  /** How long a burst of changes gets to settle before `onHandled`. */
  settleMs: number;
}

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
 * within seconds. Each time it announces mail changing or leaving the Inbox (a flag such as `\Seen` set, or an
 * EXPUNGE), as when the mail is read, moved or deleted in another app, it calls `onHandled` once the burst settles. One login covers the whole time, and waiting costs the Worker no CPU. A server without IDLE gets the
 * first STATUS only. Throws as `inboxStatus` does, for the login or the first STATUS; a connection lost while
 * watching, or a server that stopped answering, just ends the watch, since the next check logs in again.
 */
export async function watchInbox(
  login: ImapLogin,
  until: number,
  onStatus: (status: InboxStatus, fresh: FreshMail) => Promise<void>,
  open: Connect = connectToServer,
  pace: Partial<Pace> = {},
  onHandled: () => Promise<void> = async () => {},
): Promise<void> {
  const { renewMs, replyMs, settleMs }: Pace = { renewMs: IDLE_RENEW_MS, replyMs: TIMEOUT_MS, settleMs: SETTLE_MS, ...pace };
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
        let conversation = new Conversation(socket, replyMs);
        const greeting = await conversation.line();
        if (!/^\* (OK|PREAUTH)\b/i.test(greeting)) throw new Error("IMAP server didn't greet");
        if (login.security === "startTLS") {
          await conversation.command("STARTTLS");
          conversation.release();
          socket = socket.startTls();
          conversation = new Conversation(socket, replyMs, conversation.tagsSent);
        }
        if (!/^\* PREAUTH\b/i.test(greeting)) await logIn(conversation, login);
        const inbox = new Inbox(conversation);
        // Selected first when a watch follows, so the STATUS covers what arrived until it and the rounds what after.
        if (Date.now() < deadline) await inbox.examine();
        await onStatus(await status(conversation), inbox.fresh);
        return inbox;
      })(),
      timeout(TIMEOUT_MS),
    ]);
    if (Date.now() < deadline) {
      await Promise.race([idle(inbox, deadline, { renewMs, settleMs }, onStatus, onHandled), timeout(deadline - Date.now() + TIMEOUT_MS)]).catch(
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
 * What the server said about the selected mailbox since the round was last taken (`Conversation.takeRound`):
 * nothing, new mail (with or without mail changing or leaving too), or only mail changing or leaving.
 */
type Round = { kind: "quiet" } | { kind: "arrived"; changedToo: boolean } | { kind: "changed" };

/** Something the server said about the selected mailbox: it grew, or mail in it changed or left. */
type Notice = "arrived" | "changed";

const QUIET: Round = { kind: "quiet" };

/** The round once the server said `notice` too: the one place a round moves. */
function noticed(round: Round, notice: Notice): Round {
  const changed = round.kind === "changed" || (round.kind === "arrived" && round.changedToo);
  if (notice === "arrived") return { kind: "arrived", changedToo: changed };
  return round.kind === "arrived" ? { kind: "arrived", changedToo: true } : { kind: "changed" };
}

/**
 * Selects the Inbox read-only and idles in it until `deadline`, starting IDLE again every `renewMs`, reading the
 * STATUS again whenever mail arrived. An arrival counts whenever the server says it: while idling, or between two
 * IDLE commands, where the server announces it only once and a wait for the next announcement would miss it. Mail
 * changing or leaving calls `onHandled` once no more has come for `settleMs`, so reading a dozen messages costs one
 * push; when mail arrived in the same round, `onHandled` follows its STATUS, since the new mail may bring no alert.
 * Returns at once when the server doesn't take IDLE.
 */
async function idle(
  inbox: Inbox,
  deadline: number,
  { renewMs, settleMs }: Pick<Pace, "renewMs" | "settleMs">,
  onStatus: (status: InboxStatus, fresh: FreshMail) => Promise<void>,
  onHandled: () => Promise<void>,
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
    const renewal = Math.min(deadline, Date.now() + renewMs);
    while (conversation.round.kind === "quiet" && (await conversation.lineBy(renewal)) !== undefined);
    // A change seldom comes alone: the rest of the burst comes before the push. New mail ends the wait at once.
    while (
      conversation.round.kind === "changed" &&
      (await conversation.lineBy(Math.min(renewal, Date.now() + settleMs))) !== undefined
    );
    await conversation.finish(tag, "DONE");
    // Taken before the STATUS or the push, so what the server says while they are under way starts the next round.
    const said = conversation.takeRound();
    switch (said.kind) {
      case "quiet":
        break;
      case "arrived":
        await onStatus(await status(conversation), inbox.fresh);
        if (said.changedToo) await onHandled();
        break;
      case "changed":
        await onHandled();
        break;
    }
  }
}

/** The Inbox on one logged-in conversation, selected read-only once something needs it selected. */
class Inbox {
  private selection: "none" | "examined" = "none";

  constructor(readonly conversation: Conversation) {}

  async examine(): Promise<void> {
    if (this.selection === "examined") return;
    await this.conversation.command("EXAMINE INBOX");
    this.conversation.selected();
    this.selection = "examined";
  }

  readonly fresh: FreshMail = async (since) => {
    try {
      await this.examine();
      // The reply's FETCH lines carry the headers, so they are no change in the Inbox (`answersCheck`).
      const untagged = await this.conversation.command(
        `UID FETCH ${since}:* (UID FLAGS BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])`,
      );
      // `since:*` always matches the newest message, even one below `since`.
      const found = parseFetch(untagged).filter(
        (message) =>
          message.uid >= since &&
          !message.flags.some((flag) => /^\\(Seen|Deleted)$/i.test(flag)),
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
  let reading: Reading = { kind: "between" };
  const close = (message: Message) => {
    const found = headersOf(message);
    if (found) messages.push(found);
  };
  for (const line of lines) {
    if (reading.kind === "literal") {
      if (line === "") reading = { kind: "items", message: reading.message };
      else reading.message.headers.push(line);
      continue;
    }
    if (/^\* \d+ FETCH /i.test(line)) {
      if (reading.kind === "items") close(reading.message);
      reading = { kind: "items", message: { items: "", headers: [] } };
    }
    if (reading.kind === "between") continue;
    const literal = /\{\d+\}$/.exec(line);
    reading.message.items += ` ${literal ? line.slice(0, literal.index) : line}`;
    if (literal) reading = { kind: "literal", message: reading.message };
  }
  if (reading.kind !== "between") close(reading.message);
  return messages;
}

/** One message of a FETCH response as read so far: its items, and its header lines. */
interface Message {
  items: string;
  headers: string[];
}

/** Where `parseFetch` is: before the first message, in a message's items, or in its header literal. */
type Reading = { kind: "between" } | { kind: "items" | "literal"; message: Message };

/** The message's UID, flags and decoded headers, or undefined without a UID or a From header. */
function headersOf(message: Message): FetchedHeaders | undefined {
  const uid = Number(/\bUID (\d+)/i.exec(message.items)?.[1]);
  const flags = /\bFLAGS \(([^)]*)\)/i.exec(message.items)?.[1]?.trim().split(/\s+/).filter(Boolean) ?? [];
  const headers = unfold(message.headers);
  const from = headers.get("from");
  if (!Number.isSafeInteger(uid) || !from) return undefined;
  return { uid, flags, from: decodeEncodedWords(from), subject: decodeEncodedWords(headers.get("subject") ?? "") };
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

/**
 * Whether a `* n FETCH` line answers the new-mail check: it carries the headers the check asked for, which the server
 * sends no one unasked. One with only flags, a UID or a MODSEQ is mail changing, as when another app reads it.
 */
function answersCheck(line: string): boolean {
  return /\bBODY\[HEADER\.FIELDS\b/i.test(line);
}

/** Lines in and commands out over one socket. Commands are tagged in turn; untagged lines come back with the reply. */
class Conversation {
  private readonly reader: ReadableStreamDefaultReader<Uint8Array>;
  private readonly writer: WritableStreamDefaultWriter<Uint8Array>;
  private readonly decoder = new TextDecoder();
  private buffered = "";
  private pending: Promise<ReadableStreamReadResult<Uint8Array>> | undefined;
  /**
   * The selected mailbox as the server last said (RFC 3501 §7.3.1, §7.4.1): how many messages it holds, and how many
   * of them it held when the round began. New mail takes the numbers after those, so a FETCH above them is about
   * mail that just arrived, as the flags some servers send with it, and no change.
   */
  private mailbox = { size: 0, before: 0 };
  /**
   * What the server said about the selected mailbox since the round began, whichever command it said so during. New
   * mail is a `* n EXISTS` above the count so far: a count the server only repeats, or one that fell with a
   * `* n EXPUNGE`, is no arrival. Mail changing or leaving is a `* n EXPUNGE`, or a `* n FETCH` for mail that was
   * there before the round (its flags, as when another app reads it) that isn't a reply to the new-mail check.
   */
  private said: Round = QUIET;

  /**
   * The server gets `replyMs` for each line of a reply. Tags carry on from `tagsSent` commands, as on the plain
   * connection before STARTTLS.
   */
  constructor(
    socket: Socket,
    private readonly replyMs: number,
    public tagsSent = 0,
  ) {
    this.reader = socket.readable.getReader();
    this.writer = socket.writable.getWriter();
  }

  /** What the server said since the round was last taken. */
  get round(): Round {
    return this.said;
  }

  /** Hands over the round so far and starts the next one. */
  takeRound(): Round {
    const round = this.said;
    this.said = QUIET;
    this.mailbox = { ...this.mailbox, before: this.mailbox.size };
    return round;
  }

  /** Starts the first round on a mailbox just selected: the size its reply said is no arrival. */
  selected(): void {
    this.takeRound();
  }

  /** The next line of a reply the server owes. One that doesn't come in time means the server has gone quiet. */
  async line(): Promise<string> {
    const line = await this.lineBy(Date.now() + this.replyMs);
    if (line === undefined) throw new Error("IMAP server timed out");
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
        this.notice(line);
        return line;
      }
      this.pending ??= this.reader.read();
      const late = Promise.withResolvers<"late">();
      const timer = setTimeout(() => late.resolve("late"), Math.max(0, deadline - Date.now()));
      const result = await Promise.race([this.pending, late.promise]);
      clearTimeout(timer);
      if (result === "late") return undefined;
      this.pending = undefined;
      if (result.done) throw new Error("IMAP server closed the connection");
      this.buffered += this.decoder.decode(result.value, { stream: true });
    }
  }

  /** Keeps the mailbox and the round up to date with a line the server sent: the one place either moves. */
  private notice(line: string): void {
    const [, number, what] = /^\* (\d+) (EXISTS|EXPUNGE|FETCH)\b/i.exec(line) ?? [];
    const sequence = Number(number);
    const { size, before } = this.mailbox;
    switch (what?.toUpperCase()) {
      case "EXISTS":
        if (sequence > size) this.said = noticed(this.said, "arrived");
        this.mailbox = { size: sequence, before };
        break;
      case "EXPUNGE":
        this.mailbox = { size: Math.max(0, size - 1), before: sequence <= before ? before - 1 : before };
        this.said = noticed(this.said, "changed");
        break;
      case "FETCH":
        if (sequence <= before && !answersCheck(line)) this.said = noticed(this.said, "changed");
        break;
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
