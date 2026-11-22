# TestFlight and the public beta

Every build goes to two TestFlight groups:

- **Internal** has access to all builds, so its testers get each one as soon as Apple finishes processing it.
- **Apple Review** is the external group behind the public link, https://testflight.apple.com/join/JQPaJxgK. External builds need Beta App Review, so `scripts/public-beta` adds each new build to this group and submits it. The public link always offers the newest build that Apple has approved.

## Uploading a build

On the Mac, from a clean checkout of the commit you want to ship:

```bash
scripts/testflight
```

It archives two signed Release builds of the same commit, one for iOS and one for the Mac (Mac Catalyst), and gives both the same build number: the next one that is free on both platforms. It exports the iOS archive as an `.ipa` and the Mac one as a `.pkg`, uploads both with `asc` and waits for App Store Connect to process them. Then it tags the commit `testflight/<build number>`, pushes the tag, and runs `scripts/public-beta` once for each platform. `asc auth status` must show an App Store Connect API key.

The Mac upload needs a macOS platform on the app in App Store Connect, and its export signs with the cloud-managed Mac App Distribution and Mac Installer Distribution certificates, which automatic signing creates the first time.

## Signing with the API key

Automatic signing has to talk to App Store Connect to create certificates and profiles, for example the first time a new target such as a watch extension is archived. `scripts/testflight` passes the API key that `asc` uses to `xcodebuild` (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`). Nobody has to stay signed in to Xcode with an Apple ID, and an expired Xcode session can't stop a release.

The key ID and issuer ID come from `asc auth status` and `asc auth issuer-id`. `xcodebuild` needs the key as a `.p8` file. The script looks for a file whose name contains the key ID in `~/.appstoreconnect/private_keys`, `~/.asc`, `~/.asc/keys` and `~/private_keys`. If `asc` keeps the key only in the Keychain, export it once:

```bash
asc auth export-to-config --confirm --private-key-dir ~/.appstoreconnect/private_keys
```

This writes the `.p8` file with owner-only permissions. The Keychain entry stays where it is. `GOODMAIL_ASC_KEY_ID`, `GOODMAIL_ASC_ISSUER_ID` and `GOODMAIL_ASC_KEY_PATH` override what the script finds. Without a key file, it warns and falls back to the Apple ID signed in to Xcode.

No build should reach TestFlight any other way. If one does, from Xcode's Organizer for example, run `scripts/public-beta` afterwards.

## What `scripts/public-beta` does

`scripts/public-beta [BUILD_NUMBER] [IOS|MAC_OS]` takes the newest uploaded iOS build when you don't name one. Pass `MAC_OS` as the second argument for the Mac build. It calls `asc publish testflight`, which:

1. waits until the build has finished processing,
2. sets the build's What to Test notes in English,
3. adds the build to the Apple Review group,
4. submits the build for Beta App Review, unless it already has a submission.

Running it twice for the same build does nothing new, so you can rerun it after any failure. App Store Connect's API sometimes times out, so the script tries the publish three times, a minute or two apart, before it gives up. It names the group by its ID, so a slow group list can't stop it.

The What to Test notes open with one line about the app. Then they list the commit subjects since the previous `testflight/*` tag, and end with a short request for feedback. Each slice lands as one commit whose subject goes through the humanizer (ADR-028), so the notes are fit for testers to read. A build with no tag, or the first tagged one, gets the opening and closing lines only.

## When a review is still pending

If Apple refuses the submission while an older build is still waiting for review or in review, the new build stays in the group without a submission. The script says which build Apple is still reviewing and exits with status 3. Once that review clears, run `scripts/public-beta` with no arguments and it submits the newest build.

After the first build of a version is approved, Apple usually approves later builds of the same version within minutes, so this rarely lasts long.

## Test Information

Beta App Review also reads the app-level Test Information in App Store Connect: the beta app description, the feedback email, and the review contact and sign-in notes. These are set once and stay the same for every build. Change them in App Store Connect under TestFlight, Test Information, or with `asc testflight review` and `asc testflight app-localizations`.
