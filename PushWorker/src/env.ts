/** Bindings from wrangler.toml (vars and D1) plus the two secrets set with `wrangler secret put`. */
export interface Env {
  DB: D1Database;
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
  /** Secret: the HMAC key that turns email addresses into account IDs. */
  EMAIL_HMAC_SECRET: string;
}
