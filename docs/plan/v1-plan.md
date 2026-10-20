# Gmail v1 implementation plan

The plan builds on the [product brief](../product-brief.md), the [architecture decisions](../architecture/decisions.md) and the [design decisions](../design/design-decisions.md).

Each milestone is a set of vertical slices: thin, end-to-end, shippable to `main` on its own (ADR-013). Every slice's PR includes `scripts/check` output, plus screenshots or recordings in **English and Hebrew** for any UI.

## Rules that apply to every slice

- **Multi-account and RTL from day one.**
  - Every table and type carries `AccountID`, even while the UI shows one account.
  - Every user-facing string goes into a String Catalog with English and Hebrew.
- **One way to do things:**
  - Mail changes go through `MailCommands`, and navigation goes through `Route` (ADR-011).
  - Each user action ships with its App Intent in the same slice (ADR-012).
- **TDD for logic:** Swift Testing, with Gmail fixtures recorded from the test account (ADR-010).
- **Files stay under 1000 lines** (ADR-014).

## Prerequisites (owner)

| Needed for | Item |
|---|---|
| M0 | Xcode 27.2 installed and selected with `xcode-select` |
| M1 | ~~Google Cloud project, OAuth client, Gmail and People APIs~~ (done, see [setup](../setup/google-cloud.md)); ~~test account~~ (idanbirmandev@gmail.com) |
| M6 | Apple Developer Program membership, a domain, a Cloudflare account, a Pub/Sub topic (billing enabled); request the notification-filtering entitlement |
| M9 | Request the mail-client (default mail app) entitlement |

## Milestones

### M0: Foundations

**Builds:**
- the Xcode project in JSON format (ADR-015), with app, NSE and widget targets, an App Group and a Keychain group
- local packages `MailCore`, `MailStore` (with GRDB), `GmailProvider`, `MailUI` and `MailIntents`
- `scripts/check` (swift format lint, line cap, build, test), `.githooks` pre-commit and pre-push hooks
- an advisory Linux CI workflow
- String Catalogs for English and Hebrew, and the theme tokens (account color, blend, typography)

**Evidence:** `scripts/check` passes on an empty app that launches in English and Hebrew.

### M1: First light, the thinnest end-to-end path

**Builds:**
- Google sign-in (PKCE via `ASWebAuthenticationSession`), with tokens in the Keychain
- fetch the first page of Inbox threads (metadata), store them through `MailStore`, and show them in the UIKit list with the real row design (serif subject, time sections)
- **performance spike:** 50k synthetic rows, scrolled on a device and measured with Instruments

**Evidence:** a screenshot of the test account's inbox in English and Hebrew, provider tests on fixtures, and the scroll measurement.

### M2: Sync engine

**Builds:**
- initial windowed sync (ADR-007) and incremental `history.list` sync
- full resync on a 404 response
- label sync, including system labels and categories
- backfill on scroll
- background refresh
- Darwin-notification change signals between processes (ADR-002)

**Evidence:**
- fixture tests for history merging, the gap/404 path, and resuming after a crash halfway through
- a recording of mail arriving while the app is open

### M3: Reading

**Builds:**
- MIME parsing to the domain model
- the thread view, laid out as letters (timeline plus card)
- one `WKWebView` per message (ADR-003), with remote content blocked, a Load action, `cid:` images, `dir=auto`, and quoted text folded
- attachments, previewed with Quick Look

**Evidence:** rendering tests on tricky real-world MIME fixtures, and screenshots of a Hebrew/English mixed thread and an HTML newsletter.

### M4: Actions and outbox

**Builds:**
- `MailCommands`: read/unread, star, archive, trash, delete, spam, label, move, mute
- optimistic updates with idempotent outbox replay (ADR-008)
- glass swipe actions, multi-select, and undo (shake and toolbar)
- the matching `UndoableIntent`s

**Evidence:** offline replay tests (airplane mode, then reconnect), plus a swipe recording in LTR and RTL.

### M5: Compose and send

**Builds:**
- **Editor:** a TextKit 2 editor with full formatting, and a serializer from formatted text to email-safe HTML
- **Replies:** reply, reply-all and forward, with the quote kept intact
- **Attachments:** Files, Photos, camera, scan
- **Signatures and drafts:** `sendAs` signatures, drafts synced to Gmail
- **Sending:** undo send (10 s, adjustable), and outbox send over a background `URLSession`
- **Recipients:** autocomplete from local history, Contacts and the People API

**Evidence:** HTML serializer golden tests, a recording of sending a rich reply, and how that reply renders in Gmail web.

### M6: Push

**Builds:**
- **Worker:** TypeScript with D1 (ADR-006). Device registration with ID-token proof, Pub/Sub OIDC verification, HMAC lookup, dedupe on `historyId`, APNs JWT.
- **App:** watch renewal, an NSE that fetches the change, writes it and builds a notification grouped by thread, suppression through the filtering entitlement, and notification actions (Archive, Reply, Mark Read, Trash)

**Evidence:** Worker unit tests, plus an end-to-end recording on a real device: send to the test account → notification within seconds → the rich notification → an action that takes effect.

### M7: Multi-account and the full layout

**Builds:**
- several accounts, each with a theme color
- the blended unified views, the sidebar, and the category menu
- iPad three columns with the floating glass sidebar
- adaptation for resizable windows and the foldable iPhone
- multiple windows, state restoration, and handling every `Route` (notifications, `mailto:`, Handoff)

**Evidence:** screenshots at a range of window sizes, and a resize recording.

### M8: Search

**Builds:**
- local FTS5 search with instant results, then Gmail server search merged in
- the expanding glass search, with tokens (`from:`, `has:attachment`…) and recent searches

**Evidence:** search tests on fixtures (including Hebrew), and a recording of search working offline and online.

### M9: System integration

**Builds:**
- App Intents entities adopting the `.mail` schemas
- `IndexedEntity` for Spotlight
- App Shortcuts in English and Hebrew
- Focus filters (accounts per Focus) and a Control Center control
- interactive widgets
- `mailto:` handling and the default-mail-app entitlement

**Evidence:** Siri, Shortcuts and Spotlight recordings, and a widget screenshot.

### M10: Finishing

**Builds:**
- device-side snooze and scheduled send
- settings: SwiftUI forms for notifications per account (All / Primary / None), preview lines, undo-send delay, avatars, theme colors
- onboarding and empty states

**Evidence:** recordings of each flow.

### M11: Release quality

**Builds:**
- a localization and RTL audit
- an accessibility pass: VoiceOver, Dynamic Type up to AX5, Voice Control, Reduce Motion
- a performance pass: cold launch, a mailbox of 100k or more messages, NSE memory
- privacy review and a TestFlight build

**Evidence:** audit checklists, Instruments traces, and the TestFlight build.

## Ordering and parallelism

**Order:** M0 → M1 → M2 is strictly sequential, because everything else stands on the store and the sync engine.

**What can run alongside:**
- **During M1–M2:** the Worker side of M6 has no dependency on the app (it lives in its own `worker/` folder).
- **After M2:** M3, M4 and M8 touch different packages, so they can run in parallel sessions in separate worktrees.
- **After M4:** M5 needs `MailCommands` and the outbox from M4.
- **After M7:** M9 needs the Routes and multi-account work from M7.
