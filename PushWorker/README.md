# PushWorker

Goodmail's push backend (ADR-006): a Cloudflare Worker with D1 and no runtime dependencies. Gmail publishes a change to Pub/Sub, Pub/Sub pushes it here, and the Worker sends an APNs alert to the account's devices. The Notification Service Extension then fetches the change itself.

## API

| Route | Body | Result |
|---|---|---|
| `POST /v1/devices` | `{"idToken", "deviceToken", "environment": "sandbox" \| "production"}` | 204; 401 for a bad ID token |
| `DELETE /v1/devices` | `{"idToken", "deviceToken"}` | 204 |
| `POST /v1/pubsub` | a Pub/Sub push with an OIDC bearer token | 204 acknowledges it |

- **Registration:** `idToken` is the Google ID token from sign-in. It needs the `openid` and `email` scopes, and `aud` must be the iOS client ID. The Worker stores only HMAC-SHA256 of the address.
- **Push:** the payload is `{"aps": {"alert": …, "mutable-content": 1}, "account": "<email>", "historyId": "<id>"}`. Duplicate deliveries and history IDs that aren't newer are dropped. APNs `410` and `BadDeviceToken` remove the token. When the alert reaches no device because sending failed or threw, the Worker gives back the history ID and answers 503, so Pub/Sub redelivers it.

## Development

The internal disk is tight, so `node_modules` and the npm cache live on the external drive:

```bash
mkdir -p /Volumes/Idan1TB/Goodmail-build/worker-push/node_modules
ln -s /Volumes/Idan1TB/Goodmail-build/worker-push/node_modules PushWorker/node_modules
cd PushWorker
npm_config_cache=/Volumes/Idan1TB/Goodmail-build/npm-cache npm install
npm run check   # wrangler types, tsc, then the Vitest suite in the Workers runtime
```

`scripts/check` runs `npm run check` too, whenever `PushWorker/node_modules` exists.

## Deploy (owner only)

Run everything from `PushWorker/`.

1. **Log in:** `npx wrangler login`.
2. **D1:**
   - Run `npx wrangler d1 create goodmail-push` and put the printed ID in `wrangler.toml` as `database_id`.
   - Run `npx wrangler d1 migrations apply goodmail-push --remote`.
3. **APNs key:**
   - In the Apple Developer portal, go to Certificates, IDs & Profiles → Keys and create a key with Apple Push Notifications service enabled, for Sandbox & Production.
   - Download the `.p8` (it can only be downloaded once).
   - Put its Key ID and your Team ID in `wrangler.toml` as `APNS_KEY_ID` and `APNS_TEAM_ID`.
4. **Secrets:** these never go in `wrangler.toml`.
   ```bash
   npx wrangler secret put APNS_PRIVATE_KEY < AuthKey_XXXXXXXXXX.p8
   openssl rand -hex 32 | npx wrangler secret put EMAIL_HMAC_SECRET
   ```
   Changing `EMAIL_HMAC_SECRET` later orphans every registration, so keep it.
5. **Deploy:**
   - Run `npm run deploy`.
   - Set `PUBSUB_AUDIENCE` in `wrangler.toml` to the printed URL plus `/v1/pubsub`, for example `https://goodmail-push.<subdomain>.workers.dev/v1/pubsub`.
   - Deploy again.
6. **Pub/Sub push subscription:** Pub/Sub signs each push with an OIDC token for a service account. The Worker checks the token's `aud` against `PUBSUB_AUDIENCE` and its `email` against `PUBSUB_SERVICE_ACCOUNT`.
   ```bash
   gcloud iam service-accounts create gmail-push-invoker --project=goodmail-ios \
     --display-name="Pub/Sub push to the Goodmail Worker"
   # Lets Pub/Sub mint tokens for it (only required for projects created before April 2021; harmless otherwise).
   gcloud iam service-accounts add-iam-policy-binding \
     gmail-push-invoker@goodmail-ios.iam.gserviceaccount.com --project=goodmail-ios \
     --member=serviceAccount:service-847337870740@gcp-sa-pubsub.iam.gserviceaccount.com \
     --role=roles/iam.serviceAccountTokenCreator
   URL=https://goodmail-push.<subdomain>.workers.dev/v1/pubsub
   gcloud pubsub subscriptions create gmail-push-worker --project=goodmail-ios --topic=gmail-push \
     --push-endpoint="$URL" --push-auth-token-audience="$URL" \
     --push-auth-service-account=gmail-push-invoker@goodmail-ios.iam.gserviceaccount.com \
     --ack-deadline=30 --message-retention-duration=1h
   ```
   If you name the service account differently, update `PUBSUB_SERVICE_ACCOUNT` in `wrangler.toml`.
7. **Verify:**
   - Register a device from a development build.
   - Send mail to that account and watch `npx wrangler tail` for APNs errors.
   - The app's `users.watch` call must use the topic `projects/goodmail-ios/topics/gmail-push`.

## Notes

- **APNs and HTTP/2:** APNs only speaks HTTP/2. Check on the first deploy that Workers' outbound `fetch` reaches it, because the tests mock `fetch`.
- **Lost pushes:** a push is marked as sent before APNs is called. If APNs fails transiently, that push is lost, but the next one still carries a newer `historyId`. The NSE syncs from its own last history ID, so nothing is skipped.
