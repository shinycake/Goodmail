#!/bin/bash
# Cloud sessions that start in this repository: install the iOS toolchain up front (docs/setup/cloud-builds.md).
# The first run takes about two minutes; later runs find everything installed and return at once.
set -euo pipefail
[[ "${CLAUDE_CODE_REMOTE:-}" == "true" ]] || exit 0
# What the hook prints reaches the session's context, so keep it to the outcome.
if "$CLAUDE_PROJECT_DIR/scripts/cloud/ensure" 2>&1; then
    echo "Cloud iOS toolchain ready: scripts/check runs lint, the iOS compile (scripts/ios-build) and the Linux tests."
fi
