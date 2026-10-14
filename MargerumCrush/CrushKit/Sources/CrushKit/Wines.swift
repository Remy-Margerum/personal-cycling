import Foundation

/// The wines you can make: the four Margerum blends, and a single varietal
/// of each red grape for the wine the blends leave behind.
public enum WineID: String, Codable, CaseIterable, Sendable, Identifiable {
    case sybarite, rose, m5, uber
    case grenache, syrah, mourvedre, counoise, cinsault

    public var id: String { rawValue }

    public var spec: WineSpec {
        switch self {
        case .sybarite: .sybarite
        case .rose: .rose
        case .m5: .m5
        case .uber: .uber
        case .grenache: .grenache
        case .syrah: .syrah
        case .mourvedre: .mourvedre
        case .counoise: .counoise
        case .cinsault: .cinsault
        }
    }

    /// Sybarite, the rosé, M5 and ÜBER.
    public static let blends: [WineID] = [.sybarite, .rose, .m5, .uber]
    /// One wine per red grape.
    public static let singles: [WineID] = [.grenache, .syrah, .mourvedre, .counoise, .cinsault]

    /// The grape a single varietal is made of; nil for the blends.
    public var grape: Varietal? {
        switch self {
        case .sybarite, .rose, .m5, .uber: nil
        case .grenache: .grenache
        case .syrah: .syrah
        case .mourvedre: .mourvedre
        case .counoise: .counoise
        case .cinsault: .cinsault
        }
    }

    public var isSingle: Bool { grape != nil }

    /// The single varietal of a red grape.
    public static func single(_ grape: Varietal) -> WineID? {
        singles.first { $0.grape == grape }
    }
}

/// What a wine has to be, and Doug's range for it: the style he makes it in,
/// which is what the critic rewards.
public struct WineSpec: Sendable {
    enum Rule: Sendable {
        /// At least this share of one grape (75% is the legal minimum for
        /// putting a grape's name on the label).
        case varietal(Varietal, Double)
        /// A single varietal: at least 75% of the grape, and the purer it is
        /// the more it shows (`purityBonus`).
        case single(Varietal)
        /// At least 5% of each of the five reds.
        case allFive
        /// Any grapes, as long as the style is right.
        case any
    }

    public let id: WineID
    /// "Sybarite"
    public let name: String
    /// "Sauvignon Blanc"
    public let kind: String
    public let style: WineStyle
    /// Shelf price per bottle for a 90-point wine.
    public let price: Double
    public let blurb: String
    /// Doug's range: where each dimension of the taste should land.
    public let target: [TasteProfile.Dimension: ClosedRange<Double>]
    let rule: Rule

    public static let sybarite = WineSpec(
        id: .sybarite, name: "Sybarite", kind: "Sauvignon Blanc", style: .white, price: 32,
        blurb: "Crisp, citrusy Happy Canyon Sauvignon Blanc. Unoaked, and at least 75% Sauvignon Blanc.",
        target: [.fruit: 6.5...8.0, .acidity: 7.0...8.8, .tannin: 0.0...1.0,
                 .body: 3.2...4.6, .spice: 2.0...3.5, .oak: 0.0...1.0],
        rule: .varietal(.sauvignonBlanc, 0.75))

    public static let rose = WineSpec(
        id: .rose, name: "Rosé", kind: "Rosé of Rhône grapes", style: .rose, price: 28,
        blurb: "Pale, dry and bright, from red grapes picked early or bled off for saignée.",
        target: [.fruit: 6.5...8.2, .acidity: 7.0...8.8, .tannin: 0.0...1.0,
                 .body: 2.5...4.0, .spice: 1.0...2.8, .oak: 0.0...0.5],
        rule: .any)

    public static let m5 = WineSpec(
        id: .m5, name: "M5", kind: "Red Rhône blend", style: .red, price: 48,
        blurb: "The five-grape blend: Syrah, Grenache, Mourvèdre, Counoise and Cinsault. All five have to be in it.",
        target: [.fruit: 6.8...8.2, .acidity: 5.0...6.2, .tannin: 5.2...6.6,
                 .body: 6.3...7.6, .spice: 5.6...7.2, .oak: 1.4...2.8],
        rule: .allFive)

