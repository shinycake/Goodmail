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

- **Decision:** the app and the NSE both write to the shared database in the App Group container, using a GRDB `DatabasePool`. Widgets read, and their buttons change mail only through `MailCommands`, which queues the change in the outbox for the app to send on its next sync.
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
  - A `WKContentRuleList` blocks remote content by default. The reader loads it once per message, or always for a sender they trust, kept on the device by address (`TrustedImageSenders`).
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
- **`IMAPProvider`:** any IMAP and SMTP account, over TLS or STARTTLS (`MailServerSettings`); iCloud Mail is one, signed in to with an app-specific password. IMAP keeps messages in folders, so it derives thread IDs from References and In-Reply-To, keeps each message's thread in MailCore's `MessageIndexStore`, gives a message its folder's label (Archive none, `\Flagged` STARRED, no `\Seen` UNREAD), and takes every folder's STATUS as the cursor, reading changes with CONDSTORE and QRESYNC. No IMAP wire type escapes it.
- **`MailUI`:** UIKit screens and components, theme with account colors, RTL helpers.
- **`MailNotifications`:** new-mail alerts: what the NSE fetches and which threads alert, the alert content and actions, and how a tap names its thread. Shared by the app and the NSE; no UIKit.
- **Targets:** the app (thin wiring), the NSE (MailCore, MailStore, GmailProvider, MailNotifications, never MailUI), widgets.
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
  - Durable Objects: more moving parts now. iCloud didn't need them either: a cron run every 5 minutes logs in to each watched IMAP Inbox and holds IDLE until the next run. An always-on object holding IDLE would use about 83% of the free daily duration quota (research in the project files, 2026-11-16). ADR-026 moved the IMAP watching into one.
  - KV: only 1k writes a day on the free plan, and eventually consistent.

## ADR-007: Windowed offline cache

- **Headers:**
  - 90 days for Inbox, Sent, Starred and Drafts; 30 days for other labels.
  - Older mail is fetched on scroll or search.
- **Bodies:** the newest ~500 threads prefetched on Wi-Fi and the newest 50 on cellular (the reader can narrow this to Wi-Fi or turn it off), the rest on demand, under a 1 GB cap with least-recently-used eviction. A cached thread whose newest message is missing is fetched again, and a background refresh fetches the bodies of the few newest threads after its sync.
- **Attachments:** on demand.
- **Cap:** bodies and opened attachments share the 1 GB. A thread's bodies are evicted together, least recently read first; summaries stay, so lists and subject search keep working, and the body is fetched again on open. Threads with a draft or a queued action are never evicted. Prefetch never runs on a constrained path (Low Data Mode), and dates what it fetches by the mail, so it never outranks what the reader opened.
- **Search:** local FTS answers instantly, then Gmail server search fills in.
- **Rejected:** mirroring everything (multi-GB, long first sync); user-configurable windows (not for v1).
- **Amended (2026-11-20): the window depends on the device.** `OfflineWindow` (MailCore) holds the values, and the app picks one at its edge with `ProcessInfo.isMacCatalystApp`, as it does for presence (ADR-033). `.handheld` is everything above and stays as it was for iPhone and iPad. `.desktop`, for a Mac, keeps 365 days of headers for Inbox, Sent, Starred and Drafts and 90 days for the other labels, and caps the cache at 10 GB by default, with 1, 5, 10, 20 and 50 GB to choose from (a handheld offers 250 MB to 5 GB). `SyncScope.window` carries the `OfflineWindow` it keeps. The watch's Inbox head keeps looking back 90 days. A stored size that the device doesn't offer reads as its default.

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

- **Branching:** short-lived branches, one vertical slice per commit on `main`, linear history (since ADR-028, pushed straight to main, not merged through PRs).
- **The gate:** `scripts/check` runs format lint, the line cap, the build and the tests. A tracked pre-push hook (`.githooks`, `core.hooksPath`) runs it.
- **Merging:** superseded by ADR-016, then by ADR-028: changes are pushed straight to main after a local review. The owner reviews the result afterwards, and feedback becomes follow-up work.
- **CI:** a GitHub Actions Linux runner runs the Linux `scripts/check` (ADR-017) on main. Xcode Cloud comes later, only for TestFlight builds.
- **Merge-conflict hygiene:**
  - Code lives in local packages, and the app target uses Xcode synchronized (buildable) folders, so adding files doesn't edit `project.pbxproj`.
  - `swift format`, which ships with the toolchain, auto-formats.
  - Each package has its own string catalogs, one table per feature folder (ADR-014).
  - Parallel sessions work in separate git worktrees on separate packages.

## ADR-014: 1000-line hard cap per file

- `scripts/check` fails on any tracked text file over 1000 lines, code or not, and warns above 800. The pre-commit hook and CI run it too.
- **Exempt:** recorded fixtures, `project.xcproj`, lockfiles and the vendored skills in `.claude/skills`, which follow their upstream.
- **String catalogs:** each feature folder of a package has its own string table (`Resources/<Feature>.xcstrings`, used with `table:` or `tableName:`), so catalogs stay small and two features don't conflict in one file (2026-11-13).
- **On hitting the cap:** split by responsibility. Never squeeze lines to get under it.

## ADR-015: Xcode's JSON project format (`.xcproj`)

- **Decision:** the Xcode project uses the JSON project configuration format (`project.xcproj`) introduced in Xcode 27.2, not `project.pbxproj`.
- **Why:** smaller and hierarchical diffs, fewer merge conflicts, and easier editing for coding agents. This complements ADR-013's conflict hygiene.
- **Requirements:**
  - Xcode 27.2 or later to create and convert projects. Projects in the new format still open in earlier Xcode 27 versions.
  - Apple's `xcode-project-format` Swift library is available for scripted edits if ever needed. It's a dependency, so it needs approval first.
- **Note:** ADR-014's line-cap exemption for `project.pbxproj` applies to `project.xcproj` instead.

## ADR-016: Claude review gates every merge

- **Superseded by ADR-028 (2026-11-19):** there are no more PRs, and `review.yml` is deleted.
- **Decision (owner, 2026-11-12):** every PR is reviewed on GitHub by Claude (`claude-code-action` in `.github/workflows/review.yml`) against [docs/review.md](../review.md). When the review approves and the Linux `scripts/check` is green on the PR merged with the current main, the workflow squash-merges the exact commit it reviewed. If main moved after the check, the merge job checks the PR merged with the new main before merging (2026-11-13), and an approval carries over to pushes that only merge main in, keyed on the `git patch-id` of the PR's own diff. The merge job makes the squash commit itself, authored by the PR author's noreply address, and fast-forwards main to it, which fails if main moved; GitHub's own squash would author it with the account's personal email (2026-11-13).
- **Why:** a fully autonomous process where review findings are visible on GitHub, with a standard (no implicit state machines, the 1000-line cap, thermo-nuclear code quality) that doesn't depend on which session wrote the code.
- **How it's enforced:** the workflows are the gate. Since 2026-11-14 the merging is the merge queue's (ADR-020): `review.yml` judges a PR, and `merge-queue.yml` lands it only once both its review and its check passed on that exact head.
- **Exceptions:** a `hold` label stops the merge; PRs that change `.github/` are merged by the owner, because they change the gate; drafts aren't reviewed. The Claude action enforces the first part itself: it refuses to run when a PR's `review.yml` differs from main's, so a PR can't rewrite its own reviewer.
- **Setup:** the Claude GitHub app is installed on the repo, and the `CLAUDE_CODE_OAUTH_TOKEN` secret comes from `claude setup-token`.

