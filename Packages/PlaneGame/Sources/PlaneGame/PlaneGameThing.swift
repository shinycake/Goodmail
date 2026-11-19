public import Foundation

// CGPoint and CGSize come with Foundation, and their Equatable conformances from CoreGraphics on Apple platforms.
#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// Something that comes at the plane: an obstacle to fly around, a bad guy to shoot, a hazard to dodge or a pickup
/// to catch.
public struct PlaneGameThing: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable, CaseIterable {
        case stamp, postmark, spam, phish, star, heart
        /// The power-ups: Reply All, Express, Bubble Wrap and Unsubscribe.
        case spread, rapid, shield, sweep
        /// What the Phisher casts.
        case lure
        /// What the Reply-All Storm fires, and the shots Out of Office sends back.
        case reply
        /// Bulk Mail, a heavy envelope that shelters what is behind it.
        case bulk

        /// The four power-ups.
        public static let powerUps: [Kind] = [.spread, .rapid, .shield, .sweep]
    }

    /// What a kind does when the plane or a shot meets it.
    public enum Role: Equatable, Sendable {
        /// Solid: shots stop on it and the plane has to fly around it.
        case obstacle
        /// Shot down after `hits` shots for `points`.
        case badGuy(hits: Int, points: Int)
        /// Caught by flying into it.
        case pickup
        /// Shots pass through it, so it has to be dodged. It costs a life and goes.
        case hazard
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
    /// Its own sideways speed, in points a second: how fast a lure spreads from the fan it was cast in.
    var drift: CGFloat

    init(id: Int, kind: Kind, position: CGPoint, drift: CGFloat = 0) {
        self.id = id
        self.kind = kind
        self.position = position
        self.drift = drift
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
        case .bulk: .badGuy(hits: 4, points: 40)
        case .star, .heart, .spread, .rapid, .shield, .sweep: .pickup
        case .lure, .reply: .hazard
        }
    }

    public var isPowerUp: Bool {
        Self.powerUps.contains(self)
    }

    /// How close a shot or the plane has to come to touch it.
    public var radius: CGFloat {
        switch self {
        case .stamp: 19
        case .postmark: 22
        case .spam: 16
        case .phish: 15
        case .star, .heart: 16
        case .spread, .rapid, .shield, .sweep: 15
        case .lure, .reply: 7
        case .bulk: 20
        }
    }
}

extension PlaneGameThing.Role {
    /// Obstacles and bad guys: a shot stops on them.
    var stopsShots: Bool {
        switch self {
        case .obstacle, .badGuy: true
        case .pickup, .hazard: false
        }
    }

    /// Bad guys and hazards: Unsubscribe and a beaten boss pop them.
    var pops: Bool {
        switch self {
        case .badGuy, .hazard: true
        case .obstacle, .pickup: false
        }
    }
}
