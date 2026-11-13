# Privacy review

The M11 privacy review: what Goodmail stores, where it goes, the privacy manifests, and the App Store privacy label. It checks the code against the product brief's [Data and privacy](../product-brief.md#data-and-privacy) and [Backend](../product-brief.md#backend-cloudflare-workers) sections. Re-run it whenever a change adds storage, a network destination, a log line with user data, or a required-reason API.

Reviewed 2026-11-13, against `main` at 42720fc.

## Summary

- Mail, credentials and settings stay on the device or go straight to the user's mail provider. Goodmail has no server that sees mail.
- The push Worker stores only a keyed hash of the address and the APNs device token. It logs nothing personal.
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
| Diagnostics | Unified logging (`os.Logger`), MetricKit and Xcode Organizer | On device; leaves only in a sysdiagnose the user sends, or Apple's opt-in diagnostics sharing | Apple, if the user opts in |

Debug builds also read a few launch arguments through `UserDefaults` (`GoodmailSyntheticThreads`, `GoodmailDeliverTestMessageAfter` and the test-mail tools). They are compiled out of Release.

Removing an account (`AppModel.removeAccount`) deletes its refresh token, its rows in the database and its opened attachments. Deleting the app removes everything above except Keychain items, which iOS keeps across reinstalls. Items that are `ThisDeviceOnly` never leave the device.

### Findings

- **Log lines with error bodies.** `SyncScheduler` and `AppModel` log errors as `privacy: .public`. A `GmailError` carries Google's response body, which can echo a recipient address (for example "Invalid To header"). These logs stay on the device and aren't collected, so the label is unaffected. A follow-up should log the status publicly and the body as private.
- **Recent searches** are in plain `UserDefaults`, which is in device backups. That's fine for search history, but they aren't removed when an account signs out. Consider clearing them on sign-out of the last account.

## Network destinations

| Destination | Purpose | Data sent |
|---|---|---|
| `accounts.google.com`, `oauth2.googleapis.com` | Sign-in (PKCE in `ASWebAuthenticationSession`) and token refresh | OAuth code and refresh token |
| `gmail.googleapis.com` | Mail: read, send, modify, settings (`gmail.modify`, `gmail.settings.basic`) | The user's own mail, to the user's own provider |
| `people.googleapis.com` | Contacts for address completion (`contacts.readonly`, `contacts.other.readonly`) | Read only |
| Remote content in messages | Images, only when the reader allows them for a message | The image request (IP address, user agent). Blocked by default |
| The push Worker | Device registration (not wired in the app yet) | Google ID token and APNs device token |

Google here is the user's own mail provider, acting for the user. Data the app exchanges with it isn't collected by Goodmail.

## The push Worker

`PushWorker/` is a Cloudflare Worker with a D1 database (ADR-006). The brief says Durable Objects; the Worker uses D1, with the same data.

**What it receives**

- `POST`/`DELETE /v1/devices`: a Google ID token (it verifies the token and reads the `email` claim), the APNs device token, and `sandbox` or `production`.
- `POST /v1/pubsub`: Gmail's notification, `{emailAddress, historyId}`, signed by Google. No mail content, subjects or senders.

**What it stores** (`migrations/0001_init.sql`)

- `devices`: `HMAC-SHA256(lowercased email, EMAIL_HMAC_SECRET)`, the APNs token, the environment, and when it was last registered.
- `deliveries`: the same hash and the newest Gmail history ID pushed.
- No addresses, OAuth tokens or mail. The ID token is verified and dropped.

**What it sends**

- APNs: the alert `Goodmail` / `New mail`, plus `account` (the email address) and `historyId`, so the Notification Service Extension knows which account to sync. Apple relays this and keeps it only until delivery.
- Follow-up to consider: send an opaque per-account ID instead of the address, so the address doesn't transit APNs. Low risk either way, since the payload goes over TLS and only to the user's own device.

**What it logs** (checked line by line)

- The only `console` call is `apns.ts`, which logs the APNs status and reason, such as `APNs 429 TooManyRequests`. No token, address or account ID.
- Thrown errors reach the Workers runtime log. Their messages are fixed strings (`malformed token`, `JWKS fetch failed with 500`, and so on), with no request data. `TokenError`s and bad requests are answered, not thrown.
- `wrangler.toml` doesn't turn on Workers Logs or Logpush, so nothing is retained. `wrangler tail` shows live requests to the owner only, and the URLs carry no personal data.

**Retention.** A registration lasts until the app unregisters it or APNs reports the token gone (`410` or `BadDeviceToken`). There is no time-based expiry yet. When push ships, add one (for example, drop rows whose `updated_at` is older than 60 days, since the app re-registers on launch).

The brief's Outlook webhook and iCloud Email Worker aren't built yet. Their privacy claims (iCloud: envelope recipient only, message discarded unread, HPKE for any preview) must be checked here when they land.

## Privacy manifests

Each target has a `PrivacyInfo.xcprivacy` in its synchronized folder, so Xcode copies it into the bundle without project changes.

| Target | Tracking | Collected data | Required-reason APIs |
|---|---|---|---|
| Goodmail (`Goodmail/`) | No, no domains | None | `UserDefaults`: **CA92.1** (the app's own preferences and recent searches). File timestamp: **C617.1** (the attachment cache reads and sets modification dates of its own files, in the app container) |
| NotificationService (`NotificationService/`) | No | None | None |
| WidgetsExtension (`Widgets/`) | No | None | None |
| GRDB 7.11.1 | Ships its own `PrivacyInfo.xcprivacy` | | |

Update a manifest when its target starts using a required-reason API. The likely next ones:

- The NSE or widgets linking `MailStore` for push or the inbox widget: file timestamp **C617.1** if they run the cache trim.
- A shared `UserDefaults(suiteName: SharedContainer.appGroupID)`: **1C8F.1** in every target that uses it.
- `ProcessInfo.systemUptime` or `mach_absolute_time` for timing: **35F9.1**.
- Disk space checks before downloads: **E174.1**.

`grep -rnE "UserDefaults|AppStorage|contentModificationDate|creationDate|modificationDate|attributesOfItem|systemUptime|mach_absolute_time|volumeAvailableCapacity|activeInputModes"` over `Goodmail NotificationService Widgets Packages` finds them.

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
- Gmail's restricted scope (`gmail.modify`) needs Google's OAuth verification and a security assessment before the app leaves Testing mode, beyond 100 users. That's separate from Apple's review.

## Verify on a Mac

These need a build, which this review couldn't run:

- Build and check that `Goodmail.app`, `NotificationService.appex` and `WidgetsExtension.appex` each contain `PrivacyInfo.xcprivacy`.
- Archive, then use Organizer → **Generate Privacy Report**, and check it lists the two API reasons above plus GRDB's manifest.
