# Device checklist

What the simulator can't cover. Everything else in the [accessibility audit](accessibility-audit.md) was checked there.
Use a TestFlight build on an iPhone, signed in to your real accounts. Each check takes a few minutes; note anything
that feels wrong in the thread or as an issue.

## Accessibility

1. **VoiceOver.** Turn it on (triple-click the side button if you set the shortcut). In the Inbox, swipe through a few
   rows and use the Actions rotor to archive one. Open a thread, double-tap a message header to fold it, open an
   attachment, then reply and send to yourself. Each element should read a sensible name, and nothing should be
   skipped or read twice.
2. **Undo toast with VoiceOver.** Archive a thread and try to reach Undo before the toast leaves (5 seconds). If you
   can't, say so: the fix is proposed in the audit.
3. **Voice Control.** Turn it on and say "Show names" in the Inbox, a thread and compose. Every button should have a
   name you can say. Try "Tap Archive" and "Tap Reply".
4. **Reduce Motion.** Turn it on, archive a thread with a full swipe, and swipe a row open and let go. The toast
   should fade without sliding, and nothing should bounce.
5. **Largest text.** Settings › Accessibility › Display & Text Size › Larger Text, at the maximum. Open a real
   newsletter: its HTML may not scale, which the audit leaves open.

## Accounts

6. **iCloud sign-in.** Add an iCloud account with an app-specific password made at account.apple.com. Type it
   yourself. The Inbox should fill, and a reply should arrive.
7. **Gmail and Outlook attachments.** Open a real thread with a PDF and a photo in each account. Both should open, and
   a large one should show progress.
