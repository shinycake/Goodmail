import CoreGraphics

/// The dust a deleted row breaks into: the row's drawn content cut into small tiles, each released by a front that
/// sweeps across the row from one edge, then drifting up and away as it shrinks and fades. Pure geometry and timing,
/// so the effect can be checked without a screen; `DissolveView` plays it.
nonisolated struct DissolveField: Equatable, Sendable {
    struct Particle: Equatable, Sendable {
        /// The tile, in the row's coordinates.
        var frame: CGRect
        /// Seconds from the start until the tile lets go.
        var delay: Double
        /// Seconds the tile takes to drift away and fade once it has let go.
        var lifetime: Double
        /// How far the tile has moved when it is gone.
        var drift: CGVector
        /// The tile's turn, in radians, when it is gone.
        var rotation: CGFloat
        /// The tile's size when it is gone, as a share of its own.
        var scale: CGFloat
    }

    /// The edge the release front starts from.
    enum Edge: Sendable {
        case left, right
    }

    /// The smallest tile, in points: smaller reads as finer dust but costs more layers.
    static let minimumTile: CGFloat = 3
    /// Seconds the release front takes to cross the row.
    static let sweep = 0.3
    /// The longest a tile may wait past the front, so the edge it leaves is ragged rather than a straight line.
    static let jitter = 0.1
    static let lifetimes = 0.45...0.7
    /// Seconds from the start until the last tile is gone.
    static let duration = sweep + jitter + lifetimes.upperBound

    let tile: CGFloat
    let particles: [Particle]

    /// The particles for a row of `size`, at most `budget` of them. `hasContent` says whether a tile has anything
    /// drawn in it; empty tiles are left out, so the budget goes to the text. `seed` makes the scatter repeatable.
    init(
        size: CGSize, budget: Int, from edge: Edge, seed: UInt64, hasContent: (CGRect) -> Bool
    ) {
        var tile = Self.minimumTile
        var frames = Self.tiles(of: size, side: tile, where: hasContent)
        // Larger tiles until the visible ones fit the budget: coarser dust, never a stall.
        while frames.count > budget {
            tile += 1
            frames = Self.tiles(of: size, side: tile, where: hasContent)
        }
        self.tile = tile
        var random = SplitMix64(seed: seed)
        // The dust blows the way the front travels.
        let away: CGFloat = edge == .left ? 1 : -1
        particles = frames.map { frame in
            let fromEdge = edge == .left ? frame.midX : size.width - frame.midX
            let front = size.width > 0 ? Double(fromEdge / size.width) : 0
            return Particle(
                frame: frame,
                delay: front * Self.sweep + random.next(in: 0...Self.jitter),
                lifetime: random.next(in: Self.lifetimes),
                drift: CGVector(
                    dx: away * CGFloat(random.next(in: 24...110)),
                    dy: CGFloat(random.next(in: -72...12))),
                rotation: CGFloat(random.next(in: -1.6...1.6)),
                scale: CGFloat(random.next(in: 0.25...0.8)))
        }
    }

    private static func tiles(of size: CGSize, side: CGFloat, where hasContent: (CGRect) -> Bool) -> [CGRect] {
        var frames: [CGRect] = []
        var y: CGFloat = 0
        while y < size.height {
            var x: CGFloat = 0
            while x < size.width {
                let frame = CGRect(
                    x: x, y: y, width: min(side, size.width - x), height: min(side, size.height - y))
                if hasContent(frame) { frames.append(frame) }
                x += side
            }
            y += side
        }
        return frames
    }
}

/// A small seeded generator, so a field can be rebuilt exactly in tests.
nonisolated struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value spread evenly over `range`.
    mutating func next(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(1 << 53)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}
