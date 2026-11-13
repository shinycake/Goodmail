#!/bin/bash
# Cloud sessions only: install what compiles Goodmail for iOS on Linux (docs/setup/cloud-builds.md) and enable the
# tracked git hooks. The first run takes about two minutes; later runs find everything installed and return at once.
set -euo pipefail
[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0
cd "$CLAUDE_PROJECT_DIR"
git config core.hooksPath .githooks

log=/tmp/goodmail-cloud-setup.log
# What the hook prints reaches the session's context, so keep it to the outcome and leave the details in the log.
if scripts/cloud/setup >"$log" 2>&1; then
    echo "Cloud iOS toolchain ready: scripts/ios-build compiles the packages for iOS; scripts/check runs lint and that."
else
    echo "scripts/cloud/setup failed, so iOS builds are unavailable. Last lines of $log:"
    tail -n 15 "$log"
fi
