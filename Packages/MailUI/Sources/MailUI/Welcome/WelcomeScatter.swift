import CoreGraphics

extension Doodle {
    /// A ring around the envelopes: along the top and bottom of the stage and down its sides, clear of the middle.
    static let welcome: [Doodle] = [
        .init(.envelope, x: 0.11, y: 0.10, size: 34, angle: -14, tint: 0),
        .init(.sparkle, x: 0.31, y: 0.06, size: 16, angle: 0, tint: 2),
        .init(.at, x: 0.50, y: 0.07, size: 26, angle: 10, tint: 1),
        .init(.star, x: 0.70, y: 0.05, size: 19, angle: 12, tint: 0),
        .init(.plane, x: 0.90, y: 0.11, size: 34, angle: 0, tint: 2),
        .init(.heart, x: 0.065, y: 0.37, size: 22, angle: -12, tint: 2),
        .init(.stamp, x: 0.93, y: 0.42, size: 34, angle: 10, tint: 1),
        .init(.squiggle, x: 0.07, y: 0.63, size: 30, angle: -24, tint: 1),
        .init(.ring, x: 0.95, y: 0.68, size: 10, angle: 0, tint: 0),
        .init(.postmark, x: 0.11, y: 0.90, size: 40, angle: -8, tint: 0),
        .init(.cross, x: 0.35, y: 0.95, size: 10, angle: 20, tint: 2),
        .init(.sparkle, x: 0.60, y: 0.95, size: 14, angle: 0, tint: 1),
        .init(.squiggle, x: 0.75, y: 0.91, size: 30, angle: 8, tint: 0),
        .init(.star, x: 0.91, y: 0.88, size: 22, angle: -10, tint: 2),
    ]
}
