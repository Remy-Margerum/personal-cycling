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
    /// Leaves and canes in the bins: bitter and vegetal.
    case stemmy
    /// Sour rot: vinegar from the vineyard.
    case sour
    /// The white was pressed too hard: bitter press juice.
    case bitter
    /// The red was pressed with sugar left and the fermentation stuck.
    case sweet
    /// Too long in the air, on the crush pad or in a barrel nobody topped up.
    case oxidized
    /// Vinegar from a dry cap or a late start.
    case volatile
}

/// Fruit off the vine, waiting on the crush pad: what the pickers put in the
/// bins, which isn't quite the block's average.
public struct Harvest: Codable, Equatable, Sendable {
    public var blockID: String
    public var blockName: String
    public var varietal: Varietal
    /// What it was picked for.
    public var style: WineStyle
    public var tons: Double
    /// Sugar and acid (g/L) of what went into the bins.
    public var brix: Double
    public var acid: Double
    /// Shares of the fruit by weight, after any sorting: gray mold and sour rot.
    public var rotShare: Double
    public var sourShare: Double
    /// Leaves and canes for every bunch.
    public var mogShare: Double
    /// Ripe skin tannin, and skin color and fruit, against the block's average
    /// bunch: 0 is average.
    public var tannin: Double
    public var color: Double
    /// Green, bitter character from green stems, shaded fruit and wing
    /// clusters: around 0.2 in an ordinary bin.
    public var green: Double
    /// From hens-and-chicks and perfect bunches: around 0.1 in an ordinary bin.
    public var complexity: Double
    /// Moldy bunches, leaves and canes the sorting table caught.
    public var sortedOut: Int
    public var picking: PickingRound.Summary
    var site: Double
    var character: TasteProfile
    /// °C off the truck: the week's weather.
    public var temperature: Double?

    public var fruitTemperature: Double { temperature ?? 22 }

    /// Wine it will make.
    public var cases: Int { Int((tons * Game.casesPerTon).rounded()) }

    public var alcohol: Double { (brix * 0.58 * 10).rounded() / 10 }

    /// Green character a wine can carry without it showing: Sauvignon Blanc
    /// likes a little grass and lemongrass; the reds don't.
    var greenAllowed: Double { style == .white ? 0.45 : 0.22 }

    /// 0...100: picked at the right sugar for its style, clean, and interesting.
    public var quality: Double {
        let window = varietal.window(for: style)
        let off = abs(brix - window.middle)
        let halfWidth = (window.upperBound - window.lowerBound) / 2
        // Best in the middle of the window, a little less at its edges, and
        // falling fast outside it.
        let ripeness = 100 - 8 * min(off, halfWidth) - 15 * max(0, off - halfWidth)
        let clean = 100 - 400 * rotShare - 600 * sourShare - 300 * mogShare - 40 * max(0, green - greenAllowed)
        let bonus = min(4, 8 * max(0, complexity - 0.05))
        let quality = 0.5 * max(40, ripeness) + 0.5 * max(0, clean) - 11 + site + bonus
        return min(100, max(0, quality))
    }