## ADR-017: Cloud workers compile for iOS with xtool

- **Decision (owner, 2026-11-13):** Claude cloud sessions (Linux, no Xcode) compile every package and its tests for `arm64-apple-ios` with [xtool](https://github.com/xtool-org/xtool)'s Darwin SDK. A SessionStart hook installs everything ([docs/setup/cloud-builds.md](../setup/cloud-builds.md)). On Linux, `scripts/check` runs the lint, that compile, a type-check of the app and extension targets, and the native Linux tests of the packages without UIKit or SwiftUI (MailCore, GmailProvider, IMAPProvider, OutlookProvider, MailStore), which fence their few Apple-only APIs with `#if canImport`. MailUI's tests and the app run on the Mac.
- **Why:** parallel simulator builds overload the Mac. Package and logic work can move to cloud threads only if they catch compile errors before pushing.
- **The SDK:** it is built from the Mac's own Xcode, so cloud builds use the same SDK as Mac builds and never need an Apple sign-in. The SDK lives in the private `shinycake/goodmail-sdk` repository, because Apple's license doesn't allow redistributing it and a separate repository keeps it out of this repository's clones.

## ADR-018: A WIP limit keeps PRs from piling up

- **Superseded by ADR-028 (2026-11-19)**, except the conflict-hotspot rule at the end, which still holds.
- **Decision (owner, 2026-11-13):** work flows through a small number of open PRs, and each thread lands its PR before opening the next. On 2026-11-13, 19 approved PRs piled up and bounced each other off main for hours; this rule keeps that from happening again.
- **Lanes:** a lane is one stream of work: a cloud thread's `claude/project-thread-<id>` branches, or a Mac branch's name up to its first `-` or `/` (`m5-formatting` is lane `m5`). Name a Mac branch by its lane.
- **The limit:** one ready PR per lane. Until 2026-11-14 a `wip` job in `review.yml` also capped ready PRs at six and turned a PR over the limit back into a draft. GitHub refuses that conversion to the workflow's token, and the merge queue (ADR-020) now serializes merges and rechecks each PR against main itself, so the job is gone and the lane rule is a working rule each thread keeps.
- **Landing is the job:** the merge queue lands a PR on its own, but a thread whose PR's `merge-queue` status is a failure fixes it (review findings, conflicts, failing checks) before any new work. The next slice can be built on a local branch meanwhile, but isn't pushed as a PR until this one merges.
- **PR size (owner, 2026-11-18):** don't split work into many small PRs. A feature can land as one bigger PR, as long as the review still reads all of it: keep each PR to one feature, put its own tests and fixtures in it, and split it only where the parts make sense on their own. Fewer PRs also mean fewer trips through the merge queue. The Claude review scales with the diff: it runs on Opus with more turns the bigger the PR is, splits a PR over 1,200 changed lines across subagents, and can't approve until it reports every changed file as read in full. Until 2026-11-18 the aim was about 400 changed lines per PR, with a big feature landing as a stack of slices.
- **Main moving costs nothing:** the merge queue rechecks an approved PR against a newer main itself (ADR-020), so a thread never pushes just to take in main. Merge main in only when the workflow says the PR conflicts with it or fails on it.
- **Conflict hotspots:** new code goes in new files. Don't grow a central file that every feature touches (a coordinator, a registry, a shared string table). Give each feature its own file, extension or string table, and split a central file when two lines of work keep conflicting in it.

## ADR-019: Gmail asks for the full mail scope, for Delete Forever

- **Decision (owner, 2026-11-14):** Gmail signs in with `https://mail.google.com/` in place of `gmail.modify`, because only the full scope lets the API delete mail for good. Delete Forever, in Trash, then works the same on all three services: Gmail deletes each trashed message (`messages.delete`), Outlook calls Graph's `permanentDelete` on each message in Deleted Items, and iCloud marks each copy in Trash `\Deleted` and removes it with `UID EXPUNGE`. Messages of the thread outside Trash stay.
- **Why:** Goodmail is for the owner's own use, with no public release planned, so the cost of the broader scope (Google's narrowest-scope rule in verification) doesn't apply yet.
- **Consequences:** an account signed in before this change keeps a token without the scope. Gmail refuses its Delete Forever (`ACCESS_TOKEN_SCOPE_INSUFFICIENT`), the outbox drops the intent as refused, and the thread stays in Gmail's Trash, which empties itself after 30 days. Signing in to the account again (Settings → Add Account, same address, which keeps the account) grants the scope.
- **Before any public release:** both scopes are restricted, so Google's OAuth verification and the yearly CASA security assessment are needed either way, and the full scope has to be justified in that submission as the only one that allows permanent delete. If Google won't accept it, drop back to `gmail.modify` and hide Delete Forever on Gmail.

## ADR-020: A merge queue workflow lands approved PRs

- **Superseded by ADR-028 (2026-11-19):** `merge-queue.yml` and its scripts are deleted.
- **Decision (owner, 2026-11-14):** merging moves out of `review.yml` into `.github/workflows/merge-queue.yml`. A sweep runs after every review run, every 10 minutes, and after every sweep that changed something. It picks the oldest ready PR that is approved and green, checks it squashed onto the current main if main moved since its check, and fast-forwards main to that squash. It reruns a failed review run up to three attempts, and puts every PR's place in the queue on its `merge-queue` commit status.
- **Trains (2026-11-18):** a sweep checks every approved PR at once, up to six, squashed onto main one after another, with one `scripts/check`, and lands them in order. Checking each PR on its own cost about 20 minutes per PR, so six approved PRs took two hours to land. If the train fails, the queue checks its first PR alone and lands only that one.
- **Why:** the merge job ran once, inside the PR's own review run. When main kept moving, a check flaked or a run crashed, the PR sat approved until a Claude thread noticed and pushed or reran it, so threads stayed open for hours just to land their PR. Sweeps start themselves and run one at a time, so a backlog drains with nobody watching.
- **Kept from ADR-016:** the squash that lands is the tree that was checked, authored by the PR author's noreply address; main only fast-forwards and is never force-pushed; `hold` and `.github/` PRs wait for the owner.
- **Not GitHub's merge queue or auto-merge:** the merge queue needs an organization-owned repository, and auto-merge would have GitHub author the squash and start no workflows on main.

## ADR-021: Every target compiles with the strictest Swift

