import Foundation

/// How someone works the crush: when they press, bleed, add yeast, punch
/// down and chill. Doug at his best has a skill of 1; the cellar crew, a
/// little less. It drives the crew (`Winemaking.crew`), the autopilot the
/// screenshot tour uses, and the simulated players in the balance tests.
public struct CrushPlan: Sendable {
    /// 0 sloppy ... 1 spot on.
    public var skill: Double
    /// Bleed some juice off the reds for saignée rosé.
    public var saignee: Bool
    /// Where the wine goes at barrel-down: new oak only if the winery has it.
    public var split: VesselSplit

    public init(skill: Double, saignee: Bool = false, split: VesselSplit) {
        self.skill = min(1, max(0, skill))
        self.saignee = saignee
        self.split = split
    }

    /// All of it into one kind of vessel.
    public init(skill: Double, saignee: Bool = false, vessel: Vessel = .neutralOak) {
        self.init(skill: skill, saignee: saignee, split: .only(vessel))
    }

    /// The cellar crew: decent, never inspired.
    public static func crew(saignee: Bool, split: VesselSplit) -> CrushPlan {
        CrushPlan(skill: 0.55, saignee: saignee, split: split)
    }

    public static func crew(saignee: Bool, vessel: Vessel) -> CrushPlan {
        crew(saignee: saignee, split: .only(vessel))
    }

    /// The split for this wine, with what the winery has.
    func split(for w: Winemaking) -> VesselSplit {
        w.harvest.style == .rose ? .only(.stainless) : split.available(in: w.vessels)
    }

    /// The next thing to do, if it's time. With `lookahead` it answers a little
    /// early, so whoever's walking can get there in time.
    public func next(_ w: Winemaking, lookahead: Bool = false) -> Winemaking.Action? {
        let slack = 1 - skill
        let style = w.harvest.style
        switch w.stage {
        case .waiting:
            guard lookahead || w.hours >= 1 + 6 * slack else { return nil }
            // Only Doug at his best trusts the stems: whole clusters for Syrah
            // and Grenache when they're brown.
            if style == .red && skill >= 0.8 && [Varietal.syrah, .grenache].contains(w.harvest.varietal)
                && w.harvest.greenStems < 0.2 {
                return .wholeCluster
            }
            return w.actions.first
        case .skinContact:
            let target = Winemaking.pink.middle + 0.12 * slack
            return w.color >= target - (lookahead ? 0.08 : 0) ? .press : nil
        case .pressing:
            let target = w.pressKnee - 0.02 + 0.2 * slack
            return w.pressProgress >= target - (lookahead ? 0.12 : 0) ? .cutPress : nil
        case .juice:
            guard lookahead || w.hours - w.juiceSince >= 1 + 4 * slack else { return nil }
            return .barrelDown
        case .settling:
            if !w.chilling && w.temperature > 14 && (slack < 0.5 || w.hours - w.juiceSince > 6) { return .chill(true) }
            if w.yeastAt == nil && w.clarity >= 0.74 - 0.3 * slack - (lookahead ? 0.15 : 0) { return .addYeast }
            return nil
        case .soaking:
            if w.bleeding {
                return w.bleed >= 0.2 - (lookahead ? 0.06 : 0) ? .closeBleed : nil
            }
            if saignee && w.bleed < 0.01
                && w.color >= Winemaking.pink.lowerBound + 0.06 * slack - (lookahead ? 0.06 : 0) {
                return .openBleed
            }
            if w.yeastAt == nil, let crushed = w.crushedAt,
               w.hours - crushed >= w.yeastWindow.lowerBound + 4 + 16 * slack - (lookahead ? 5 : 0) {
                return .addYeast
            }
            return nil
        case .fermenting:
            guard style == .red else {
                return !w.chilling && w.temperature > 14 ? .chill(true) : nil
            }
            if w.bleeding { return .closeBleed }
            if !w.chilling && w.temperature > 30.5 + 2.5 * slack - (lookahead ? 1.5 : 0) { return .chill(true) }
            if w.chilling && w.temperature < 27.5 - 2 * slack + (lookahead ? 1.5 : 0) { return .chill(false) }
            if w.cap >= 0.6 + 0.35 * slack - (lookahead ? 0.25 : 0) { return .punchDown }
            return nil
        case .dry:
            let since = w.hours - (w.dryAt ?? w.hours)
            return since >= w.macerationHours + 16 * slack - (lookahead ? 4 : 0) ? .press : nil
        case .pressed:
            guard lookahead || w.hours - w.juiceSince >= 1 + 3 * slack else { return nil }
            return .barrelDown
        case .done:
            return nil
        }
    }

    /// Where to wait when there's nothing to do yet.
    public func standby(_ w: Winemaking) -> StationID? {
        switch w.stage {
        case .waiting: w.actions.first?.station
        case .skinContact, .pressing, .dry: .press
        case .juice, .pressed: .barrels
        case .settling: .lab
        case .soaking: saignee && w.bleed < 0.2 ? .fermenter : .lab
        case .fermenting: w.harvest.style == .red ? .fermenter : .chiller
        case .done: nil
        }
    }
}

extension Vessel {
    /// Where it stands on the floor.
    public var station: StationID {
        switch self {
        case .stainless: .steelTank
        case .neutralOak: .barrels
        case .newOak: .newBarrels
        }
    }
}

extension Winemaking {
    /// The crew makes the wine while Doug's elsewhere: the whole session,
    /// played out at once.
    public static func played(_ harvest: Harvest, vessels: [Vessel], plan: CrushPlan) -> Winemaking {
        var w = Winemaking(harvest: harvest, vessels: vessels)
        w.finish(with: plan)
        return w
    }

    /// Hands the rest of the crush to the crew: plays it out at once.
    public mutating func finish(with plan: CrushPlan) {
        var steps = 0
        while !isFinished && steps < 50_000 {
            if let action = self.plan(plan) {
                if action == .barrelDown { split = plan.split(for: self) }
                perform(action)
            }
            advance(by: 0.1)
            steps += 1
        }
    }

    private func plan(_ plan: CrushPlan) -> Action? {
        guard let action = plan.next(self), actions.contains(action) else { return nil }
        return action
    }

    /// Plays itself: walks Doug to whatever needs doing next and does it. For
    /// the screenshot tour, which can't keep up with a real-time game.
    public mutating func autopilot(_ plan: CrushPlan) {
        guard busy <= 0, !isFinished else { return }
        if let action = plan.next(self), actions.contains(action) {
            if station == action.station {
                if action == .barrelDown { split = plan.split(for: self) }
                act(action)
            } else if destination != action.station {
                walk(to: action.station)
            }
            return
        }
        let coming = plan.next(self, lookahead: true).flatMap { actions.contains($0) ? $0.station : nil }
        if let target = coming ?? plan.standby(self), station != target, destination != target {
            walk(to: target)
        }
    }
}
