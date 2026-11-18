# PushWorker

Goodmail's push backend (ADR-006): a Cloudflare Worker with D1 and no runtime dependencies. Gmail publishes a change to Pub/Sub, Pub/Sub pushes it here, the Worker reads what arrived, and it sends an APNs alert with the email's sender and subject to the account's devices. Outlook works the same way through Microsoft Graph change notifications, which come straight here, and the Worker watches iCloud and other IMAP Inboxes itself. The Notification Service Extension then fetches the change and adds the sender's picture and a preview.

## API

| Route | Body | Result |
|---|---|---|
| `POST /v1/attest/challenges` | none | `{"challenge"}`, good once for 5 minutes; 429 after 10 a minute from one address |
| `POST /v1/attest/keys` | `{"keyId", "attestation", "challenge"}`, an App Attest key, Apple's attestation of it (base64) and the challenge it binds | 204; 401 when the challenge is unknown, used or stale, or Apple's chain doesn't vouch for the key |
| `POST /v1/devices` | `{"idToken", "deviceToken", "environment": "sandbox" \| "production"}` | 204; 401 for a bad ID token |
| `DELETE /v1/devices` | `{"idToken", "deviceToken"}` | 204 |
| `POST /v1/pubsub` | a Pub/Sub push with an OIDC bearer token | 204 acknowledges it |
| `POST /v1/graph/subscriptions` | `{"subscriptionId", "clientState", "account", "deviceToken", "environment", "expiresAt"}` | 204; 403 when the subscription is registered with another clientState |
| `DELETE /v1/graph/subscriptions` | `{"subscriptionId", "clientState"}` | 204 |
| `POST /v1/graph` | Graph's `validationToken` check, or a batch of change notifications | the token as text; 202 for notifications |
| `POST /v1/graph/grants` | `{"subscriptionId", "clientState", "refreshToken"}`, the app's own Outlook refresh token | 204; 401 when Microsoft refuses it; 403 when the clientState isn't the subscription's |
| `POST /v1/gmail/grants` | `{"refreshToken", "primaryOnly"}`, the app's own Gmail refresh token and its Primary Only choice | 204; 400 for a token that can't read history; 401 when Google refuses it |
| `POST /v1/imap/watches` | `{"watchId", "secret", "account", "deviceToken", "environment", "host", "port", "security", "username", "password"}` | 204; 401 when the server refuses the login; 403 when the watch is registered with another secret; 429 after too many login checks; 503 when the server can't be reached |
| `DELETE /v1/imap/watches` | `{"watchId", "secret"}` | 204 |

