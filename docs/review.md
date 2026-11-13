# Review standard

Every pull request is reviewed against this standard before it merges, by the Claude review in `.github/workflows/review.yml` and by any session reviewing locally with `/pstack:thermo-nuclear-code-quality-review`. The bar is thermo-nuclear: working code is not enough. The review approves only when the change leaves the codebase as simple as it could reasonably be.

## Hard blockers

Any one of these means "changes requested".

1. **An implicit state machine.** State that is spread across several booleans, optionals, flags or counters whose valid combinations live only in the author's head. Typical signs: `isLoading` next to `error` next to `result`; an optional that is only meaningful while a flag is set; transitions made by assigning several properties in different places; `if a && !b` checks that guess which state we are in. The fix is an explicit model: an `enum` whose cases are the states, carrying the data valid in each state as associated values, with transitions in one place. Invalid states must be unrepresentable.
2. **A file over 1000 lines** (ADR-014), counting fixtures as exempt. Splitting by responsibility is the fix; squeezing lines is not.
3. **A correctness bug** the reviewer can name with a concrete scenario: wrong output, a crash, a race, data loss, a mail action that isn't idempotent or skips `MailCommands` and the outbox.
4. **A broken architectural rule** from `docs/architecture/decisions.md`: GRDB imported outside `MailStore`, navigation outside `Route`, a new third-party dependency without the owner's approval, logic in a thin app target that belongs in a package.
5. **A Swift Concurrency violation** of the vendored `swift-concurrency` skill (`.claude/skills/swift-concurrency/SKILL.md`; read it, and the reference it routes to, whenever the diff touches tasks, actors, `Sendable`, `@MainActor`, `nonisolated` or callbacks). Blocking cases: network, database or sync work that runs on the main actor; a `@MainActor` (or app-default-isolated) function handed to an API that calls it on another queue; `@unchecked Sendable`, `nonisolated(unsafe)`, `@preconcurrency` or `Task.detached` without a stated safety invariant; a `Task { }` nobody owns, whose errors are swallowed or that outlives its owner without cancellation; long-running loops that ignore cancellation; locks, semaphores or `DispatchQueue` used to guard state an `actor` or `Mutex` should own; `@MainActor` added as a blanket fix to silence a diagnostic.
6. **Logic without tests.** New logic in a package needs Swift Testing coverage of its observable behavior.
7. **A code-quality blocker** from the list below, unless the PR description justifies it convincingly.

## Code-quality blockers

Look for the "code judo" move: a restructuring that keeps the behavior and makes whole branches, flags, helpers or layers disappear. When one is visible and the PR doesn't take it, that is a finding.

- **Spaghetti growth.** New ad-hoc conditionals or special cases bolted onto an unrelated flow. Push the logic into its own type, policy or module instead.
- **Incidental complexity kept.** The PR preserves complexity that a plausible reframing would delete, or moves complexity around without reducing the number of concepts a reader holds.
- **Hollow abstraction.** Thin wrappers, identity layers or pass-through helpers that add indirection without clarity, and "magic" generic mechanisms that hide a simple data shape.
- **Muddy contracts.** Unneeded optionals, force casts, `Any`, or silent fallbacks that paper over an unclear invariant. Make the boundary explicit with a type.
- **Wrong layer or duplicate helper.** Feature logic leaking into shared code, or a bespoke helper where the codebase already has the canonical one.
- **Needless sequencing or half-applied updates.** Independent async work serialized for no reason, or related updates that can leave state half-applied when an atomic structure is obvious.

## Skills the review applies

Besides this standard, hold SwiftUI code to `.claude/skills/swiftui-expert-skill/SKILL.md` and tests to `.claude/skills/swift-testing-expert/SKILL.md`. A departure from them is a finding when it causes a concrete problem (wrong state ownership, needless view invalidation, a flaky or unclear test); cite the skill's section.

## What the review writes

- One inline comment per blocking finding, on the line it is about, in prose: the problem, the evidence, and the remedy.
- Few, high-conviction comments. No cosmetic nits when structural problems exist; formatting is `swift format`'s job.
- A summary comment that starts with the verdict.
- Tone: direct and demanding, never rude. If the change makes the code messier, say so plainly.
