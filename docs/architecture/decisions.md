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
- **Kept on the device:** how the device answered shared-account offers and whether it shares accounts (each device decides those for itself), recent searches (history, not a choice), the Focus filter (iOS sets it per device), and bookkeeping such as push subscriptions, how far mail has alerted or been through the rules, and minimized drafts. Gmail signatures sync through Gmail itself. Pins, device-side mutes and snoozes are mail state rather than settings and stay local for now.
- **Why not the iCloud key-value store:** it is the usual home for preferences and tells the app at once when another device changes something, but it needs the iCloud capability on the App ID, which Xcode couldn't add without signing in again. iCloud Keychain needs nothing new and already carries the accounts. Passes run at launch, every foreground sync round (30 seconds), when Settings closes and when the app leaves the foreground. `SettingsSync` takes any `SecretStore`, so moving to the key-value store later only changes where the app points it.

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
- **Bosses:** what the world sends at the plane is one `Encounter` value: ordinary waves, the field clearing, or a boss. `PlaneGameWorld.stepEncounter(by:)` is the only place it moves from one case to the next, and a boss's own status (arriving, fighting, falling) changes only through `PlaneGameBoss`. Ordinary arrivals come only during waves, so nothing else needs to know a boss is on.

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
