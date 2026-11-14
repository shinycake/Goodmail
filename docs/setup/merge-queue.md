# The merge queue

`.github/workflows/merge-queue.yml` (ADR-020) lands every approved, green PR on its own. Nobody, person or Claude thread, has to watch a PR for it to merge. `review.yml` judges a PR (the Claude review and the Linux `scripts/check`); the merge queue merges it.

## How a PR lands

1. A ready PR gets a `review` run: `scripts/check` on the PR merged with main, and the Claude review.
2. When that run ends, a merge-queue sweep starts. It also starts every 10 minutes, and again after each sweep that merged a PR or found why one can't merge.
3. The sweep's `plan` job looks at every ready PR from this repository, oldest first, and puts its place in the queue on the PR's **`merge-queue` status**, in the PR's checks list. The first PR that is approved and green is next.
4. The `verify` job squashes that PR onto the current main. If the tree is the one the review run checked, it's done; if main moved since, it runs `scripts/check` on the squash, and once more if that fails, in case a test is flaky. This job runs the PR's code, so it has read access only.
5. The `land` job squashes again onto the same main, authored by the PR author's noreply address, and fast-forwards main to it. Main is never force-pushed: if it moved in the meantime, the push fails and the next sweep starts over on the new main. GitHub then marks the PR merged, and the branch is deleted.
6. The `land` job starts the next sweep, so a backlog drains one PR at a time.

Sweeps run one at a time, so only the queue moves main between its check and its push.

## Why a PR is stuck

The `merge-queue` status says it in one line, and each sweep's run summary has a table of every PR. A PR is in one of three states:

| State | Status | What it means |
|---|---|---|
| ready | pending, "next to merge" or "queued behind #N" | Approved and green; it merges in turn. |
| waiting | pending | The queue is waiting on something that needs nobody's action: a run in progress, a rerun, the `hold` label, or the owner (a PR that changes `.github/`). |
| stuck | failure | The author has to act. The queue also comments once on the PR. |

A PR is stuck when:

- **The Claude review requested changes.** Fix the findings and push.
- **It conflicts with main**, found by squashing it onto main, or GitHub sees a conflict and so never starts its review. Merge main into the branch and push. The queue squashes onto main itself, so a branch that is only behind main never needs updating.
- **`scripts/check` fails on it squashed onto main**, twice. Fix it and push. The queue tries again by itself whenever main moves.
- **Its review run failed three times** for something other than the review's verdict: a crashed review, a failing check, a runner that went away. The queue reruns a failed run's failed jobs itself, up to three attempts in all. Push a fix, or rerun the run once the cause is gone.

## Exceptions

- A PR labeled `hold` is reviewed but waits until the label comes off.
- A PR that changes `.github/` waits for the owner, because it changes the gate itself. The Claude action won't review it either, since its `review.yml` differs from main's. Merge it once `check / check` is green.
- Drafts and PRs from forks are skipped.

## Running a sweep by hand

`gh workflow run merge-queue.yml -R shinycake/Goodmail` starts one at once; it's always safe, since a sweep that finds nothing to do changes nothing.

## Why not GitHub's merge queue or auto-merge

GitHub's merge queue needs an organization-owned repository, and Goodmail is under a personal account. Auto-merge would make GitHub author the squash, and its merge would start no workflows when the queue's token enables it. The workflow keeps what ADR-016 asked for: the squash that lands is the tree that was checked, under a noreply author, and main only fast-forwards.
