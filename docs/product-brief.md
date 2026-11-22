# Goodmail product brief

Decisions from the goal-definition phase, 2026-10-20. Architecture and the implementation plan build on this document.

## Why

- Apple Mail has no push for Gmail.
- Gmail's own app has ugly UI and poor UX.
- Other clients push AI and subscriptions, and are too complicated.

## Principles

Simple, beautiful, lean, performant, robust. Bring stability and delight. The highest craft and attention to detail.

## Product

- **Providers, in order:** Gmail (Gmail API) → Outlook (Microsoft Graph) → iCloud (IMAP/SMTP).
- **v1 is Gmail only**, with the provider abstraction in place from day one.
- **Gmail coverage:** comprehensive, prioritized by user value. v1 includes:
  - Core mail: inbox, threads, read, archive, delete, labels, server-side search, compose/reply/forward, attachments, signatures, undo send.
  - Multiple accounts with per-account colors, and a unified inbox.
  - Privacy: remote images and tracking pixels blocked by default.
  - System integration: default mail app (mailto), widgets, App Intents/Shortcuts, Spotlight, notification actions.
- **Snooze and scheduled send** aren't in the Gmail API, so they run on the device as best effort.
- **AI:** system-only. We get what iOS gives standard controls (for example Writing Tools) and build nothing of our own.
- **Platforms:** iPhone and iPad. Every window size, including resizable iPad windows and the foldable iPhone.
- **Design:** Goodmail's own soul and style, in Apple's design language with vanilla SwiftUI/UIKit components, following the HIG. The only customization is a theme and per-account colors.
- **Localization:** built on Apple tooling (String Catalogs, Xcode translation skills). English and Hebrew are polished at launch, and Hebrew is the reference for RTL. RTL support must be foundational, not retrofitted.
- **Distribution:** personal use and TestFlight first, with Google OAuth published "In production" but unverified (up to 100 accounts, an unverified-app warning at sign-in, ADR-009).

## Data and privacy

- **Credentials** (OAuth tokens, iCloud and IMAP app passwords) live in the Keychain, shared with the app's extensions. Two copies also go to the push relay, so it can tell when new mail arrives: each Gmail account's refresh token, and each iCloud or IMAP login. The relay keeps them encrypted and uses them only to look at the Inbox (see below).
- **Offline-first:** a local cache, plus an outbox that queues actions while offline.
- **Telemetry:** none. MetricKit and Xcode Organizer only.

## Backend: Cloudflare Workers

The backend relays push and nothing else. It never reads or stores mail.

- **What it stores:** which APNs device token to wake for which account, kept in D1 (SQLite). Addresses are stored only as keyed hashes. It also keeps the Gmail refresh token and the iCloud/IMAP logins it needs to look at the Inbox, encrypted with AES-GCM (decided 2026-11-16).
- **Gmail:** a Pub/Sub push subscription calls the Worker, which sends a content-free APNs push. The Notification Service Extension fetches the message on the device.
  - Watches expire every 7 days, so the device renews them (app launch, background refresh, extension runs).
- **Outlook:** a Graph change-notification webhook calls the Worker, which pushes the same way. The device renews subscriptions.
- **iCloud and other IMAP accounts:** the servers push to no one but Apple Mail, so the Worker watches the Inbox itself with the login the device registers. It keeps a connection open to each Inbox (IMAP IDLE, logging in again every 30 minutes) and pushes when the Inbox's UIDNEXT grows. For the alert it reads the sender, subject and flags of what arrived, never a body. The device fetches over IMAP.
  - Forwarding to a Cloudflare Email Worker was the earlier plan. It's kept as a fallback, since it would send a copy of every message through the relay (research in the project files, 2026-11-16).
- **Testing caveat:** APNs needs HTTP/2, which works from deployed Workers but not from `wrangler dev`. Push tests run against a deployed preview.

## Engineering

- **Stack:** iOS 27, Swift 6.4, Xcode 27.
- **Dependencies:** none from third parties unless truly needed. Each one needs the owner's approval and an ADR. Approved so far: GRDB (ADR-001).
- **Testing:** TDD for logic, using Swift Testing against recorded API fixtures.
- **Workflow:** Claude works autonomously. Each change lands on main with its evidence (tests, screenshots, recordings) shown in its thread, which is what the owner reviews.

## Prerequisites the owner must set up

- Apple Developer Program, which blocks push, TestFlight and the default-mail-app entitlement
- A domain for Goodmail (push relay, OAuth pages, forwarding addresses)
- A Cloudflare account
- A Google Cloud project: OAuth client, Gmail API, Pub/Sub (likely needs billing enabled; usage fits the free tier)