    public static let uber = WineSpec(
        id: .uber, name: "ÜBER Syrah", kind: "Syrah", style: .red, price: 70,
        blurb: "Big, dark, over-the-top Syrah from new French oak. At least 75% Syrah.",
        target: [.fruit: 7.5...9.5, .acidity: 4.5...6.0, .tannin: 6.8...8.8,
                 .body: 8.2...9.5, .spice: 5.0...7.5, .oak: 4.0...6.0],
        rule: .varietal(.syrah, 0.75))

    /// Points a single varietal of one grape alone earns for showing that
    /// grape and its vineyard plainly: a pure Grenache scores with the M5
    /// its grapes would have gone into. Nothing at 75%, all of it at 100%.
    public static let purityBonus = 3.0

    public static let grenache = WineSpec(
        id: .grenache, name: "Grenache", kind: "Single varietal", style: .red, price: 45,
        blurb: "Bright, red-fruited Grenache from neutral barrels. At least 75% Grenache, and the purer the better.",
        target: [.fruit: 7.8...9.4, .acidity: 3.0...4.6, .tannin: 4.2...5.8,
                 .body: 7.0...8.6, .spice: 3.6...5.2, .oak: 0.8...2.4],
        rule: .single(.grenache))

    public static let syrah = WineSpec(
        id: .syrah, name: "Syrah", kind: "Single varietal", style: .red, price: 50,
        blurb: "Estate Syrah: dark fruit and pepper, mostly neutral barrels. At least 75% Syrah, and the purer the better.",
        target: [.fruit: 7.2...8.8, .acidity: 3.0...4.8, .tannin: 6.8...8.4,
                 .body: 7.8...9.4, .spice: 5.6...7.4, .oak: 1.2...3.6],
        rule: .single(.syrah))

    public static let mourvedre = WineSpec(
        id: .mourvedre, name: "Mourvèdre", kind: "Single varietal", style: .red, price: 45,
        blurb: "Savory, structured Mourvèdre. At least 75% Mourvèdre, and the purer the better.",
        target: [.fruit: 5.2...7.0, .acidity: 3.4...5.0, .tannin: 7.2...8.8,
                 .body: 7.0...8.6, .spice: 6.6...8.2, .oak: 1.0...2.8],
        rule: .single(.mourvedre))

    public static let counoise = WineSpec(
        id: .counoise, name: "Counoise", kind: "Single varietal", style: .red, price: 40,
        blurb: "Light, spicy, peppery Counoise. At least 75% Counoise, and the purer the better.",
        target: [.fruit: 6.8...8.4, .acidity: 4.6...6.2, .tannin: 2.8...4.4,
                 .body: 4.8...6.4, .spice: 6.2...7.8, .oak: 0.8...2.4],
        rule: .single(.counoise))

    public static let cinsault = WineSpec(
        id: .cinsault, name: "Cinsault", kind: "Single varietal", style: .red, price: 40,
        blurb: "Silky, perfumed Cinsault, partly in steel to keep it fresh. At least 75% Cinsault, and the purer the better.",
        target: [.fruit: 7.8...9.4, .acidity: 4.2...5.8, .tannin: 1.8...3.2,
                 .body: 4.5...6.1, .spice: 2.6...4.0, .oak: 0.6...2.2],
        rule: .single(.cinsault))

    /// The grapes the rule asks for, for showing what's missing.
    public var requiredVarietals: [Varietal] {
        switch rule {
        case .varietal(let grape, _): [grape]
        case .single(let grape): [grape]
        case .allFive: Varietal.allCases.filter(\.isRed)
        case .any: []
        }
    }

