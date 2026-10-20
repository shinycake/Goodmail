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
- **Distribution:** personal use and TestFlight first, which means Google's OAuth Testing mode (up to 100 accounts).

## Data and privacy

- **Credentials** (OAuth tokens, iCloud app passwords) never leave the device. They live in the Keychain, shared with the app's extensions.
- **Offline-first:** a local cache, plus an outbox that queues actions while offline.
- **Telemetry:** none. MetricKit and Xcode Organizer only.

## Backend: Cloudflare Workers

The backend relays push and nothing else.

- **What it stores:** the account → APNs device token mapping, kept in Durable Objects (SQLite). It holds no tokens and no mail.
- **Gmail:** a Pub/Sub push subscription calls the Worker, which sends a content-free APNs push. The Notification Service Extension fetches the message on the device.
  - Watches expire every 7 days, so the device renews them (app launch, background refresh, extension runs).
- **Outlook:** a Graph change-notification webhook calls the Worker, which pushes the same way. The device renews subscriptions.
- **iCloud:** a user-configured forwarding rule sends a copy to a per-account address handled by a Cloudflare Email Worker.
  - The Worker reads only the envelope recipient, discards the message unread, and pushes. The device fetches over IMAP.
  - If a header preview is ever needed, the Worker encrypts it straight away to a device-held key (HPKE). Nothing is stored or logged.
  - The Worker is to be open-sourced so this can be verified.
- **Testing caveat:** APNs needs HTTP/2, which works from deployed Workers but not from `wrangler dev`. Push tests run against a deployed preview.

## Engineering

- **Stack:** iOS 27, Swift 6.4, Xcode 27.
- **Dependencies:** none from third parties unless truly needed. Each one needs the owner's approval and an ADR.
- **Testing:** TDD for logic, using Swift Testing against recorded API fixtures.
- **Workflow:** Claude works autonomously. Each change ships as a PR whose evidence (tests, screenshots, recordings) is what the owner reviews.

## Prerequisites the owner must set up

- Apple Developer Program, which blocks push, TestFlight and the default-mail-app entitlement
- A domain for Goodmail (push relay, OAuth pages, forwarding addresses)
- A Cloudflare account
- A Google Cloud project: OAuth client, Gmail API, Pub/Sub (likely needs billing enabled; usage fits the free tier)
