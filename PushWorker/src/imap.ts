import { connect } from "cloudflare:sockets";

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

/** The server refused the login. The relay stops logging in with it, so it never locks the account. */
export class LoginRefused extends Error {}

/** Opens a TCP connection, as `cloudflare:sockets` does; tests pass a scripted server. */
export type Connect = (login: ImapLogin) => Socket;

export const connectToServer: Connect = (login) =>
  connect(
    { hostname: login.host, port: login.port },
    { secureTransport: login.security === "tls" ? "on" : "starttls", allowHalfOpen: false },
  );

/** A whole conversation, greeting to logout, gets this long. */
const TIMEOUT_MS = 20_000;

/**
 * Logs in and reads the Inbox's STATUS: one short conversation, so the relay holds no connection between checks.
 * Throws `LoginRefused` when the server refuses the login for good, and anything else (network, timeout, a server
 * saying it is unavailable) for a failure worth trying again.
 */
export async function inboxStatus(login: ImapLogin, open: Connect = connectToServer): Promise<InboxStatus> {
  let socket = open(login);
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new Error("IMAP server timed out")), TIMEOUT_MS);
  });
  try {
    return await Promise.race([
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
        const untagged = await conversation.command("STATUS INBOX (UIDNEXT UIDVALIDITY)");
        const status = untagged.map(parseStatus).find((found) => found !== undefined);
        if (!status) throw new Error("IMAP server sent no STATUS");
        await conversation.command("LOGOUT").catch(() => undefined);
        return status;
      })(),
      timeout,
    ]);
  } finally {
    if (timer !== undefined) clearTimeout(timer);
    await socket.close().catch(() => undefined);
  }
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

  /** Tags carry on from `tagsSent` commands, as on the plain connection before STARTTLS. */
  constructor(
    socket: Socket,
    public tagsSent = 0,
  ) {
    this.reader = socket.readable.getReader();
    this.writer = socket.writable.getWriter();
  }

  async line(): Promise<string> {
    for (;;) {
      const end = this.buffered.indexOf("\r\n");
      if (end >= 0) {
        const line = this.buffered.slice(0, end);
        this.buffered = this.buffered.slice(end + 2);
        return line;
      }
      const { value, done } = await this.reader.read();
      if (done) throw new Error("IMAP server closed the connection");
      this.buffered += this.decoder.decode(value, { stream: true });
    }
  }

  /** Sends `text` and reads to its tagged reply. Returns the untagged lines; throws `CommandFailed` for NO or BAD. */
  async command(text: string): Promise<string[]> {
    const tag = `g${++this.tagsSent}`;
    await this.writer.write(new TextEncoder().encode(`${tag} ${text}\r\n`));
    const untagged: string[] = [];
    for (;;) {
      const line = await this.line();
      if (!line.startsWith(`${tag} `)) {
        untagged.push(line);
        continue;
      }
      const [, status, rest] = /^\S+ (OK|NO|BAD)\b ?(.*)$/i.exec(line) ?? [];
      if (status?.toUpperCase() === "OK") return untagged;
      throw new CommandFailed(status?.toUpperCase() === "NO" ? "NO" : "BAD", rest ?? line);
    }
  }

  /** Lets go of the socket's streams, as `startTls` needs. */
  release(): void {
    this.reader.releaseLock();
    this.writer.releaseLock();
  }
}
