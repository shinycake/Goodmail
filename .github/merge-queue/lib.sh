# Shared by the merge queue's steps (docs/setup/merge-queue.md). Needs gh, jq, GH_TOKEN and GITHUB_REPOSITORY.
# shellcheck shell=bash

R="$GITHUB_REPOSITORY"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/$R/actions/runs/${GITHUB_RUN_ID:-0}"
# The commit status the queue keeps on each PR's head commit, so the PR's checks say where it stands in the queue.
CONTEXT=merge-queue

# The queue's last status on a commit, as "state<TAB>description", or nothing.
last_status() {
    gh api "repos/$R/commits/$1/statuses?per_page=100" \
        --jq "[.[] | select(.context == \"$CONTEXT\")][0] // empty | [.state, .description] | @tsv"
}

# Sets the queue's status on a commit: pending, success or failure, and why. Only a change is posted, so a sweep that
# finds nothing new is silent.
report() {
    local sha=$1 state=$2 description=${3:0:140}
    [[ "$(last_status "$sha")" == "$state"$'\t'"$description" ]] && return 0
    gh api -X POST "repos/$R/statuses/$sha" -f state="$state" -f context="$CONTEXT" \
        -f description="$description" -f target_url="$RUN_URL" >/dev/null
}

# Comments on a PR once per key, for a stuck PR whose author has to act. The key names the head and main it is about.
notify() {
    local pr=$1 body=$3 marker="<!-- merge-queue: $2 -->"
    if gh api "repos/$R/issues/$pr/comments" --paginate \
        --jq '.[] | select(.user.login == "github-actions[bot]") | .body' | grep -qF "$marker"; then
        return 0
    fi
    gh api -X POST "repos/$R/issues/$pr/comments" -f body="$body"$'\n\n'"$marker" >/dev/null
}

# A verdict the queue reached on a PR merged with main holds while main stays put; descriptions end with this stamp.
stamp() { echo "(main ${1:0:7})"; }

# Starts the next sweep. A push made with the workflow's token starts no workflows, a dispatch does.
next_sweep() { gh workflow run merge-queue.yml -R "$R" --ref main; }
