import type { ApnsEnvironment } from "./apns";
import type { Env } from "./env";
import { clientStateHash, sameHash } from "./graph";
import {
  type Connect,
  connectToServer,
  type ImapLogin,
  type InboxStatus,
  inboxStatus,
  isQuotable,
  LoginRefused,
} from "./imap";
import {
  canonicalLogin,
  findWatch,
  loginSealer,
  loginState,
  refusedAgain,
  removeWatch,
  renewWatch,
  setLoginState,
  storeWatch,
  WATCH_LIFETIME_MS,
  WATCHING,
  type WatchState,
} from "./imap-watches";
import { BadRequest, readJson } from "./shared";

const WATCH_ID = /^[0-9a-f-]{36}$/i;
const SECRET = /^[0-9a-f]{64}$/i;
const ACCOUNT_ID = /^[A-Za-z0-9-]{1,64}$/;
const DEVICE_TOKEN = /^[0-9a-f]{64,200}$/i;
/** A host name, never a URL or anything with spaces. */
const HOST = /^[A-Za-z0-9.-]{1,253}$/;
const ENVIRONMENTS: readonly ApnsEnvironment[] = ["sandbox", "production"];
const SECURITIES: readonly ImapLogin["security"][] = ["tls", "startTLS"];

/** Reads a watch's ID and secret from a request body. */
function watchCredentials(body: Record<string, unknown>): { watchId: string; secret: string } {
  const { watchId, secret } = body;
  if (typeof watchId !== "string" || !WATCH_ID.test(watchId)) throw new BadRequest("bad watchId");
  if (typeof secret !== "string" || !SECRET.test(secret)) throw new BadRequest("bad secret");
  return { watchId: watchId.toLowerCase(), secret };
}

function loginIn(body: Record<string, unknown>): ImapLogin {
  const { host, port, security, username, password } = body;
  if (typeof host !== "string" || !HOST.test(host)) throw new BadRequest("bad host");
  if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65_535) throw new BadRequest("bad port");
  const found = SECURITIES.find((candidate) => candidate === security);
  if (!found) throw new BadRequest("security must be tls or startTLS");
  // IMAP quoted strings carry printable ASCII only, which app passwords and addresses are.
  if (typeof username !== "string" || username.length === 0 || username.length > 320 || !isQuotable(username)) {
    throw new BadRequest("bad username");
  }
  if (typeof password !== "string" || password.length === 0 || password.length > 256 || !isQuotable(password)) {
    throw new BadRequest("bad password");
  }
  return { host, port, security: found, username, password };
}

/**
 * A registration checks a refused login again once this long has passed since the server last refused it. Opening the
 * app registers, so it brings a wrongly refused watch back, while a burst of registrations costs one login.
 */
export const RECHECK_AFTER_MS = 60_000;

/**
 * Stores or renews a device's watch on an IMAP Inbox. A login the relay already watches with is renewed without
 * logging in, and one the server refused under any watch within the last minute is refused at once (401). Any other
 * login is checked by logging in, which also gives the Inbox's UIDs to compare later ones with: 401 when the server
 * refuses it, 503 when the server can't be reached, so the app tries again. 403 when the watch ID is someone else's.
 */
export async function registerWatch(
  request: Request,
  env: Env,
  now: number,
  open: Connect = connectToServer,
): Promise<Response> {
  const body = await readJson(request);
  const { watchId, secret } = watchCredentials(body);
  const { account, deviceToken } = body;
  const environment = ENVIRONMENTS.find((candidate) => candidate === body.environment);
  if (!environment) throw new BadRequest("environment must be sandbox or production");
  if (typeof account !== "string" || !ACCOUNT_ID.test(account)) throw new BadRequest("bad account");
  if (typeof deviceToken !== "string" || !DEVICE_TOKEN.test(deviceToken)) throw new BadRequest("bad deviceToken");
  const login = loginIn(body);
  const device = { token: deviceToken.toLowerCase(), environment };
  const expiresAt = now + WATCH_LIFETIME_MS;

  const sealer = loginSealer(env.EMAIL_HMAC_SECRET);
  const secretHash = await clientStateHash(secret);
  const loginHash = await sealer.hash(canonicalLogin(login));
  const existing = await findWatch(env.DB, watchId);
  if (existing && !sameHash(existing.secretHash, secretHash)) return new Response(null, { status: 403 });
  if (existing?.loginHash === loginHash && existing.state.kind === "watching") {
    await renewWatch(env.DB, watchId, account, device, expiresAt);
    return new Response(null, { status: 204 });
  }
  // By login, not by watch: a device whose registration failed makes a new watch ID for the same login.
  const known = await loginState(env.DB, loginHash);
  if (known?.kind === "refused" && now < known.refusedAt + RECHECK_AFTER_MS) return new Response(null, { status: 401 });

  // Each check is a login at someone's server: a few a minute from one address is plenty for the app, and too few
  // to try passwords with.
  const address = request.headers.get("cf-connecting-ip") ?? "unknown";
  if (!(await env.IMAP_LOGIN_CHECKS.limit({ key: address })).success) return new Response(null, { status: 429 });
  let checked: { state: WatchState; inbox: InboxStatus };
  try {
    checked = { state: WATCHING, inbox: await inboxStatus(login, open) };
  } catch (error) {
    if (!(error instanceof LoginRefused)) {
      console.warn(`IMAP check failed: ${error instanceof Error ? error.message : String(error)}`);
      return new Response(null, { status: 503 });
    }
    // Kept, so the login is tried again later (`isDue`) and the next registrations are answered from here. A
    // watch that was following this login keeps its place in the Inbox, for the mail that arrives meanwhile.
    const refused = refusedAgain(known, now);
    const inbox = existing?.loginHash === loginHash ? existing.inbox : { uidValidity: 0, uidNext: 0 };
    checked = { state: refused, inbox };
    console.warn(`IMAP login refused at registration (${refused.refusals} in a row): ${error.message}`);
  }
  const stored = await storeWatch(env.DB, {
    watchId,
    secretHash,
    account,
    device,
    login: await sealer.seal(canonicalLogin(login)),
    loginHash,
    ...checked,
    expiresAt,
  });
  if (!stored) return new Response(null, { status: 403 });
  // The server's answer holds for every device watching with this login.
  await setLoginState(env.DB, loginHash, checked.state);
  return new Response(null, { status: checked.state.kind === "watching" ? 204 : 401 });
}

export async function unregisterWatch(request: Request, env: Env): Promise<Response> {
  const { watchId, secret } = watchCredentials(await readJson(request));
  await removeWatch(env.DB, watchId, await clientStateHash(secret));
  return new Response(null, { status: 204 });
}
