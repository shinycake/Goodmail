# Drafts pill, round 2: plan

Answers the owner's four notes on build 37:

1. Picking a card in the picker: the card grows into the composer.
2. To and from the pill: one smooth motion, fades allowed.
3. The search transition leaves a blank capsule hanging at the left.
4. The picker's cards grow out of the pill.

Written against `origin/main` at `f6db3e8`. Nothing here was run: every claim about how iOS 27 behaves is marked **[verify]** and has a line in the Mac checklist (section 7). Round 1's plan is `plan.md` beside this file; what it says still holds unless this one changes it.

## 0. The design in one page

- **One leg each way.** `lifting` and `draining` go, and the rest between legs with them. Minimize is one spring from the open card to the pill; open is one spring back. `Leg` has two cases, `opening` and `leaving`, and `ComposerStage.land` is still the only place a leg ends.
- **The card thins out over the real pill.** Over the 38% of the way nearest the pill, the whole card (surface, composer, shadow) goes from opaque to clear, and the real pill underneath shows through with its glass, icon and count. No look-alike of the pill is drawn, so the last frame is the real pill by construction.
- **The pill only changes under the full-size card.** On the way in, the pill counts the message from the moment the card sets off, while the open card still covers it. On the way out, it lets the message go when the card has landed open. Neither needs a signal from the middle of an animation, which is what forced two legs in round 1.
- **The picker is a child of the shelf, not a modal.** It sits over the mail screens and under the composer's card, in the same coordinate space as both. Its cards grow out of the pill and fold back into it with their own animation.
- **A picked card becomes the composer.** The composer's card starts on the picked card's frame and grows from there in the same single spring, fading in over the picked card while the other cards fold back into the pill.
- **Search.** The blank capsule is UIKit's, born from the search button's own glass. No code of ours touches the bar during the transition. The fix is to give the search button a trailing group of its own; the plan has a ten-minute check that settles the cause on the Mac, and two fallbacks.

Two slices, landed separately (ADR-028): the search fix first (small, section 4), then the drafts motion (sections 1 to 3).

## 1. Item 2: one motion to and from the pill

Numbers are for a 402 × 874 iPhone. `O` is the open card `(0, 70, 402, 842)`. `P` is the pill's glass, about `(16, 796, 76, 44)`, measured at run time. `τ` is how far along the motion is, 0 at `O` and 1 at `P`.

### 1.1 Minimize

One `ScrubbedAnimation`, 0.5 s, damping 1, scrubbed by the finger and handed to the spring on release exactly as today.

| τ | Card frame, radius | Composer scale | Card opacity | What is on screen |
|---|---|---|---|---|
| 0 | `(0, 70, 402, 842)`, 38 | 1.00 | 1 | The drag begins (or Minimize is tapped). Before anything moves, the pill is told to count this message: it appears, or its count goes up by one, **under the open card**. The stage measures `P`. |
| 0.25 | `(4, 252, 320, 642)`, 34 | 0.80 | 1 | The live composer, scaled, clipped by the shrinking shape. Dimming at 0.75. |
| 0.50 | `(8, 433, 239, 443)`, 30 | 0.59 | 1 | |
| 0.62 | `(10, 520, 200, 347)`, 28 | 0.50 | 1 | The card starts to thin. |
| 0.80 | `(13, 651, 141, 204)`, 25 | 0.35 | 0.53 | The pill shows through the card's lower leading corner, already with its new count. |
| 0.90 | `(14, 723, 109, 124)`, 24 | 0.27 | 0.26 | The card's outline is closing on the pill's. |
| 1 | `(16, 796, 76, 44)`, 22 | 0.19 | 0 | Only the pill. `land`: the card is hidden, the shelf marks the message minimized (the pill already shows it, so nothing on screen changes), the icon bounces once. |

- **What fades:** `card.alpha`, the whole `ComposerCardView` as one group, so the composer never shows through its own surface. Nothing else: the pill, its icon and its count are the real ones and never change opacity.
- **Curve:** the frame, radius, scale, dimming and opacity are keyframes of one animation, so they share one curve whatever the finger or the spring does. Opacity is linear in `τ` from 0.62 to 1. Under the finger, `τ` is the finger's travel over 726 points, so the card starts to thin when the finger is about 450 points down. Programmatic, the spring is critically damped: the thinning runs from roughly 0.12 s to 0.35 s and ends with the shape. **[verify]**
- **No rest.** There is no frame where an opaque chip sits on the pill.
- **Let go short:** the spring runs back to `O`, opacity back to 1. On landing back, the pill stops counting the message, under the open card. `composer.stayed()` as today.
- **How the pill's change is hidden:** it happens at τ = 0, in the same run-loop turn the drag begins, inside `performWithoutAnimation`, when the card is opaque and `O` contains `P`. A rectangle moving linearly from `O` to `P` contains `P` all the way, so the pill stays covered until the card thins, and by then it is already right.
- `Fade.share = 0.38` and `Timing.pill = 0.5` are the two knobs.

