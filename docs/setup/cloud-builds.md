# iOS builds on Linux cloud workers

Claude cloud sessions run on Linux without Xcode. They compile every package and its tests for iOS (`arm64-apple-ios`) with [xtool](https://github.com/xtool-org/xtool)'s Darwin SDK, so package work can leave the Mac (ADR-017). Linux has no iOS simulator, and xtool doesn't have one either. So cloud sessions run the tests of the packages that also build for Linux, natively: MailCore, GmailProvider and MailStore. The Mac's `scripts/check` runs everything, including MailUI's tests and the app's launch tests.

## In a cloud session

Nothing to do. Setup runs on its own, in two ways:

- When a session starts inside this repository, the SessionStart hook (`.claude/hooks/session-start.sh`) runs it.
- A session with several repositories attached, such as this one and `goodmail-sdk`, starts in their parent folder, and Claude Code doesn't load this repository's hooks there. So `scripts/check` and `scripts/ios-build` run `scripts/cloud/ensure` first, and that runs setup when something is missing.

Setup also enables the tracked git hooks. Its first run in a fresh container takes about two minutes. Later runs find everything installed and return at once. The setup log is at `/tmp/goodmail-cloud-setup.log`. In a multi-repository session, run `scripts/check --lint` once before your first commit, so the git hooks are in place before you commit or push.

- `scripts/ios-build [Package …]` compiles packages and their tests for iOS. With no arguments it compiles all of them, then type-checks the Xcode targets that SwiftPM can't build (the app, NotificationService and WidgetsExtension) against those package builds. The type-check uses the project's Debug Swift settings, which are listed in the script, so update them there when the project's settings change. It catches compile errors, but it doesn't link, compile assets or String Catalogs, or check entitlements. Only the Mac's build does those.
- `scripts/check` on Linux runs the lint, the line cap, `scripts/ios-build`, and `swift test` for MailCore, GmailProvider and MailStore. The pre-push hook runs it.
- `swift test --package-path Packages/MailStore` runs one package's tests natively.

## Keeping the logic packages Linux-testable

MailCore, GmailProvider and MailStore stay free of UIKit and SwiftUI. Where they need an Apple-only API, it is fenced with `#if canImport(…)`, so Linux test builds compile without it:

- `Keychain` exists only where Security does. Callers pass a `SecretStore`, which tests replace with memory.
- Charset lookup uses CoreFoundation on Apple platforms. Linux's Foundation has no windows-1255, so that one test is skipped there.
- `SharedContainer.directoryURL` is `nil` on Linux, because there are no App Groups.
- GmailProvider imports `FoundationNetworking` for `URLSession`. It falls back to a small SHA-256 for PKCE, because CryptoKit doesn't exist on Linux.
- `ChangeSignal` uses Darwin notifications between processes. On Linux it signals within the process only, which is what the tests exercise.

A new Apple-only import in these packages breaks the Linux tests in `scripts/check`, which catches the regression in a cloud session.

## What setup installs

| Piece | Where from | Where to |
| --- | --- | --- |
| Swift 6.4.2, matching Xcode 27.2 | The official `swift:6.4.2-noble` image on Docker Hub, because cloud workers can't reach download.swift.org. `scripts/cloud/fetch-docker-layer.py` downloads the toolchain layer and checks its digest. | `/opt/swift`, plus `swift` and `swiftc` in `/usr/local/bin` |
| xtool 1.24.0 | GitHub release AppImage, checked against its pinned SHA-256 and unpacked because containers have no FUSE | `/opt/xtool`, plus `xtool` in `/usr/local/bin` |
| Darwin SDK | Built by `xtool sdk build` from the Xcode subset in the private [`shinycake/goodmail-sdk`](https://github.com/shinycake/goodmail-sdk) repository: the checkout next to this one, or a fresh clone | `~/.swiftpm/swift-sdks/darwin.artifactbundle` |

Two adjustments make swift-build work on Linux:

- The SDK's platform `Info.plist` files set `SWIFT_STDLIB_TOOL_STRIP_BITCODE = NO`. Embedding Swift libraries in a test bundle otherwise calls Apple's `bitcode_strip`, which Linux doesn't have.
- `scripts/cloud/xcstringstool` stands in for Apple's String Catalog compiler. The catalog stays uncompiled, which is harmless because cloud builds only compile.

## After an Xcode update

The SDK has to come from the Xcode the Mac builds with. Xcode.xip downloads need an Apple sign-in, so cloud workers never download Xcode themselves. On the Mac:

```bash
brew install zstd   # once
gh repo clone shinycake/goodmail-sdk ../goodmail-sdk
scripts/cloud/export-xcode-sdk /Applications/Xcode-<version>.app ../goodmail-sdk
cd ../goodmail-sdk && git add -A && git commit -m "Xcode <version> SDK subset" && git push
```

Then raise `XCODE_VERSION` in `scripts/cloud/setup`, and `SWIFT_VERSION` to the Swift that ships with that Xcode. The export is about 220 MB, stored in parts under GitHub's 100 MB file limit. The repository must stay private, because Apple's Xcode license doesn't allow redistribution.