- **Decision (owner, 2026-11-15):** every package target, test targets included, and every Xcode target compile in Swift 6 mode with complete concurrency checking, every Swift 7 upcoming feature (`ExistentialAny`, `ImmutableWeakCaptures`, `InferIsolatedConformances`, `InternalImportsByDefault`, `MemberImportVisibility`, `NonisolatedNonsendingByDefault`), the lifetime checker (`Lifetimes`), strict memory safety, run-time exclusivity checks in every configuration, and every warning an error. [scripts/strict-swift](../../scripts/strict-swift) holds the one list. Each `Package.swift` declares it as `strictSwift` for each of its targets, the Xcode project sets it once for all targets, and `scripts/ios-build` takes its `swiftc` flags from the script.
- **Why:** crashes from data races, double resumes and unexpected isolation reached TestFlight. The compiler catches more of these with each feature on, and warnings that nobody has to fix pile up until nobody reads them.
- **How it's enforced:** `scripts/check` runs `scripts/strict-swift --check`, which fails when a manifest's `strictSwift` drifts from the list, a target goes without it, a manifest loosens it, or the Xcode project doesn't set it at the project level alone. Since every warning is an error, the iOS compile in CI fails on any new one.
- **Unsafe code:** strict memory safety makes every unsafe construct (a pointer, `unsafe` C API, `Unmanaged`, `nonisolated(unsafe)`, `@unchecked Sendable`) visible as an `unsafe` expression or `@unsafe` declaration. Each one carries a comment that states why it is safe, as `@unchecked Sendable` already must (docs/review.md, blocker 5). Prefer an API that keeps the pointer inside the framework, such as a Core Graphics bitmap with `data: nil`.
- **Adding a feature:** add it to `scripts/strict-swift`, run `scripts/strict-swift --check` for the block to paste into each manifest, and set the Xcode spelling (`SWIFT_UPCOMING_FEATURE_*`, or `OTHER_SWIFT_FLAGS` when Xcode has none).

## ADR-022: The Apple Watch app shows the iPhone's mail

Amended by ADR-023: Gmail and Outlook accounts are now read on the watch itself.

- **Decision (owner, 2026-11-17):** the watch app keeps a snapshot of the Inbox that the iPhone sends it over WatchConnectivity, and it sends changes back as commands that the iPhone runs through `MailCommands`. It holds no sign-ins, no database and no sync engine. With the iPhone away it shows the last snapshot; the owner chose not to have the watch fetch mail on its own.
- **Why:** IMAP and SMTP need a raw TLS socket, which watchOS allows only for audio and VoIP apps, so a watch that talked to servers itself would lose iCloud and custom IMAP accounts. Snooze, pins, rules and the Focus live only in the iPhone's database. New-mail alerts already reach the watch: iOS mirrors them, and their actions run in the iPhone app.
- **Naming:** Apple Watch types are called Wrist (`MailWrist`, `WristSnapshot`), because Watch already means Gmail's watch and `ChangeWatchers`. Only the Xcode target says Watch.
- **Exceptions:** the watch's screens are SwiftUI, the only UI watchOS has (ADR-004). Its actions will be its own commands, not App Intents (ADR-012), since MailIntents needs CoreSpotlight and the `.mail` schema macros.
- **Rejected:** a watch that syncs on its own, for the reasons above, and a relay with no copy on the watch, where every screen would wait for the iPhone.

## ADR-023: The Apple Watch reads Gmail and Outlook itself

- **Decision (owner, 2026-11-17):** on the watch, each account has one source. A Gmail or Outlook account whose sign-in is in the watch's Keychain is direct: the watch keeps the newest 100 Inbox conversations in its own database, syncs them with `SyncEngine`, and sends archive, trash, read and reply through its own `MailCommands` and outbox. Every other account is relayed, as ADR-022 describes. The iPhone stays the keeper of the account list and of pins, snoozes, device-side mute, rules, Focus and device-side signatures, which it sends in the snapshot for the watch to lay over its rows. Pin and Snooze always run on the iPhone.
- **Why:** the owner wants mail on the watch with the iPhone off or away. In the background, the watch can't tell whether the iPhone is reachable, so the path can't depend on that, and a relayed snapshot goes stale whenever the iPhone app is suspended. Apple's guidance agrees: WatchConnectivity is an optimization, not the main source of data.
- **Amends ADR-022:** "It holds no sign-ins, no database and no sync engine" now holds for relayed accounts only. iCloud and IMAP stay relayed for the reason ADR-022 gives: watchOS blocks the raw TLS sockets they need (TN3135).
- **Sign-ins:** they come from iCloud Keychain, through the shared access group. Nobody signs in on the watch, and the watch has no OAuth client of its own.
- **Alerts:** the relay sends each alert to the iPhone. When the iPhone's notification extension doesn't confirm it within 8 seconds, the relay sends it to the watch's own token, which the iPhone registered beside its own.
- **One host:** `WristMailHost` in `MailWristHost` turns a database into snapshots, runs commands and builds conversations. The iPhone uses it for the watch, and the watch uses it for itself.
- **States:** `WristAccountSource` says who serves an account and why, and only `WristAccountSources.resolve` changes it. `WristExecutor` is stamped on a command when the command is made.
- **Builds:** MailCore, MailStore, GmailProvider, OutlookProvider and MailWrist also build for watchOS, which only the Mac can compile (`scripts/check`, `WATCH_BUILT_PACKAGES`).
- **Rejected:**
  - Switching between the iPhone and direct by reachability, which the watch can't know in the background.
  - An IMAP proxy in the push Worker, which would pass mail through the server.
  - Signing in on the watch.
  - A fully independent watch app, which would lose iCloud, IMAP and every iPhone-only feature.

## ADR-024: Settings follow the reader through iCloud Keychain

- **Decision (2026-11-17):** the reader's settings sync to their other devices through `SettingsSync`. Each group of settings (the preferences in `UserDefaults`, image rules, unsubscribed lists, and the database's signatures, alerts, badge choices and rules) is one synchronizable Keychain item under the service `com.idanbirman.goodmail.settings`. Accounts themselves, with their names, colors and order, keep syncing through `AccountSharing`.
- **Conflicts:** each setting in a group merges on its own, and the newest change wins wherever it was made (`SettingsMerge`). A device keeps a ledger of what it last synced, so it can tell its own edits, made since, from values that came from elsewhere. Removals stay as dated entries for 180 days, so a device that still has a value learns it went. A setting a device never synced gives way to the shared one, so a new device or a reinstall takes up the reader's settings instead of sharing its defaults. Item-level last-writer-wins in iCloud Keychain loses nothing: a device whose write was overwritten still has the entry in its ledger and shares it again on the next pass.
- **Kept on the device:** how the device answered shared-account offers and whether it shares accounts (each device decides those for itself), recent searches (history, not a choice), the Focus filter (iOS sets it per device), and bookkeeping such as push subscriptions, how far mail has alerted or been through the rules, and minimized drafts. Gmail signatures sync through Gmail itself. Pins, device-side mutes and snoozes are mail state rather than settings, and sync on their own since ADR-037.
- **Why not the iCloud key-value store:** it is the usual home for preferences and tells the app at once when another device changes something, but it needs the iCloud capability on the App ID, which Xcode couldn't add without signing in again. iCloud Keychain needs nothing new and already carries the accounts. Passes run at launch, every foreground sync round (30 seconds), when Settings closes and when the app leaves the foreground. `SettingsSync` takes any `SecretStore`, so moving to the key-value store later only changes where the app points it.
- **Amended (2026-11-20): storage choices stay on the device.** The cache size and Download Ahead (`cacheLimit`, `prefetchScope`) leave the synced preferences and join the device-local settings, because what a Mac can spare says nothing about an iPhone. They keep their `UserDefaults` keys, so each device keeps the value it has when it updates and nothing is converted. A device never takes up the shared entries for these two keys again, and the entries already in the Keychain are left for older builds to read.
- **Amended (2026-11-20): the reader's zoom stays on the device.** `ReaderZoomModel` keeps the size ⌘+, ⌘− and ⌘0 set in `UserDefaults` under `readerZoom`, outside `Preferences.syncedSettings`, since a Mac display and a phone want different sizes. Every message view reads it through Observation, so each open window follows.

## ADR-025: Only the genuine app may use the push relay

