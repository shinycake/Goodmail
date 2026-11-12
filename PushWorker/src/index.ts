import { type ApnsConfig, type ApnsEnvironment, ApnsSigner, newMailPayload, type PushOutcome, sendPush } from "./apns";
import { base64Decode } from "./encoding";
import type { Env } from "./env";
import { GoogleKeys, TokenError, verifyIdToken, verifyPubSubToken } from "./google";
import {
  accountId,
  claimHistoryId,
  devicesFor,
  registerDevice,
  releaseHistoryId,
  removeToken,
  unregisterDevice,
} from "./store";

export type { Env } from "./env";

/** Shared by every request this isolate serves, so the JWKS and the APNs token are fetched and signed rarely. */
const googleKeys = new GoogleKeys();
let apnsSigner: ApnsSigner | undefined;

const DEVICE_TOKEN = /^[0-9a-f]{64,200}$/i;
const HISTORY_ID = /^\d{1,20}$/;
const ENVIRONMENTS: readonly ApnsEnvironment[] = ["sandbox", "production"];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const { pathname } = new URL(request.url);
    try {
      if (pathname === "/v1/devices" && request.method === "POST") return await register(request, env);
      if (pathname === "/v1/devices" && request.method === "DELETE") return await unregister(request, env);
      if (pathname === "/v1/pubsub" && request.method === "POST") return await pubSubPush(request, env);
      if (pathname === "/v1/devices" || pathname === "/v1/pubsub") return new Response(null, { status: 405 });
      return new Response(null, { status: 404 });
    } catch (error) {
      if (error instanceof TokenError) return new Response(null, { status: 401 });
      if (error instanceof BadRequest) return new Response(error.message, { status: 400 });
      throw error;
    }
  },
} satisfies ExportedHandler<Env>;

class BadRequest extends Error {}

const nowSeconds = () => Math.floor(Date.now() / 1000);

async function readJson(request: Request): Promise<Record<string, unknown>> {
  const body = await request.json().catch(() => undefined);
  if (typeof body !== "object" || body === null) throw new BadRequest("expected a JSON object");
  return body as Record<string, unknown>;
}

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

  // Pub/Sub's redelivery is the only retry, so an alert that reached no device gives its claim back and asks for it.
  let outcomes: PushOutcome[];
  try {
    const signer = signerFor(env);
    const payload = newMailPayload(emailAddress, historyId);
    outcomes = await Promise.all(
      devices.map(async (device) => {
        const outcome = await sendPush(signer, device, payload);
        if (outcome === "gone") await removeToken(env.DB, device.token);
        return outcome;
      }),
    );
  } catch (error) {
    await releaseHistoryId(env.DB, claim);
    throw error;
  }
  if (outcomes.includes("failed") && !outcomes.includes("delivered")) {
    await releaseHistoryId(env.DB, claim);
    return new Response(null, { status: 503 });
  }
  return new Response(null, { status: 204 });
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