### 1.2 Open, one draft (tap the pill)

The same backward, never under a finger.

| τ (from the pill) | Card | Opacity | What is on screen |
|---|---|---|---|
| 0 | at `P`, radius 22, composer at 0.19 | 0 | Tap. The card is put on the pill, clear. The pill is untouched and still says 1. |
| 0 → 0.38 | grows to `(10, 520, 200, 347)` | 0 → 1 | The card comes up over the pill as it grows out of it. |
| 0.38 → 1 | grows to `O`, radius 38 | 1 | The opaque card, growing. The pill is under it. |
| 1 | `O` | 1 | `land`: the pill lets the message go (it hides) under the open card; `composer.didOpen()` brings the keyboard. |

`reopen()` already changes the shelf at the tap and defers `shelfChanged()` to the `undocked` closure. The only change is when the stage calls it: on landing instead of after the lift.

### 1.3 Everything else

- **No pill on show** (a thread is pushed, selecting, searching): unchanged. The card shrinks out through the bottom-leading corner with no fade, `docked()` on landing. Opening with no pill on show grows from the corner.
- **Discard, Send, Delete, Save:** unchanged, the card slides down.
- **Reduce Motion:** slides as today. One change: `undocked()` runs on landing here too, so the stage has one rule. The card rising from below covers the toolbar before it lands.
- **Rotation mid-motion:** `settleEverything()` as today; with one leg per motion it has less to walk.
- **Right to left:** nothing new; `P` is measured.
- **Corners:** the card keeps `.continuous` corners throughout. The switch to `.circular` existed so an opaque chip matched the capsule exactly; the card is clear by then now. `ComposerCardView.cornerCurve` is deleted.

### 1.4 Wide windows (iPad, a large iPhone sideways)

The open card is 720 wide and centred, so it does not cover the pill. The pill's change is therefore seen there: it appears (or counts one more) when the drag begins and goes back if the drag is let go short; on opening it keeps its count until the card has landed, then hides. The card still thins out over the pill at the end of a minimize and comes up over it at the start of an open. This is open question 1.

## 2. Item 4: the picker grows out of the pill

The picker is the existing `DraftPickerViewController`, with the same cards, blur, scrolling and New Message button. It stops being a modal: the shelf adds it as a child, just under the stage's dimming. Layout at rest is today's: on the 402 × 874 iPhone with two drafts, the front card (last written) at `(16, 454, 370, 300)`, the one behind at `(16, 304, 370, 300)` showing its top 150 points, New Message centred above the bottom safe area.

The pill does not change while the picker is up. It keeps its count behind the blur, as in build 37; the cards come out of it and go back into it.

