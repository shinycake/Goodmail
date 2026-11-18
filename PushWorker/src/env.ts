import type { InboxHolder } from "./inbox-holder";

/** Bindings from wrangler.toml (vars, D1 and the rate limit) plus the two secrets set with `wrangler secret put`. */
export interface Env {
  DB: D1Database;
  /** The Durable Object that keeps a connection open to each watched IMAP Inbox (inbox-holder.ts). */
  INBOX_HOLDER: DurableObjectNamespace<InboxHolder>;
  /** The app's Microsoft client ID, which its Outlook refresh tokens are refreshed with. */
  OUTLOOK_CLIENT_ID: string;
  /** The iOS OAuth client ID; registration ID tokens must carry it as `aud`. */
  GOOGLE_CLIENT_ID: string;
  /** The audience set on the Pub/Sub push subscription, normally this Worker's `/v1/pubsub` URL. */
  PUBSUB_AUDIENCE: string;
  /** The service account the push subscription signs its OIDC tokens as. */
  PUBSUB_SERVICE_ACCOUNT: string;
  APNS_TOPIC: string;
  APNS_KEY_ID: string;
  APNS_TEAM_ID: string;
  /** Secret: the APNs auth key (.p8, PKCS #8 PEM). */
  APNS_PRIVATE_KEY: string;
  /** Limits IMAP login checks per client address (wrangler.toml `[[ratelimits]]`). */
  IMAP_LOGIN_CHECKS: RateLimit;
  /** Limits App Attest challenges per client address (wrangler.toml `[[ratelimits]]`). */
  ATTEST_CHALLENGES: RateLimit;
  /** `observe` logs requests the genuine app didn't sign; anything else refuses them (attest-routes.ts). */
  APP_ATTEST: string;
  /** Secret: the HMAC key that turns email addresses into account IDs. */
  EMAIL_HMAC_SECRET: string;
}
