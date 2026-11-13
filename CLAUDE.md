# Goodmail

A native iOS email client. Read [README.md](README.md) for the build and the gate, [docs/product-brief.md](docs/product-brief.md) for product decisions, [docs/architecture/decisions.md](docs/architecture/decisions.md) for architecture, and [docs/plan/v1-plan.md](docs/plan/v1-plan.md) for what's next.

## Rules every change follows

- **No implicit state machines.** Model state explicitly, usually as an `enum` with associated values and one place that makes transitions. Never spread a state across booleans, optionals and flags whose valid combinations are implied. The review blocks on this.
- **No file over 1000 lines** (ADR-014). `scripts/check` fails above 1000 and warns above 800. Split by responsibility.
- **Thermo-nuclear code quality.** Every PR is held to [docs/review.md](docs/review.md). Look for the restructuring that deletes complexity before you write code that adds it.
- No third-party dependency without the owner's approval. GRDB is the only one.
- Logic is developed test-first with Swift Testing.
- Run `swift format format -i -r Packages Goodmail` before committing, and `scripts/check` before pushing (the pre-push hook does it). In a Linux cloud session, `scripts/check` sets up the toolchain if it's missing (run `scripts/check --lint` once before your first commit when the session started outside this repository, so the git hooks are on), compiles everything for iOS and runs the MailCore, GmailProvider, ICloudProvider, OutlookProvider and MailStore tests natively ([docs/setup/cloud-builds.md](docs/setup/cloud-builds.md)).

## How work lands (ADR-016)

The process is autonomous. Nobody needs to approve routine work.

1. Work on a short-lived branch, one vertical slice per PR. Pass `scripts/check` locally.
2. Open a ready (not draft) PR with evidence: the `scripts/check` output, plus simulator screenshots or recordings for UI changes.
3. `.github/workflows/review.yml` runs the Linux `scripts/check` on the PR merged with main, and a Claude review against [docs/review.md](docs/review.md). Its comments land on the PR.
4. If the review approves and the check is green, the workflow squash-merges the reviewed commit and deletes the branch. If main moved after the check, the merge job checks the PR merged with the new main itself before merging, so there's nothing to push. Merge main in yourself only when the workflow says the PR conflicts with main or fails on it. A push that only takes in main keeps the approval, because the review is keyed on the PR's own changes.
5. If the review requests changes, fix them and push. Every push that changes the PR's own diff is reviewed again from scratch. If you believe a finding is wrong, justify the trade-off in the PR description before pushing the fix for the rest.

Don't merge PRs by hand to get around the gate. Exceptions:

- A PR labeled `hold` is reviewed but not merged.
- A PR that changes `.github/` is reviewed but the owner merges it, because it changes the gate itself.
- Draft PRs aren't reviewed until they are marked ready.
