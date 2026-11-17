import { type ApnsConfig, type ApnsEnvironment, ApnsSigner, type PushOutcome, sendAlert } from "./apns";
import { base64Decode } from "./encoding";
import type { Env } from "./env";
import { TokenError, verifyIdToken, verifyPubSubToken } from "./google";
import { forgetGrant, grantsFor, storeGrant } from "./grant-routes";
import { pollWatches } from "./imap-poll";
import { registerWatch, unregisterWatch } from "./imap-routes";
import { OutlookGrantRevoked, OutlookGrants, refreshOutlookToken } from "./outlook";
import { BadRequest, googleKeys, mailboxCheck, nowSeconds, outlookCheck, readJson } from "./shared";
import {
  hasGraphSubscriptions,
  registerGraphSubscription,
  unregisterGraphSubscription,
  verifiedSubscription,
} from "./graph";
import {
  accountId,
  claimHistoryId,
  claimPushSlot,
  devicesFor,
  registerDevice,
  releaseHistoryId,
  releasePushSlot,
  unregisterDevice,
} from "./store";
import { forgetDeviceToken } from "./tokens";

export type { Env } from "./env";

/** Shared by every request this isolate serves, so the APNs token is signed rarely. */
let apnsSigner: ApnsSigner | undefined;

const DEVICE_TOKEN = /^[0-9a-f]{64,200}$/i;
const HISTORY_ID = /^\d{1,20}$/;
const ENVIRONMENTS: readonly ApnsEnvironment[] = ["sandbox", "production"];
const GRAPH_SUBSCRIPTION_ID = /^[0-9a-f-]{36}$/i;
/** Graph allows up to 128 characters; the app sends 64 hex digits. */
const CLIENT_STATE = /^[\x21-\x7e]{32,128}$/;
const ACCOUNT_ID = /^[A-Za-z0-9-]{1,64}$/;

export default {
  async fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;
    try {
      if (pathname === "/v1/devices" && request.method === "POST") return await register(request, env);
      if (pathname === "/v1/devices" && request.method === "DELETE") return await unregister(request, env);
      if (pathname === "/v1/pubsub" && request.method === "POST") return await pubSubPush(request, env);
      if (pathname === "/v1/gmail/grants" && request.method === "POST") return await storeGrant(request, env);
      if (pathname === "/v1/graph" && request.method === "POST") return await graphNotification(request, url, env, context);
      if (pathname === "/v1/graph/subscriptions" && request.method === "POST") return await registerGraph(request, env);
      if (pathname === "/v1/graph/subscriptions" && request.method === "DELETE") return await unregisterGraph(request, env);
      if (pathname === "/v1/graph/grants" && request.method === "POST") return await storeGraphGrant(request, env);
      if (pathname === "/v1/imap/watches" && request.method === "POST") return await registerWatch(request, env, Date.now());
      if (pathname === "/v1/imap/watches" && request.method === "DELETE") return await unregisterWatch(request, env);
      const known = [
        "/v1/devices",
        "/v1/pubsub",
        "/v1/graph",
        "/v1/graph/subscriptions",
        "/v1/graph/grants",
        "/v1/gmail/grants",
        "/v1/imap/watches",
      ];
      if (known.includes(pathname)) {
        return new Response(null, { status: 405 });
      }
      return new Response(null, { status: 404 });
    } catch (error) {
      if (error instanceof TokenError) return new Response(null, { status: 401 });
      if (error instanceof BadRequest) return new Response(error.message, { status: 400 });
      throw error;
    }
  },

  /** Every 5 minutes (wrangler.toml `[triggers]`): watches the IMAP Inboxes until the next run. */
  async scheduled(_controller: ScheduledController, env: Env, context: ExecutionContext): Promise<void> {
    context.waitUntil(pollWatches(env, signerFor(env), Date.now()));
  },
} satisfies ExportedHandler<Env>;

