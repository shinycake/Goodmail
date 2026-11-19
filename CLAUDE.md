# Goodmail

A native iOS email client. Read [README.md](README.md) for the build and the gate, [docs/product-brief.md](docs/product-brief.md) for product decisions, [docs/architecture/decisions.md](docs/architecture/decisions.md) for architecture, and [docs/plan/v1-plan.md](docs/plan/v1-plan.md) for what's next.

## Rules every change follows

- **No implicit state machines.** Model state explicitly, usually as an `enum` with associated values and one place that makes transitions. Never spread a state across booleans, optionals and flags whose valid combinations are implied. The review blocks on this.
- **No file over 1000 lines** (ADR-014). `scripts/check` fails above 1000 and warns above 800. Split by responsibility.
- **Thermo-nuclear code quality.** Every change is held to [docs/review.md](docs/review.md). Look for the restructuring that deletes complexity before you write code that adds it.
- **Swift Concurrency done right.** Every piece of state and work has a deliberate isolation: UI state on `@MainActor`, shared mutable state behind an `actor`, everything else `Sendable` values. Network, database and sync work never runs on the main actor. No `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` or `Task.detached` without a written safety invariant; no fire-and-forget `Task` whose result, errors and cancellation nobody owns. The app targets default to `MainActor` isolation, so a callback the system invokes on its own queue (BGTaskScheduler, notification delegates, `NWPathMonitor`) must be `nonisolated` or `@Sendable` and hop explicitly.
- **Use the vendored skills** in [.claude/skills](.claude/skills/README.md): load `swift-concurrency` before touching tasks, actors, `Sendable` or isolation, `swiftui-expert-skill` before writing SwiftUI, and `swift-testing-expert` before writing tests. The review holds code to them.
- **Clean up the Mac after yourself** ([docs/setup/mac-disk.md](docs/setup/mac-disk.md)). Get simulators only from `scripts/sim <purpose>`, never `xcrun simctl create`. Keep build output under `scripts/build-paths`' `BUILD_ROOT` on the external drive, never in Xcode's default DerivedData. When a task ends, run `scripts/cleanup --done` in its worktree before removing the worktree; it shuts down and deletes the simulators named for that worktree and deletes its build folder. `scripts/check` sweeps up what's left every six hours.
- No third-party dependency without the owner's approval. GRDB is the only one.
- Logic is developed test-first with Swift Testing.
- Run `swift format format -i -r Packages Goodmail` before committing, and `scripts/check` before pushing (the pre-push hook does it). In a Linux cloud session, `scripts/check` sets up the toolchain if it's missing (run `scripts/check --lint` once before your first commit when the session started outside this repository, so the git hooks are on), compiles everything for iOS and runs the MailCore, GmailProvider, IMAPProvider, OutlookProvider, MailStore and PlaneGame tests natively ([docs/setup/cloud-builds.md](docs/setup/cloud-builds.md)).

## How work lands (ADR-028)

There are no pull requests (owner, 2026-11-18). Nobody needs to approve routine work.

1. Work on a short-lived branch, one complete vertical slice at a time.
   - New code goes in new files. Don't grow a central file every feature touches (coordinators, registries, shared string tables): give each feature its own file or table.
2. Before landing, review the whole diff against [docs/review.md](docs/review.md): correctness, concurrency and the rules above. Make it deep, with subagents for a big change. Fix everything it finds.
3. Squash the slice into one commit whose subject is written for people (run it through the humanizer): `scripts/public-beta` puts commit subjects in TestFlight's What to Test notes. Run `swift format`, rebase onto the latest main, pass `scripts/check`, and `git push origin HEAD:main`. Main only fast-forwards and is never force-pushed. The pre-push hook runs `scripts/check` on what you push.
   - Show evidence in the thread: the `scripts/check` result, plus simulator screenshots or recordings for UI changes.
4. GitHub runs nothing on its own. `.github/workflows/check.yml` runs the Linux `scripts/check` when started by hand (`gh workflow run check.yml`).
