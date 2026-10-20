# Architecture grounding

The facts every design must honor. Product decisions are in [../product-brief.md](../product-brief.md). Facts marked *(verify)* come from training knowledge and are not confirmed against current docs.

## Toolchain

- Xcode 27.2 RC (27B48), Swift 6.4, iPhoneOS27.2 SDK. The SDK is at `$(xcrun --sdk iphoneos --show-sdk-path)`; grep its `.swiftinterface` files rather than guessing at APIs.
- Swift 6 language mode with strict concurrency. Approachable-concurrency settings are available (default MainActor isolation per module, `nonisolated(nonsending)` by default).
- Present in the SDK: SwiftData, WebKit (`WebPage` for SwiftUI plus `WKWebView`), AppIntents, WidgetKit, BackgroundTasks, CoreSpotlight, UserNotifications/UI, AuthenticationServices, Network, FoundationModels (not used: AI is system-only).
- New SwiftData types in this SDK: `ResultsObserver`, `HistoryObserver`, `SectionedResults`, `DataStoreBatching`, `HistoryDescriptor`. `ModelConfiguration` supports a `GroupContainer` (App Group).
- System `libsqlite3` is available with FTS5 *(verify)*, so a raw-SQLite store needs no third-party code.
- Dependency policy: Apple frameworks only. Every third-party package needs owner approval and an ADR.

## Gmail API (REST, v1)

**Resources:**
- `users.getProfile`: returns `emailAddress`, `historyId`, `messagesTotal`.
- `users.messages`:
  - list (`q` uses Gmail search syntax, `labelIds`, `pageToken`, `maxResults` up to 500)
  - get (`format=minimal|metadata|full|raw`, `metadataHeaders`)
  - modify, `batchModify` (≤1000 ids), trash/untrash, delete, `batchDelete`
  - send (multipart/resumable upload up to 35 MB), insert, import
  - `attachments.get`
- `users.threads`: list, get, modify, trash/untrash, delete.
- `users.labels`: CRUD, with color, `labelListVisibility` and `messageListVisibility`.
  - System labels: INBOX, SENT, DRAFT, SPAM, TRASH, UNREAD, STARRED, IMPORTANT, CHAT, plus CATEGORY_PERSONAL, CATEGORY_SOCIAL, CATEGORY_PROMOTIONS, CATEGORY_UPDATES and CATEGORY_FORUMS.
- `users.drafts`: create, update, get, list, send, delete.
- `users.history.list`:
  - Takes `startHistoryId` and `historyTypes` (`messageAdded`, `messageDeleted`, `labelAdded`, `labelRemoved`), and is paged.
  - A `startHistoryId` that's too old (usually around a week, sometimes less) returns **404**, and the client must do a full resync.
- `users.watch` / `users.stop`:
  - `watch` takes `topicName`, `labelIds` and `labelFilterBehavior`. It returns `historyId` and `expiration`, and expires after 7 days.
  - Calling it again renews the watch.
- `users.settings`: `sendAs` (signatures, display names, aliases), filters, `forwardingAddresses`, `autoForwarding`, `vacation`, `imap`, `pop`, `language`, `delegates`.

**Other behavior:**
- Batch HTTP endpoint: `multipart/mixed`, up to 100 calls each (Google recommends ≤50).
- Quotas *(verify)*: 250 units per user per second.
  - messages.get/list/modify cost 5 units each, threads.get 10, history.list 2.
  - send and drafts.send cost 100, batchModify 50, watch 100.
- Not in the API: snooze, scheduled send, Smart Compose, undo send (client-side delay only).
- Pub/Sub push payload: base64 JSON `{emailAddress, historyId}`, with no message data. Push requests can carry a Google-signed OIDC JWT, which the receiver verifies.

## OAuth (Google)

- iOS OAuth client: authorization code with PKCE. The redirect uses the reverse-client-ID custom scheme and runs through `ASWebAuthenticationSession`. There's no client secret on device.
- Scopes:
  - `gmail.modify` is restricted, and covers everything except permanent delete.
  - `https://mail.google.com/` is restricted and also allows permanent delete.
  - `gmail.settings.basic` covers settings; `openid email` returns an ID token.
