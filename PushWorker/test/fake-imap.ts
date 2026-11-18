import type { Connect, ImapLogin } from "../src/imap";

/** A scripted IMAP server: `reply` answers each command line the client sends, by tag. */
export interface FakeImap {
  connect: Connect;
  /** Each connection's login, then the lines the client sent on it ("[TLS]" marks STARTTLS taking effect). */
  sessions: { login: ImapLogin; lines: string[] }[];
  /** Sends `line` unasked on every connection, as a server announcing new mail to the clients idling in the Inbox. */
  announce(line: string): void;
}

export type Reply = (tag: string, command: string) => string[];

/** A message as the fake server's FETCH hands it over. */
export interface FakeMessage {
  uid: number;
  flags?: string[];
  from: string;
  subject: string;
}

/**
 * iCloud as it answers the relay: LOGIN, STATUS, EXAMINE, IDLE, the new-mail FETCH and LOGOUT, with `status` as the
 * Inbox's UIDs. The FETCH hands over `messages()`, by default one unread email from Dana as the newest message.
 */
export function inboxServer(
  status: { uidValidity: number; uidNext: number },
  login: "ok" | "refused" = "ok",
  messages: () => FakeMessage[] = () => [{ uid: status.uidNext - 1, from: "Dana Levi <dana@example.com>", subject: "Lunch?" }],
): Reply {
  let idling = "";
  return (tag, command) => {
    if (tag === "DONE") return [`${idling} OK IDLE terminated`];
    if (command === "EXAMINE INBOX") return ["* 3 EXISTS", `${tag} OK [READ-ONLY] EXAMINE completed`];
    if (command === "IDLE") {
      idling = tag;
      return ["+ idling"];
    }
    if (command.startsWith("LOGIN")) {
      return login === "ok"
        ? [`${tag} OK [CAPABILITY IMAP4rev1 IDLE] LOGIN completed`]
        : [`${tag} NO [AUTHENTICATIONFAILED] Authentication failed`];
    }
    if (command.startsWith("STATUS")) {
      return [`* STATUS "INBOX" (UIDNEXT ${status.uidNext} UIDVALIDITY ${status.uidValidity})`, `${tag} OK STATUS done`];
    }
    if (command.startsWith("UID FETCH")) {
      return [
        ...messages().flatMap((message, index) => {
          const headers = `From: ${message.from}\r\nSubject: ${message.subject}\r\n\r\n`;
          return [
            `* ${index + 1} FETCH (UID ${message.uid} FLAGS (${(message.flags ?? []).join(" ")}) BODY[HEADER.FIELDS (FROM SUBJECT)] {${headers.length}}`,
            ...headers.split("\r\n").slice(0, -1),
            ")",
          ];
        }),
        `${tag} OK FETCH done`,
      ];
    }
    if (command === "STARTTLS") return [`${tag} OK Begin TLS`];
    if (command === "LOGOUT") return ["* BYE", `${tag} OK LOGOUT completed`];
    return [`${tag} BAD unknown`];
  };
}

export function fakeImap(reply: () => Reply, greeting = "* OK [CAPABILITY IMAP4rev1] ready"): FakeImap {
  const sessions: FakeImap["sessions"] = [];
  const connections: ((lines: string[]) => void)[] = [];
  const connect: Connect = (login) => {
    const session = { login, lines: [] as string[] };
    sessions.push(session);
    const answer = reply();
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    const encoder = new TextEncoder();
    const send = (lines: string[]) => {
      for (const line of lines) controller.enqueue(encoder.encode(`${line}\r\n`));
    };
    connections.push(send);
    const socket = {
      readable: new ReadableStream<Uint8Array>({
        start(started) {
          controller = started;
          send([greeting]);
        },
      }),
      writable: new WritableStream<Uint8Array>({
        write(chunk) {
          for (const line of new TextDecoder().decode(chunk).split("\r\n").filter(Boolean)) {
            session.lines.push(line);
            const [tag = "", ...rest] = line.split(" ");
            send(answer(tag, rest.join(" ")));
          }
        },
      }),
      startTls() {
        session.lines.push("[TLS]");
        return socket;
      },
      close: async () => {},
    };
    return socket as unknown as Socket;
  };
  return { connect, sessions, announce: (line) => connections.forEach((send) => send([line])) };
}
