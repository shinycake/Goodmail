# Architecture decisions

The owner decided these on 2026-10-20 after talking through the options. Each entry gives the decision, the reason, and what was rejected. Platform facts are in [grounding.md](grounding.md).

## ADR-001: Local storage is SQLite through GRDB

- **Decision:** SQLite (WAL mode, FTS5 for offline full-text search) accessed through [GRDB](https://github.com/groue/GRDB.swift). It is the single approved third-party dependency.
- **Why:**
  - A mail client is a large indexed table of headers, with many-to-many labels and text search. SQLite does this best.
  - GRDB supplies migrations, observation, FTS and multi-process support, so we don't write and maintain our own layer.
- **Rejected:**
  - SwiftData: unproven at 100k+ messages, slow many-to-many queries, no FTS.
  - Core Data: no FTS.
  - Raw SQLite C API: about 1–2k lines of wrapper we'd own.
- **Rule:** only the `MailStore` package imports GRDB.

## ADR-002: App and Notification Service Extension both write

- **Decision:** the app and the NSE both write to the shared database in the App Group container, using a GRDB `DatabasePool`. Widgets only read.
- **Why:** the NSE can persist the messages it fetches, so the app shows them on open without fetching them again.
- **Obligations:**
  - Writes are short transactions, finished before the extension returns. iOS kills a suspended process that holds a lock in a shared container (`0xdead10cc`).
  - Every process handles `SQLITE_BUSY` with a busy timeout.
  - Cross-process changes are announced with a Darwin notification, and the other process re-reads.
  - Database files use `NSFileProtectionCompleteUntilFirstUserAuthentication` so the NSE can open them while the phone is locked.
- **Rejected:** the app as the only writer, with the NSE handing new mail over in a side file.

## ADR-003: One web view per message

- **Decision:** each message in a thread renders in its own `WKWebView`:
  - Collapsed messages aren't rendered.
  - Email JavaScript is off.
  - A `WKContentRuleList` blocks remote content by default.
  - `cid:` images are served by a `WKURLSchemeHandler`.
  - Our own script, in an isolated `WKContentWorld`, measures height and applies `dir=auto`.
- **Why:** per-message actions, accessibility and RTL stay simple, and it matches Apple Mail.
- **Rejected:** one web view per thread, which scrolls more smoothly but makes all of the above harder.

## ADR-004: Programmatic UIKit for the core UI

- **Decision:** UIKit for every core surface:
  - `UISplitViewController`
  - `UICollectionView` with diffable data sources and list layout
  - `UITextView` on TextKit 2 for compose
  - reactivity through Observation (automatic tracking, `updateProperties()`) and trait collections
- **Never** Storyboards or XIBs; all UI is programmatic.
- **SwiftUI is allowed only for:** WidgetKit, App Intents snippets, and simple low-traffic settings forms hosted in UIKit.
- **Why:** the owner's call, for performance and smoothness. UIKit gives the most control over list scrolling and rich-text editing.

## ADR-005: Local Swift packages split by knowledge

- **`MailCore`:** domain types (Account, Thread, Message, Label, Mailbox), the provider protocol, the sync engine, the outbox. Pure Swift, no UIKit.
- **`MailStore`:** GRDB schema, migrations, queries, cross-process change notices. Nothing else imports GRDB.
- **`GmailProvider`:** Gmail REST and JSON, OAuth, history sync, watch renewal. It converts everything into `MailCore` types, and no Gmail wire type escapes it. `OutlookProvider` comes later as a sibling.
- **`ICloudProvider`:** IMAP over TLS with an app-specific password. IMAP keeps messages in folders, so it derives thread IDs from References and In-Reply-To, keeps each message's thread in MailCore's `MessageIndexStore`, gives a message its folder's label (Archive none, `\Flagged` STARRED, no `\Seen` UNREAD), and takes every folder's STATUS as the cursor, reading changes with CONDSTORE and QRESYNC. No IMAP wire type escapes it.
- **`MailUI`:** UIKit screens and components, theme with account colors, RTL helpers.
- **Targets:** the app (thin wiring), the NSE (MailCore, MailStore, GmailProvider, never MailUI), widgets.
- **Why:** the compiler enforces the boundaries, so Gmail code can't leak into the UI and only `MailStore` sees the database.
- **Layout (revised 2026-10-24, at the owner's request):** one local package per module under `Packages/` (`MailCore`, `MailStore`, `GmailProvider`, `MailUI`, `MailIntents`), each with its own manifest and tests. Dependencies between them are `path:` packages; only `MailStore` pins GRDB. A module's manifest states exactly what it may import, and each can be built and tested alone.
- **Earlier layout (M0):** one `GoodmailKit` package with a target per module. Replaced because the owner wants each module standalone.
- **Rejected:** one target with folders (no enforcement); per-feature packages (premature).

## ADR-006: Push backend is a TypeScript Worker with D1

- **Decision:** a Cloudflare Worker in TypeScript with zero runtime dependencies. APNs JWT signing and Google OIDC/ID-token checks use WebCrypto.
- **Dev tooling only:** `wrangler`, `typescript`, and the Cloudflare Vitest integration.
- **Storage:** D1 holds HMAC(email) → device tokens and APNs environment. Duplicate Pub/Sub deliveries are dropped by a conditional write on `(account, historyId)`.
- **Why:** D1 is the simplest fit for one table and has generous free limits.
- **Rejected:**
  - Durable Objects: more moving parts now; reconsider for iCloud.
  - KV: only 1k writes a day on the free plan, and eventually consistent.

## ADR-007: Windowed offline cache

- **Headers:**
  - 90 days for Inbox, Sent, Starred and Drafts; 30 days for other labels.
  - Older mail is fetched on scroll or search.
- **Bodies:** the newest ~500 threads prefetched on Wi-Fi, the rest on demand, under a 1 GB cap with least-recently-used eviction.
- **Attachments:** on demand.
- **Cap:** bodies and opened attachments share the 1 GB. A thread's bodies are evicted together, least recently read first; summaries stay, so lists and subject search keep working, and the body is fetched again on open. Threads with a draft or a queued action are never evicted. Prefetch runs only on a path that is neither expensive nor constrained, and dates what it fetches by the mail, so it never outranks what the reader opened.
- **Search:** local FTS answers instantly, then Gmail server search fills in.
- **Rejected:** mirroring everything (multi-GB, long first sync); user-configurable windows (not for v1).

## ADR-008: Outbox replays intents idempotently

- **Decision:** user actions apply to the local store immediately and are queued as intents, for example "archive thread T". Replay sends exactly the intent, so a repeat is harmless. No merge dialogs, ever.
- **Failures:**
  - If the target is gone on the server, the intent is dropped silently.
  - Only failures the user must know about, such as a failed send, are shown.

## ADR-009: Google OAuth is "In production", unverified, for TestFlight

- **Decision:** publish the OAuth consent screen as "In production" without verification.
- **Why:** Testing mode expires refresh tokens after 7 days, which would force a weekly sign-in and break push.
- **Accepted costs:** a one-time "unverified app" warning at sign-in, and a cap of 100 users.
- **Timing (2026-10-20):** publishing needs a home page, a privacy policy and an authorized domain. The owner chose to proceed without any domain for now: the app stays in Testing (7-day refresh tokens, test users only) until a domain is bought. The push Worker uses its free `workers.dev` address, and a domain is needed only for publishing to production and for iCloud forward-to-push (post-v1). See [../setup/google-cloud.md](../setup/google-cloud.md).

## ADR-010: Sync tests run on scrubbed recorded fixtures

- **Decision:** record Gmail API responses from a dedicated test Gmail account that the owner provides, never a personal inbox. A script strips personal data, and the fixtures are committed.
- **Tests:** sync and provider tests run offline against them with Swift Testing.

## ADR-011: MVVM+C with Commands and Routes

- **ViewModel:** `@MainActor @Observable`, with no UIKit import. It holds screen state and calls domain APIs.
- **ViewController:** programmatic UIKit. It renders through Observation (`updateProperties()`) and forwards user events. No logic.
- **Coordinator:** one per window (scene), owning the `UISplitViewController`. Child coordinators handle flows (compose, account setup).
- **Commands:** `MailCommands` in `MailCore` is the only way to change mail (archive, send, move, label…). View models, App Intents, notification actions and widgets all call it. It applies the change locally and queues the intent in the outbox (ADR-008).
- **Routes:** a typed `Route` enum is the only way to navigate. Notifications, Spotlight, `mailto:`, App Intents, Handoff and state restoration all produce Routes, and the scene coordinator handles them.
- **Rejected:**
  - TCA: a dependency.
  - VIPER: too much ceremony.
  - Plain MVVM+C: action logic would be duplicated between view models and intents.

## ADR-012: App Intents are a first-class surface

- **Package:** a `MailIntents` package (`AppIntentsPackage`), shared by the app, widgets and the NSE.
- **Entities:** Account, Mailbox, Thread, Message, Draft and Contact, adopting the SDK's `.mail` app-schema domain (`MailAccountEntity`, `MailboxEntity`, `MailThreadEntity`, `MailMessageEntity`, `MailDraftEntity`).
- **Spotlight:** entities are `IndexedEntity`. This is the one mechanism for Spotlight; there is no separate `CSSearchableIndex` code.
- **Rule:** every user action is an intent, and calls `MailCommands`. Destructive intents are `UndoableIntent`.
- **v1 scope** (the full surface):
  - App Shortcuts with English and Hebrew phrases
  - Focus filters (accounts per Focus)
  - a Control Center control (New Message)
  - interactive widgets
  - open intents that produce Routes

## ADR-013: Trunk-based workflow with a local gate

- **Branching:** short-lived branches, one vertical slice per PR, squash-merged into `main`, linear history.
- **The gate:** `scripts/check` runs format lint, the line cap, the build and the tests. A tracked pre-push hook (`.githooks`, `core.hooksPath`) runs it. Each PR description includes its output and other evidence (screenshots, recordings).
- **Merging:** superseded by ADR-016. PRs merge through the review pipeline, not by hand. The owner reviews evidence afterwards, and feedback becomes follow-up PRs.
- **CI:** GitHub Actions Linux runners: format lint and the line cap. Xcode Cloud comes later, only for TestFlight builds.
- **Merge-conflict hygiene:**
  - Code lives in local packages, and the app target uses Xcode synchronized (buildable) folders, so adding files doesn't edit `project.pbxproj`.
  - `swift format`, which ships with the toolchain, auto-formats.
  - Each package has its own String Catalog.
  - Parallel sessions work in separate git worktrees on separate packages.

## ADR-014: 1000-line hard cap per file

- `scripts/check` fails on any `.swift` or `.ts` file over 1000 lines, and warns above 800. The pre-commit hook and CI run it too.
- **Exempt:** fixtures, `.xcstrings`, `project.pbxproj`, lockfiles and other generated files.
- **On hitting the cap:** split by responsibility. Never squeeze lines to get under it.

## ADR-015: Xcode's JSON project format (`.xcproj`)

- **Decision:** the Xcode project uses the JSON project configuration format (`project.xcproj`) introduced in Xcode 27.2, not `project.pbxproj`.
- **Why:** smaller and hierarchical diffs, fewer merge conflicts, and easier editing for coding agents. This complements ADR-013's conflict hygiene.
- **Requirements:**
  - Xcode 27.2 or later to create and convert projects. Projects in the new format still open in earlier Xcode 27 versions.
  - Apple's `xcode-project-format` Swift library is available for scripted edits if ever needed. It's a dependency, so it needs approval first.
- **Note:** ADR-014's line-cap exemption for `project.pbxproj` applies to `project.xcproj` instead.

## ADR-016: Claude review gates every merge

- **Decision (owner, 2026-11-12):** every PR is reviewed on GitHub by Claude (`claude-code-action` in `.github/workflows/review.yml`) against [docs/review.md](../review.md). When the review approves and lint is green, the workflow squash-merges the exact commit it reviewed.
- **Why:** a fully autonomous process where review findings are visible on GitHub, with a standard (no implicit state machines, the 1000-line cap, thermo-nuclear code quality) that doesn't depend on which session wrote the code.
- **How it's enforced:** the repo is private on a free plan, so GitHub's branch protection and native auto-merge are unavailable. The workflow is the gate: the merge job runs only after both jobs pass, and `--match-head-commit` refuses to merge a commit that wasn't reviewed.
- **Exceptions:** a `hold` label stops the merge; PRs that change `.github/` are merged by the owner, because they change the gate; drafts aren't reviewed. The Claude action enforces the first part itself: it refuses to run when a PR's `review.yml` differs from main's, so a PR can't rewrite its own reviewer.
- **Setup:** the Claude GitHub app is installed on the repo, and the `CLAUDE_CODE_OAUTH_TOKEN` secret comes from `claude setup-token`.

## ADR-017: Cloud workers compile for iOS with xtool

- **Decision (owner, 2026-11-13):** Claude cloud sessions (Linux, no Xcode) compile every package and its tests for `arm64-apple-ios` with [xtool](https://github.com/xtool-org/xtool)'s Darwin SDK. A SessionStart hook installs everything ([docs/setup/cloud-builds.md](../setup/cloud-builds.md)). On Linux, `scripts/check` runs the lint, that compile, a type-check of the app and extension targets, and the native Linux tests of the packages without UIKit or SwiftUI (MailCore, GmailProvider, MailStore), which fence their few Apple-only APIs with `#if canImport`. MailUI's tests and the app run on the Mac.
- **Why:** parallel simulator builds overload the Mac. Package and logic work can move to cloud threads only if they catch compile errors before pushing.
- **The SDK:** it is built from the Mac's own Xcode, so cloud builds use the same SDK as Mac builds and never need an Apple sign-in. The SDK lives in the private `shinycake/goodmail-sdk` repository, because Apple's license doesn't allow redistributing it and a separate repository keeps it out of this repository's clones.
