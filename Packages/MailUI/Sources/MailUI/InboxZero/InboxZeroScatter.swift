import CoreGraphics

nonisolated extension Doodle {
    /// A ring around the envelopes and the words under them: the welcome screen's, with two fewer and the rest
    /// spaced out for a taller field.
    static let inboxZero: [Doodle] = [
        .init(.envelope, x: 0.13, y: 0.07, size: 32, angle: -14, tint: 0),
        .init(.sparkle, x: 0.36, y: 0.02, size: 15, angle: 0, tint: 2),
        .init(.at, x: 0.60, y: 0.06, size: 25, angle: 10, tint: 1),
        .init(.plane, x: 0.87, y: 0.10, size: 32, angle: 0, tint: 2),
        .init(.heart, x: 0.07, y: 0.33, size: 21, angle: -12, tint: 2),
        .init(.stamp, x: 0.93, y: 0.37, size: 32, angle: 10, tint: 1),
        .init(.squiggle, x: 0.075, y: 0.60, size: 28, angle: -24, tint: 1),
        .init(.ring, x: 0.94, y: 0.63, size: 10, angle: 0, tint: 0),
        .init(.postmark, x: 0.14, y: 0.90, size: 38, angle: -8, tint: 0),
        .init(.cross, x: 0.37, y: 0.985, size: 10, angle: 20, tint: 2),
        .init(.sparkle, x: 0.61, y: 0.97, size: 14, angle: 0, tint: 1),
        .init(.star, x: 0.87, y: 0.89, size: 21, angle: -10, tint: 2),
    ]
}

nonisolated extension Doodle {
    /// Two columns of doodles to either side of the envelopes and the words, for a space too low for the ring above
    /// and below them, such as a landscape iPhone's. They keep to the outer sixth of each side, clear of the words.
    static let inboxZeroFlanks: [Doodle] = [
        .init(.envelope, x: 0.08, y: 0.14, size: 28, angle: -14, tint: 0),
        .init(.heart, x: 0.15, y: 0.50, size: 19, angle: -12, tint: 2),
        .init(.sparkle, x: 0.04, y: 0.62, size: 13, angle: 0, tint: 1),
        .init(.squiggle, x: 0.09, y: 0.90, size: 26, angle: -24, tint: 1),
        .init(.plane, x: 0.91, y: 0.12, size: 28, angle: 0, tint: 2),
        .init(.ring, x: 0.96, y: 0.40, size: 9, angle: 0, tint: 0),
        .init(.stamp, x: 0.85, y: 0.55, size: 28, angle: 10, tint: 1),
        .init(.star, x: 0.93, y: 0.88, size: 19, angle: -10, tint: 2),
    ]

    /// The doodles carrying on into the pane beside an empty Inbox, where no message is open: thickest by the list
    /// and thinning out toward the far side, a little smaller as they go, so they read as the ring spilling over
    /// rather than as a second field. `x` runs from the side next to the list.
    static let inboxZeroBeyond: [Doodle] = [
        .init(.sparkle, x: 0.03, y: 0.20, size: 14, angle: 0, tint: 1),
        .init(.envelope, x: 0.14, y: 0.08, size: 27, angle: 12, tint: 2),
        .init(.at, x: 0.09, y: 0.42, size: 23, angle: -8, tint: 0),
        .init(.heart, x: 0.22, y: 0.30, size: 18, angle: 10, tint: 0),
        .init(.star, x: 0.04, y: 0.66, size: 19, angle: 12, tint: 2),
        .init(.postmark, x: 0.20, y: 0.57, size: 31, angle: 6, tint: 1),
        .init(.squiggle, x: 0.13, y: 0.86, size: 25, angle: 18, tint: 2),
        .init(.ring, x: 0.36, y: 0.15, size: 9, angle: 0, tint: 1),
        .init(.stamp, x: 0.40, y: 0.44, size: 24, angle: -10, tint: 2),
        .init(.cross, x: 0.33, y: 0.74, size: 9, angle: 20, tint: 0),
        .init(.sparkle, x: 0.50, y: 0.93, size: 12, angle: 0, tint: 0),
        .init(.plane, x: 0.60, y: 0.27, size: 22, angle: -12, tint: 1),
        .init(.heart, x: 0.66, y: 0.66, size: 15, angle: -14, tint: 2),
        .init(.sparkle, x: 0.86, y: 0.45, size: 10, angle: 0, tint: 1),
        .init(.ring, x: 0.92, y: 0.84, size: 8, angle: 0, tint: 0),
    ]
}
