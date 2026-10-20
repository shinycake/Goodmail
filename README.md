# Goodmail

An iOS email client. Product decisions are in [docs/product-brief.md](docs/product-brief.md); architecture decisions are in [docs/architecture/decisions.md](docs/architecture/decisions.md); design decisions are in [docs/design/design-decisions.md](docs/design/design-decisions.md); the v1 plan is in [docs/plan/v1-plan.md](docs/plan/v1-plan.md).

## Development environment

Claude Code tooling is declared in the repo:

- `.claude/settings.json` enables these plugins, and Claude Code asks you to install them when you open the folder:
  - [pstack](https://github.com/michael-denyer/pstack-claude) and [ECC](https://github.com/affaan-m/ECC)
  - Antoine van der Lee's Swift skills: [SwiftUI](https://github.com/AvdLee/SwiftUI-Agent-Skill), [Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill), [Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill), [Core Data](https://github.com/AvdLee/Core-Data-Agent-Skill), [Xcode Build Optimization](https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill)
- `.mcp.json` registers Xcode's MCP bridge (`xcrun mcpbridge`). It covers builds, previews, documentation search and String Catalog tools, and works only while Xcode has the project open.
- `scripts/sync-xcode-skills.sh` copies the agent skills that ship with the active Xcode, currently String Catalog translation, into `.claude/skills/`. Run it after cloning and after each Xcode update.

Requires Xcode 27 / Swift 6.4.