- **Only the genuine app (`src/attest-routes.ts`, `src/app-attest.ts`):** the source is public, so anyone could build the app and point it here. Every route the app calls (all of the above but `/v1/pubsub`, `/v1/graph` and the two attest routes) must be signed with an App Attest key: Apple attests that the key lives in the Secure Enclave of a real device, inside an app with the App ID `APNS_TEAM_ID.APNS_TOPIC`, so a build under another team can't make one. The app attests once per install, then sends three headers with each request: `X-Goodmail-Attest-Key` (the key ID), `X-Goodmail-Attest-Time` (milliseconds since 1970) and `X-Goodmail-Attest-Assertion`, the key's assertion over `SHA-256("<method> <path>\n<time>\n" || body)`. A request more than 10 minutes off is refused, so a replay can only repeat, briefly, what the genuine app asked for. With `APP_ATTEST = "observe"` the Worker only logs requests that fail; any other value refuses them: 428 when there is no key or the Worker doesn't know it (the app attests again and retries once), 401 when the signature doesn't hold. Keys unused for 180 days are dropped. The pinned root is Apple's App Attestation Root CA (`src/apple-root.ts`).
- **Registration:** `idToken` is the Google ID token from sign-in. It needs the `openid` and `email` scopes, and `aud` must be the iOS client ID. The Worker stores only HMAC-SHA256 of the address.
- **Alerts only with content (`src/new-mail.ts`):** every alert passes one gate. The Worker alerts only for an email it has read, and the alert carries its sender as the title and its subject as the body: `{"aps": {"alert": {"title": "<sender>", "body": "<subject>"}, "sound": "default", "mutable-content": 1}, …}`. The payload can't be built without one, so no provider can send a bare "New mail". Each provider reads the change and answers with an `Arrival`: the newest email the app alerts for (unread and in the Inbox, as Apple Mail alerts for, including mail the account sent itself, and in Primary for a Gmail account set to Primary Only), `none` (a read, archive, delete or label change, or mail read or deleted before the check), or `retry` when it couldn't read yet. A retry never alerts. Gmail answers 503 so Pub/Sub delivers the notification again, IMAP moves the watch back for the next check, and Outlook tries twice more within the notification. A new provider has to hand over an `Arrival` the same way. Without the app's token for an account the Worker can't read its mail, so it sends nothing.
- **Push:** Gmail's payload adds `"account": "<email>", "historyId": "<id>"`. Duplicate deliveries and history IDs that aren't newer are dropped. APNs `410` and `BadDeviceToken` remove the token. When the alert reaches no device because sending failed or threw, the Worker gives back the history ID and answers 503, so Pub/Sub redelivers it. One email reaches Pub/Sub as a burst of history changes, so a push within 15 seconds of the last one for the account is dropped: the device catches up on the whole burst from the first.
- **Gmail:** the app sends each Gmail account's own refresh token, with its Primary Only choice, every time it brings push up to date, so a new sign-in reaches the Worker at once. A token the Worker already holds (matched by its HMAC) only takes the choice and answers 204 without calling Google. A new one must refresh, carry a scope that can read history, and name its account through the Gmail profile, whose history ID the first notification checks from. The Worker stores it AES-GCM encrypted with a key derived from `EMAIL_HMAC_SECRET`. For each notification it lists the history since the last notification's ID (`historyTypes=messageAdded`, `labelId=INBOX`) and reads each added message's labels, From and Subject (`format=metadata`) as they are now. A history ID too old to list sends nothing. Google's `invalid_grant` deletes the stored copy, and so does the account's last device leaving. The token is never revoked from here, because it is the app's own sign-in.

- **Outlook:** each device creates its own Graph subscription to `me/mailFolders('inbox')/messages` with `notificationUrl` set to `/v1/graph`, then registers it here. `clientState` is a random secret only the device and Graph know. The Worker keeps only its SHA-256, and a notification counts only when its `clientState` matches. The first registration of a subscription ID owns it, so renewals must send the same `clientState`. `account` is the app's opaque account ID, never an address. The app also sends the account's refresh token to `/v1/graph/grants` on every refresh, proven by the subscription's `clientState`; it is sealed like Gmail's, the newest one Microsoft hands out is kept, and it goes when the account's last subscription does. For each subscription a batch names, the Worker reads each notified message (`subject`, `from`, `isRead`, `parentFolderId`) and sends one alert for the newest it alerts for, with `"accountID": "<id>"` in the payload. `expiresAt` is in milliseconds, and rows are dropped a day after it.

