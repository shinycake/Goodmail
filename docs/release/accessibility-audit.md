# Accessibility audit (M11)

The release pass over VoiceOver, Dynamic Type and Reduce Motion for the custom views in `MailUI`. Standard UIKit
controls (bar buttons, list cells, menus, alerts) are left to UIKit and only checked where we configure them.

Status: ✅ passes by reading the code · 🔧 fixed in this pass · 📱 needs a check on a device or simulator · ⏭ open,
proposed as a follow-up.

## VoiceOver

| Area | Status | Notes |
| --- | --- | --- |
| Thread row (`ThreadRow`) | ✅ | One element: "Unread, sender, subject, date, preview". The preview is left out when the row hides it. |
| Swipe actions (`SwipeActions`) | ✅ | VoiceOver reaches every leading and trailing action as a custom action on the cell (Actions rotor), so the gesture is never the only way. The glass buttons are labelled buttons for Voice Control and Switch Control. |
| Monogram (`MonogramView`) | 🔧 | Was read as loose initials ("DL") inside the message card. Now hidden: the name always sits beside it. |
| Message card header (`MessageCardView`) | 🔧 | The header folds the message on tap, but VoiceOver saw only separate labels with no way to fold. It is now one button: "sender, date, to …". The card's own `accessibilityLabel` did nothing (the card isn't an element) and is gone. |
| Thread history row (`TimelineRowView`) | ✅ | A button: "sender, summary, date". |
| Thread subject | ✅ | Marked as a header, so the rotor's Headings jump to it. |
| Attachments (`AttachmentListView`, compose capsules) | ✅ | "filename, size" buttons. Compose capsules open a menu with Remove. |
| Attachment download spinner | 🔧 | The button's value reads "Downloading" while it spins, in the reader and the chat (`showsDownloading`). |
| Quoted text fold in the reader | ✅ | A `<details>`/`<summary>` with an `aria-label`, so WebKit reports expanded and collapsed itself. |
| Quoted text fold in compose | 🔧 | The "•••" button always said "Show Quoted Text". It now says "Hide Quoted Text" once open. |
| Compose fields | ✅ | To, Cc, Bcc and Subject fields are labelled by their row title; the body is "Message"; From reads "From: address". |
| Recipient suggestions | 🔧 | VoiceOver says how many there are when the number changes, queued after the letter just typed, without leaving the field. |
| Undo toast (`UndoToastView`) | 🔧 | Its message is announced when it appears, and Undo is a button. It now stays 20 seconds while VoiceOver or Switch Control runs (`ToastTime`), and VoiceOver's two-finger double tap (Magic Tap) undoes while it shows. Shake still undoes. |
| Inbox category pill | ✅ | "Inbox category: Primary"; the menu lists unread counts as subtitles. |
| Label picker | ✅ | Each label carries its state (On, Off, Some) as the value. |
| Move picker | ✅ | Rows carry the button trait. |

## Dynamic Type (up to AX5)

| Area | Status | Notes |
| --- | --- | --- |
| Fonts | ✅ | Every label uses a text style or `Typography`, which scales the system font with `UIFontMetrics`, and sets `adjustsFontForContentSizeCategory`. The category pill uses `Typography` at semibold subheadline. |
| Thread row size changes while open | 🔧 | `setContentText` bakes the font into the attributed text, which doesn't rescale on its own. The row now sets its text again when the size setting changes. |
| Thread row header at accessibility sizes | 🔧 | Sender and date sat side by side with the date unsqueezable, so a long name truncated to a few letters. At accessibility sizes the date now goes under the name (`stacksVerticallyAtAccessibilitySizes`). |
| Message card header at accessibility sizes | 🔧 | The same change for sender and date. |
| Thread history rows and message card labels after a size change | 📱 | Same baked-font pattern as the row. They are reconfigured whenever the thread updates; check that changing the size with a thread open rescales them, and give them the row's fix if not. |
| Thread history row at AX5 | 🔧 | The date goes under the summary, which gets two lines, and the row sets its text again when the size changes. |
| `MonogramView` (40 pt, 15 pt initials) | ✅ | Fixed on purpose: decorative, hidden from VoiceOver, and the circle doesn't grow. |
| `ThreadRowMetrics` insets, `SwipeLayout` sizes | ✅ | Spacing and touch targets, not text. Swipe buttons are 60 pt, over the 44 pt minimum. |
| Swipe button symbols at AX5 | 📱 | The symbol uses the `.title2` text style inside a fixed 60 pt circle; check it still fits. |
| Message body | 📱 | Plain text and unstyled HTML use `-apple-system-body`, which follows the setting. HTML mail with pixel font sizes won't scale, and the quote fold uses a fixed 15 px font. Check a newsletter at AX5 and decide whether to scale the web view's zoom. |

## Reduce Motion

| Area | Status | Notes |
| --- | --- | --- |
| Undo toast | 🔧 | Slid and scaled up with a bounce. With Reduce Motion it now only fades (`Motion.entrance`, `Motion.bounce`). |
| Swipe buttons | 🔧 | The buttons follow the finger (direct manipulation, kept), but the full-swipe snap, the settle open and the press feedback bounced. They now settle without overshoot under Reduce Motion. |
| Compose Cc/Bcc reveal and quote fold | ✅ | Springs without bounce that only resize the layout. |
| Navigation, sheets, menus | ✅ | UIKit's own, which already follow the setting. |

## Simulator pass (2026-11-13)