/** Verifies the ID token in the body and returns the account ID it proves, plus the validated device token. */
async function authenticateDevice(body: Record<string, unknown>, env: Env): Promise<{ account: string; token: string }> {
  const { idToken, deviceToken } = body;
  if (typeof idToken !== "string") throw new BadRequest("idToken is required");
  if (typeof deviceToken !== "string" || !DEVICE_TOKEN.test(deviceToken)) throw new BadRequest("bad deviceToken");
  const email = await verifyIdToken(idToken, env.GOOGLE_CLIENT_ID, googleKeys, nowSeconds());
  return { account: await accountId(email, env.EMAIL_HMAC_SECRET), token: deviceToken.toLowerCase() };
}

async function register(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const environment = ENVIRONMENTS.find((candidate) => candidate === body.environment);
  if (!environment) throw new BadRequest("environment must be sandbox or production");
  const { account, token } = await authenticateDevice(body, env);
  await registerDevice(env.DB, account, { token, environment }, Date.now());
  return new Response(null, { status: 204 });
}

async function unregister(request: Request, env: Env): Promise<Response> {
  const { account, token } = await authenticateDevice(await readJson(request), env);
  await unregisterDevice(env.DB, account, token);
  // No device is left to alert, so the relay has no reason to keep looking at the mailbox.
  if ((await devicesFor(env.DB, account)).length === 0) await forgetGrant(env, account);
  return new Response(null, { status: 204 });
}

/**
 * Handles one Pub/Sub push. Any 2xx acknowledges the message; malformed messages are acknowledged too, since
 * redelivering them can't help.
 */
async function pubSubPush(request: Request, env: Env): Promise<Response> {
  const bearer = /^Bearer (.+)$/.exec(request.headers.get("authorization") ?? "")?.[1];
  if (!bearer) return new Response(null, { status: 401 });
  await verifyPubSubToken(bearer, env.PUBSUB_AUDIENCE, env.PUBSUB_SERVICE_ACCOUNT, googleKeys, nowSeconds());

  const notification = await decodeNotification(request);
  if (!notification) return new Response(null, { status: 204 });
  const { emailAddress, historyId } = notification;

  const account = await accountId(emailAddress, env.EMAIL_HMAC_SECRET);
  const devices = await devicesFor(env.DB, account);
  if (devices.length === 0) return new Response(null, { status: 204 });
  const claim = await claimHistoryId(env.DB, account, historyId);
  if (!claim) return new Response(null, { status: 204 });
  // Only mail the relay has read alerts (new-mail.ts). One it couldn't read yet gives the claim back and asks
  // Pub/Sub to deliver the notification again.
  const arrival = await mailboxCheck.arrival(grantsFor(env), env.GOOGLE_CLIENT_ID, account, claim.previous);
  if (arrival.kind === "retry") {
    await releaseHistoryId(env.DB, claim);
    return new Response(null, { status: 503 });
  }
  if (arrival.kind === "none") return new Response(null, { status: 204 });
  const now = Date.now();
  const slot = await claimPushSlot(env.DB, account, now);
  if (slot === false) return new Response(null, { status: 204 });
  const release = async () => {
    await releaseHistoryId(env.DB, claim);
    await releasePushSlot(env.DB, account, now, slot);
  };

  // Pub/Sub's redelivery is the only retry, so an alert that reached no device gives its claim back and asks for it.
  let outcomes: PushOutcome[];
  try {
    const signer = signerFor(env);
    outcomes = await Promise.all(
      devices.map(async (device) => {
        const outcome = await sendAlert(signer, device, arrival.newest, { account: emailAddress, historyId });
        if (outcome === "gone") await forgetDeviceToken(env.DB, device.token);
        return outcome;
      }),
    );
  } catch (error) {
    await release();
    throw error;
  }
  if (outcomes.includes("failed") && !outcomes.includes("delivered")) {
    await release();
    return new Response(null, { status: 503 });
  }
  return new Response(null, { status: 204 });
}

