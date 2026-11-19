# Disk use on the Mac

Goodmail work on the Mac leaves three things behind, and before `scripts/cleanup` nothing removed them:

- Simulators. Each one keeps 2 to 5 GB of its own data on the internal disk, in
  `~/Library/Developer/CoreSimulator/Devices`, on top of the blocks it shares with the iOS runtime. Tasks used to create
  about a dozen a day and never delete them: 59 were deleted by hand between November 16 and 18, 2026, and 24 of them
  held about 8 GB.
- Build folders on the external drive, under `/Volumes/Idan1TB/Goodmail-build`. Every worktree gets its own
  `DerivedData` of about 1.2 GB under `worktrees/`, and ad hoc folders such as `sanitizers/` or `crashfix/` collect
  next to them. The drive reached 187 GB.
- Xcode's own `~/Library/Developer/Xcode/DerivedData`, on the internal disk, for builds that didn't pass
  `-derivedDataPath`. It grew to about 7 GB in a few days, twice.

## The rule

1. Get a simulator with `scripts/sim <purpose> [device type]`. Never run `xcrun simctl create` by hand. It names
   the simulator `Goodmail <purpose> <worktree>` and slims it, and asking again for the same purpose returns the same
   one. When a task needs it clean, run `xcrun simctl erase <udid>` on it instead of creating another. An iPad is
   `scripts/sim ipad "iPad Pro 13-inch (M5)"`. Shut it down (`xcrun simctl shutdown <udid>`) whenever you stop using it: the Mac
   has 16 GB, and two booted simulators beside the Claude sessions already push it deep into swap. `scripts/sim`
   warns when two are booted.
2. Every build writes under `scripts/build-paths`' `BUILD_ROOT`, on the external drive. `scripts/check`, `scripts/run`
   and `scripts/testflight` already do. Pass `-derivedDataPath "$BUILD_DIR/<name>"` to any `xcodebuild` you run yourself, and
   `--scratch-path` to `swift build` or `swift test`.
3. When a task ends (its work landed on main, or the work dropped), run `scripts/cleanup --done` in its worktree, then remove
   the worktree. It shuts down and deletes every simulator named for that worktree, deletes the worktree's build
   folder, and runs the sweep.

## The sweep

`scripts/check` runs `scripts/cleanup --if-due` on the Mac, which sweeps at most once every six hours. Run
`scripts/cleanup --dry-run` to see what it would delete. It deletes:

| What | When |
|---|---|
| A shut-down simulator whose name starts with "Goodmail" | Nobody has booted it for a day, or the worktree in its name is gone |
| Build output in `Goodmail-build`: DerivedData folders, SwiftPM scratch folders and archives | Untouched for 3 days (`GOODMAIL_CLEANUP_DAYS`), or an hour after its worktree is gone |
| Check result bundles (`results/*.xcresult`) | All but the newest three in each folder |
| `xcodebuild-*.log` | An hour old. `scripts/check` deletes its own unless the build failed |
| SwiftPM `.build` folders inside a worktree, on any disk | Untouched for 3 days |
| Goodmail's folders in Xcode's DerivedData | Untouched for 3 days. Each folder's `info.plist` names its workspace |

It leaves alone:

- a booted simulator, and every simulator whose name doesn't start with "Goodmail". That covers Apple's standard
  ones and the dev simulator, iPhone 18 Pro. The main checkout's "Goodmail Check" stays too, because every check
  there reuses it.
- other files in `Goodmail-build`, such as evidence screenshots, logs or a dashboard's data. It finds build output by
  its markers (an Xcode `info.plist` beside `Build`, a SwiftPM `workspace-state.json`, an `.xcarchive`);
- a folder written to in the last hour, a folder a running process names on its command line (such as an
  `xcodebuild -derivedDataPath`), and a folder that is or holds a git checkout;
- anything outside Goodmail, such as Quill's `quill-work` folder on the external drive, which `~/.local/bin/mac-cleanup`
  handles.

Everything it deletes is a cache. The next build or `scripts/sim` call makes it again, so a deleted folder costs one
cold build.

## What stays on the disk

With the sweep, the internal disk holds the simulators of the last day: a few GB, where it used to grow by about
4 GB a day. The external drive holds the build folders of worktrees used in the last three days, about 1.2 GB each
plus the shared ones, so roughly 10 to 30 GB instead of 187 GB and climbing. Xcode's DerivedData stays at whatever
Goodmail built there in the last three days.