Run on the iOS 27.2 simulator with the test-mail corpus filed into the Inbox (`-GoodmailSyntheticCorpus <repo>/TestMail`),
in English and Hebrew, at the default size and AX5, with `performAccessibilityAudit` and the accessibility tree on each
screen.

| Area | Result |
| --- | --- |
| Inbox, thread, compose at AX5 | Text scales and wraps; nothing clipped except what truncates by design (long recipients and subjects in compose). |
| Mailboxes list at AX5 | 🔧 Names broke mid-word beside the count. The count now moves under the name (#80). |
| Thread toolbar More menu | 🔧 The star showed with no name, and Reply was listed three times (#82). |
| Thread reader | Message header is one button, attachments read "name, size", the quote fold reads "Show Quoted Text". |
| Quote fold in the reader | ⏭ About 41 × 23 pt, under the 44 pt target. |
| Compose | Title, To, Cc/Bcc, Subject, attach and send are labelled; the reply mirrors correctly in Hebrew. |
| Reduce Motion | ✅ by reading the code: `Motion` removes the bounce from swipes and the toast, and the toast fades in place. The simulator can't show how it feels. |
| VoiceOver, Voice Control | Labels and traits checked through the accessibility tree. Gestures, the rotor and "Show names" can't be driven in the simulator. |

What still needs a real iPhone is in [device-checklist.md](device-checklist.md).

## Sweep (2026-11-17)

`GoodmailUITests/AccessibilityAuditTests` runs Xcode's accessibility audit (`performAccessibilityAudit`) on the inbox,
a classic thread, a chat thread with its tray open and shut, the composer, the mailboxes and Settings. It runs in
English at the default size and at AX5, and in Hebrew at AX5 in dark mode. It is part of `scripts/check` on the Mac,
so a regression fails the gate. Text scaling and clipping are audited only at AX5, where they show; at the default
size the audit only guesses at them. What the test lets through, and why, is in its `Tolerated` list. An audit that can't run, which happens on a Mac short of memory, is reported in
the screen's attachment and doesn't fail the test. On a simulator slimmed with simslim the dark run still draws light,
because the profile switches off whatever applies the appearance; run it on a stock simulator to see dark.

The first run found 79 issues. What changed:

| Area | Status | Notes |
| --- | --- | --- |
| Chat composer at AX5 | 🔧 | The …, + and Send circles clipped their symbols and the field read "Messa…". The bar now acts like a toolbar: symbols keep their size and show in the Large Content Viewer when held, and the field's text grows up to the first accessibility size. |
| Message header at AX5 | 🔧 | "to …" truncated after a name or two. The names now wrap, Details drops under them, and the line rescales after a size change. |
| Details / Hide | 🔧 | Took touches only on its text. It now takes them, and VoiceOver's focus, over a 44 pt square (`MinimumTargetButton`). |
| Voice Control names | 🔧 | Rows, message cards, headers, letters and attachments were named by their whole spoken label. They now answer to what they show first: "Tap Dana Levi", "Tap invoice.pdf". |
| Smart Invert | 🔧 | Sender photos, service logos and the transfer QR code keep their colors. |
| Reduce Motion | 🔧 | A chat reply's arrival and the minimized-drafts bar still bounced; both settle without overshoot now. |
| Hardware keyboard and Full Keyboard Access | 🔧 | Apple Mail's shortcuts: ⌘N, ⇧⌘N, ⌥⌘F in a list; ⌘R, ⇧⌘R, ⇧⌘F, ⌃⌘A, ⌘⌫, ⇧⌘U, ⇧⌘L in a thread; ⇧⌘D in the composer. Holding ⌘ lists the ones that work on the screen shown. The window offers them (`CommandRouting`), so they work with nothing focused. |
| Welcome screen | ✅ | The redesign (#258) swapped the white-on-blue buttons for glass ones. The audit covers the screen again, in English at AX5 and in Hebrew at the default size. The audit reports the glass buttons' labels as low contrast because it measures them against the glass's translucent layers; the screenshots show black on near-white, so that is tolerated for the `addAccount.` buttons. The title stops growing at AX2 so the buttons stay on screen, and the screen scrolls past that. |
| Navigation bar subtitle in a chat | ✅ | UIKit draws and sizes it; tolerated. |
| Avatar initials | ✅ | Fixed on purpose inside a fixed circle; tolerated. |
| Section headers and footers in Settings | ✅ | The system's own secondary gray, which the audit calls "nearly passed"; tolerated. Real contrast failures still fail. |

## Apple Watch (2026-11-17)

The same pass over `MailWristUI`, for the watch app and its watch face widget.

- ✅ Inbox rows read as one element: sender, subject, preview, time, with "Unread" and "Pinned" spoken for the dot and the pin.
- 🔧 Chat bubbles said nothing about who wrote them: the side and the color carried it. Each now starts with the sender, or "You" for the reader's own.
- 🔧 One-time codes read as one big number. The code card in a conversation and on the watch face now spell them digit by digit.
- 🔧 The watch face's dash before the iPhone has sent anything now reads "Waiting for iPhone", and the card's count reads "3 Unread" rather than "3".
- ✅ Swipe actions, More, Reply, quick replies and Undo are labeled buttons.
- ✅ Text uses text styles and the unread dot scales with `@ScaledMetric`. Codes use `minimumScaleFactor` so the longest fits on one line.
- 📱 The largest text size on the 42 mm watch, and Always On (the watch face hides sender, subject, preview and code while locked through `privacySensitive`).