/** Reads a Graph subscription's ID and clientState from a registration body. */
function graphCredentials(body: Record<string, unknown>): { subscriptionId: string; clientState: string } {
  const { subscriptionId, clientState } = body;
  if (typeof subscriptionId !== "string" || !GRAPH_SUBSCRIPTION_ID.test(subscriptionId)) {
    throw new BadRequest("bad subscriptionId");
  }
  if (typeof clientState !== "string" || !CLIENT_STATE.test(clientState)) throw new BadRequest("bad clientState");
  return { subscriptionId: subscriptionId.toLowerCase(), clientState };
}

/** Stores the device's Graph subscription; 403 when it is registered under another clientState. */
async function registerGraph(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const { subscriptionId, clientState } = graphCredentials(body);
  const { account, deviceToken, expiresAt } = body;
  const environment = ENVIRONMENTS.find((candidate) => candidate === body.environment);
  if (!environment) throw new BadRequest("environment must be sandbox or production");
  if (typeof account !== "string" || !ACCOUNT_ID.test(account)) throw new BadRequest("bad account");
  if (typeof deviceToken !== "string" || !DEVICE_TOKEN.test(deviceToken)) throw new BadRequest("bad deviceToken");
  if (typeof expiresAt !== "number" || !Number.isFinite(expiresAt)) throw new BadRequest("bad expiresAt");
  const stored = await registerGraphSubscription(
    env.DB,
    { subscriptionId, account, device: { token: deviceToken.toLowerCase(), environment }, expiresAt },
    clientState,
    Date.now(),
  );
  return new Response(null, { status: stored ? 204 : 403 });
}

async function unregisterGraph(request: Request, env: Env): Promise<Response> {
  const { subscriptionId, clientState } = graphCredentials(await readJson(request));
  const subscription = await verifiedSubscription(env.DB, subscriptionId, clientState);
  await unregisterGraphSubscription(env.DB, subscriptionId, clientState);
  // No device is left to alert, so the relay has no reason to keep the account's token.
  if (subscription && !(await hasGraphSubscriptions(env.DB, subscription.account))) {
    await new OutlookGrants(env.DB, env.EMAIL_HMAC_SECRET).remove(subscription.account);
    outlookCheck.forget(subscription.account);
  }
  return new Response(null, { status: 204 });
}

/**
 * Stores the app's Outlook refresh token for the account of a Graph subscription, which the device proves with its
 * clientState. The app sends it each time it brings push up to date, so a token already held answers at once. A new
 * one must refresh; 401 when Microsoft refuses it, 403 for a subscription that isn't the caller's.
 */
async function storeGraphGrant(request: Request, env: Env): Promise<Response> {
  const body = await readJson(request);
  const { subscriptionId, clientState } = graphCredentials(body);
  const { refreshToken } = body;
  if (typeof refreshToken !== "string" || refreshToken.length === 0 || refreshToken.length > 4096) {
    throw new BadRequest("bad refreshToken");
  }
  const subscription = await verifiedSubscription(env.DB, subscriptionId, clientState);
  if (!subscription) return new Response(null, { status: 403 });
  const grants = new OutlookGrants(env.DB, env.EMAIL_HMAC_SECRET);
  if (await grants.holds(subscription.account, refreshToken)) return new Response(null, { status: 204 });
  try {
    const token = await refreshOutlookToken(refreshToken, env.OUTLOOK_CLIENT_ID, Date.now());
    await grants.store(subscription.account, refreshToken, token.refreshToken ?? refreshToken, Date.now());
  } catch (error) {
    if (error instanceof OutlookGrantRevoked) return new Response(null, { status: 401 });
    throw error;
  }
  outlookCheck.forget(subscription.account);
  return new Response(null, { status: 204 });
}

/** Waits before each new try at reading a notification's mail that Graph couldn't hand over yet. */
const GRAPH_RETRY_DELAYS_MS = [3_000, 10_000];

