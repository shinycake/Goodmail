public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Something that comes at the plane: an obstacle to fly around, a bad guy to shoot or a pickup to catch.
public struct PlaneGameThing: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable, CaseIterable {
        case stamp, postmark, spam, phish, star, heart
    }

    /// What a kind does when the plane or a shot meets it.
    public enum Role: Equatable, Sendable {
        /// Solid: shots stop on it and the plane has to fly around it.
        case obstacle
        /// Shot down after `hits` shots for `points`.
        case badGuy(hits: Int, points: Int)
        /// Caught by flying into it.
        case pickup
    }

    public let id: Int
    public let kind: Kind
    public var position: CGPoint
    /// Degrees it has turned from upright.
    public var turn: Double
    /// Hits it can still take; meaningful for bad guys.
    public var hitsLeft: Int
    /// The x it arrived at, which weaving and swaying swing around.
    var lane: CGFloat
    /// Seconds since it arrived.
    var age: TimeInterval = 0

    init(id: Int, kind: Kind, position: CGPoint) {
        self.id = id
        self.kind = kind
        self.position = position
        turn = 0
        hitsLeft = if case .badGuy(let hits, _) = kind.role { hits } else { 0 }
        lane = position.x
    }
}

extension PlaneGameThing.Kind {
    public var role: PlaneGameThing.Role {
        switch self {
        case .stamp, .postmark: .obstacle
        case .spam: .badGuy(hits: 1, points: 10)
        case .phish: .badGuy(hits: 2, points: 25)
        case .star, .heart: .pickup
        }
    }

    /// How close a shot or the plane has to come to touch it.
    public var radius: CGFloat {
        switch self {
        case .stamp: 19
        case .postmark: 22
        case .spam: 16
        case .phish: 15
        case .star, .heart: 16
        }
    }
}