    /// Tastes a blend of lots, `cases` of each.
    public func analyze(_ parts: [(lot: Lot, cases: Int)]) -> BlendAnalysis {
        let used = parts.filter { $0.cases > 0 }
        let cases = used.reduce(0) { $0 + $1.cases }
        let total = Double(max(1, cases))
        let profile = TasteProfile.blend(used.map { ($0.lot.profile, Double($0.cases)) }) ?? TasteProfile()
        let quality = used.reduce(0) { $0 + $1.lot.quality * Double($1.cases) } / total
        let alcohol = used.reduce(0) { $0 + $1.lot.alcohol * Double($1.cases) } / total
        let color = RGB.mix(used.map { ($0.lot.color, Double($0.cases)) })
        var shares: [Varietal: Double] = [:]
        for part in used { shares[part.lot.varietal, default: 0] += Double(part.cases) / total }
        let composition = Varietal.allCases
            .compactMap { grape in shares[grape].map { VarietalShare(varietal: grape, share: $0) } }
            .sorted { $0.share > $1.share }

        var problems: [String] = []
        if cases == 0 { problems.append("Add some wine.") }
        // Blend as you like, within what the label allows: a little white in
        // a red is fine (Côte-Rôtie does it), but it has to be mostly the
        // right color...
        let inStyle = used.filter { $0.lot.style == style }.reduce(0) { $0 + $1.cases }
        if cases > 0 && Double(inStyle) < 0.85 * total {
            problems.append("\(name) has to be at least 85% \(style.name.lowercased()) wine. Now \(percent(Double(inStyle) / total)).")
        }
        // ...and 85% from one harvest to put a vintage on it.
        var byVintage: [Int: Int] = [:]
        for part in used { byVintage[part.lot.vintage, default: 0] += part.cases }
        let main = byVintage.sorted { ($0.value, $0.key) > ($1.value, $1.key) }.first
        if cases > 0, let main, Double(main.value) < 0.85 * total {
            problems.append("A vintage on the label needs 85% from one harvest. Now \(percent(Double(main.value) / total)) "
                            + "from \(main.key).")
        }
        var purity = 0.0
        switch rule {
        case .varietal(let grape, let minimum):
            let share = shares[grape] ?? 0
            if cases > 0 && share < minimum {
                problems.append("Needs at least \(percent(minimum)) \(grape.name). Now \(percent(share)).")
            }
        case .single(let grape):
            let share = shares[grape] ?? 0
            if cases > 0 && share < 0.75 {
                problems.append("Needs at least 75% \(grape.name). Now \(percent(share)).")
            }
            purity = Self.purityBonus * min(1, max(0, (share - 0.75) / 0.25))
        case .allFive:
            let missing = requiredVarietals.filter { (shares[$0] ?? 0) < 0.05 }
            if cases > 0 && !missing.isEmpty {
                problems.append("Needs at least 5% of each of the five grapes. Short: \(list(missing.map(\.name))).")
            }
        case .any:
            break
        }

        var misses: [TasteProfile.Dimension: Double] = [:]
        var stylePenalty = 0.0
        for (dimension, range) in target {
            let value = profile[dimension]
            if value < range.lowerBound { misses[dimension] = value - range.lowerBound }
            if value > range.upperBound { misses[dimension] = value - range.upperBound }
            stylePenalty += 2 * range.distance(to: value)
        }
        // Blending pays: each extra grape (at 5% or more) adds three quarters
        // of a point, and all five together a point more.
        let grapes = composition.filter { $0.share >= 0.05 }.count
        let complexity = 0.75 * Double(max(0, grapes - 1)) + (grapes >= 5 ? 1 : 0)
        let hot = 2 * max(0, alcohol - 15.5)
        // Bottled before it settled, or before the reds came together.
        let young = used.reduce(0) { $0 + Aging.youth($1.lot.style, months: $1.lot.months) * Double($1.cases) } / total
        let raw = 61 + 0.35 * quality + complexity + purity - stylePenalty - hot - young
        let score = cases > 0 ? Int(min(100, max(70, raw)).rounded()) : 0

        return BlendAnalysis(cases: cases, profile: profile, quality: quality, alcohol: alcohol, color: color,
                             composition: composition, problems: problems, misses: misses, young: young, score: score,
                             vintage: main?.key)
    }
}

