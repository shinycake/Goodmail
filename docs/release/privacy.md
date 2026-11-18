# Privacy review

The M11 privacy review: what Goodmail stores, where it goes, the privacy manifests, and the App Store privacy label. It checks the code against the product brief's [Data and privacy](../product-brief.md#data-and-privacy) and [Backend](../product-brief.md#backend-cloudflare-workers) sections. Re-run it whenever a change adds storage, a network destination, a log line with user data, or a required-reason API.

Reviewed 2026-11-13, against `main` at 42720fc. The push Worker section was updated on 2026-11-16 for Outlook, the Gmail history check (#232) and iCloud/IMAP watches (#241, #243).

## Summary

- Mail and settings stay on the device or go straight to the user's mail provider. Goodmail has no server that sees mail.
- Credentials live in the Keychain. The push Worker also keeps two kinds, encrypted, so it can tell when new mail arrives: each Gmail account's refresh token, and each iCloud or IMAP login. It uses them only to read Gmail's change history or the Inbox's UID counters.
- Otherwise the push Worker stores keyed hashes of addresses, opaque account IDs and APNs device tokens. It logs nothing personal.
- No tracking, no analytics SDKs, no third-party code besides GRDB, which ships its own privacy manifest.
- The release build today collects no data in Apple's sense. When the app starts registering with the push Worker, the label changes to one entry, **User ID**. See [Privacy label](#app-store-privacy-label).

## On the device

| What | Where | Protection | Shared with |
|---|---|---|---|
| Gmail refresh tokens | Keychain, generic password, service `com.idanbirman.goodmail`, shared access group `com.idanbirman.goodmail.shared` | `AfterFirstUnlockThisDeviceOnly`: not in backups, not migrated to a new device | App and its extensions |
| Access tokens | Memory only (`GmailSession`) | Process lifetime | None |
| Mail cache: accounts, signatures, threads, labels, messages and bodies, the full-text index of bodies, sync cursors, the outbox and outgoing drafts, the address book of recent correspondents | SQLite (GRDB) at `<App Group>/Mail/mail.sqlite` | `completeUntilFirstUserAuthentication` | App and its extensions, through the App Group |
| Opened attachments | `Caches/Attachments/<account>/<message>-<part>/` | Default class; the system may purge Caches. The cache cap evicts the least recently opened first | None |
| Preferences: undo-send delay, accounts with unsorted Inbox | `UserDefaults.standard` | Default | None |
| Recent searches (up to 8 query strings) | `UserDefaults.standard` | Default | None |
| Apple Watch mailbox: the Inbox's newest rows (sender, subject, a short preview, a one-time code when the message has one), the unread counts and the changes the iPhone hasn't run yet | JSON at `<watch App Group>/wrist-mailbox.json` (`WristStore`), written by the watch app and read by its watch face widget | Default class (`completeUntilFirstUserAuthentication`) | The watch app and its widget extension. The iPhone sends it over WatchConnectivity, which Apple encrypts between the paired devices |
| Watch changes already run (command IDs, the last 64) | `UserDefaults.standard` on the iPhone (`WristAppliedCommands`) | Default | None |
| Diagnostics | Unified logging (`os.Logger`), MetricKit and Xcode Organizer | On device; leaves only in a sysdiagnose the user sends, or Apple's opt-in diagnostics sharing | Apple, if the user opts in |

Debug builds also read a few launch arguments through `UserDefaults` (`GoodmailSyntheticThreads`, `GoodmailSyntheticCorpus`, `GoodmailDeliverTestMessageAfter`, the test-mail tools, and the watch app's `GoodmailWristSample` and `GoodmailWristSampleOpen`). They are compiled out of Release.

Removing an account (`AppModel.removeAccount`) deletes its refresh token, its rows in the database and its opened attachments; the next snapshot the iPhone sends leaves its rows off the watch. Deleting the app removes everything above except Keychain items, which iOS keeps across reinstalls. Items that are `ThisDeviceOnly` never leave the device.

### Findings

- **Log lines with error bodies.** `SyncScheduler` and `AppModel` log errors as `privacy: .public`. A `GmailError` carries Google's response body, which can echo a recipient address (for example "Invalid To header"). These logs stay on the device and aren't collected, so the label is unaffected. A follow-up should log the status publicly and the body as private.
- **Recent searches** are in plain `UserDefaults`, which is in device backups. That's fine for search history, but they aren't removed when an account signs out. Consider clearing them on sign-out of the last account.

## Network destinations

| Destination | Purpose | Data sent |
|---|---|---|
| `accounts.google.com`, `oauth2.googleapis.com` | Sign-in (PKCE in `ASWebAuthenticationSession`) and token refresh | OAuth code and refresh token |
| `gmail.googleapis.com` | Mail: read, send, modify, delete forever, settings (`https://mail.google.com/`, `gmail.settings.basic`) | The user's own mail, to the user's own provider |
| `people.googleapis.com` | Contacts for address completion (`contacts.readonly`, `contacts.other.readonly`) | Read only |
| Remote content in messages | Images, only when the reader allows them for a message | The image request (IP address, user agent). Blocked by default |
| The push Worker | Push registration | Gmail: Google ID token, APNs device token, and the account's refresh token. Outlook: the Graph subscription's ID and secret, the app's account ID, the device token. iCloud/IMAP: the server, user name and app password, the app's account ID, the device token |

Google here is the user's own mail provider, acting for the user. Data the app exchanges with it isn't collected by Goodmail.

## The push Worker

`PushWorker/` is a Cloudflare Worker with a D1 database (ADR-006). Its README documents every route.

**What it receives**

- `POST`/`DELETE /v1/devices`: a Google ID token (it verifies the token and reads the `email` claim), the APNs device token, and `sandbox` or `production`.
- `POST /v1/pubsub`: Gmail's notification, `{emailAddress, historyId}`, signed by Google. No mail content, subjects or senders.
- `POST /v1/gmail/grants`: the Gmail account's refresh token, on every push refresh.
- `POST`/`DELETE /v1/graph/subscriptions` and `POST /v1/graph`: Outlook's Graph subscriptions and their change notifications, which name a subscription and carry no mail.
- `POST`/`DELETE /v1/imap/watches`: an iCloud or IMAP account's server, user name and app password, the app's account ID, the device token, and a watch ID and secret the device made.

**What it stores** (`migrations/`)

- `devices`, `deliveries`, `push_times`: `HMAC-SHA256(lowercased email, EMAIL_HMAC_SECRET)`, APNs tokens, the newest Gmail history ID pushed, and when the last push went out.
- `gmail_grants`: the refresh token, AES-GCM encrypted, and an HMAC of it to recognize it when sent again.
- `graph_subscriptions`: the subscription ID, a SHA-256 of its secret, the app's opaque account ID, the device token and the expiry.
- `imap_watches`: the login (server, user name and password) as AES-GCM encrypted JSON, an HMAC of it, a SHA-256 of the watch secret, the app's account ID, the device token, the Inbox's UIDVALIDITY and UIDNEXT, and whether the server refused the login, how many times in a row and when.
- `attest_keys`: each install's App Attest public key, its environment, its newest counter and when it was last used, so only the genuine app can register (`src/attest-routes.ts`). A key names no person or account. `attest_challenges` holds one-time challenges for 5 minutes.
- No addresses in the clear and no mail. The ID token is verified and dropped.
- **Encryption:** the AES-GCM keys are derived with HKDF from the Worker secret `EMAIL_HMAC_SECRET`, one key per kind of secret. A copy of the database alone reveals no token or password. Someone who controls the Cloudflare account, or Cloudflare itself, could run code with the secret and decrypt them. D1 is also encrypted at rest by Cloudflare.

**What it does with the credentials**

- Gmail: refreshes an access token and lists history since the last notification (`messageAdded`, Inbox only), to stay silent when nothing new reached the Inbox.
- iCloud/IMAP: every 5 minutes it logs in, reads `STATUS INBOX (UIDNEXT UIDVALIDITY)`, selects the Inbox read-only and holds IDLE until the next run. When UIDNEXT grew, it fetches the From and Subject headers and the flags of what arrived, for the alert, and never a body. A refused login is tried again at the next run, then after about 15 minutes, an hour, and every 6 hours.

**What it sends**

- APNs: the alert `Goodmail` / `New mail`, plus `account` (the email address) and `historyId` for Gmail, or `accountID` (the app's opaque ID) for Outlook and IMAP, so the Notification Service Extension knows which account to sync. Apple relays this and keeps it only until delivery.
- Follow-up to consider: send an opaque per-account ID for Gmail too, so the address doesn't transit APNs. Low risk either way, since the payload goes over TLS and only to the user's own device.

**What it logs**

- `console.warn` and `console.log` lines: the APNs status and reason, why a Gmail or IMAP check failed (fixed messages or the server's own error text, such as `IMAP NO [UNAVAILABLE]`), when an IMAP run ended, and for each IMAP alert or refused login the first 8 characters of the watch's ID. No token, password, address, account ID, sender or subject.
- Thrown errors reach the Workers runtime log. Their messages are fixed strings with no request data.
- `wrangler.toml` turns on Workers Logs, which keeps these lines and each request's route, status and outcome for a few days, readable by the owner only. Without them nobody could tell why iCloud alerts had stopped (2026-11-17). Logpush is off. The URLs carry no personal data.

**Retention**

- A Gmail registration lasts until the app unregisters it or APNs reports the token gone (`410` or `BadDeviceToken`). There is no time-based expiry yet.
- The Gmail refresh token is deleted when the account's last device leaves or Google answers `invalid_grant`.
- Graph subscription rows are dropped a day after they expire. IMAP watches, with their logins, are dropped 30 days after the device last registered them, or when the app removes the account or turns its alerts off.
- A token APNs reports gone is removed from every table.

## Privacy manifests

Each target has a `PrivacyInfo.xcprivacy` in its synchronized folder, so Xcode copies it into the bundle without project changes.

| Target | Tracking | Collected data | Required-reason APIs |
|---|---|---|---|
| Goodmail (`Goodmail/`) | No, no domains | None | `UserDefaults`: **CA92.1** (the app's own preferences and recent searches). File timestamp: **C617.1** (the attachment cache reads and sets modification dates of its own files, in the app container) |
| NotificationService (`NotificationService/`) | No | None | None |
| WidgetsExtension (`Widgets/`) | No | None | None |
| GoodmailWatch (`GoodmailWatch/`) | No, no domains | None | None (its `UserDefaults` reads are the Debug launch arguments) |
| GoodmailWatchWidgets (`GoodmailWatchWidgets/`) | No, no domains | None | None |
| GRDB 7.11.1 | Ships its own `PrivacyInfo.xcprivacy` | | |

Update a manifest when its target starts using a required-reason API. The likely next ones:

- The NSE or widgets linking `MailStore` for push or the inbox widget: file timestamp **C617.1** if they run the cache trim.
- A shared `UserDefaults(suiteName: SharedContainer.appGroupID)`: **1C8F.1** in every target that uses it.
- `ProcessInfo.systemUptime` or `mach_absolute_time` for timing: **35F9.1**.
- Disk space checks before downloads: **E174.1**.

`grep -rnE "UserDefaults|AppStorage|contentModificationDate|creationDate|modificationDate|attributesOfItem|systemUptime|mach_absolute_time|volumeAvailableCapacity|activeInputModes"` over `Goodmail NotificationService Widgets GoodmailWatch GoodmailWatchWidgets Packages` finds them.

## App Store privacy label

Apple counts data as collected when it leaves the device and the developer or a partner can access it for longer than it takes to serve the request. Mail exchanged with Google on the user's behalf isn't collected by Goodmail.

**Today (no device registration in the app): "Data Not Collected".**

- Do you or your third-party partners collect data from this app? **No.**

**Once the app registers with the push Worker:**

- Do you collect data? **Yes.**
- **Identifiers → User ID.** The keyed hash of the address is an account-level ID that the owner can recompute from an address, so it isn't anonymized.
  - Purposes: **App Functionality** only.
  - Linked to the user's identity: **Yes.**
  - Used for tracking: **No.**
- Not declared:
  - **Device ID.** The APNs token is a push routing token, not a device identifier in Apple's sense.
  - **Email address.** The Worker hashes it on arrival and doesn't keep it. It passes through only to serve the request.
  - **Emails or text messages, Contacts.** These go between the device and Google, never to Goodmail.
  - **Diagnostics.** MetricKit and Organizer data come from Apple's own opt-in sharing, which Apple discloses.

The registration PR must add the same entry to the app's manifest (`NSPrivacyCollectedDataTypeUserID`, linked, not tracking, purpose `NSPrivacyCollectedDataTypePurposeAppFunctionality`), so the manifest and the label agree.

**Also for App Store Connect**

- A privacy policy URL is required, even for "Data Not Collected". It can be a short page made from this document.
- Gmail's restricted scope (`https://mail.google.com/`, the full scope Delete Forever needs, ADR-019) needs Google's OAuth verification and a CASA security assessment before the app leaves Testing mode, beyond 100 users. That's separate from Apple's review.

## Verify on a Mac

These need a build, which this review couldn't run:

- Build and check that `Goodmail.app`, `NotificationService.appex` and `WidgetsExtension.appex` each contain `PrivacyInfo.xcprivacy`.
- Archive, then use Organizer → **Generate Privacy Report**, and check it lists the two API reasons above plus GRDB's manifest.