**Tucked** means a card scaled to the pill's width about its own centre and moved so its centre is the pill's centre (a transform; the card's layout is untouched). For a 370-wide card and a 76-wide pill that is a scale of 0.205.

### 2.1 Fan out (tap the pill holding several)

One animation, 0.45 s, damping 1, not interactive.

| τ | Cards | Blur | New Message |
|---|---|---|---|
| 0 | All tucked in the pill, opacity 0. The scroll view stops clipping, so cards can be seen below it where the pill is. | none (`effect = nil`) | moved down off the bottom edge |
| 0 → 0.3 | Each card's opacity goes 0 → 1 over its first 30%. The front card starts at τ = 0; each card behind starts 0.05 later, at most 0.25 later in all, so they deal out from behind the front one. | coming in | rising |
| 0 → 1 | Each card's transform goes to identity: the front card to `(16, 454, 370, 300)`, the next to `(16, 304, 370, 300)`, and so on up. | reaches `.systemUltraThinMaterialDark` | reaches its place |
| 1 | Laid out. The scroll view clips again. | | |

- Nothing glass changes opacity: the blur comes in by animating `effect`, and the New Message glass button moves, it doesn't fade. Only the cards (plain views) fade.
- Taps count from the first frame. A tap on a card or outside during the fan settles the fan at its end first (`settleNow()`), then acts.
- VoiceOver: the picker's view is `accessibilityViewIsModal`, and `.screenChanged` is posted with the front card's title once it is in.

### 2.2 Fold back (tap outside, VoiceOver escape, or a route that needs the mail screens)

One animation, 0.4 s, damping 1.

| τ | Cards | Blur | New Message |
|---|---|---|---|
| 0 | Laid out. The scroll view stops clipping. Touches off. | full | in place |
| 0 → 1 | Transforms go to tucked, the cards behind leading by 0.05 each. | going | dropping |
| 0.7 → 1 | Opacity 1 → 0. | | |
| 1 | The picker is removed from the shelf; `then` runs. The pill was never touched. | none | gone |

If no pill is on show when a fold starts (it can't be at a fan), the cards tuck into `DraftsPillPlacement.corner` instead, as a card leaving with no pill does.

## 3. Item 1: a picked card grows into the composer

Tap the front card, "Lunch", at `F = (16, 454, 370, 300)`.

| When | Composer's card (stage) | Picker |
|---|---|---|
| Tap | `shelf.choose(id)`. The pill still says 2. The stage puts the card on `F`, radius 28, clear, the composer scaled to 0.92 and clipped to the card, so what would show is the composer's top: bar, To, Subject, the start of the body, close to what the picked card shows. Stage dimming at 0. | Any fan is settled. The fold starts with the picked card left out: it stays where it is, opaque. |
| τ 0 → 0.38 | Grows from `F` toward `O` and goes from clear to opaque: the summary on the picked card dissolves into the live composer in the same growing shape. At 0.38 it is `(10, 308, 382, 506)`, radius 32. | The other cards fold into the pill, the blur goes, New Message drops. |
| τ 0.38 → 1 | Opaque, grows to `O`, radius 38, composer scale 1. Dimming reaches 1. `O` contains `F`, so the picked card is covered from here on. | The fold lands at 0.4 s, under the card; the picker is removed. |
| Land (0.5 s) | The pill lets the message go, under the open card: it says 1. `composer.didOpen()`; the keyboard rises. | |

- It is the same `opening` leg as from the pill, with a different start frame and radius. One spring, no hand-off between two animations of the same shape.
- A card picked from behind the front one starts on its whole frame, above the others, so it comes to the front as it fades in.
- The other cards go back into the pill rather than away, because that is where they are: the pill counts them.
- The close button on a card, and New Message, behave as today; the picker goes by folding where it used to dissolve.
- Reduce Motion: the picker's cards fade in place (no transforms), and a picked message slides up from below as it does today.

## 4. Item 3: the blank capsule in the search transition

### 4.1 What the recording shows

From `search-transition-build37.mp4` stepped at 60 fps, 1.55 s to 2.15 s:

1. The search button is pressed: its disc brightens and swells to about 57 points.
2. Next frame: the sidebar button is gone, glass and all, with no animation, and the magnifier glyph is gone from the bright disc. One frame later Select is gone the same way.
3. The search field (dark glass, with a rim) starts growing leftward from behind the disc.
4. The bright disc stretches into a flat, bright capsule. Its right end stays on the field's leading end; its left end runs left twice as fast as the field's leading edge does (measured: width = 57 + the distance the field's edge has moved). It leaves the screen at the left.
5. It parks from off screen to about x = 95 and stays, still bright, under the field's leading end, until the frame the field takes focus, where it vanishes at once.

So the capsule is **born from the search button's own glass, in its pressed (brightened) state**. It never comes from the sidebar button's place, whose glass is already gone in step 2.

### 4.2 What the code rules out

Nothing of ours is in the navigation bar or changes it during the transition:

- `willPresentSearchController` and `didDismissSearchController` (`MailboxViewController+InboxZero.swift:88`) only call `lendInboxZero()`.
- The `viewWillLayoutSubviews` override that toggled `searchBarPlacementAllowsToolbarIntegration` was deleted in round 1; it is set once in `installSearch()` (`MailboxViewController.swift:191`).
- `leftBarButtonItems` is set only in `viewWillAppear` and `setEditing`, neither of which runs when search opens. The results screen's own list (`SearchResultsController.list`) does run `viewWillAppear`, but its `navigationController` is `nil` and its navigation item is not on show. **[verify]** with a breakpoint in `MailboxViewController.viewWillAppear` while tapping Search: it must not be hit for the list on screen.
- The drafts pill is in the toolbar and plays no part.

What is ours is the configuration that puts the bar on this path (`MailboxViewController.swift:129, 188–199`): the system's `searchBarPlacementBarButtonItem` placed by hand in the legacy `rightBarButtonItems` array, in the same implicit group as Select, with toolbar integration off. Placing that item in a navigation bar is new in the iOS 27 SDK and is the least-trodden part.

### 4.3 The cause, as far as it can be read from here

The bar hides "all other navigation bar content" when search opens. The search button shares its implicit group with Select. The group's glass for the button is not retired with the button: it is laid out again against the expanding field (the doubled leftward travel is what a frame worked out in the bar's coordinates and applied in the field's looks like) and is only removed when the transition completes. It is visible because it is stuck in its pressed look; unpressed dark glass on a dark list would hardly show.

That reading is consistent with every frame, but it is UIKit's internals seen from outside. The first step on the Mac settles it.

### 4.4 Settle it on the Mac first (ten minutes)

1. Simulator, dark mode, Debug ▸ Slow Animations. Tap Search, and capture the view hierarchy mid-transition (Xcode's Debug View Hierarchy). Find the view whose frame is the bright capsule. Note its class, which bar group it sits in, and whether it is the search item's or the leading group's.
2. Open search with ⌘F instead of a tap (`beginSearch`, no press). If the capsule is absent or dark, the stuck pressed state is what makes it visible.

### 4.5 The fix

**A. Give the search button a group of its own** (first choice; keeps Search just inside Select). In `MailboxViewController`, stop using `rightBarButtonItems` and set the trailing groups in the one place that already decides them:

```swift
/// The trailing groups while browsing: Select at the corner, Search just inside it. Each has a group of its own, so
/// opening search morphs the search button's glass alone.
private var browsingTrailingGroups: [UIBarButtonItemGroup] {
    var groups: [UIBarButtonItemGroup] = []
    if viewModel.actions != nil { groups.append(selectItem().creatingFixedGroup()) }
    if search != nil { groups.append(navigationItem.searchBarPlacementBarButtonItem.creatingFixedGroup()) }
    return groups
}
```

`viewDidLoad` sets `navigationItem.trailingItemGroups = browsingTrailingGroups`; `setEditing` sets `editing ? [done.creatingFixedGroup()] : browsingTrailingGroups`, still after the search controller is put back. **[verify]** the order (Search immediately inside Select in English and Hebrew; swap the two appends if not), that the capsule is gone opening and closing search, and that Select, Done and the sidebar button come back in place.

**If step 1 of 4.4 shows the capsule belongs to the leading group instead:** take the leading items away ourselves for the length of the search. `willPresentSearchController` sets `navigationItem.leftBarButtonItems = nil`; `didDismissSearchController` sets them back to `browsingLeadingItems` unless selecting. Both without animation.

**B. Fallback: let the system place the button.** Leave `searchBarPlacementBarButtonItem` out of the trailing items altogether. With toolbar integration off, the system puts the search button in the navigation bar itself, which is what the iPad list did before round 1. The order beside Select is then the system's. If it isn't "just inside Select", tell the owner with a screenshot before landing.

**C. Last resort, only if A and B both still show it:** the capsule is the system's morph on this device class and no placement avoids it. Replace the morph: our own magnifier button in the trailing items, and on tap put `search.searchBar` in the bar as the title view with a close button, swapping the items with a plain cross-fade; put them back on close. This changes how the field opens, so the owner is asked first (open question 2).

Whichever lands, add the line to `docs/design/design-decisions.md` only if the placement changed.

## 5. Architecture

All of it is UI state in `MailUI`, which defaults to `MainActor`. No tasks, no actors, no `Sendable` crossings. `DraftFan` is `nonisolated` pure geometry, as `DraftsPillPlacement` is. `MailCore` is untouched (`DraftShelf`, `CardDrag`).

### 5.1 Files

New:

| Path | Holds |
|---|---|
| `Packages/MailUI/Sources/MailUI/Drafts/DraftFan.swift` | `DraftFan`: the tucked transform and the cards' stagger |
| `Packages/MailUI/Sources/MailUI/Drafts/DraftCard.swift` | `DraftCard` and `UIColor.draftCard`, moved out of the picker's file unchanged (now internal) |
| `Packages/MailUI/Tests/MailUITests/DraftFanTests.swift` | |

Changed:

| Path | Change |
|---|---|
| `Drafts/ComposerStage.swift` | two legs, the thinning keyframe, `Origin.card`, the dock's new calls, `place(_:)` (5.3) |
| `Drafts/ComposerCardView.swift` | delete `cornerCurve`; corners always `.continuous`; the doc comment no longer says nothing changes opacity |
| `Drafts/DraftsDock.swift` | `expect()`, `turnAway()`, `land(_:)`, `spot(in:)` (5.2) |
| `Drafts/DraftsPillItem.swift` | `spot(in:)` only measures; `PillSpot.icon` goes |
| `Drafts/DraftsPillPlacement.swift` | delete `dot(at:)`, `dotSize` |
| `Drafts/DraftPickerViewController.swift` | a child, not a modal; `fanOut`, `fold`, `frame(of:in:)`, `settleNow` (5.4) |
| `Drafts/DraftShelfViewController.swift` | holds the picker as a child with an explicit state; `choose` hands the card's frame to the stage; `topPresenter` goes (5.5) |
| `Mailbox/MailboxViewController.swift` | trailing groups (4.5) |
| `Tests/MailUITests/DraftsPillTests.swift`, `DraftsPillPlacementTests.swift` | the dock's new calls; the dot's test goes |
| `GoodmailUITests/DraftsPillTests.swift` | section 6, step 8 |
| `docs/design/design-decisions.md` | "Bars and search": the composer thins out over the pill; several drafts fan out of it and a picked one grows into the composer |

Unchanged: `ScrubbedAnimation.swift`, `CardDrag.swift`, `Draft+Shelf.swift`, `ComposerHost.swift`, `MailboxViewController+DraftsPill.swift`, strings.

### 5.2 `DraftsDock` and `DraftsPillItem`

```swift
public final class DraftsDock {
    /// How many messages are minimized. Only `show` changes it.
    private(set) var count = 0
    private var title: String?
    /// Whether a card is on its way into the pill, which counts its message from the moment it sets off.
    private var isReceiving = false

    func show(_ minimized: [Draft])                 // as today; the pills show count + (isReceiving ? 1 : 0)
    /// A card set off for the pill: every pill counts its message from now, while the open card still covers it.
    func expect()
    /// The card came back: the pills stop counting its message.
    func turnAway()
    /// The card is in: `docked` marks its message minimized, and the pills go on showing what they showed.
    func land(_ docked: () -> Void)                 // isReceiving = false, without rendering; docked(); render
    /// Where the pill on show is in `view` as it shows now; `nil` when none is on show or placed.
    func spot(in view: UIView) -> PillSpot?
}
```

`count` and `isReceiving` are two independent facts (the shelf's and the stage's), every combination is valid, and one private `render()` turns them into what the pills show. `DraftsPillItem.show(_:title:)` already does nothing for an unchanged count, so `land` lays nothing out. `DraftsPillItem.spot(in:)` loses its `showing:` parameter and the show, measure, put-back dance: it measures the pill as it is.

### 5.3 `ComposerStage`

```swift
enum Origin {
    /// Out of the drafts pill, or its corner when no pill is on show.
    case dock(undocked: () -> Void)
    /// Out of a laid-out draft's card at `frame`, in the shelf's view, with corners of `cornerRadius`.
    case card(CGRect, cornerRadius: CGFloat, undocked: () -> Void)
    /// Below the screen, for a new message.
    case below
}
// `undocked` runs once, as the card lands open: the pill lets the message go under it.

private enum Leg {
    /// Onto the screen. `arrived` runs as it lands.
    case opening(arrived: () -> Void)
    /// Off the screen to `landing`.
    case leaving(Landing, landed: (Bool) -> Void)
}

private enum Landing {
    /// Onto the pill, thinning out over it. The pill already counts the message.
    case pill(PillSpot, docked: () -> Void)
    case offscreen(CGRect, docked: () -> Void)      // as today
    case away(CGRect)                                // as today
}

private enum Timing {
    static let slide: TimeInterval = 0.5            // below ↔ open, and away
    static let pill: TimeInterval = 0.5             // open ↔ the pill, its corner, or a laid-out card
}
/// The share of the way nearest the pill, or a laid-out card, over which the card thins out or comes up.
private static let fadeShare = 0.38
```

Resolving a landing is where the pill starts counting:

```swift
case .dock(let docked):
    if SystemAccessibility.reducesMotion { return .offscreen(below, docked: docked) }
    guard dock.shownPill != nil else { return .offscreen(corner, docked: docked) }
    dock.expect()
    if let spot = dock.spot(in: shelf.view) { return .pill(spot, docked: docked) }
    dock.turnAway()                                  // the toolbar hasn't placed it: nothing to aim at
    return .offscreen(corner, docked: docked)
```

The animation block of a leg that thins is one keyframe animation, so shape and opacity cannot drift apart:

```swift
UIView.animateKeyframes(withDuration: 0, delay: 0, options: [.calculationModeLinear]) {
    UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 1) {
        self.card.fit(target, cornerRadius: radius)
        self.dimming.alpha = 0
    }
    UIView.addKeyframe(withRelativeStartTime: 1 - Self.fadeShare, relativeDuration: Self.fadeShare) {
        self.card.alpha = 0
    }
}
```

Opening from the pill or a card is the mirror: the card is posed at the start frame with `alpha = 0`, and the second keyframe is `(0, fadeShare) { card.alpha = 1 }`. This is the pattern `ComposerStage` used before round 1 (`f6db3e8^`, keyframes inside the scrubbed spring), so it is known to scrub and to reverse. **[verify]** that the motion still eases like the slide does and is not constant speed; if it is, give the pill legs a cubic ease-out (`UICubicTimingParameters`) in `ScrubbedAnimation`'s initializer and keep the spring for the finger's release.

`land(arrived:)`, still the one place:

```swift
guard case .moving(let move) = motion else { return }
let composer = move.composer
switch move.leg {
case .opening(let arrived):
    assert(arrived, "An opening came back")
    rest(composer)                                   // card.alpha = 1, dimming 1, refit
    arrived()                                        // the pill lets the message go, under the open card
    composer.didOpen()
case .leaving(let landing, let landed):
    guard arrived else {
        if case .pill = landing { dock.turnAway() }  // under the card, back at full size
        rest(composer)
        return landed(false)
    }
    clear(composer)                                  // hides the card, then card.alpha = 1 for next time
    switch landing {
    case .pill(let spot, let docked):
        dock.land(docked)
        spot.pill.bounce()
    case .offscreen(_, let docked): docked()
    case .away: break
    }
    landed(true)
}
```

- `open(_:from:)`: `.below` as today. `.dock` with Reduce Motion: from `below`. `.dock` with `dock.spot(in:)`: start at the spot's frame, radius half its height, clear. `.dock` with no spot: from `corner`, opaque. `.card(frame, radius, _)`: start at `frame`, `radius`, clear. Every one passes its `undocked` (or `{}`) as `arrived`.
- `settleNow()` is `if case .moving(let move) = motion { move.animation.finishNow() }`; `settleEverything()` keeps its loop for a message that a landing opens.
- `clearLeftover()` also calls `dock.turnAway()` when the leg it drops is a `.leaving(.pill, …)`, so the pill can't be left counting a card that never landed.
- `func place(_ view: UIView)` inserts `view` just under the dimming: the picker's place.
- Deleted: `Leg.lifting`, `Leg.draining`, `lifting(…)`, `draining(…)`, `dotRadius`, `Timing.shrink/drain/lift/grow`, every `cornerCurve` assignment.

Pitfalls from round 1, and how this stands to each: `dock.expect()` and `dock.turnAway()` lay the toolbar out inside `performWithoutAnimation` before the animator is made or after it has ended, never while one is paused or running; nothing in an animation block touches a constraint; nothing is snapshotted.

### 5.4 `DraftPickerViewController` and `DraftFan`

```swift
nonisolated enum DraftFan {
    /// The transform that tucks a card at `card` into the pill at `pill`: scaled to the pill's width about the
    /// card's centre, its centre on the pill's.
    static func tucked(_ card: CGRect, into pill: CGRect) -> CGAffineTransform
    /// How far into the fan the card `index` places behind the front one starts: 0.05 each, 0.25 at most in all.
    static func delay(behind index: Int, of count: Int) -> Double
}
```

The picker:

- `init` no longer sets a modal style. `dimming` and `newMessage` become properties; `dimming.effect` starts `nil`. `view.accessibilityViewIsModal = true`.
- State, private, changed only by the three methods below and their landing:

```swift
private enum Motion {
    /// Laid out and still.
    case laidOut
    /// Coming out of the pill.
    case fanning(ScrubbedAnimation)
    /// Going back into it; `gone` runs once they are in.
    case folding(ScrubbedAnimation, gone: () -> Void)
}
```

```swift
/// Brings the cards out of the pill at `pill`, in the view's coordinates. Call once the view is laid out.
func fanOut(from pill: CGRect)
/// Sends the cards back into the pill at `pill`, all but `chosen`, which stays for the composer's card to grow
/// over. `gone` runs once they are in.
func fold(into pill: CGRect, leaving chosen: Draft.ID? = nil, gone: @escaping () -> Void)
/// Ends a fan or a fold at once, at its end.
func settleNow()
/// Where `id`'s card is in `view`, at rest.
func frame(of id: Draft.ID, in view: UIView) -> CGRect?
```

- Both motions are a `ScrubbedAnimation` run with no pan (`distance: 0`), the stage's idiom for a leg no finger drives, which brings `finishNow()` and one `landed` callback. The block sets `dimming.effect` plainly and the cards and the button in keyframes, each card's start delayed by `DraftFan.delay`.
- `scrollView.clipsToBounds` is `false` while fanning or folding and `true` laid out.
- `DraftCard` gains `let id: Draft.ID`, so `frame(of:in:)` and `fold(leaving:)` find a card without a second table, and `static let cornerRadius: CGFloat = 28` in place of the literal, for the stage's start pose.
- With Reduce Motion, `fanOut` and `fold` change only the cards' opacity and the blur.

### 5.5 `DraftShelfViewController`

```swift
/// The drafts laid out to pick from, over the mail screens and under the composer's card.
private enum Laid {
    case away
    /// Laid out, or coming out of the pill.
    case out(DraftPickerViewController)
    /// Going back into the pill, picked from or not.
    case returning(DraftPickerViewController)
}
private var laid = Laid.away
```

Only `showPicker()`, `closePicker(leaving:then:)` and the fold's landing assign it.

```swift
private func showPicker() {
    if case .returning(let old) = laid { old.settleNow() }      // lands, which removes it
    let picker = DraftPickerViewController(entries: shelf.entries.map(\.draft))
    …                                                            // the four callbacks, as today
    addChild(picker)
    picker.view.frame = view.bounds
    picker.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    stage.place(picker.view)
    picker.didMove(toParent: self)
    picker.view.layoutIfNeeded()
    laid = .out(picker)
    picker.fanOut(from: pillFrame)
}

private func closePicker(leaving chosen: Draft.ID? = nil, then next: (() -> Void)? = nil) {
    guard case .out(let picker) = laid else { next?(); return }
    laid = .returning(picker)
    picker.fold(into: pillFrame, leaving: chosen) { [weak self] in
        self?.remove(picker)                                     // willMove, removeFromSuperview, removeFromParent;
        next?()                                                  // laid = .away if it is still this picker's
    }
}

/// The pill on show, or its corner of the screen when none is.
private var pillFrame: CGRect { dock.spot(in: view)?.frame ?? corner }

private func choose(_ id: Draft.ID) {
    guard case .out(let picker) = laid else { return }
    picker.settleNow()
    let from = picker.frame(of: id, in: view)
    shelf.choose(id)
    guard let composer = shelf.writing?.composer else { return }
    closePicker(leaving: id)
    let undocked: () -> Void = { [weak self] in self?.shelfChanged() }
    stage.open(
        composer,
        from: from.map { .card($0, cornerRadius: DraftCard.cornerRadius, undocked: undocked) }
            ?? .dock(undocked: undocked))
}
```

- `shelfChanged()` after a choice moves into `undocked`, so the pill counts one fewer when the card has landed, not at the tap.
- `viewWillTransition` also settles the picker: `if case .out(let p) = laid { p.settleNow() }`, and the same for `.returning`.
- `open(_:)`, `uncover(then:)`, the New Message callback and `composerDidClose` keep calling `closePicker(then:)` as today; `then` now runs when the fold lands.
- `askToClose` still presents its sheet from the picker.
- `topPresenter` is deleted; nothing else used it.
- `corner` is `DraftsPillPlacement.corner(lane:bounds:rightToLeft:)`, as the stage computes it.

## 6. Implementation steps

Before anything: read `docs/review.md`, load `swift-testing-expert` (and `swift-concurrency` if anything beyond plain `MainActor` UI state turns up), and run `scripts/check --lint` once so the hooks are on. Tests come first where a step has logic.

**Slice 1: search**

1. On the Mac, do 4.4. Apply fix A (or the leading-items variant, or B) as the check decides. Add the UI test `testSearchOpensAndClosesLeavingTheBarAsItWas`: note the frames of Select, Search and the sidebar button; tap Search; the field exists; tap the close button; all three are back at the same frames. Record the transition at 60 fps before and after as the evidence. Review, `swift format`, `scripts/check`, land.

**Slice 2: the drafts motion**

2. **`DraftFan`.** Tests first in `DraftFanTests.swift`: `tucked` applied to the card's frame gives a rectangle as wide as the pill and centred on it, for a card left of, right of and above the pill; a card already the pill's width is only moved; `delay` is 0 for the front card, 0.05 for the next, and never above 0.25 however many there are, and 0 for a single card.
3. **The dock.** Tests first in `DraftsPillTests.swift`, with the stub site: `expect()` shows one more on every pill and unhides a pill at none; `turnAway()` puts it back; `show` while expecting shows the new count plus one; `land` whose `docked` shows one more draft leaves the pill's count as it was and tells the site of no change; `land` whose `docked` does nothing drops the extra one. Then `expect`, `turnAway`, `land`, `spot(in:)`, and `DraftsPillItem.spot(in:)` without `showing:`. Delete the dot and its test.
4. **The stage's two legs.** Rewrite `ComposerStage` as in 5.3 with `Origin.dock` and `.below` only. Delete `cornerCurve`. `scripts/ios-build`. The existing UI tests still pass unchanged.
5. **The picker as a child.** Move `DraftCard` to its file. `Laid`, `showPicker`, `closePicker`, `stage.place`, `fanOut`, `fold`, `settleNow`. Choosing still opens from the pill at this step (`closePicker { stage.open(… .dock …) }`), so the step stands on its own.
6. **Growing from the card.** `Origin.card`, `frame(of:in:)`, `fold(leaving:)`, the new `choose`.
7. **Edges.** Reduce Motion in the picker, the VoiceOver `.screenChanged`, rotation settling the picker.
8. **UI tests** in `GoodmailUITests/DraftsPillTests.swift`: the eight existing ones pass as they are. Add `testThePickerFoldsBackIntoThePill` (two drafts, tap the pill, tap above the cards, no `drafts.card` left, the pill says "2 Drafts") and, in `testSeveralDraftsArePickedFrom`, an assertion that the pill says "1 Draft" after the first pick is minimized and the second opened.
9. **Words.** `docs/design/design-decisions.md`; the doc comments on `ComposerStage`, `ComposerCardView`, `DraftShelfViewController` that describe the chip and the drain.
10. **Review and land.** The whole diff against `docs/review.md`, with subagents on the stage's state and re-entrancy and on the picker's. `swift format format -i -r Packages Goodmail`, rebase, `scripts/check`, the Mac checklist, land with the recordings in the thread.

## 7. Mac simulator checklist

`scripts/sim <purpose>`, then `scripts/cleanup --done`. iPhone 18 Pro, light and dark, English and Hebrew. Record at 60 fps and step through.

Search:

1. Tap Search: no blank capsule at any frame, opening or closing. Compare with the build 37 recording.
2. Select, Search and the sidebar button are at the same frames before and after a search, and after Select then Done. Search is immediately inside Select in both languages.
3. ⌘F and the Home Screen Search quick action open the field the same way.
4. iPad and a large iPhone sideways: the same.

Minimize and open:

5. Minimize without a finger (the grabber's VoiceOver action, or New Message while one is being written): no frame shows an opaque chip at rest on the pill. The card's opacity starts to fall when it is about half its width, and reaches zero as the shape reaches the pill.
6. The motion eases (fast start, soft landing), the same character as the slide. If it runs at constant speed, see 5.3.
7. The pill is never seen changing on iPhone: step from the first frame of a drag; when the card first shows anything through it, the pill underneath already has its new count.
8. Pull down slowly to the pill and hold: the card thins under the finger and comes back solid when pulled up again. Let go short from there: it returns, and once it is back the toolbar has no pill (or the old count).
9. Tap the pill with one draft: the card comes up over the pill and grows, no frame where the pill is gone and nothing is in its place. After it lands and is minimized again, the pill is right.
10. Compose doesn't move at any frame of any of this.
11. The keyboard leaving at the start of a minimize doesn't hold the card or flash over the pill worse than in build 37.
12. A thread pushed: reply, pull down: out by the corner as before, no fade.
13. Rotation mid-minimize and mid-open: ends at once, the pill right afterward, and never left counting one too many.

Picker:

14. Two drafts, tap the pill: both cards come out of the pill, the rear one from behind the front one; no card is cut off at the scroll view's bottom edge on the way; the blur comes in; New Message rises from the bottom edge and never looks washed out.
15. Tap outside: they go back into the pill; the pill never changed. Tap the pill again straight away: they come out again.
16. Tap a card mid-fan: it opens from where the card comes to rest, with no jump worth seeing.
17. Pick the front card: it grows into the composer in one motion; the others fold away; the picked card is never seen behind or beside the growing one. Pick the rear card: the same, coming to the front.
18. After a pick lands, the pill says one fewer; it did not change before the card covered it.
19. Five drafts: scroll, pick one near the top.
20. Close a card with its button until one is left: the last folds into the pill.
21. New Message from the picker: the cards fold, then the new message comes up.
22. Reduce Motion: cards fade in place; a picked message slides up.
23. VoiceOver: focus lands on the front card when the picker opens; the mail list can't be reached behind it; escape folds it.
24. iPad, 11-inch, both orientations: the fan and the fold aim at the list column's pill; a picked card grows to the centred composer; what the pill does is what question 1 settles.
25. Hebrew: the fan comes out of the pill at the bottom right.
26. `scripts/check` on the Mac, with the UI tests and the accessibility audit.

## 8. Open questions for the owner

1. **iPad and a sideways large iPhone.** There the composer sits in the middle and doesn't cover the pill, so the pill's change can't be hidden under it. The plan: the pill appears (or counts one more) the moment you start pulling the composer down, and goes back if you let go short; when a draft opens out of it, the pill keeps its count until the composer has finished opening. On an upright iPhone none of that is seen. Is that all right on iPad, or do you want something else there?
2. **Search, only if the clean fix fails on the Mac.** If giving the search button its own group doesn't remove the capsule, the next step moves the button to wherever the system puts it (possibly the other side of Select), and the step after that replaces the system's morph with a plain cross-fade into the field. Should either be shipped without asking, or do you want to see a recording first?
