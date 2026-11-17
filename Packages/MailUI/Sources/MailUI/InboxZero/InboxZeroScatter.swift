import CoreGraphics

extension Doodle {
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