/// How many cases of each lot go into a wine.
public struct Blend: Equatable, Sendable {
    public var wine: WineID
    public var cases: [UUID: Int]

    public init(wine: WineID, cases: [UUID: Int] = [:]) {
        self.wine = wine
        self.cases = cases
    }
}

public struct VarietalShare: Codable, Equatable, Sendable, Identifiable {
    public var varietal: Varietal
    /// 0...1
    public var share: Double

    public var id: Varietal { varietal }
}

public struct BlendAnalysis: Equatable, Sendable {
    public var cases: Int
    public var profile: TasteProfile
    public var quality: Double
    public var alcohol: Double
    public var color: RGB
    /// Biggest share first.
    public var composition: [VarietalShare]
    /// Why it can't be bottled yet.
    public var problems: [String]
    /// How far each dimension is outside the target: negative is too little.
    public var misses: [TasteProfile.Dimension: Double]
    /// Points lost to bottling too soon (see `Aging.youth`).
    public var young: Double
    /// The winemaker's estimate. The critic may land a point either side.
    public var score: Int
    /// The harvest most of it came from: the vintage on the label.
    public var vintage: Int?

    public var canBottle: Bool { problems.isEmpty && cases > 0 }
}

/// A wine in bottle, with the critic's verdict.
public struct BottledWine: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var wine: WineID
    public var vintage: Int
    public var cases: Int
    public var score: Int
    public var note: String
    public var alcohol: Double
    public var color: RGB
    public var composition: [VarietalShare]
    /// What it sold for, once the vintage is released.
    public var revenue: Double?
    /// The cellar month it was bottled (see `Aging.months`).
    public var month: Int?
    /// How far its oak landed outside Doug's range (negative: too little).
    /// Doug's notes at barrel-down learn from it.
    public var oakMiss: Double?

    public var spec: WineSpec { wine.spec }
    public var verdict: String { Self.verdict(score) }

    public static func verdict(_ score: Int) -> String {
        switch score {
        case 95...: "Classic"
        case 90..<95: "Outstanding"
        case 85..<90: "Very good"
        case 80..<85: "Good"
        default: "Fair"
        }
    }
}