- **Decision (owner, 2026-11-17):** every request the app makes to the push Worker is signed with an App Attest key, and the Worker refuses unsigned ones once `APP_ATTEST` is `enforce`. `RelayAttestation` (MailCore) attests one key per install and signs each request; `PushRelayClient` sends the headers and, on a 428, attests again and retries once. The Worker checks attestations against Apple's App Attestation root (`PushWorker/src/app-attest.ts`) with its own small DER, X.509 and CBOR readers rather than a dependency.
- **Why:** the repository is public, so anyone can build the app with our Google and Microsoft client IDs and the Worker's address baked in. Without a check, a fork could store tokens and IMAP logins on our relay and take the IMAP watch slots our own mail needs. App Attest ties a key to our team's App ID on a real device, which a fork under another team can't fake.
- **Replays:** an assertion covers the method, path, a timestamp and the body, and the Worker allows 10 minutes of skew, so a captured request can only be repeated as is for a short while. The assertion counter isn't required to increase, because the app's requests can arrive out of order.
- **Limits:** the Simulator can't attest, so a Simulator build only reaches the relay while it is in `observe`. Google sign-in is guarded by the OAuth app staying in Testing with a short test-user list, and Microsoft's by Graph being free per mailbox; the Azure app has public client flows (device code, ROPC) turned off.

## ADR-026: One Durable Object holds the IMAP Inboxes

- **Decision (owner, 2026-11-17):** one Durable Object, `InboxHolder`, keeps an IMAP connection open to every watched Inbox. Its alarm goes off every minute and starts a watch on each mailbox that is due and has none. A watch holds IDLE for 30 minutes. The 5-minute cron stays as a watchdog: it wakes the holder, and when the holder can't be reached it watches the Inboxes itself, as every run did before.
- **Why:** the cron runs were inexact. In 30 hours, 4 of 365 runs never started and 5 started more than once, and each run left about 13 seconds between its logout and the next login. The cron also logged in to iCloud 288 times a day for each mailbox. The holder logs in 48 times a day and has no gap between runs.
- **Trial (2026-11-18, free plan):** one object held one iCloud connection for 46 minutes, until the trial ended it. Its 51 alarms came 60.001 to 60.011 seconds apart and used 0 to 2 ms of CPU each. Three test emails were announced 3 to 6 seconds after they were sent. After a forced reset the next alarm logged in again by itself.
- **Cost:** $0. An object that never sleeps uses about 11,060 of the free plan's 13,000 GB-seconds a day, so the account has room for this one object and no second one. If Cloudflare refuses the object for the rest of a day, the cron's own watching takes over until the next day.
- **Limit:** the holder watches 4 mailboxes at a time, since a Worker may hold 6 connections. With more, each takes its turn, and one can wait up to 30 minutes for a check, because the cron no longer polls while the holder answers.
- **State:** D1 keeps the watches, as before. The holder keeps only which mailboxes it is watching, in memory, and reads a mailbox's devices from D1 each time it reads the STATUS. A watch is moved with a conditional write, so the holder and a cron run that look at the same mailbox alert once.
- **Rejected:**
  - One object per mailbox: two always-on objects go over the free daily duration.
  - Forwarding iCloud mail to a Cloudflare Email Worker: needs a domain on Cloudflare and a forwarding rule set up in each mailbox. Kept in reserve.
  - A home server or a small VM: something more to run and keep up, for the same result.

## ADR-027: The paper plane game's rules are their own package

- **Decision (2026-11-18):** the paper plane game hidden in the empty Inbox keeps its rules in `PlaneGame`, a package of its own: the tap streak that opens it, the flight paths the plane takes onto the field and home (`FlightPath`), and the world with its field, plane, arrivals, shots, collisions and score, as `Sendable` values stepped by `PlaneGameWorld.advance(by:input:)`. The world is simulated in the window's own coordinates: the plane flies up from near the bottom and the world comes down from the top, the same in every language, so nothing in play is mirrored. It imports Foundation only. MailUI depends on it and draws it, and owns everything with a look or a clock: the art, the morphs in and out, the HUD and the display link.
- **Why:** the rules are logic, so they belong in a module of their own (ADR-005) and out of MailUI, whose tests run only on the Mac. With Foundation alone the package builds on Linux, so `scripts/check` runs its tests on every push and a cloud session can build it test-first.
- **Replays:** a world takes a seed, and its random numbers come from a small seeded generator stored in it, so the same seed and inputs always give the same world. Tests rely on this, and so can a bug report.
- **Bosses:** what the world sends at the plane is one `Encounter` value: ordinary waves, the field clearing, or a boss. `PlaneGameWorld.stepEncounter(by:)` is the only place it moves from one case to the next, and a boss's own status (arriving, fighting, falling) changes only through `PlaneGameBoss`. Ordinary arrivals come only during waves, so nothing else needs to know a boss is on. The round is the number of the coming boss, read from the encounter rather than stored, and everything that hardens with it (`PlaneGameHeat`, the formations, each boss's tier, level and tempo) is a pure function of it. A boss's status is its only state: each kind's moves and attacks live in their own `PlaneGameBoss+<Kind>.swift`, worked out from its kind, number, age, hits and status, and `PlaneGameBoss+Motion.swift` only hands each step to them. Everything a boss sends goes through `PlaneGameWorld.send`, which stops at `PlaneGameRules.fieldHolds`, so a later boss can't flood the field.

## ADR-028: Changes go straight to main

- **Decision (owner, 2026-11-18 and 2026-11-19):** no more pull requests. The session that wrote a change reviews its whole diff against [docs/review.md](../review.md) (deep, with subagents for a big change), fixes what it finds, passes `scripts/check` and pushes to main.
- **Why:** the PR loop of a Claude review, the merge queue and a check per train made landing slow, and threads sat open waiting on it. Builds, TestFlight uploads and the Mac tests already run on the owner's Mac, so GitHub only needs to run one check.
- **What's left on GitHub:** `check.yml` runs the Linux `scripts/check` on main after each push, and a newer push cancels an older run. The repository stays public (owner, 2026-11-19), so Actions minutes are free. `review.yml` and `merge-queue.yml` (a sweep every 10 minutes) are gone because they only served PRs.
- **Commits:** squash each slice into one commit with a subject written for people, since `scripts/public-beta` lists the subjects in each TestFlight build's What to Test notes. Put evidence (screenshots, recordings) in the thread that did the work.
- **Still true:** main only fast-forwards and is never force-pushed. The pre-push hook runs `scripts/check`. Commits use the owner's noreply address.

## ADR-029: Alerts come down once their mail is dealt with