/**
 * Graph's change notifications. Creating a subscription first checks the URL by sending a `validationToken`, which
 * must come straight back as text. A notification batch is acknowledged at once, as Graph wants within seconds. Each
 * subscription it names with the right clientState gets one alert, for the newest message it named that the app
 * alerts for (`new-mail.ts`), tried again a couple of times when the mail can't be read yet.
 */
async function graphNotification(request: Request, url: URL, env: Env, context: ExecutionContext): Promise<Response> {
  const validationToken = url.searchParams.get("validationToken");
  if (validationToken !== null) {
    return new Response(validationToken, { status: 200, headers: { "content-type": "text/plain" } });
  }
  const body = (await request.json().catch(() => undefined)) as { value?: unknown } | undefined;
  const notifications = Array.isArray(body?.value) ? body.value : [];
  const named = new Map<string, { clientState: string; messageIds: Set<string> }>();
  for (const notification of notifications) {
    const { subscriptionId, clientState, resourceData } = (notification ?? {}) as Record<string, unknown>;
    if (typeof subscriptionId !== "string" || typeof clientState !== "string") continue;
    const entry = named.get(subscriptionId.toLowerCase()) ?? { clientState, messageIds: new Set<string>() };
    const id = (resourceData as { id?: unknown } | undefined)?.id;
    if (typeof id === "string") entry.messageIds.add(id);
    named.set(subscriptionId.toLowerCase(), entry);
  }
  const grants = new OutlookGrants(env.DB, env.EMAIL_HMAC_SECRET);
  context.waitUntil(
    Promise.all(
      [...named].map(async ([subscriptionId, { clientState, messageIds }]) => {
        const subscription = await verifiedSubscription(env.DB, subscriptionId, clientState);
        if (!subscription) return;
        const ids = [...messageIds];
        let arrival = await outlookCheck.arrival(grants, env.OUTLOOK_CLIENT_ID, subscription.account, ids);
        for (const delay of GRAPH_RETRY_DELAYS_MS) {
          if (arrival.kind !== "retry") break;
          await new Promise((resolve) => setTimeout(resolve, delay));
          arrival = await outlookCheck.arrival(grants, env.OUTLOOK_CLIENT_ID, subscription.account, ids);
        }
        if (arrival.kind !== "mail") return;
        const outcome = await sendAlert(signerFor(env), subscription.device, arrival.newest, {
          accountID: subscription.account,
        });
        if (outcome === "gone") await forgetDeviceToken(env.DB, subscription.device.token);
      }),
    ),
  );
  return new Response(null, { status: 202 });
}

/** Gmail's notification is `{emailAddress, historyId}` as base64 JSON in `message.data`. */
async function decodeNotification(request: Request): Promise<{ emailAddress: string; historyId: string } | undefined> {
  try {
    const envelope = (await request.json()) as { message?: { data?: string } };
    const data = JSON.parse(new TextDecoder().decode(base64Decode(envelope.message?.data ?? ""))) as {
      emailAddress?: unknown;
      historyId?: unknown;
    };
    const historyId = typeof data.historyId === "number" ? String(Math.trunc(data.historyId)) : data.historyId;
    if (typeof data.emailAddress !== "string" || typeof historyId !== "string" || !HISTORY_ID.test(historyId)) {
      return undefined;
    }
    return { emailAddress: data.emailAddress, historyId };
  } catch {
    return undefined;
  }
}

/** The isolate's signer, rebuilt only when the APNs secrets change. */
function signerFor(env: Env): ApnsSigner {
  const config: ApnsConfig = {
    keyId: env.APNS_KEY_ID,
    teamId: env.APNS_TEAM_ID,
    privateKey: env.APNS_PRIVATE_KEY,
    topic: env.APNS_TOPIC,
  };
  if (!apnsSigner || JSON.stringify(apnsSigner.config) !== JSON.stringify(config)) apnsSigner = new ApnsSigner(config);
  return apnsSigner;
}