    var faults: [Fault] {
        var faults: [Fault] = []
        if green > greenAllowed + 0.25 { faults.append(.green) }
        if rotShare > 0.06 { faults.append(.moldy) }
        if sourShare > 0.03 { faults.append(.sour) }
        if mogShare > 0.06 { faults.append(.stemmy) }
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
        // What went into the bins: ripe skins add structure and color...
        p.tannin += 1.2 * tannin
        p.fruit += 0.6 * color
        // ...green stems and shaded fruit, green, bitter edges (grass and
        // lemongrass in a Sauvignon Blanc)...
        let g = green - 0.2
        if varietal.isRed {
            p.tannin += 0.5 * g
            p.spice += 0.6 * g
            p.fruit -= 0.8 * g
        } else {
            p.spice += 0.9 * g
            p.fruit -= 0.3 * g
        }
        // ...leaves and canes, bitterness...
        p.tannin += 5 * mogShare
        p.spice += 3 * mogShare
        p.fruit -= 6 * mogShare
        // ...rot, mustiness and vinegar...
        p.fruit -= 4 * rotShare + 6 * sourShare
        // ...and interesting bunches, depth.
        p.body += 0.5 * complexity
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

    /// The wine from Doug's crush, or the crew's: one lot, or two for a saignée.
    func lots(from r: WinemakingResult) -> [Lot] {
        let quality = min(100, max(0, self.quality + r.quality))
        let made = max(1, Int((Double(cases) * r.cases).rounded()))
        switch style {
        case .rose:
            return [lot(name: "\(blockName) Rosé", style: .rose, vessel: .stainless, cases: made,
                        profile: profile(as: .rose) + r.profile, quality: quality,
                        color: varietal.roseColor(r.roseColor ?? 0.36), extra: r.faults)]
        case .white:
            return [lot(name: blockName, style: .white, vessel: r.vessel, cases: made,
                        profile: profile(as: .white) + r.profile, quality: quality, extra: r.faults)]
        case .red:
            let rose = Int((Double(cases) * r.bleed).rounded())
            var lots = [lot(name: blockName, style: .red, vessel: r.vessel, cases: cases - rose,
                            profile: profile(as: .red) + r.profile, quality: quality, extra: r.faults)]
            if rose > 0 {
                // Bled off before the red's troubles: only the fruit's own faults.
                let c = r.bleedColor
                var pink = profile(as: .rose)
                pink.body += 2.0 * (c - 0.36)
                pink.tannin += 3 * max(0, c - 0.42)
                lots.append(lot(name: "\(blockName) Saignée", style: .rose, vessel: .stainless, cases: rose,
                                profile: pink, quality: min(100, max(0, self.quality + r.bleedQuality)),
                                color: varietal.roseColor(c)))
            }
            return lots
        }
    }

    private func lot(name: String, style: WineStyle, vessel: Vessel, cases: Int,
                     profile: TasteProfile, quality: Double, color: RGB? = nil, extra: [Fault] = []) -> Lot {
        var all = faults
        for fault in extra where !all.contains(fault) { all.append(fault) }
        return Lot(name: name, varietal: varietal, style: style, vessel: vessel, cases: cases,
                   profile: profile + vessel.effect, quality: quality, alcohol: alcohol,
                   color: color ?? varietal.wineColor(for: style), faults: all, complexity: complexity)
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
    /// How it tastes this month.
    public private(set) var profile: TasteProfile
    /// 0...100
    public var quality: Double
    public var alcohol: Double
    public var color: RGB
    public var faults: [Fault]
    /// How it tasted at its reference month (see `Aging`): the cellar's months
    /// move `profile` away from this.
    public private(set) var base: TasteProfile
    /// Months in tank or barrel since the harvest.
    public private(set) var months = 0
    /// Months since the barrels were topped up. Steel tanks don't need it.
    public private(set) var sinceTopped = 0
    /// Interest from the picking: a share of brown-stemmed, shot-berry or
    /// perfect bunches. Adds to the critic's score.
    public var complexity: Double

    public init(id: UUID = UUID(), name: String, varietal: Varietal, style: WineStyle, vessel: Vessel, cases: Int,
                profile: TasteProfile, quality: Double, alcohol: Double, color: RGB, faults: [Fault],
                complexity: Double = 0) {
        self.id = id
        self.name = name
        self.varietal = varietal
        self.style = style
        self.vessel = vessel
        self.cases = cases
        self.base = profile
        self.profile = profile
        self.quality = quality
        self.alcohol = alcohol
        self.color = color
        self.faults = faults
        self.complexity = complexity
        self.profile = taste(at: 0)
    }

    /// Barrels lose a little wine every month; topped up every two months
    /// they never see the air.
    public var needsTopping: Bool { vessel != .stainless && sinceTopped >= 2 }

    /// How it will taste `months` from now.
    public func taste(in months: Int) -> TasteProfile { taste(at: self.months + months) }

    func taste(at month: Int) -> TasteProfile {
        (base + Aging.delta(month, style: style, vessel: vessel)).clamped()
    }

    /// The same lot `months` older, for projections.
    public func aged(by months: Int) -> Lot {
        var lot = self
        lot.months += months
        lot.profile = lot.taste(at: lot.months)
        return lot
    }

    /// A month in the cellar. Barrels left too long without topping oxidize.
    mutating func age() {
        months += 1
        if vessel != .stainless {
            sinceTopped += 1
            if sinceTopped >= 3 {
                quality = max(0, quality - 1.5)
                base.fruit -= 0.25
                if sinceTopped >= 4 && !faults.contains(.oxidized) { faults.append(.oxidized) }
            }
        }
        profile = taste(at: months)
    }

    mutating func topUp() {
        sinceTopped = 0
    }
}
