#!/usr/bin/env bash
# Copies the agent skills bundled with the active Xcode into .claude/skills/.
# They are Apple's files and track the installed Xcode, so they are gitignored; rerun after Xcode updates.
set -euo pipefail
cd "$(dirname "$0")/.."
xcode="$(xcode-select -p)/.."
dest=.claude/skills
find "$xcode/PlugIns" -type d -path '*/Resources/Skills' -prune | while read -r root; do
  for skill in "$root"/*/; do
    name="xcode-$(basename "$skill")"
    rm -rf "$dest/$name"; mkdir -p "$dest/$name"
    (cd "$skill" && find . -name '*.packaged' | while read -r f; do
      mkdir -p "$OLDPWD/$dest/$name/$(dirname "$f")"
      cp "$f" "$OLDPWD/$dest/$name/${f%.packaged}"
    done)
    # Xcode namespaces these under its own plugin; point cross-references at the local names.
    sed -i '' 's/xcode-integration:\([a-z-]*\)/xcode-\1/g' "$dest/$name/SKILL.md"
    if [[ "$(head -1 "$dest/$name/SKILL.md")" != "---" ]]; then
      title="$(head -1 "$dest/$name/SKILL.md" | sed 's/^# //')"
      summary="$(sed -n '3p' "$dest/$name/SKILL.md" | cut -d. -f1)"
      printf -- '---\nname: %s\ndescription: "%s (bundled with Xcode). %s. Needs the xcode MCP server (xcrun mcpbridge) with the project open in Xcode."\n---\n\n' \
        "$name" "$title" "$summary" | cat - "$dest/$name/SKILL.md" > "$dest/$name/SKILL.tmp"
      mv "$dest/$name/SKILL.tmp" "$dest/$name/SKILL.md"
    fi
    echo "synced $name"
  done
done
