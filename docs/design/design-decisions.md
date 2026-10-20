# Design decisions

The owner decided these on 2026-10-20. They build on [../product-brief.md](../product-brief.md) and [../architecture/decisions.md](../architecture/decisions.md).

## Thesis

**Goodmail is Apple Mail's structure, made calmer and faster.** We don't invent new UI patterns. Goodmail's character comes from:

- **Felt speed.** Everything is instant and every action updates the screen immediately. No spinner where data could already be on screen.
- **Typography and rhythm.** Careful spacing, hierarchy and density with system fonts and Dynamic Type.
- **Account color.** A quiet thread through the app, not decoration.
- **Motion and haptics.** They confirm an action (archive, send, undo) and never decorate.
- **RTL indistinguishable from native.** Mixed Hebrew/English content renders correctly, and gestures and animations mirror.

Use the iOS 27 design language (Liquid Glass bars, sidebars and sheets) as standard UIKit components provide it. Follow the HIG.

## Structure

- **Sidebar (Apple Mail model):**
  - All Inboxes first.
  - Then a collapsible section per account: Inbox, Starred, Sent, Drafts, Archive (All Mail), Spam, Trash, then the user's labels nested beneath.
- **Layouts:**
  - iPad and wide windows: three columns.
  - Narrow windows and iPhone: a pushed navigation stack.
  - The layout adapts continuously to window size, never to a list of devices.
- **Gmail categories:** a segmented category bar at the top of the Inbox (Primary / Promotions / Social / Updates).
  - Primary is the default, and each category shows its unread count.
  - The bar can be turned off per account.
- **Stars, as in Gmail:** a star glyph, with no translation into flags. The Important marker is shown subtly.

## Account color

Account color appears in four places:

1. the unread dot in unified views
2. the account glyph or monogram in the sidebar and account switcher
3. a tinted "From" chip in compose
4. the window tint while viewing a single account

Unified views use the app tint.

## Message list

- **Avatars:** the contact photo if the sender is in Contacts (permission asked for only when enabled), otherwise a tinted monogram. A setting hides avatars.
- **Preview:** 2 lines by default, adjustable from 0 to 5.
- **Swipe actions:** several per side, and a full swipe runs the outermost one. No configuration in v1.
  - Leading: Read/Unread (full swipe), Star.
  - Trailing: Archive (full swipe), Trash, More….
  - More… opens Move/Label, Mute, Snooze, Spam.
  - Haptic on commit, and mirrored in RTL.

## Thread view

- **Order:** chronological, oldest to newest. Read messages collapse to a one-line header, and the view opens on the first unread message.
- **Quoted text:** folded.
- **Rendering:** one web view per message (ADR-003), with remote content blocked until the user allows it.

## Compose

- **Formatting:** full formatting, because compose is a core experience and must be superb. Fonts, sizes, colors, bold/italic/underline/strikethrough, alignment, lists, links, quote levels, inline images.
- **Attachments:** from Files, Photos, camera and document scan.
- **Signatures:** from Gmail's send-as settings.
- **Editor architecture:**
  - Your own text is written in a native `UITextView` (TextKit 2), which brings native selection, dictation, Writing Tools and RTL.
  - The quoted original of a reply or forward is kept as an untouched HTML block, shown read-only and sent byte-for-byte. You can remove or trim it, but not edit inside it.
  - We own a clean serializer from formatted text to email-safe HTML.
  - Rejected: a contenteditable web editor (not native in feel, a large JS surface); converting the quote into editable text (lossy).
- **Recipient autocomplete:**
  - addresses learned from local mail
  - iOS Contacts, if allowed
  - Google contacts and "other contacts" through the People API, which adds the sensitive scopes `contacts.readonly` and `contacts.other.readonly`
- **Undo send:** 10 s by default, adjustable to Off, 5, 10, 20 or 30 s.
- **Feel:** a subtle send haptic, and the system send and new-mail sounds.

## Notifications

- **Default:** every new inbox message notifies. Per account: All / Primary only / None.
- **Grouping:** notifications are grouped by thread.
- **Actions:** Archive, Reply, Mark Read, Trash. These are App Intents running `MailCommands` (ADR-011/012).