- **Testing-mode caveat** *(verify)*: in "Testing" publishing status, external-user refresh tokens **expire after 7 days**.
  - Moving the app to "In production" while unverified avoids that, at the cost of an unverified-app warning and a 100-user cap.
  - This decides how TestFlight-first actually feels to users.

## iOS platform constraints

**Notification Service Extension (NSE):**
- It runs only for alert pushes with `mutable-content: 1`. Silent pushes don't wake it.
- It has about 30 s of wall time and a tight memory ceiling (about 24 MB, *verify*), but it does have network access.
- If it fails or times out, the original alert text is shown, so the server's placeholder text must be acceptable on its own.
- Suppressing a notification, for example when a push turned out to be a read-state change, requires the `com.apple.developer.usernotifications.filtering` entitlement, which must be requested from Apple.

**Pushes:** APNs payloads are at most 4 KB.

**Shared state:**
- App, NSE, widgets and intents are separate processes. Shared data lives in an App Group container, and shared secrets in a Keychain access group.
- The NSE runs while the phone is locked. Files and Keychain items it needs must be `CompleteUntilFirstUserAuthentication` / `kSecAttrAccessibleAfterFirstUnlock`.
- Multi-process writes to SQLite need WAL mode and coordination. Only one process should own writes, or every writer must tolerate concurrency.

**Background work:**
- BGTaskScheduler (`BGAppRefreshTask`, `BGProcessingTask`, `BGContinuedProcessingTask`) gives no timing guarantees.
- A background `URLSession` can finish uploads and downloads after the app is suspended.

**Entitlements:**
- Default mail app: `com.apple.developer.mail-client`, requested from Apple. It enables `mailto:` handling and requires meeting Apple's mail-client criteria.

**Windows:**
- Multiple windows through UIScene or SwiftUI `WindowGroup`.
- iPadOS has freely resizable windows, and the foldable iPhone has dynamic size classes.
- Layouts must adapt continuously, not to a fixed list of devices.

**HTML mail:**
- Rendered with `WKWebView` or SwiftUI `WebPage`.
- `WKContentRuleList` blocks remote loads.
- `WKURLSchemeHandler` serves `cid:` inline images and proxied or explicitly allowed remote images.
- JavaScript disabled for content, and a non-persistent data store.
- Thread view needs several messages stacked with correct heights: one web view per message, or one web view per thread.

**Spotlight:** `CSSearchableIndex`. **Widgets:** WidgetKit with App Intents for interactivity.

## Backend (Cloudflare Workers)

- Free plan: 100k requests a day, 10 ms CPU per invocation.
- Durable Objects (SQLite-backed classes only on free), Cron Triggers, and Email Routing with Email Workers.
- APNs over HTTP/2 works through `fetch()` from deployed Workers, but **not** from local `wrangler dev`.
- APNs JWT (ES256) is signed with WebCrypto, so no dependencies are needed.

**The Worker must never hold user credentials or mail content.** It stores:
- a mapping from **HMAC(emailAddress)** to APNs device tokens
- per-device APNs environment (sandbox or production)

**Registration security:**
- A device proves it owns the mailbox by sending a Google ID token, which the Worker verifies.
- Otherwise anyone could register for a victim's address and receive metadata about when their mail arrives.

**Push flow:** Pub/Sub sends `{email, historyId}` to the Worker. The Worker HMACs the address, looks up the devices, and sends an APNs alert with `mutable-content: 1`. The payload carries only the opaque account key and `historyId`. The NSE then fetches the changes with the token stored on the device, and builds or suppresses the notification.

**Renewals:** the device renews `users.watch` (and later Graph subscriptions) opportunistically: on app launch, in BG refresh and from the NSE. The Worker cannot renew watches because it has no tokens.

## Future providers the abstraction must fit (not built in v1)

**Microsoft Graph:**
- Folders, not labels. Delta queries per folder.
- Change-notification subscriptions expire in about 3 days and require a validation handshake.
- Categories and a focused inbox.

**iCloud:**
- IMAP + SMTP with an app-specific password.
- Folders, UIDVALIDITY/UID, CONDSTORE/QRESYNC *(verify support)*, IDLE in the foreground.
- Push comes from forwarding to an Email Worker.

**Concept mismatch:** Gmail has labels (many-to-many), the others have folders (one-to-many). Gmail has native threads. Graph has `conversationId`. IMAP has no threads, so it needs References/In-Reply-To threading.
