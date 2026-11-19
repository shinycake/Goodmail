import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// The Reply-All Storm fires fans of replies aimed at where the plane is, then dashes to its next post and waits
/// there. Angry, it fires again in quick succession before it moves on.
extension PlaneGameBoss {
    /// How many more volleys follow each one in quick succession.
    var stormEchoes: Int {
        min(level, 2)
    }

    /// The post it heads for once it has made `attacks`: a golden-ratio walk across its reach, the same every game.
    func stormPost(after attacks: Int, on field: PlaneGameField) -> CGFloat {
        let post = attacks / (stormEchoes + 1)
        let share = (0.5 + Double(post) * PlaneGameRules.stormWalk).truncatingRemainder(dividingBy: 1)
        return sway(2 * share - 1, reach: PlaneGameRules.stormReach, on: field)
    }

    mutating func stormDash(by dt: TimeInterval, on field: PlaneGameField, attacks: Int) {
        head(
            toward: stormPost(after: attacks, on: field), speed: PlaneGameRules.stormDash * CGFloat(tempo), over: dt)
    }

    /// The long wait before the first volley of each burst, the short one before an echo.
    func stormWait(before attack: Int) -> TimeInterval {
        guard attack.isMultiple(of: stormEchoes + 1) else { return PlaneGameRules.stormEchoGap }
        return max(
            PlaneGameRules.stormReplyEvery - PlaneGameRules.stormQuicker * Double(level),
            PlaneGameRules.stormQuickestReply)
    }

    /// An odd fan of replies whose middle one lands where the plane is now, with the world falling at `scroll`.
    func stormReplies(towardX planeX: CGFloat, on field: PlaneGameField, scroll: CGFloat) -> [Sent] {
        let count = 3 + 2 * ((level + 1) / 2)
        let fall = max(scroll + PlaneGameRules.replyExtraSpeed * field.pace, 1)
        let flight = max((field.row - muzzle.y) / fall, PlaneGameRules.stormShortestFlight)
        let most = PlaneGameRules.stormMostAim
        let aim = min(max((planeX - position.x) / flight, -most), most)
        return fan(of: .reply, count: count, gap: PlaneGameRules.stormFan, around: aim)
    }
}
