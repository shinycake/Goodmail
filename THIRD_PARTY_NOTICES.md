# Third-party notices

Goodmail's own code is proprietary (see [LICENSE](LICENSE)). The components below are not: each stays under its own license, which is reproduced or linked here as that license requires. Nothing in Goodmail's LICENSE limits the rights those licenses give you over those components.

## Built into the app

### GRDB.swift 7.11.1

Fetched by Swift Package Manager from <https://github.com/groue/GRDB.swift>. It is not copied into this repository.

```
Copyright (C) 2015-2025 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

GRDB embeds nothing else; it links the SQLite that ships with iOS, which is in the public domain.

## Vendored in this repository

### Antoine van der Lee's agent skills (MIT)

`.claude/skills/swift-concurrency`, `.claude/skills/swiftui-expert-skill` and `.claude/skills/swift-testing-expert` are copies of [Swift-Concurrency-Agent-Skill](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill), [SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) and [Swift-Testing-Agent-Skill](https://github.com/AvdLee/Swift-Testing-Agent-Skill), Copyright (c) 2026 Antoine van der Lee, under the MIT License. Each folder keeps its `LICENSE` file, which governs that folder.

## Development tools only

These are used to build, test or deploy, and none of their code ships in the app or the push Worker:

- The push Worker's dev dependencies (`PushWorker/package.json`): [Wrangler](https://github.com/cloudflare/workers-sdk) and `@cloudflare/vitest-plugin` (MIT or Apache-2.0), [Vitest](https://github.com/vitest-dev/vitest) (MIT) and [TypeScript](https://github.com/microsoft/TypeScript) (Apache-2.0). The Worker itself imports nothing from npm.
- [xtool](https://github.com/xtool-org/xtool) (MIT), [simslim](https://github.com/MobAI-App/simslim) (MIT) and [swift-format](https://github.com/swiftlang/swift-format) (Apache-2.0), installed by the scripts, not vendored.
- Apple's Xcode and iOS SDK, under Apple's own license. They are never redistributed from this repository; the SDK copy the cloud builds use lives in a private repository for that reason.

## Trademarks

Gmail and Google are trademarks of Google LLC. Outlook and Microsoft are trademarks of Microsoft Corporation. Apple, iCloud, iPhone, iPad and iOS are trademarks of Apple Inc. Goodmail is not affiliated with, endorsed by or sponsored by any of them.