- **Decision (owner's ask, 2026-11-19):** an alert in Notification Center goes away by itself once its mail is read, archived, moved or deleted, wherever that happened: in Goodmail, on another device, on the watch, or in another app. The store decides it (`MailDatabase.handledAlerts(_:)`): a new-mail alert is done once its thread is read, out of the Inbox or gone; a rule's once read, in Trash or Spam, or gone; a push iOS showed as the relay sent it once its thread is stored as of the alert or later, and read or out of the Inbox. The sweep owns only these alerts; a snooze alarm and other features' alerts stay. A new alert posted under the same identifier while a sweep runs stays too. `HandledAlerts` (MailNotifications) reads the delivered alerts (`DeliveredAlert`, MailCore) and removes those.
- **When it runs:** the app follows a small summary of which threads are unread, in the Inbox, in Trash and in Spam (`MailDatabase.handlingChanges()`) and sweeps whenever it moves, which covers its own actions, every sync and what the notification extension stored. The extension sweeps after each catch-up. When the app isn't running, the relay sends a quiet background push for changes that brought no new mail (PushWorker/README.md), and the app syncs that account and sweeps. The watch sweeps the alerts the relay sent it from the Inbox it holds (`WristMailbox.handledAlerts`); alerts mirrored from the iPhone come down with the iPhone's. The relay spaces its quiet pushes 20 seconds apart per device and account, sending the last change of a burst at the end of the gap.
- **Why the summary:** counts and row-ID sums of four sets are cheap to read on every write, stay the same through syncs that change nothing that matters, and move whenever a thread enters or leaves one.
- **Limits:** iOS decides when a background push wakes the app and coalesces them, so an alert can stay for a while when the app is suspended, and never comes down while the app is force-quit until the next push or launch. The watch takes an alert down only when its copy of the Inbox holds mail as new as the alert, since the relay alerts the watch just when the iPhone may not have the mail. An IMAP push shown as sent names no conversation, so it comes down only with the placeholders when the app opens.

## ADR-030: The Share extension sends on its own, over a queue of its own

- **Decision (owner's ask, 2026-11-20):** other apps share into Goodmail through `ShareExtension`, which shows the app's own composer (`ComposeViewController` in a `ComposeWindowController`) filled with what was shared: Safari's page title as the subject (from `ShareScript.js`), text and links in the body above the signature, and files attached up to the composer's size limit. Send and Save Draft run right there while the sheet stays open under a progress card. `ImmediateDelivery` (MailCore) hands the message to a `Sender` of its own, over a `PrivateQueue` that holds only that message, with `InlineUploads` as the transport. Send Later puts the message in the shared queue as a scheduled send, and the app sends it.
- **Why a private queue:** the app's `Sender` drains the shared queue, and a direct (SMTP) send isn't marked as going before it goes. Two processes draining the same queue could send one message twice, and either could mistake the other's upload for a lost one. The extension's message isn't in the shared queue while it goes, so neither process can reach the other's messages.
- **What doesn't finish:** whatever is left in the private queue goes into the shared queue as it was left, and the queue's own rules finish it. A message still to go (offline, or its account has no login on this device) is sent at the app's next sync. An upload that ended without an answer, which the extension couldn't confirm by asking the service, is settled by the app's sender the same way, by asking before sending again. A refused message shows as failed. The sheet says which before it closes.
- **Leaving the screen:** the attempt runs under `performExpiringActivity`, so it finishes when the host app goes to the background. If that time runs out first, `ImmediateDelivery.handOver()` empties the private queue into the shared one, and nothing more is tried here. Only a direct send already on the wire can then go twice, the same window a launch killed mid-send leaves. An upload whose answer says nothing about whether it went isn't checked here: right after a send, Gmail's search may not find it yet, so the app asks on a later sync instead.
- **Limits:** a Send Later message waits in the shared queue, and the app schedules its own wake-up for it only the next time it runs.
- **Kept as it is written (owner's ask, 2026-11-20):** `DraftKeeper` (MailCore) puts each autosaved version in the shared queue as the app's composer does: a draft save due after the usual wait, or at once when the sheet leaves the screen. So a sheet the other app or iOS closes, or a crash, leaves the message in Drafts the next time the app runs. Writes go one at a time under `performExpiringActivity`, and a version asked for during a write replaces any still waiting, since each carries the draft's files. Delete Draft takes the save back and queues the copy's removal only when the app saved one. A swipe down saves it as a draft. Send and Save Draft from the sheet first wait for those writes, then take the waiting save back, since the private queue carries the message from there; if the message can't be kept at all, the save is put back and the composer keeps it again. The app may be saving that very version at the moment it's taken back, as a save stays queued while it goes: its copy is then replaced or removed by the sheet's own save or send if the app recorded it in time, and otherwise stays in Drafts.
- **Why not a background upload:** the extension is gone once its sheet closes, and its background session's outcome would reach the app under another session identifier, which can't be held by both processes at once. A share is small, and the sheet stays up only for the second or two it takes.
- **Shared code:** `MailClients` builds each account's client from the shared Keychain, the same way for the app, the notification extension and the Share extension.

## ADR-031: Drops go into the message being written, or start one

- **Decision (owner's ask, 2026-11-20):** links, text, pictures and files dragged in from another app go where Mail would put them. With a message being written, they go into it: dropped on its text, words land at the drop's caret; dropped anywhere else on the composer or the window, at the writer's caret. With none, the drop starts a new message from the account on screen, its words above the signature and its files attached. In a conversation read as a chat, the drop goes into the chat's reply field, as in Messages. Files are always attached (the composer has no inline images) while they fit under `ComposeViewModel.attachmentLimit`; past it, the File Too Large alert says so.
- **One reader:** `SharedItems` (MailUI) reads a drop exactly as the Share extension reads a share, so both decide the same way what is a link, text, or a file. `ContentIntake` is the one way in for a place that writes a message: the composer, the chat bar, and the window's root (`DraftShelfViewController`), which takes what nothing above it took.
- **Text views:** a drop on a text view goes through its paste, so the text view keeps its own drop caret and undo. `ContentIntake` widens its paste configuration to files and, as its paste delegate, lets words through and holds files back to attach. So pasting a copied file or picture attaches it too, instead of putting an image in the text that the message can't send.
- **Our own drags:** a thread's row (to open a window) and a recipient's token carry a local object, and the drop interactions ignore those items, so a row dropped on the window never starts a message. A text view's paste can't see the drag item, so a recipient dropped on the message's text writes their address there, as dropping any text does.
- **Words keep apart:** dropped words get a space where they would otherwise run into a word beside the caret (`DroppedWords`).
- **Leaving:** a composer that closes or minimizes, and a chat that's left, cancel what they are still reading (`ContentIntake.cancel()`), and the file copy stops with it.

## ADR-032: The Mac app is the iOS app, built with Mac Catalyst

- **Decision (owner's approval, 2026-11-20):** the Mac app is the iOS app built with Mac Catalyst in the Mac idiom ("Optimize for Mac"), as a second destination of the `Goodmail` target and under the same bundle ID, `com.idanbirman.goodmail`. This amends ADR-004: UIKit stays the way every core surface is built, and now it runs on the Mac too. No code is forked and no second app target exists.
- **Same bundle ID:** the Mac app keeps the iOS app's App ID, so push topics, App Attest, the OAuth redirects, the Keychain group and the App Group are the ones the relay and the providers already know.
- **Interaction style:** whether a window is driven by touch or by a pointer and a keyboard is one value, `InteractionStyle` with the cases `.touch` and `.desktop`. It is a custom `UITrait`, set once per window by the scene coordinator: Mac windows get `.desktop`, everything else gets `.touch`, an iPad with a keyboard included. Screens read the trait and never ask which device they run on. Layout still comes from size classes and widths, never from an idiom check.
- **Compile-time checks only where an API is missing:** `#if targetEnvironment(macCatalyst)` appears where Catalyst lacks an API, each with a one-line reason. Today that is the system Format panel in the composer, VisionKit's code scanner (the Mac can show a transfer code but can't scan one, and the receive screen already has that state),. Differences in behavior are run-time values, such as the interaction style.
- **Checked on every push:** the packages the app links declare Mac Catalyst, and a Linux cloud session and CI compile them, and type-check the app and its extensions, for `arm64-apple-ios27.2-macabi` as well as for iOS (`scripts/ios-build`, docs/setup/cloud-builds.md). A change that breaks the Mac build fails the check, with no Mac at hand. Only the Mac's build links, signs and runs it.
- **Rejected:** a separate AppKit app, which would build every screen twice, and a SwiftUI rewrite, which ADR-004 already rules out.
- **Mac-only settings (Phase 3):** `DesktopSettings` (MailUI) holds the Settings rows only a Mac has, and exists only in a Catalyst build (`DesktopSettings.forThisDevice()`, behind `#if targetEnvironment(macCatalyst)` because `SMAppService` is unavailable on iOS). Open at Login is `SMAppService.mainApp`: the toggle follows the system's status through `OpenAtLogin` (MailCore, pure and tested), which is read again after every change and whenever the app becomes active, since the reader can change it in System Settings. Waiting for approval shows as on, with a button to Login Items. "Double-Click Opens a Window" and the Delete key (Move to Trash or Archive, `DeleteKeyAction`) are `DesktopPreferences`. All three are this Mac's own and aren't in `Preferences.syncedSettings` (ADR-024). Delete in Trash is always for good. The sandboxed Mac app needs no entitlement for `SMAppService.mainApp`.
- **Audit of the system features on Catalyst (by reading the code and the Catalyst SDK interfaces, no Mac at hand):**
  - Dock badge: `AppBadge` and the notification extension use `UNUserNotificationCenter.setBadgeCount`, which Catalyst has. Nothing iOS-only. The Mac asks the reader for Badge in System Settings > Notifications, as iOS does.
  - Spotlight: `SpotlightIndexer` uses `CSSearchableIndex.indexAppEntities` with `IndexedEntity`, and `OpenThreadIntent` opens a result through `IntentRoutes` into the frontmost mail window. No Catalyst restriction in the SDK interfaces.
  - App Intents, Shortcuts and the Focus filter: the `AppEntity`/`AppIntent(schema:)` macros are iOS 18 and macOS 15, `SetFocusFilterIntent` is iOS 16 and macOS 13, and nothing in use is marked unavailable for Catalyst (only `PushToTalkTransmissionIntent` is). `MailIntents` lists `.macCatalyst("27.2")`, and the app's uses stay behind `#if canImport(MailIntents)`.
  - Widgets: WidgetKit's Catalyst exclusions are Live Activities and the Dynamic Island, which Goodmail doesn't use. `ControlWidget` is available on Catalyst (iOS 18, macOS 26).
  - Share extension, notification extension and Widgets are targets with `SUPPORTS_MACCATALYST` and their own sandboxed Mac entitlements, with the app group and Keychain group the app has.
  - Handoff: the window, compose and Settings activity types are in `NSUserActivityTypes`, and `scene(_:continue:)` lays a handed-off window out for the Mac (`InteractionStyle.laying(out:)`). The reading activity is for Siri and isn't handed off, so it needs no entry.
  - Alerts: the actions are `UNNotificationAction`s answered by `AlertResponder`, whose delegate calls come on the system's queue and hop to the main actor, as on iOS.
- **Needs a real Mac:** the Open at Login toggle against a signed build (status after register, the approval button, removing it in System Settings and coming back); that a Delete key press archives when chosen; that a Spotlight result or a Shortcut's Open Conversation brings a window up when every window is closed and the app is still running (`IntentRoutes` keeps the route for the first window that connects, and nothing here asks for a window itself); a Focus filter set in System Settings reaching the app; the Share menu sheet and its send; widgets in Notification Center and on the desktop; alert actions from a banner; Handoff between an iPhone and the Mac; and the Turn On in Settings link of Badge App Icon, which opens `UIApplication.openNotificationSettingsURLString`.

## ADR-033: Presence says what the app does when the reader looks away

- **Decision (owner, 2026-11-20, for the Mac app):** one value, `AppPresence` (MailCore), says whether anyone is looking at the app and whether the system may stop it. `PresenceTracker` in the app target holds it, is the only code that observes UIKit's lifecycle notifications, and makes every change through the pure `AppPresence.after(_:policy:)`. Sync, the change watches, the database suspension, background refresh and push follow the tracker and never read the lifecycle themselves.
- **States:** `attended` (a window has the reader's attention); `covered` (iOS: Control Center, a call or the app switcher passed over an attended app, and everything goes on); `arriving` (iOS: in the foreground, not active yet, at launch or on the way back); `unattended` (Mac: running with no one looking, behind other apps or with no window open); `suspendable` (iOS: in the background, where the system may freeze the process). The architecture sketch had a `leaving` state for the few seconds after the app leaves the foreground. Those seconds are one more piece of database work holding a background task in `BackgroundDatabaseWork`, so presence doesn't need a state for them.
- **Policy:** `PresencePolicy` is chosen once per process. `.suspends` on iPhone and iPad; `.keepsRunning` when `isMacCatalystApp`, which covers the Catalyst build and the iPad app on a Mac. Under `.keepsRunning`, resigning active or entering the background makes the app `unattended`, and it is never `suspendable`.
- **What follows from it:**

| | attended, covered | arriving | unattended (Mac) | suspendable (iOS) |
|---|---|---|---|---|
| Sync rounds | every 30 s, at once on becoming attended | none | every 5 min | cancelled; background app refresh asked for |
| Change watches (IMAP IDLE) | held | none | held | stopped |
| Database | open | open | open | suspended after the leaving time, unless work holds it |
| Inbox marked seen | after each round | | no | |
| Settings sharing | every round | | every round | one pass on leaving |
| Prefetch | by network allowance | | by network allowance | cancelled |
| Placeholder alerts, push subscriptions, badge | refreshed on becoming attended | | | |

- **iOS stays as it was:** every `didBecomeActive` becomes `attended` and every `didEnterBackground` becomes `suspendable`, so each consumer does what its own notification observer did before. The one difference: if the database finishes opening while something covers the app, sync starts then instead of waiting for the cover to go.
- **Mac only:** background refresh isn't registered, since nothing launches a Mac app in the background. Sync measures its waits on the continuous clock, which counts time asleep: a wait that took more than twice as long as asked, and over a minute longer (`Oversleep`), means the Mac slept, so the watches open afresh and the next round runs at once. When the network allows more than it did, as when it comes back after waking, the watches open afresh and a round runs at once. A watch that ended by itself (a server that can't IDLE, a refused password) tries again after a minute, then less often, up to once an hour (`WatchRestarts`); on iOS it waits for the next foreground as before.
- **Why:** on a Mac the process keeps running with every window closed. Keyed to "entered background", the iOS code would have suspended the database while Goodmail sat in the Dock, so writes failed, and stopped IDLE and sync. Four observers each decided what "background" meant; now one place does.
- **Limits:** App Nap may slow the 5-minute rounds while the app is unattended. Alerts still come from the push relay through the notification extension, and becoming attended syncs at once. If lists go stale in practice, the fix is one `ProcessInfo.beginActivity` held while watches are open. Snooze wake-ups and scheduled sends, which lean on background refresh on iOS, happen in the Mac's rounds while the app runs.
- **Rejected:** checking for the Mac in each consumer, which spreads one decision over four files; and keeping iOS's three lifecycle notifications as the model, with booleans for the Mac's extra cases.

## ADR-034: One command table for the menu bar, the keyboard and the toolbar

- **Decision (owner's plan for the Mac app, 2026-11-20):** every command the reader can name is a case of `MailCommand` (MailCore). Each case says which section of the menu bar lists it (`MenuPlace`), which keys reach it (`CommandKeys`) and whether the toolbar may show it. The 16 keyboard shortcuts iPad had are among them with the same keys. The menu bar (`MailMenus`) and the key commands are both built from the table, and both perform through the window's `performCommand(_:)`, so they can't disagree. The customizable toolbar and a row's context menu read the same table when they come.
- **Screens answer one question:** `answer(to:) -> CommandAnswer` (`CommandScreen`). `.notHere` passes the command to the next screen and then the window. `.unavailable` dims it and stops there, as Move to Trash in Trash. `.ready(perform:title:isOn:)` enables it, and the window's `validate(_:)` gives the menu item the title and check mark the screen sends, as "Mark as Read" for an unread thread or a check on the Inbox category on show. With several threads picked, the list answers for all of them with what their context menu offers (`ThreadMenu(several:)`), counted where Mail counts, as "Archive 3 Conversations". `CommandRouting` asks a presented screen alone, else the shown screens front to back: the thread, its list, the mailboxes.
- **Keys as plain values:** `KeyChord` holds the keys without UIKit, so the table and its clash test live in MailCore and run on Linux. `MailCommandTests` fails when two commands share keys, or a command of its own takes keys a system menu holds (`KeyChord.heldBySystemMenus`). UIKit drops a whole menu without an error on such a clash, which cost time during the iPad work.
- **Keys a system item holds:** Mail's Search Mail keys (⌥⌘F) belong to Edit > Find and Replace, and Print's (⌘P) to File > Print. Such a command says `.system(item)`. Where the menu bar has the item, the window answers the item's action (`findAndReplace(_:)`, `printContent(_:)`) with the command; New Window and Close are left to the system entirely. Where it has no such item, as on iPhone, the command takes the keys as its own.
- **What's left to the system:** Bold, Italic, Underline, Bigger, Smaller, alignment and writing direction in the composer are the Format menu's own items, which the text view answers. Show Sidebar (⌃⌘S) is the split view's own.
- **Not yet:** smart mailboxes, Apply Rules and Block Sender arrive with P3 and P4. Erase Spam waits for a Delete Forever that works outside Trash. Save Draft without closing, text colors and the snooze times as a submenu need work in the composer and the menu builder first.
- **The reader on a desktop (2026-11-20):** Find in Conversation, Find Next and Find Previous ride on the system's Find items (⌘F, ⌘G, ⇧⌘G) and Zoom In and Zoom Out on Format > Font's Bigger and Smaller (⌘+, ⌘−), so no command of ours repeats keys a system menu holds. Actual Size (⌘0) and Quick Look Attachment (⌘Y) have keys of their own. Search Mail stays on ⌥⌘F. A thread answers them while it shows letters; the chat layout leaves them dimmed. The window answers the system items' actions (`find(_:)`, `findNext(_:)`, `findPrevious(_:)`, `increaseSize(_:)`, `decreaseSize(_:)`). Without a menu bar they are plain key commands, so an iPhone or iPad keyboard finds and zooms too.
- **The list filter and the number keys (2026-11-21):** `ListFilter` (MailCore) is `.off(last:)` or `.on(choices)`, with Unread, Starred and With Attachments all having to hold, and builds a `MailCondition` the list asks of each conversation's `MailFacts`. It lives in `WindowState.filter` and, like the Inbox category, stays when the window moves to another mailbox, is saved with the window and goes with a handoff. The button in the list's top bar toggles it and a long press opens the choices; the View menu has Turn Filter On or Off (⌘L, Mail's) and Filter by. While it is on the button is filled and the title area names the choices. When it hides every conversation the mailbox has, the list says "No Unread Mail" and the like, with Turn Off Filter, and Inbox Zero stays away. A filter never fetches more mail: it shows what the list has loaded. With Attachments can only know a conversation whose messages were downloaded (`MailDatabase.threadsHoldingAttachments`, followed only while that choice is on), so a conversation never opened doesn't show under it. A listed conversation's unread marker now reaches `MailFacts` (providers keep it out of the thread's labels), which also fixes the Unread flag of Shortcuts' Find on listed threads.
- **Rows by number:** ⌘1 to ⌘9 open the first nine rows of the sidebar and ⌃⌘1 to ⌃⌘9 move the picked conversations to them (`RowShortcut`, `NumberedRows`). The rows are the ones on show, in order: a label folded away has no number, and a folder that only holds labels takes none, since it opens nothing. The model owns what is folded (`MailboxesViewModel.folded`), so the numbering needs no view. Both go in the Mailbox menu's Go To and Move To submenus, titled with the row's name, or "Inbox (me@example.com)" among several accounts. Move To counts the rows as Go To does and asks `MailDrop`, so a row that refuses the drop, or no pick, dims its item with the row's name, and a number past the last row hides it (`CommandAnswer.notHere`). The list and the mailboxes answer, so iPhone and iPad keyboards reach them where the menu bar isn't. ⌘0 stays Actual Size.
- **Rejected:** keeping an optional closure per screen, which can't dim an item or rename it; one table of keys per menu, which would let two menus take the same keys.

## ADR-035: On the Mac, new messages, Settings and opened conversations get windows of their own

- **Decision (owner's plan for the Mac app, 2026-11-20):** a `Route` still names where to go (ADR-011). What differs by interaction style (ADR-032) is only how the scene coordinator presents three of them, and `InteractionStyle+Windows` (MailUI) decides it: `composePlacement` (`.sheet` or `.ownWindow`), `settingsPlacement` (`.cover` or `.ownWindow`) and `threadWindowLayout` (`.viewer` or `.message`). Touch windows answer as before, so iPhone and iPad behave as they did.
- **New messages:** in a desktop window every `.compose` route, so every new message, reply, forward, `mailto:` link and intent, opens a `ComposeWindowCoordinator` window, titled with the subject or New Message. Closing it saves the message to Drafts the way closing a share sheet's composer does (`dismissKeepingDraft`) and keeps nothing for the drafts pill, which stays empty on the Mac. A viewer claims no minimized messages there: a compose window reads its own message back when the system restores it, and autosave has it in Drafts. Send hands the message to the front viewer window's `MailActions`, so the Undo Send toast shows there, and an Undo opens the message in a new window again. With no viewer open, the compose window keeps the message: it stays after Send and shows `UndoCountdown`, what was done with the time left and Undo, until the Undo Send wait is over (`MailActions.waitOutUndo`), then closes. Undo brings the message back into that same window. A drop of files or text on a viewer starts its message in a compose window too, and what was dropped goes in once the composer shows there.
- **Settings:** `SettingsWindowCoordinator` holds the one Settings window (`SettingsWindow` activity). ⌘, or the Goodmail menu brings it forward when it is open. `SettingsWindowState` (MailCore) says whether it is closed, asked of the system and not connected yet, or open, so asking twice before the window connects opens one window, and a second Settings window the system restores gives way to the first. Settings asked for at a page, as Swipe Actions from a swipe button held down, opens the window at that page, or shows the page in the window already open (`SettingsPages`). It shows the same `SettingsView` without its Close button, and sign-ins and transfer codes show over it (`AccountSignIn`, `TransferScreens`). When it closes, every mail window follows what changed, as one does when the Settings sheet closes.
- **Message windows:** `WindowState.layout` is `.viewer` or `.message` and is saved with the window; a state saved before it reads as a viewer. A message window always has its thread open: closing the thread, or reading a state without one, makes it a viewer. Open in New Window, Return and a double-click open `.message` on the Mac: the reader alone, titled with the subject. An action that leaves the thread, such as Archive or Trash, closes the window once it can't be undone: the window shows `UndoCountdown` in the thread's place for as long as the action's toast would, Undo brings the thread back in the window, and an action with nothing to undo closes it at once. Keeping the window was chosen over handing the undo to a viewer window: the action may not have applied yet when the thread leaves, so its undo doesn't exist to hand over, a message window may have no viewer beside it, and the undo stays in the window where the reader acted, with its ⌘Z. A touch window lays out every state as a viewer, so a message window handed off to an iPhone opens the viewer with its thread.
- **Not yet:** a message window shows no toast for Move, which leaves its thread open there, though ⌘Z undoes it. Undo Send handed to a viewer goes with that viewer if it closes during the wait.

## ADR-036: Mail is dragged by conversation, and each window decides what the drag carries

- **Decision (owner's plan for the Mac app, 2026-11-20):** a drag out of the list carries the conversation, or the whole pointer selection when the row is in it. Every item holds a `DraggedThread` (the conversation and the mailbox it left) for drops inside the app. What else it holds is decided in one place, `ConversationCarry`, from the window's `InteractionStyle`: touch carries the new window's activity, as before; a desktop window carries one `.eml` file for each message, named by its subject as Share names them, made only when a drop asks (`MailProvider.source(of:)` through `ConversationSources`, off the main actor). A new window on the Mac comes from a double-click.
- **Drop rules:** `MailDrop` (MailCore, tested on Linux) decides what a row does with a drop, so the sidebar can highlight or refuse and the drop can carry it out. Archive, Trash and Spam do what their commands do, except from Spam or Trash, where the move takes the conversation out of both. A folder or label moves there. Holding option adds the label and leaves the mail where it was, on accounts that keep several labels (`MailService.keepsMailUnderSeveralLabels`, Gmail). Starred, Sent, Drafts, smart mailboxes, the rows that blend accounts and another account's rows refuse. Every drop goes through `MailActions`, so it has the undo toast.
- **iPad:** the sidebar takes drops from touch drags too.
- **Compose windows:** a desktop drag's files attach there like files from Finder (`ContentIntake`).
- **Attachments:** in a desktop window an attachment's capsule drags out as its file (`AttachmentDrag`).

## ADR-037: Pins, snoozes and device mutes follow the reader between devices

- **Decision (owner's plan for the Mac app, Phase 3, 2026-11-21):** pins, snoozes and the mutes kept on the device for Outlook, iCloud and IMAP (`MailService.mutesOnDevice`) sync between the reader's devices as three `SettingsSync` groups (`MailDatabase.syncedMailState`: `pins`, `snoozes`, `deviceMutes`). They merge as settings do (ADR-024): each element on its own, the newest change wins, a ledger tells this device's edits from the others', and removals stay as dated entries. Each thread is one element, named `account/thread` (`ThreadSummary.ID.syncedElement`) by IDs that are the same on every device, and a device leaves alone the threads of accounts it doesn't have (`LocalSettings.Scope.threads(of:)`). A pin or a mute shares only that it exists. A snooze shares `SharedSnooze`: asleep until a time, or woken at one. Unpin, unmute, unsnooze and a snooze that ended are removals.
- **Transport:** iCloud Keychain, through a second `SettingsSync` with a ledger of its own (`SettingsSync/mail-state-ledger.json`) and items under the service `com.idanbirman.goodmail.mailstate`, so a pass can run right where a wake needs it without a settings pass around it. It is already in use and needs nothing new. The key-value store and CloudKit both need the iCloud capability that Xcode couldn't add without signing in again (ADR-024), and the key-value store holds 1 MB in all. Gmail labels could carry pins and snoozes for Gmail alone, would show up in Gmail on the web, and can't hold a wake time. Outlook and iCloud have no mute to carry them.
- **Size:** Apple publishes no size limit for a Keychain item, and iCloud Keychain is made for small ones, so each record is kept small. A thread costs about 150 bytes. Pins and mutes remember removals for 180 days, like settings; snoozes for 30 (`SettingsFamily.removalMemory`), since every snooze ends as a removal a day after it wakes. A reader with 50 pins, 500 mutes and 10 snoozes a day carries records of about 8, 75 and 50 KB. If one outgrows that, the next step is a record per account.
- **When it runs:** in `AppModel.syncAll`, before snoozed threads are woken and again as soon as this device woke one; before the account sync that the relay's quiet push asks for (ADR-029), so a mute's archive or a wake made elsewhere brings its state to an iPhone whose app is suspended; and as the app leaves the foreground. Taking up a change writes the database alone (`setPins`, `takeUpSnoozes`, `takeUpMutes`) and queues nothing, because the device that made the change queued what the service has to hear.
- **Snooze return:** the device that snoozes a thread keeps it (`SnoozeKeeper.thisDevice`). A device that takes the snooze up keeps it as `otherDevice`; that isn't shared, since it follows from where the snooze came from. The keeper schedules the alarm and wakes the thread at its time, as before. Every other device stays silent and wakes the thread only once `SnoozeKeeper.fallbackDelay` (15 minutes) has passed with the thread still asleep in its copy, which covers a keeper that's asleep, off or suspended. The wake is the woken state, shared like any change: a device that takes it up marks the thread woken and queues nothing. Snoozing the thread again on another device makes that device the keeper. A thread taken up asleep leaves that device's Inbox at once, on the device alone, so that `pruneSnoozes` doesn't take it for a thread put back in the Inbox some other way before the device's own sync hears of the archive.
- **Once, not twice:** one device queues the move back (Inbox and unread) in the usual case. Two devices both queue it only when each woke the thread before the other's wake reached it: the keeper was 15 minutes late and hadn't shared yet, or iCloud Keychain hadn't delivered. Both queue the same labels, so the outcome is that of one wake. A reply to a muted thread may be archived by every device that has the mute, and archiving twice changes nothing (ADR-008).
- **Alerts:** only the keeper's alarm goes off (`SnoozeAlarm.changes` schedules only for `SnoozeKeeper.alerts`). A fallback wake is silent and shows the thread at the top of the Inbox, as any woken thread. The services send no new-mail alert for it, since it brings no new message.
- **Limits:** an iPhone whose app hasn't run since the snooze ended elsewhere still holds the alarm and alerts at the old time; the quiet push for the move back usually runs the app first. When the keeper is off at the time, no device alerts. The notification extension takes up nothing, so a reply to a thread muted on the Mac alerts on an iPhone whose app hasn't run since the mute. A device away for longer than a removal is remembered may share a pin, a mute or a snooze again. IMAP threads are named from their headers, which gives every device the same name in the usual case; where it doesn't, the state just doesn't show on the other device. The elements of an account that no device has any more stay in the record.
- **Rejected:** an elected device by device ID, which needs a registry of devices and strands a thread whose keeper sleeps; every device waking the thread at its time and alerting, which marks a thread unread again after it was read on another device and rings on every device; one record for all three, which grows fastest where it has to stay smallest; and the key-value store, CloudKit and Gmail labels, for the reasons above.
