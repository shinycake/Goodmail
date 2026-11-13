# Goodmail

An iOS email client. Product decisions are in [docs/product-brief.md](docs/product-brief.md); architecture decisions are in [docs/architecture/decisions.md](docs/architecture/decisions.md); design decisions are in [docs/design/design-decisions.md](docs/design/design-decisions.md); the v1 plan is in [docs/plan/v1-plan.md](docs/plan/v1-plan.md).

## Development environment

Claude Code tooling is declared in the repo:

- `.claude/settings.json` enables these plugins, and Claude Code asks you to install them when you open the folder:
  - [pstack](https://github.com/michael-denyer/pstack-claude)
  - Antoine van der Lee's Swift skills: [SwiftUI](https://github.com/AvdLee/SwiftUI-Agent-Skill), [Swift Concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill), [Swift Testing](https://github.com/AvdLee/Swift-Testing-Agent-Skill), [Core Data](https://github.com/AvdLee/Core-Data-Agent-Skill), [Xcode Build Optimization](https://github.com/AvdLee/Xcode-Build-Optimization-Agent-Skill)
- `.mcp.json` registers Xcode's MCP bridge (`xcrun mcpbridge`). It covers builds, previews, documentation search and String Catalog tools, and works only while Xcode has the project open.
- `scripts/sync-xcode-skills.sh` copies the agent skills that ship with the active Xcode, currently String Catalog translation, into `.claude/skills/`. Run it after cloning and after each Xcode update.

Requires Xcode 27.2 / Swift 6.4.

## Building and the gate

- Open `Goodmail.xcodeproj` (JSON project format). Code lives in local packages, one per module, under `Packages/` (`MailCore`, `MailStore`, `GmailProvider`, `ICloudProvider`, `MailUI`, `MailIntents`); the app, `NotificationService` and `Widgets` targets are thin.
- `scripts/check` is the gate: swift-format lint, the 1000-line cap, package tests and the app's English/Hebrew launch tests. `scripts/check --lint` runs only the fast part. Its tests run on a separate "Goodmail Check" simulator.
- `scripts/record-fixtures` files the `TestMail` corpus into the signed-in test account and records Gmail's responses as fixtures (ADR-010). `TestMail/generate.py` writes the corpus.
- `scripts/run` builds the signed Debug app and installs it on the dev simulator, keeping its Gmail sign-in. Arguments pass through to the app, e.g. `scripts/run -AppleLanguages "(he)"`.
- Claude cloud sessions (Linux) compile the packages and their tests for iOS with xtool (`scripts/ios-build`) and run the MailCore, GmailProvider, ICloudProvider, OutlookProvider and MailStore tests natively; `scripts/check` does both there. Setup is automatic: see [docs/setup/cloud-builds.md](docs/setup/cloud-builds.md).
- After cloning, enable the tracked hooks (pre-commit runs `--lint`, pre-push runs everything):

  ```bash
  git config core.hooksPath .githooks
  ```
