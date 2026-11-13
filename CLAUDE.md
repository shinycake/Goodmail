# Goodmail

A native iOS email client. Read [README.md](README.md) for the build and the gate, [docs/product-brief.md](docs/product-brief.md) for product decisions, [docs/architecture/decisions.md](docs/architecture/decisions.md) for architecture, and [docs/plan/v1-plan.md](docs/plan/v1-plan.md) for what's next.

## Rules every change follows

- **No implicit state machines.** Model state explicitly, usually as an `enum` with associated values and one place that makes transitions. Never spread a state across booleans, optionals and flags whose valid combinations are implied. The review blocks on this.
- **No file over 1000 lines** (ADR-014). `scripts/check` fails above 1000 and warns above 800. Split by responsibility.
- **Thermo-nuclear code quality.** Every PR is held to [docs/review.md](docs/review.md). Look for the restructuring that deletes complexity before you write code that adds it.
- No third-party dependency without the owner's approval. GRDB is the only one.
- Logic is developed test-first with Swift Testing.
- Run `swift format format -i -r Packages Goodmail` before committing, and `scripts/check` before pushing (the pre-push hook does it). In a Linux cloud session, `scripts/check` compiles the packages and tests for iOS but can't run them ([docs/setup/cloud-builds.md](docs/setup/cloud-builds.md)).

## How work lands (ADR-016)

The process is autonomous. Nobody needs to approve routine work.

1. Work on a short-lived branch, one vertical slice per PR. Pass `scripts/check` locally.
2. Open a ready (not draft) PR with evidence: the `scripts/check` output, plus simulator screenshots or recordings for UI changes.
3. `.github/workflows/review.yml` runs lint and a Claude review against [docs/review.md](docs/review.md). Its comments land on the PR.
4. If the review approves and lint is green, the workflow squash-merges the reviewed commit and deletes the branch.
5. If the review requests changes, fix them and push. Every push is reviewed again from scratch. If you believe a finding is wrong, justify the trade-off in the PR description before pushing the fix for the rest.

Don't merge PRs by hand to get around the gate. Exceptions:

- A PR labeled `hold` is reviewed but not merged.
- A PR that changes `.github/` is reviewed but the owner merges it, because it changes the gate itself.
- Draft PRs aren't reviewed until they are marked ready.
