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
| Attachment download spinner | ⏭ | `showsActivityIndicator` isn't announced. Proposal: set `accessibilityValue` to "Downloading" while it spins. |
| Quoted text fold in the reader | ✅ | A `<details>`/`<summary>` with an `aria-label`, so WebKit reports expanded and collapsed itself. |
| Quoted text fold in compose | 🔧 | The "•••" button always said "Show Quoted Text". It now says "Hide Quoted Text" once open. |
| Compose fields | ✅ | To, Cc, Bcc and Subject fields are labelled by their row title; the body is "Message"; From reads "From: address". |
| Recipient suggestions | ⏭ | They appear under the field silently. Proposal: post `.layoutChanged` pointing at the first suggestion, or an announcement with the count. |
| Undo toast (`UndoToastView`) | ✅ / ⏭ | Its message is announced when it appears, and Undo is a button. But it leaves after 5 seconds, which is short for a VoiceOver user to reach Undo. Shake still undoes. Proposal: keep it while VoiceOver runs (`UIAccessibility.isVoiceOverRunning`), or make the two-finger double tap (Magic Tap) undo while it shows. |
| Inbox category pill | ✅ | "Inbox category: Primary"; the menu lists unread counts as subtitles. |
| Label picker | ✅ | Each label carries its state (On, Off, Some) as the value. |
| Move picker | ✅ | Rows carry the button trait. |

## Dynamic Type (up to AX5)

| Area | Status | Notes |
| --- | --- | --- |
| Fonts | ✅ | Every label uses a text style or `Typography`, which scales New York with `UIFontMetrics`, and sets `adjustsFontForContentSizeCategory`. The category pill scales its 15 pt font with `UIFontMetrics`. |
| Thread row size changes while open | 🔧 | `setContentText` bakes the font into the attributed text, which doesn't rescale on its own. The row now sets its text again when the size setting changes. |
| Thread row header at accessibility sizes | 🔧 | Sender and date sat side by side with the date unsqueezable, so a long name truncated to a few letters. At accessibility sizes the date now goes under the name (`stacksVerticallyAtAccessibilitySizes`). |
| Message card header at accessibility sizes | 🔧 | The same change for sender and date. |
| Thread history rows and message card labels after a size change | 📱 | Same baked-font pattern as the row. They are reconfigured whenever the thread updates; check that changing the size with a thread open rescales them, and give them the row's fix if not. |
| Thread history row at AX5 | ⏭ | Its summary is one line beside the date. Proposal: the same vertical stack and two lines. |
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