- **iCloud and other IMAP accounts:** their servers push to no one but Apple Mail, so the relay looks itself. Each device registers its own watch, like an Outlook subscription: `watchId` is a UUID and `secret` 32 random bytes as hex that only the device knows (the Worker keeps its SHA-256). `account` is the app's opaque account ID. `security` is `tls` or `startTLS`; the relay never logs in without TLS. The login (server, user name and password) is stored AES-GCM sealed under a key derived from `EMAIL_HMAC_SECRET`, and an HMAC of it tells a renewal with the same login from a changed one. A new or changed login is checked by logging in, which also records the Inbox's `UIDNEXT` and `UIDVALIDITY`; the same login is renewed without logging in. The app registers on every refresh, so a new password reaches the relay at once, and a watch lasts 30 days after its last registration. One Durable Object, the holder (`src/inbox-holder.ts`), keeps a connection open to each watched mailbox, one per login however many devices watch with it. Its alarm goes off every minute and starts a watch on each mailbox that is due and has none. A watch logs in and reads `STATUS INBOX (UIDNEXT UIDVALIDITY)`, which catches mail that arrived while no connection was open. Then it selects the Inbox read-only and holds IDLE for 30 minutes, starting IDLE again every 2 minutes and reading the STATUS again whenever the server says the Inbox grew (a `* n EXISTS` above the count so far), so alerts go out within seconds at 48 logins a day per mailbox. The growth counts whichever command the server says it during, because mail announced between two IDLE commands is announced only once. A server that owes a reply and sends nothing for 20 seconds ends the watch. A mailbox whose watch ended early is logged in to again 5 minutes after that watch started, so a server without IDLE gets the STATUS check every 5 minutes. The holder watches 4 mailboxes at a time, and with more, each gets its turn as watches end. The devices watching a mailbox are read from D1 each time its STATUS is read, so a device that registers or leaves needs no new connection. What is being watched lives only in the object's memory: when Cloudflare restarts the object, the alarm wakes the new one within a minute and it logs in again. Waiting on IDLE costs no CPU. Every 5 minutes a cron run wakes the holder, which starts the alarm again if it was lost. When the holder can't be reached, as on a day the free Durable Object time ran out, that run does the watching itself: it logs in to each mailbox and holds IDLE until just before the next run (`src/imap-poll.ts`). Both move a watch with the same conditional write, so mail alerts once even when both look at a mailbox. When `UIDNEXT` grew, new mail arrived (a read, flag, move out or delete never grows it). The Worker then fetches the From and Subject headers and flags of what arrived (`UID FETCH`, at most the newest 50) and alerts each watching device, with its `accountID`, for the newest that is unread and not deleted. A failed fetch or alert moves the watch back, so the next STATUS or watch tries again. A changed `UIDVALIDITY` is taken as the new start without an alert. When the server refuses the login (`NO` without a try-later code such as `[UNAVAILABLE]`), at registration or in a check, every watch on that login is kept as refused, with how many times in a row and when. A server can refuse a good login once, so a refused login is tried again: after about 5 minutes, then 15 minutes, an hour, and every 6 hours from then on. A wrong password is tried a few times a day, which locks no account. The first login the server takes puts the watches back to watching, and mail that arrived meanwhile alerts. A registration with a refused login answers 401 without logging in for a minute after the last refusal, and after that it checks the login again, so opening the app brings back a watch that was refused by mistake. A rate limit allows 5 login checks a minute per client address, so the route can't be used to try passwords. Removing the watch, the account, or APNs reporting the token gone deletes the stored login.

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
   Changing `EMAIL_HMAC_SECRET` later orphans every registration, and the stored Gmail tokens and IMAP logins can't be opened any more, so keep it.
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
7. **App Attest:** deploy with `APP_ATTEST = "observe"`, install a TestFlight build that signs its requests, and check that `SELECT environment, last_used_at FROM attest_keys` shows its key. Then set `APP_ATTEST = "enforce"` and deploy again.
8. **Verify:**
   - Register a device from a development build.
   - Send mail to that account and watch `npx wrangler tail` for APNs errors.
   - The app's `users.watch` call must use the topic `projects/goodmail-ios/topics/gmail-push`.

## Notes

- **APNs and HTTP/2:** APNs only speaks HTTP/2. Check on the first deploy that Workers' outbound `fetch` reaches it, because the tests mock `fetch`.
- **Logs:** Workers Logs are on (`[observability]` in `wrangler.toml`) and keep a few days. The relay logs each Inbox watch when it ends and how long it lasted, each alert it sent with APNs' answer, and each refused login with the server's own words and the count in a row. Lines name a watch by the first 8 characters of its ID and a login by the first 8 of its hash, never an address, sender or subject. Read them in the Cloudflare dashboard under the Worker's Logs tab, or live with `npx wrangler tail`.
- **Lost pushes:** a push is marked as sent before APNs is called. If APNs fails transiently, that push is lost, but the next one still carries a newer `historyId`. The NSE syncs from its own last history ID, so nothing is skipped.
