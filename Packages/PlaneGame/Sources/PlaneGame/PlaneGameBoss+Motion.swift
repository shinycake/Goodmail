import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// How a boss moves and attacks, in one place for every kind: each kind's own moves, waits and attacks are in its
/// own file, and this hands each step to them.
extension PlaneGameBoss {
    /// Moves it on by `dt` on `field`, with the plane at `planeX` and the world falling at `scroll`, and says what
    /// it sent. It attacks only while `attacking`, but its attacks are counted either way.
    mutating func advance(
        by dt: TimeInterval, towardX planeX: CGFloat, on field: PlaneGameField, scroll: CGFloat, attacking: Bool
    ) -> [Sent] {
        age += dt
        var sent: [Sent] = []
        switch status {
        case .arriving(let elapsed):
            let now = elapsed + dt
            status =
                now >= PlaneGameRules.bossArrival ? .fighting(sinceAttack: 0, attacks: 0) : .arriving(elapsed: now)
        case .fighting(let sinceAttack, let attacks):
            creep(by: dt, towardX: planeX, on: field, sinceAttack: sinceAttack, attacks: attacks)
            var since = sinceAttack + dt
            var made = attacks
            let wait = wait(before: attacks) / tempo
            if since >= wait {
                // What is over carries into the next wait, but never more than this step, so a wait that shortens
                // as the boss gets angrier can't fire a backlog on the frames after.
                since = min(since - wait, dt)
                if attacking {
                    sent = volley(
                        as: attacker(at: attacks), attack: attacks, towardX: planeX, on: field, scroll: scroll)
                }
                made += 1
            }
            status = .fighting(sinceAttack: since, attacks: made)
        case .falling(let elapsed):
            status = .falling(elapsed: elapsed + dt)
        }
        place(on: field)
        return sent
    }

    /// Puts it where its status says on `field`: sliding down to hover under the ceiling, then there, inside the
    /// lanes by its radius, every body of it. A resize comes through here too.
    mutating func place(on field: PlaneGameField) {
        let hover = field.ceiling + radius
        let lanes = field.lanes(inset: radius)
        switch status {
        case .arriving(let elapsed):
            let start = -radius
            let eased = 1 - pow(1 - min(max(elapsed / PlaneGameRules.bossArrival, 0), 1), 3)
            position = CGPoint(x: sway(0, reach: 0, on: field), y: start + (hover - start) * CGFloat(eased))
            copies = []
        case .fighting:
            switch kind {
            case .junk:
                position.x = junkGlide(on: field)
            case .overload:
                position.x = overloadGlide(on: field)
            case .mailingList:
                let places = mailingListPlaces(on: field)
                position.x = places[0]
                copies = places.dropFirst().map { CGPoint(x: $0, y: hover) }
            case .phisher, .storm, .outOfOffice:
                // They keep the x they crept to.
                break
            }
            position.y = hover
        case .falling:
            position.y = hover
        }
        position.x = lanes.clamping(position.x)
        copies = copies.map { CGPoint(x: lanes.clamping($0.x), y: hover) }
    }

    /// Seconds it has fought.
    var fightTime: TimeInterval {
        max(age - PlaneGameRules.bossArrival, 0)
    }

    /// The x `share` of the way from the middle of the lanes toward a side, -1 to 1, never farther than `reach`
    /// from the middle, so a glide is no faster in a wide window.
    func sway(_ share: Double, reach: CGFloat, on field: PlaneGameField) -> CGFloat {
        let lanes = field.lanes(inset: radius)
        let middle = (lanes.lowerBound + lanes.upperBound) / 2
        return middle + min(lanes.upperBound - middle, reach) * CGFloat(share)
    }

    /// Moves its x toward `target` by at most `speed` points a second over `dt`.
    mutating func head(toward target: CGFloat, speed: CGFloat, over dt: TimeInterval) {
        let reach = speed * CGFloat(dt)
        position.x += min(max(target - position.x, -reach), reach)
    }

    /// The kinds that creep do it here: the Phisher beside the plane, the Storm to its next post, Out of Office over
    /// the plane while its sign is up.
    private mutating func creep(
        by dt: TimeInterval, towardX planeX: CGFloat, on field: PlaneGameField, sinceAttack: TimeInterval,
        attacks: Int
    ) {
        switch kind {
        case .phisher: phisherCreep(by: dt, towardX: planeX, on: field, sinceAttack: sinceAttack)
        case .storm: stormDash(by: dt, on: field, attacks: attacks)
        case .outOfOffice: outOfOfficeCreep(by: dt, towardX: planeX, on: field)
        case .junk, .mailingList, .overload: break
        }
    }

    /// The time before attack number `attack`, at the first tier's tempo.
    private func wait(before attack: Int) -> TimeInterval {
        switch kind {
        case .junk: junkWait
        case .phisher: phisherWait
        case .storm: stormWait(before: attack)
        case .outOfOffice: outOfOfficeWait
        case .mailingList: mailingListWait
        case .overload: overloadWait
        }
    }

    /// Attack number `attack` as `attacker` makes it, from where this boss is, at this boss's level.
    private func volley(
        as attacker: Kind, attack: Int, towardX planeX: CGFloat, on field: PlaneGameField, scroll: CGFloat
    ) -> [Sent] {
        switch attacker {
        case .junk: junkDrop(on: field)
        case .phisher: phisherCast(on: field)
        case .storm: stormReplies(towardX: planeX, on: field, scroll: scroll)
        case .outOfOffice: outOfOfficeColleagues(on: field)
        case .mailingList: mailingListForwards(on: field, attack: attack)
        case .overload: overloadWall(on: field, attack: attack)
        }
    }
}
