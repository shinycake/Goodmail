# Localization and right-to-left audit

Goodmail ships in English and Hebrew (M11). This is the release checklist for both: what was checked in code, what this audit fixed, what is left, and what only a device can confirm. Run it again before each release.

Audited on 2026-11-13 against `main` at `42720fc`.

## How to re-run the code checks

- **Catalog gaps.** Every key in `Packages/MailUI/Sources/MailUI/Resources/Localizable.xcstrings`, `Widgets/Localizable.xcstrings` and `Goodmail/InfoPlist.xcstrings` has a `he` value in state `translated`, and none is `stale`. A short Python pass over the JSON finds the rest.
- **Strings outside the catalog.** In `MailUI`, every `String(localized:)` and `Text("…")` passes `bundle: .module`. Without it the lookup goes to the app's bundle and the Hebrew value is never found. App targets (`Goodmail`, `Widgets`) use their own bundle and need no argument.
- **Prose stored as data.** Search for English sentences assigned to properties or written to the database, such as `reason: "…"`. Store a case and word it in `MailUI`.
- **Layout.** No `.left` or `.right` in Auto Layout, insets or `NSTextAlignment`, except where the code chooses an edge from a direction it worked out first.
- **Direction of mixed text.** A Hebrew value whose first strong character is Latin, usually because it starts with a `%@` that holds an address or a brand, takes a leading U+200F RIGHT-TO-LEFT MARK. Without it, UIKit lays the whole paragraph out left to right.

## Checklist

### Catalogs

- [x] All MailUI keys (117 with this audit's two) have a translated `he` value; none is stale or new.
- [x] All 3 widget keys have a translated `he` value.
- [x] `CFBundleName` had no `he` value. **Fixed:** "Goodmail", as `CFBundleDisplayName` already has, since the brand stays in Latin script.
- [x] Plural keys have `he` variations. Hebrew's `two` falls back to `other`, which reads correctly for all five plural keys.
- [x] Format specifiers match between `en` and `he` values.
- [x] The remove-account message, `%@ והדואר שלו יוסרו…`, started with the account's address, so it laid out left to right. **Fixed:** it now starts with U+200F, as the 25 MB attachment message already did.

### Strings in code

- [x] Every `String(localized:)` and `Text` in MailUI passes `bundle: .module`.
- [x] Mailbox, category, search filter and toast strings are all in the catalog.
- [x] A failed send showed an English sentence in its alert in every language, because `Sender` stored the prose in the `outgoing.failure` column. **Fixed:** `OutgoingMessage.failure` is now a `SendFailure` case and `SendFailureAlert` words it from the catalog. A sentence stored by an earlier build reads back as `.rejected`, the same way an unknown `purpose` reads back as `.saveDraft`.
- [ ] `error.localizedDescription` is shown as the alert text when sign-in fails (`WelcomeView` and `AddAccountView`, through `AccountAdder`), when Settings fails (`SettingsView`) and in `ThreadViewController`. `ProviderError`, the OAuth errors and `Keychain.Failure` aren't `LocalizedError`s with catalog strings, so they show Foundation's generic "The operation couldn't be completed (… error N.)", or English for `Keychain.Failure`. **Follow-up:** give these alerts a fixed, localized message per case at the MailUI boundary.
- [ ] The reply attribution ("On …, … wrote:") and the forwarded-message header ("---------- Forwarded message ---------", "From:", "Date:" and so on) in `Draft.quote` and `Draft.forwardedQuote` are always in English, though the date in them follows the user's locale. Gmail words these in the sender's language. **Product decision:** keep English, which every recipient's client recognizes, or localize them, which needs a string catalog in MailCore.
- [x] "Re:" and "Fwd:" stay in English on purpose, as RFC 5322 and Gmail do. `TextDirection.of(subject:)` already skips Hebrew clients' "השב:" and "הועבר:".
- [ ] "Nothing is deleted from Gmail." names Gmail. **Follow-up** for the Outlook and iCloud work: name the account's provider. (Adding an account now goes through a chooser that names each service.)
- [ ] A push whose notification extension doesn't run shows the Worker's fallback text, "Goodmail" and "New mail", in English (`PushWorker/src/apns.ts`). **Follow-up:** send `title-loc-key` and `loc-key`, with matching keys in an app-target catalog, so the device words the fallback. Adding the catalog to the app target needs Xcode on a Mac.

### Layout

- [x] No `leftAnchor`, `rightAnchor` or left and right insets that aren't symmetric. The one `UIEdgeInsets(left:right:)`, in compose, is zero on both sides.
- [x] Swipe actions choose `.leading` or `.trailing` from the swipe direction and `effectiveUserInterfaceLayoutDirection` (`SwipeActions.swift`).
- [x] `NSTextAlignment.left` and `.right` appear only in `UILabel.setContentText`, which sets them from a direction it worked out first: the content's, or the interface's for labels that sit beside other elements.
- [x] Sender, subject, preview and recipient labels use `setContentText` or `setSubjectText`, so a Hebrew subject in an English interface reads right to left, and the other way round.

### HTML reader (`MessageDocument`, `MessageScript`)

- [x] Plain-text bodies render one `dir="auto"` block per line, and quotes use `padding-inline-start` and `border-inline-start`.
- [x] `MessageScript` sets `dir="auto"` on the body and on every block where the sender set no `dir` on that element. A Hebrew reply above an English quote reads each way.
- [x] The fold control takes the direction of the reply text before it, not of the quote.
- [x] Known trade-off, kept: a block without its own `dir` inside a sender's `dir="rtl"` or `dir="ltr"` container follows its own first strong character, not the container. This is what makes Hebrew read right to left in Gmail's `<div dir="ltr">` wrapper, the common case. An English line inside a Hebrew Outlook message aligns left as a result.
- [x] `directionBefore` treats Hebrew and Arabic as right to left and Latin, Greek and Cyrillic as left to right. Other scripts fall back to left to right, which is right for every script Goodmail ships.

### Outgoing HTML (`Draft`, `RichTextSerializer`)

- [x] Composed paragraphs are written as `<div dir="auto">`, so recipients' clients lay each one out in its own direction.
- [x] Known trade-off, kept: the reply quote uses Gmail's exact markup, with `border-left` and `padding-left`, because Outlook desktop and older clients ignore logical properties. A Hebrew quote shows its bar on the left, as Gmail's own replies do.

## Needs a device

These can only be confirmed in the simulator or on a phone with the language set to Hebrew. Run them on the Mac before each release.

- [ ] Every screen in Hebrew: mailbox list, thread, compose, search, Move To, label picker, settings, welcome, widget. Nothing truncates or overlaps, and nothing English remains apart from the brand and Gmail.
- [ ] Reply, Reply All and Forward icons mirror in Hebrew. `arrowshape.turn.up.left` and its relatives are directional SF Symbols and should flip on their own.
- [ ] Swiping a row left and right in Hebrew triggers the action shown on that side.
- [ ] The remove-account alert in Hebrew aligns right with the address first.
- [ ] A failed send in Hebrew shows the Hebrew reason. To trigger one, forward a message with an attachment, then delete the original on the web before the undo window closes.
- [ ] The compose screen's folded quote, a plain `UILabel`, reads correctly for a Hebrew quote in an English interface and the other way round.
- [ ] A Hebrew Outlook message (`<div class="WordSection1" dir="rtl">`), a Gmail Hebrew reply (`<div dir="ltr">` with Hebrew inside), and a mixed English and Hebrew newsletter all read correctly in the thread view.
