import Foundation

/// Where the wine ferments and ages.
public enum Vessel: String, Codable, CaseIterable, Sendable {
    case stainless, neutralOak, newOak

    public var name: String {
        switch self {
        case .stainless: "Stainless steel"
        case .neutralOak: "Neutral oak"
        case .newOak: "New French oak"
        }
    }

    public var blurb: String {
        switch self {
        case .stainless: "Fresh and fruity."
        case .neutralOak: "Rounder, with a hint of oak."
        case .newOak: "Toast, vanilla and grip."
        }
    }

    /// Barrel cost per ton of fruit.
    public var costPerTon: Double { self == .newOak ? 1_500 : 0 }

    var effect: TasteProfile {
        switch self {
        case .stainless: TasteProfile(fruit: 0.4, acidity: 0.3)
        case .neutralOak: TasteProfile(acidity: -0.2, tannin: 0.3, body: 0.6, oak: 1.5)
        case .newOak: TasteProfile(fruit: -0.3, tannin: 1, body: 0.9, oak: 4.5)
        }
    }
}

/// What to do with red grapes on the crush pad.
public enum CrushMethod: String, Codable, CaseIterable, Sendable {
    /// All of it becomes red wine.
    case red
    /// Bleed off a fifth of the juice as rosé. The red left behind is darker
    /// and more concentrated.
    case saignee

    public var name: String {
        switch self {
        case .red: "All red"
        case .saignee: "Saignée"
        }
    }

    public var blurb: String {
        switch self {
        case .red: "Every drop becomes red wine."
        case .saignee: "Bleed off 20% as rosé; the red gets more concentrated."
        }
    }

    static let bleed = 0.2
}

/// Something the critic can taste.
public enum Fault: String, Codable, Sendable {
    /// Too many unripe clusters went in.
    case green
    /// Too many moldy clusters went in.
    case moldy
}

/// Fruit off the vine, waiting on the crush pad.
public struct Harvest: Codable, Equatable, Sendable {
    public var blockID: String
    public var blockName: String
    public var varietal: Varietal
    /// What it was picked for.
    public var style: WineStyle
    public var tons: Double
    public var brix: Double
    /// Titratable acidity, g/L.
    public var acid: Double
    /// Shares of the fruit by weight, after any sorting.
    public var unripeShare: Double
    public var rotShare: Double
    /// Moldy clusters the sorting table caught.
    public var sortedOut: Int
    public var picking: PickingRound.Summary
    var site: Double
    var character: TasteProfile

    /// Wine it will make.
    public var cases: Int { Int((tons * Game.casesPerTon).rounded()) }

    public var alcohol: Double { (brix * 0.58 * 10).rounded() / 10 }

    /// 0...100: picked at the right sugar for its style, and clean.
    public var quality: Double {
        let window = varietal.window(for: style)
        let off = abs(brix - window.middle)
        let halfWidth = (window.upperBound - window.lowerBound) / 2
        // Best in the middle of the window, a little less at its edges, and
        // falling fast outside it.
        let ripeness = 100 - 8 * min(off, halfWidth) - 15 * max(0, off - halfWidth)
        let clean = 100 - 400 * rotShare - 250 * unripeShare
        let bonus = min(3, Double(picking.tally.golden))
        let quality = 0.5 * max(40, ripeness) + 0.5 * max(0, clean) - 7 + site + bonus
        return min(100, max(0, quality))
    }

    var faults: [Fault] {
        var faults: [Fault] = []
        if unripeShare > 0.12 { faults.append(.green) }
        if rotShare > 0.06 { faults.append(.moldy) }
        return faults
    }

    /// How the fruit tastes made into a style of wine, before the vessel.
    func profile(as wineStyle: WineStyle) -> TasteProfile {
        let window = varietal.window(for: style)
        let off = brix - window.middle
        var p = varietal.baseProfile + character
        // Flavor follows ripeness for the style it was picked for...
        p.fruit += 0.3 * off - 0.6 * window.distance(to: brix)
        p.spice -= 0.25 * off // early picks are peppery and herbal
        p.tannin += 0.15 * off
        // ...while body (alcohol) and acidity are what they are.
        p.body += 0.55 * (brix - varietal.window(for: varietal.mainStyle).middle)
        p.acidity += 0.9 * (acid - varietal.acidAtIdeal)
        // What went into the bins.
        p.fruit -= 3 * unripeShare + 4 * rotShare
        p.acidity += 2 * unripeShare
        p.spice += 1.5 * unripeShare
        if wineStyle == .rose {
            // A few hours on the skins: color and fruit, almost no tannin.
            p = TasteProfile(fruit: p.fruit * 0.9, acidity: p.acidity + 1, tannin: p.tannin * 0.15,
                             body: p.body * 0.5 + 0.3, spice: p.spice * 0.45)
        }
        return p
    }

    /// Turns the fruit into one lot, or two for a saignée.
    func lots(vessel: Vessel, method: CrushMethod) -> [Lot] {
        let quality = self.quality
        switch style {
        case .rose:
            return [lot(name: "\(blockName) Rosé", style: .rose, vessel: .stainless, cases: cases,
                        profile: profile(as: .rose), quality: quality)]
        case .white:
            return [lot(name: blockName, style: .white, vessel: vessel, cases: cases,
                        profile: profile(as: .white), quality: quality)]
        case .red where method == .red:
            return [lot(name: blockName, style: .red, vessel: vessel, cases: cases,
                        profile: profile(as: .red), quality: quality)]
        case .red:
            let rose = Int((Double(cases) * CrushMethod.bleed).rounded())
            let concentrated = profile(as: .red) + TasteProfile(fruit: 0.4, tannin: 0.8, body: 0.6)
            return [
                lot(name: blockName, style: .red, vessel: vessel, cases: cases - rose,
                    profile: concentrated, quality: min(100, quality + 2)),
                lot(name: "\(blockName) Rosé", style: .rose, vessel: .stainless, cases: rose,
                    profile: profile(as: .rose), quality: quality),
            ]
        }
    }

    private func lot(name: String, style: WineStyle, vessel: Vessel, cases: Int,
                     profile: TasteProfile, quality: Double) -> Lot {
        Lot(id: UUID(), name: name, varietal: varietal, style: style, vessel: vessel, cases: cases,
            profile: (profile + vessel.effect).clamped(), quality: quality, alcohol: alcohol,
            color: varietal.wineColor(for: style), faults: faults)
    }
}

/// Wine in tank or barrel, waiting to be blended.
public struct Lot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// "Ballard Canyon Syrah"
    public var name: String
    public var varietal: Varietal
    public var style: WineStyle
    public var vessel: Vessel
    public var cases: Int
    public var profile: TasteProfile
    /// 0...100
    public var quality: Double
    public var alcohol: Double
    public var color: RGB
    public var faults: [Fault]
}
