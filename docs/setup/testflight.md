# TestFlight and the public beta

Every build goes to two TestFlight groups:

- **Internal** has access to all builds, so its testers get each one as soon as Apple finishes processing it.
- **Apple Review** is the external group behind the public link, https://testflight.apple.com/join/JQPaJxgK. External builds need Beta App Review, so `scripts/public-beta` adds each new build to this group and submits it. The public link always offers the newest build that Apple has approved.

## Uploading a build

On the Mac, from a clean checkout of the commit you want to ship:

```bash
scripts/testflight
```

It archives a signed Release build, uploads it with `asc` and waits for App Store Connect to process it. Then it tags the commit `testflight/<build number>`, pushes the tag, and runs `scripts/public-beta` for the new build. You need Xcode signed in to the team, and `asc auth status` must show an App Store Connect API key.

No build should reach TestFlight any other way. If one does, from Xcode's Organizer for example, run `scripts/public-beta` afterwards.

## What `scripts/public-beta` does

`scripts/public-beta [BUILD_NUMBER]` takes the newest uploaded build when you don't name one. It calls `asc publish testflight`, which:

1. waits until the build has finished processing,
2. sets the build's What to Test notes in English,
3. adds the build to the Apple Review group,
4. submits the build for Beta App Review, unless it already has a submission.

Running it twice for the same build does nothing new, so you can rerun it after any failure. App Store Connect's API sometimes times out, so the script tries the publish three times, a minute or two apart, before it gives up. It names the group by its ID, so a slow group list can't stop it.

The What to Test notes open with one line about the app. Then they list the commit subjects since the previous `testflight/*` tag, which are the titles of the PRs in the build, and end with a short request for feedback. PR titles already go through the humanizer, so the notes are fit for testers to read. A build with no tag, or the first tagged one, gets the opening and closing lines only.

## When a review is still pending

If Apple refuses the submission while an older build is still waiting for review or in review, the new build stays in the group without a submission. The script says which build Apple is still reviewing and exits with status 3. Once that review clears, run `scripts/public-beta` with no arguments and it submits the newest build.

After the first build of a version is approved, Apple usually approves later builds of the same version within minutes, so this rarely lasts long.

## Test Information

Beta App Review also reads the app-level Test Information in App Store Connect: the beta app description, the feedback email, and the review contact and sign-in notes. These are set once and stay the same for every build. Change them in App Store Connect under TestFlight, Test Information, or with `asc testflight review` and `asc testflight app-localizations`.
