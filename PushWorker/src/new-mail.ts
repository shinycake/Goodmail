/**
 * The one gate every alert passes through. The relay alerts only for an email it has read the sender and subject of,
 * so the alert means something even when the device can't add to it. A bare "New mail" can't be built here, so no
 * provider, now or later, can send one: each must find the mail and hand it over as an `Arrival`.
 */

/** An email the app would alert for, as Apple Mail would: unread and in the Inbox, whoever sent it. */
export interface NewMail {
  /** The sender's name, or their address when the From header gives no name. */
  sender: string;
  subject: string;
  /** The service's ID of its conversation, when the provider knows it, so a tap on the watch can open it. */
  threadID?: string;
}

/**
 * What a provider found in a change: `mail` to alert for (the newest such email), `none` when the change brought
 * nothing the app alerts for (a read, an archive, a delete), or `retry` when it couldn't tell
 * yet. A retry never alerts: the caller tries again later, so no real email is lost and no empty alert goes out.
 */
export type Arrival = { kind: "mail"; newest: NewMail } | { kind: "none" } | { kind: "retry" };

export const NONE: Arrival = { kind: "none" };
export const RETRY: Arrival = { kind: "retry" };

/** How the device finds the account: Gmail's address with its history ID, or the app's own account ID. */
export type Target = { account: string; historyId: string } | { accountID: string };

/** Longest sender and subject sent, well inside APNs' 4 KB, and more than a lock screen shows. */
const MOST_SENDER = 100;
const MOST_SUBJECT = 250;

/**
 * The alert for `mail`, named `alert` for the iPhone to confirm (ADR-023): the sender as the title and the subject as the body, mutable so the Notification Service
 * Extension can add the sender's picture and a preview, and showing as it is when the extension can't.
 */
export function alertPayload(mail: NewMail, target: Target, alert: string): object {
  const subject = clip(mail.subject, MOST_SUBJECT);
  return {
    aps: {
      alert: subject ? { title: clip(mail.sender, MOST_SENDER), body: subject } : { title: clip(mail.sender, MOST_SENDER) },
      sound: "default",
      "mutable-content": 1,
    },
    ...target,
    alert,
    ...(mail.threadID && { threadID: mail.threadID }),
  };
}

/** The newest of `found`, or `none` when it is empty. */
export function newestOf(found: { mail: NewMail; at: number }[]): Arrival {
  const newest = found.reduce<{ mail: NewMail; at: number } | undefined>(
    (best, next) => (best === undefined || next.at > best.at ? next : best),
    undefined,
  );
  return newest ? { kind: "mail", newest: newest.mail } : NONE;
}

function clip(text: string, most: number): string {
  const trimmed = text.replace(/\s+/g, " ").trim();
  return trimmed.length <= most ? trimmed : `${trimmed.slice(0, most - 1)}…`;
}

/** The display name in a From header, or its address when it has none: `"Dana" <dana@x>` is `Dana`. */
export function senderName(from: string): string {
  const decoded = decodeEncodedWords(from).trim();
  const angle = /^(.*?)<([^>]*)>\s*$/.exec(decoded);
  if (!angle) return decoded.replace(/^"|"$/g, "");
  const name = angle[1]!.trim().replace(/^"|"$/g, "").replace(/\\(.)/g, "$1").trim();
  return name || angle[2]!.trim();
}

/**
 * Decodes RFC 2047 encoded words (`=?UTF-8?B?...?=` and `=?ISO-8859-1?Q?...?=`), as IMAP servers send non-ASCII
 * headers. Whitespace between two encoded words is dropped, as the RFC says. A word that can't be decoded stays as
 * it is.
 */
export function decodeEncodedWords(text: string): string {
  return text
    .replace(/(=\?[^?]+\?[BbQq]\?[^?]*\?=)\s+(?==\?)/g, "$1")
    .replace(/=\?([^?]+)\?([BbQq])\?([^?]*)\?=/g, (word, charset: string, encoding: string, data: string) => {
      try {
        const bytes = encoding.toUpperCase() === "B" ? base64Bytes(data) : quotedPrintableBytes(data);
        return new TextDecoder(charset.split("*")[0]!.toLowerCase(), { fatal: true, ignoreBOM: false }).decode(bytes);
      } catch {
        return word;
      }
    });
}

function base64Bytes(data: string): Uint8Array {
  const binary = atob(data);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function quotedPrintableBytes(data: string): Uint8Array {
  const bytes: number[] = [];
  for (let index = 0; index < data.length; index++) {
    const character = data[index]!;
    if (character === "_") bytes.push(0x20);
    else if (character === "=" && /^[0-9A-Fa-f]{2}$/.test(data.slice(index + 1, index + 3))) {
      bytes.push(parseInt(data.slice(index + 1, index + 3), 16));
      index += 2;
    } else bytes.push(character.charCodeAt(0));
  }
  return Uint8Array.from(bytes);
}
