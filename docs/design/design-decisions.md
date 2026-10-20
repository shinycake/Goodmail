# Design decisions

The owner decided these on 2026-10-20 after reviewing mockups. The design will be refined further during the build. They build on [../product-brief.md](../product-brief.md) and [../architecture/decisions.md](../architecture/decisions.md).

## Thesis

**Letters, not tickets.** Goodmail should feel like reading your post, not working through a queue. We use vanilla UIKit components with taste, and we don't copy Apple Mail.

**The content is the hero, and the chrome recedes.** Before shipping any screen, ask what the user cares about here (who wrote, what about, the message itself) and what's background noise. Remove the noise or quiet it down.

- **Felt speed.** Everything is instant and every action updates the screen immediately. No spinner where data could already be on screen.
- **Liquid Glass throughout:**
  - controls float as glass capsules and circles over content that scrolls underneath
  - sheets float inset with large corner radii
  - on iPad, the sidebar is a floating glass panel
- **Typography:**
  - New York (system serif, `UIFontDescriptor.withDesign(.serif)`) for large titles, subjects and message bodies
  - SF Pro for names, times, metadata and controls
  - Dynamic Type throughout
- **Motion and haptics** confirm actions and never decorate. SF Symbol effects provide the delight moments.
- **RTL indistinguishable from native.** Mixed Hebrew/English content renders correctly, and gestures and animations mirror.

## Color

There's one main color: the account's theme color. Everything else is neutral.

- **Single-account views:** the theme color appears only on the large title, nav controls, unread badges and the primary action (Compose, Reply, the full-swipe action).
- **Unified views:** a blend of all account colors (a gradient, or an animated `MeshGradient`) on the title and Compose.
  - The one exception: unread badges keep their own account's color, so you can tell where a message belongs.
- **Red is only for destructive actions:** Trash and Delete in swipes, toolbars and menus.
- **Avatars:** neutral gray monograms, or the contact photo when Contacts access is granted. Never rainbow colors.
- **Icons and attachments:** neutral glyphs, never colored file-type icons.

## Structure

- **iPhone:** a pushed stack. Sidebar → mailbox → thread.
- **iPad and wide windows:** three columns.
  - a floating glass sidebar
  - the message list
  - a reading pane, which caps the letter at a readable width (`readableContentGuide`) and centers it
- **Adaptation:** `UISplitViewController` with trait changes, never device lists. As the window narrows, the sidebar collapses behind its toggle, then the layout becomes the iPhone stack.
- **Sidebar:** All Inboxes first, then a collapsible section per account. Each section has Inbox, Starred, Sent, Drafts, Archive (All Mail), Spam, Trash, then the user's labels.
  - The account appears as a small dot in its theme color beside the account name. Mailbox icons are neutral.
  - The selected row has a neutral highlight.
- **Gmail categories:** a compact glass "Primary ▾" menu pill in the inbox's top bar (Primary / Promotions / Social / Updates / Forums), defaulting to Primary. It can be turned off per account.
- **Stars, as in Gmail:** a star glyph. The Important marker is subtle.

## Bars and search

- **Top:** glass circle and capsule controls float over the content: the sidebar toggle or back button, and the category menu.
- **Bottom on iPhone:** a glass search icon on one side and Compose on the other. There is no permanent search bar.
- **Search:** tapping the icon expands search.
  - The field rises above the keyboard.
  - Recent searches appear as glass tokens (`from:maya`, `has:attachment`).
  - Top hits come first, with the matched term emphasized.
- **iPad:** search is a glass icon in the list column's toolbar.

## Message list

- **Sections by time of day:** This morning, Yesterday, Last week… The headers are quiet sentence-case labels.
- **Rows:**
  - sender in SF, with unread rows semibold
  - subject in New York
  - a 2-line preview by default, adjustable from 0 to 5
- **The account badge** in the theme color sits on the avatar's top corner, and appears only while the message is unread.
- **Swipe actions are separate glass buttons**, revealed as the row slides aside. Never colored blocks.
  - Trailing: More (neutral glass), Trash (glass, red glyph), Archive (solid theme color, the full-swipe action).
  - Leading: Read/Unread (theme color, the full-swipe action), Star (neutral glass).
  - Haptic on commit, mirrored in RTL. No configuration in v1.
- **Empty inbox:** `UIContentUnavailableConfiguration` with an SF Symbol effect and warm, time-aware copy ("All caught up. Nothing new since 17:10."). If another category has unread mail, a link points there.

## Thread view

- **Header:** the subject in large New York type, with a quiet metadata line (account · labels · number of letters).
- **Older messages:** a slim timeline of one-line summaries ("Dan — Can we pull push earlier?").
- **The newest or first unread message:** a rounded card, with the body in New York.
- **Order:** chronological, oldest to newest, and the view opens on the first unread message. Quoted text is folded.
- **Toolbar:**
  - one neutral glass group with Archive, Trash (red glyph), Label and More
  - Reply as the single prominent capsule in the thread's account color
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
- **Look:** a floating inset sheet. The From chip and the Send button take the sending account's color, and the formatting bar is glass.

## Notifications

- **Default:** every new inbox message notifies. Per account: All / Primary only / None.
- **Grouping:** notifications are grouped by thread.
- **Actions:** Archive, Reply, Mark Read, Trash. These are App Intents running `MailCommands` (ADR-011/012).
