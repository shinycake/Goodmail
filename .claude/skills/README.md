# Vendored agent skills

These skills are checked into the repository so that every Claude session loads them: cloud threads, the Mac, and the review in `.github/workflows/review.yml`. Claude Code picks up any `SKILL.md` under `.claude/skills/` on its own; no plugin install is needed.

| Skill | Use it for | Source | Commit |
|---|---|---|---|
| [`swift-concurrency`](swift-concurrency/SKILL.md) | Actors, `@MainActor`, `Sendable`, tasks, cancellation, Swift 6 strict concurrency | [AvdLee/Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) | `3b1580d8398e0b5408b3bf0bada0e941a1cfc642` |
| [`swiftui-expert-skill`](swiftui-expert-skill/SKILL.md) | SwiftUI state, view structure, lists, navigation, performance, accessibility, localization | [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) | `62bd760f005093d1e2e4de5db156e456a5f96400` |
| [`swift-testing-expert`](swift-testing-expert/SKILL.md) | Swift Testing structure, `#expect`/`#require`, traits, parameterized and async tests | [AvdLee/Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill) | `798e9b1a2bcac164d4f0c781908199e754f0bab6` |

All three are by Antoine van der Lee under the MIT License; each folder keeps its `LICENSE`. They are copied unchanged except that the logo images (`assets/`) and the OpenAI agent manifests (`agents/`) are left out.

The author's Core Data and Xcode build optimization skills stay out: Goodmail stores mail with GRDB, not Core Data, and build tuning isn't part of everyday work here. They are still enabled as plugins in `.claude/settings.json` for sessions that want them.

## Updating

Clone the source repository, copy its skill folder over the one here (the folder under `skills/` in the source), drop `assets/` and `agents/`, and update the commit in the table above. Keep the `LICENSE`.
