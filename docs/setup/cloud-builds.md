# iOS builds on Linux cloud workers

Claude cloud sessions run on Linux without Xcode. They compile every package and its tests for iOS (`arm64-apple-ios`) with [xtool](https://github.com/xtool-org/xtool)'s Darwin SDK, so package work can leave the Mac (ADR-017). They can't run the tests: Linux has no iOS simulator. The Mac's `scripts/check` still runs the tests.

## In a cloud session

Nothing to do. Cloud sessions check out `goodmail-sdk` next to this repository, and the SessionStart hook (`.claude/hooks/session-start.sh`) runs `scripts/cloud/setup` and enables the tracked git hooks. Its first run in a fresh container takes about two minutes. Later runs find everything installed and return at once. The setup log is at `/tmp/goodmail-cloud-setup.log`.

- `scripts/ios-build [Package …]` compiles packages and their tests for iOS. With no arguments it compiles all of them.
- `scripts/check` on Linux runs the lint, the line cap, and `scripts/ios-build`. The pre-push hook runs it.

## What setup installs

| Piece | Where from | Where to |
| --- | --- | --- |
| Swift 6.4.2, matching Xcode 27.2 | The official `swift:6.4.2-noble` image on Docker Hub, because cloud workers can't reach download.swift.org. `scripts/cloud/fetch-docker-layer.py` downloads the toolchain layer and checks its digest. | `/opt/swift`, plus `swift` and `swiftc` in `/usr/local/bin` |
| xtool 1.24.0 | GitHub release AppImage, unpacked because containers have no FUSE | `/opt/xtool`, plus `xtool` in `/usr/local/bin` |
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
