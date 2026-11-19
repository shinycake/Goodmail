import Foundation

/// How angry a boss is: a tier angrier each time the roster comes round, and a level angrier each phase of its
/// fight. Every boss's attacks read `level` and `tempo`; at tier 0 Junk Mail and the Phisher fight as they always did.
extension PlaneGameBoss {
    /// How many times the roster has come round before it: 0 the first time.
    public var tier: Int {
        (max(number, 1) - 1) / Kind.allCases.count
    }

    /// How many phases its fight has: two for the first four bosses the first time round, three for everything later.
    var phases: Int {
        switch kind {
        case .junk, .phisher, .storm, .outOfOffice: tier == 0 ? 2 : 3
        case .mailingList, .overload: 3
        }
    }

    /// Which phase it is in, from 0: one more for each equal share of its hits it has lost.
    var stage: Int {
        min((hits - hitsLeft) * phases / max(hits, 1), phases - 1)
    }

    /// How hard it attacks, from 0: its tier and its phase together, at most `bossMostLevel`.
    var level: Int {
        min(tier + stage, PlaneGameRules.bossMostLevel)
    }

    /// How much faster it moves and attacks than the first time round: 1, then rising toward `1 + bossTempoGain`.
    var tempo: Double {
        let tier = Double(tier)
        return 1 + PlaneGameRules.bossTempoGain * tier / (tier + PlaneGameRules.bossTempoEase)
    }

    /// Whose attack its attack number `index` (from 0) is: its own, or one borrowed from the bosses after it in the
    /// roster, in turn. Inbox Overload sends its own wall and the other five bosses' attacks in turn. The others borrow
    /// nothing the first time round, every third attack the second time, and every other attack after that.
    func attacker(at index: Int) -> Kind {
        let roster = Kind.allCases
        if kind == .overload {
            return index.isMultiple(of: 2) ? .overload : roster[(index / 2) % (roster.count - 1)]
        }
        let every: Int
        switch tier {
        case 0: return kind
        case 1: every = 3
        default: every = 2
        }
        guard index % every == every - 1 else { return kind }
        let own = (max(number, 1) - 1) % roster.count
        return roster[(own + 1 + index / every) % roster.count]
    }
}
