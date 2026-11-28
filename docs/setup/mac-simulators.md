# Simulators on the Mac

The Mac is a 16 GB machine shared by several Claude threads, and each thread that builds or tests boots its own
simulator. A stock iOS 27.2 simulator runs about 200 processes and several GB of memory, most of it background
services (Siri, widgets and wallpaper, iCloud, Spotlight) that development and tests never use. The Mac allows 2,666
processes per user (`sysctl kern.maxprocperuid`), so about eleven stock simulators exhaust it, and after that nothing
can start a process: builds fail and new Claude Code sessions don't open.

## Which simulator is whose

- **iPhone 18 Pro** is the dev simulator. It holds the owner's real sign-ins, and `scripts/run` installs the signed
  Debug build on it. Only the main session uses it. Never slim, erase, reboot or shut it down.
- **Goodmail Check** and **Goodmail Check <worktree>** belong to `scripts/check`. A worktree's own one is deleted when
  its check ends.
- **Goodmail Check2** and **Goodmail Check2 <worktree>** are the full UI suite's second simulator (`scripts/ui-suite`,
  `scripts/check --ui`), which runs a share of the suite, split by test count, next to the first. It's slimmed like the
  first and shut down when the run ends. A worktree's own one is deleted then, and `scripts/cleanup` keeps the main one
  like **Goodmail Check**. With two or more other simulators booted, the suite leaves it off and runs on one simulator,
  so the Mac doesn't page.
- **Goodmail <purpose> <worktree>** belongs to the thread working in that worktree. `scripts/sim` creates them, and
  `scripts/cleanup` deletes them ([mac-disk.md](mac-disk.md)).
- Any other simulator a thread created is that thread's. Don't shut down or reboot a simulator you didn't boot.

## simslim

[simslim](https://github.com/MobAI-App/simslim) (MIT) switches off the background services a simulator doesn't need by
writing `launchctl disable` overrides into that one simulator's launchd store
(`/private/var/tmp/com.apple.CoreSimulator.SimDevice.<udid>/disabled.plist`). It touches nothing else on the Mac, has no
network access, and `simslim off <udid>` puts a simulator back to stock. It only drives `xcrun simctl`, so it works
with any Xcode; it was checked against Xcode 27.2 and iOS 27.2.

Measured on this Mac (iOS 27.2, idle after 90 seconds, `simslim measure`):

| | Processes | Memory (phys_footprint) |
|---|---|---|
| Stock | 205 | 7.9 GB |
| Slim, Goodmail profile | 67 | 2.1 GB |

On a slim simulator the app's tests went 9 passed, 3 failed and 3 skipped on the first run. The 3 that failed,
`ChatLayoutTests.testALaidOutLetterOpensInFull`, `SwipeTests.testOpenButtonsStayOnTheirRowWhenMailArrivesAbove` and
`SettingsTests.testOpeningAnAccountAfterAChangeKeepsSettingsOpen`, are timing-sensitive on a Mac deep in swap: rerun
on the same simulator, 1 still failed slim and 2 failed once it was back to stock. None failed because of slimming.

### Install

```bash
brew install mobai-app/tap/simslim
```

The formula builds from source with Go.

### The Goodmail profile

[`scripts/simslim-profile.json`](../../scripts/simslim-profile.json) disables everything simslim manages except:

- `photos`, because the compose attach menu uses the Photos picker;
- `search`, because the document picker's Recents needs `searchd`;
- `com.apple.apsd`, so the app can register for remote notifications.

Keychain (`securityd`) is never in simslim's list, so sign-ins still work. Lost on a slim simulator: Siri, widgets and
Live Activities on the Home and Lock Screen, iCloud, universal links, Contacts and Calendar pickers. Turn a category
back on without a reboot when a task needs it, for example `simslim enable <udid> widgets` for widget work.

### Using it

- `scripts/check` slims its simulator automatically when simslim is installed and the simulator is shut down, which
  covers every new per-worktree check simulator.
- `scripts/sim` slims the simulators it creates. Slim any other simulator you created yourself before you boot it:

  ```bash
  simslim on <udid> --profile scripts/simslim-profile.json --preserve-boot-state
  ```

- A simulator that is already booted, and that someone else may be using, can be slimmed in place without a reboot.
  This stops the services but leaves the simulator, its apps and any running test alone:

  ```bash
  simslim on <udid> --no-reboot --profile scripts/simslim-profile.json
  ```

  Never run `simslim on` without `--no-reboot` on a simulator you didn't boot, because it shuts it down to apply the
  profile.
- `simslim list` shows which simulators are slim, and `simslim measure <udid>` a booted one's processes and memory.
- Don't run `simslim watch`: it slims every shut-down simulator, including the dev simulator.
