import type { Connect, ImapLogin } from "../src/imap";

/** A scripted IMAP server: `reply` answers each command line the client sends, by tag. */
export interface FakeImap {
  connect: Connect;
  /** Each connection's login, then the lines the client sent on it ("[TLS]" marks STARTTLS taking effect). */
  sessions: { login: ImapLogin; lines: string[] }[];
}

export type Reply = (tag: string, command: string) => string[];

/** iCloud as it answers the relay: LOGIN, STATUS and LOGOUT, with `status` as the Inbox's UIDs. */
export function inboxServer(status: { uidValidity: number; uidNext: number }, login: "ok" | "refused" = "ok"): Reply {
  return (tag, command) => {
    if (command.startsWith("LOGIN")) {
      return login === "ok"
        ? [`${tag} OK [CAPABILITY IMAP4rev1 IDLE] LOGIN completed`]
        : [`${tag} NO [AUTHENTICATIONFAILED] Authentication failed`];
    }
    if (command.startsWith("STATUS")) {
      return [`* STATUS "INBOX" (UIDNEXT ${status.uidNext} UIDVALIDITY ${status.uidValidity})`, `${tag} OK STATUS done`];
    }
    if (command === "STARTTLS") return [`${tag} OK Begin TLS`];
    if (command === "LOGOUT") return ["* BYE", `${tag} OK LOGOUT completed`];
    return [`${tag} BAD unknown`];
  };
}

export function fakeImap(reply: () => Reply, greeting = "* OK [CAPABILITY IMAP4rev1] ready"): FakeImap {
  const sessions: FakeImap["sessions"] = [];
  const connect: Connect = (login) => {
    const session = { login, lines: [] as string[] };
    sessions.push(session);
    const answer = reply();
    let controller!: ReadableStreamDefaultController<Uint8Array>;
    const encoder = new TextEncoder();
    const send = (lines: string[]) => {
      for (const line of lines) controller.enqueue(encoder.encode(`${line}\r\n`));
    };
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
  return { connect, sessions };
}