/// The critic's words.
enum TastingNote {
    static func write(for spec: WineSpec, analysis: BlendAnalysis, score: Int, faults: Set<Fault>,
                      using rng: inout SeededGenerator) -> String {
        let p = analysis.profile
        var sentences: [String] = []

        switch spec.style {
        case .white: sentences.append(p.body > 4.5 ? "Bright gold." : "Pale straw with green glints.")
        case .rose: sentences.append(p.body > 3.8 ? "Copper-pink." : "Pale salmon.")
        case .red: sentences.append(p.body > 7.5 ? "Inky purple." : p.body > 6 ? "Deep garnet." : "Bright ruby.")
        }

        var flavors: [String] = []
        for part in analysis.composition where part.share >= 0.1 && flavors.count < 3 {
            let words = part.varietal.descriptors(for: spec.style).filter { !flavors.contains($0) }
            if let word = words.prefix(2).randomElement(using: &rng) { flavors.append(word) }
        }
        if spec.style == .red && p.spice >= 6 {
            flavors.append(["cracked pepper", "garrigue", "smoked meat"].randomElement(using: &rng) ?? "spice")
        } else if spec.style == .white && p.spice >= 3 {
            flavors.append("fresh-cut herbs")
        }
        if !flavors.isEmpty {
            let leads = flavors.count == 1
                ? ["leads the way", "jumps from the glass", "fills the nose", "comes first"]
                : ["lead the way", "jump from the glass", "fill the nose", "come first"]
            let lead = leads.randomElement(using: &rng) ?? leads[0]
            sentences.append("\(capitalized(list(flavors))) \(lead).")
        }

        let body = p.body >= 8 ? "Full-bodied and generous" : p.body >= 5.5 ? "Medium-bodied" : "Light on its feet"
        let acid = p.acidity >= 7.5 ? "mouthwatering acidity" : p.acidity >= 5 ? "fresh acidity" : "a soft, round texture"
        if spec.style == .red {
            let tannin = p.tannin >= 7.5 ? "firm, chewy tannins" : p.tannin >= 5 ? "polished tannins" : "silky tannins"
            sentences.append("\(body), with \(tannin) and \(acid).")
        } else {
            sentences.append("\(body), with \(acid).")
        }

        if p.oak >= 4 {
            sentences.append("Toasty new French oak frames it all.")
        } else if p.oak >= 1.5 {
            sentences.append("A gentle touch of oak.")
        } else if spec.style == .white {
            sentences.append("Pure and unoaked.")
        }

        if faults.contains(.moldy) { sentences.append("A musty note distracts.") }
        if faults.contains(.green) { sentences.append("Some green, unripe edges.") }
        if faults.contains(.stemmy) { sentences.append("Bitter, leafy and stemmy on the finish.") }
        if faults.contains(.sour) || faults.contains(.volatile) {
            sentences.append("A whiff of vinegar spoils it.")
        }
        if faults.contains(.bitter) { sentences.append("A bitter, phenolic bite from the press.") }
        if faults.contains(.sweet) { sentences.append("A touch of sugar left behind: the fermentation stuck.") }
        if faults.contains(.oxidized) { sentences.append("Tired, nutty and a little brown.") }
        if analysis.alcohol > 15.5 { sentences.append("The alcohol runs hot on the finish.") }
        if analysis.young >= 1 {
            sentences.append(spec.style == .red ? "Bottled young: the oak and tannin haven't come together yet."
                                                : "Bottled young, before it settled: a little raw.")
        }

        switch score {
        case 98...: sentences.append("A benchmark for Santa Barbara County.")
        case 95..<98: sentences.append("A stunner. Buy it by the case.")
        case 92..<95: sentences.append("Outstanding.")
        case 89..<92: sentences.append("Very good, and easy to love.")
        case 85..<89: sentences.append("Pleasant, if a little simple.")
        default: sentences.append("Drink it soon, and drink it cold.")
        }
        return sentences.joined(separator: " ")
    }

    private static func capitalized(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// "a, b and c"
func list(_ items: [String]) -> String {
    switch items.count {
    case 0: ""
    case 1: items[0]
    default: items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}

/// "75%"
func percent(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
}

extension WineSpec {
    /// How Doug barrels down the wine for it, from the Margerum tech sheets
    /// (nudged to fit the game's oak): Sybarite mostly steel with a little
    /// neutral oak, M5 in neutral barrels with a few new, ÜBER mostly new
    /// French oak; the single varietals mostly neutral barrels, Cinsault
    /// partly in steel and the Syrah with a quarter new.
    public var barrels: VesselSplit {
        switch id {
        case .sybarite: VesselSplit(stainless: 0.85, neutralOak: 0.15)
        case .rose: .only(.stainless)
        case .m5: VesselSplit(neutralOak: 0.8, newOak: 0.2)
        case .uber: VesselSplit(neutralOak: 0.15, newOak: 0.85)
        case .grenache: VesselSplit(stainless: 0.1, neutralOak: 0.9)
        case .syrah: VesselSplit(neutralOak: 0.75, newOak: 0.25)
        case .mourvedre: VesselSplit(neutralOak: 0.9, newOak: 0.1)
        case .counoise: .only(.neutralOak)
        case .cinsault: VesselSplit(stainless: 0.3, neutralOak: 0.7)
        }
    }
}

/// Doug's note at barrel-down for one wine a lot might go into.
public struct BarrelNote: Equatable, Sendable, Identifiable {
    public let wine: WineID
    public let text: String
    /// Where he'd aim.
    public let target: VesselSplit
    /// How sure he is of the main vessel's share, either way; nil while it's
    /// only a hunch.
    public let margin: Double?

    public var id: WineID { wine }
}
