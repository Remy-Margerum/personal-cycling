import Foundation

/// The wines you can make.
public enum WineID: String, Codable, CaseIterable, Sendable, Identifiable {
    case sybarite, rose, m5, uber

    public var id: String { rawValue }

    public var spec: WineSpec {
        switch self {
        case .sybarite: .sybarite
        case .rose: .rose
        case .m5: .m5
        case .uber: .uber
        }
    }
}

/// What a wine has to be, and the style the critic expects of it.
public struct WineSpec: Sendable {
    enum Rule: Sendable {
        /// At least this share of one grape (75% is the legal minimum for
        /// putting a grape's name on the label).
        case varietal(Varietal, Double)
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
    /// The style the critic is looking for.
    public let target: [TasteProfile.Dimension: ClosedRange<Double>]
    let rule: Rule

    public static let sybarite = WineSpec(
        id: .sybarite, name: "Sybarite", kind: "Sauvignon Blanc", style: .white, price: 32,
        blurb: "Crisp, citrusy Happy Canyon Sauvignon Blanc. Unoaked, and at least 75% Sauvignon Blanc.",
        target: [.fruit: 6.5...8.0, .acidity: 7.5...9.0, .tannin: 0.0...1.0,
                 .body: 3.2...4.6, .spice: 2.0...3.5, .oak: 0.0...1.0],
        rule: .varietal(.sauvignonBlanc, 0.75))

    public static let rose = WineSpec(
        id: .rose, name: "Rosé", kind: "Rosé of Rhône grapes", style: .rose, price: 28,
        blurb: "Pale, dry and bright, from red grapes picked early or bled off for saignée.",
        target: [.fruit: 6.5...8.2, .acidity: 7.0...8.5, .tannin: 0.0...1.0,
                 .body: 2.5...4.0, .spice: 1.0...2.8, .oak: 0.0...0.5],
        rule: .any)

    public static let m5 = WineSpec(
        id: .m5, name: "M5", kind: "Red Rhône blend", style: .red, price: 48,
        blurb: "The five-grape blend: Syrah, Grenache, Mourvèdre, Counoise and Cinsault. All five have to be in it.",
        target: [.fruit: 6.8...8.2, .acidity: 5.0...6.2, .tannin: 5.5...6.8,
                 .body: 6.3...7.6, .spice: 5.6...7.2, .oak: 2.0...3.2],
        rule: .allFive)

    public static let uber = WineSpec(
        id: .uber, name: "ÜBER Syrah", kind: "Syrah", style: .red, price: 70,
        blurb: "Big, dark, over-the-top Syrah from new French oak. At least 75% Syrah.",
        target: [.fruit: 7.5...9.5, .acidity: 4.0...5.5, .tannin: 7.2...9.0,
                 .body: 8.2...9.5, .spice: 4.5...7.0, .oak: 4.0...6.0],
        rule: .varietal(.syrah, 0.75))

    /// The grapes the rule asks for, for showing what's missing.
    public var requiredVarietals: [Varietal] {
        switch rule {
        case .varietal(let grape, _): [grape]
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
        for part in used where part.lot.style != style {
            problems.append("\(part.lot.name) is \(part.lot.style.name.lowercased()); \(name) has to be \(style.name.lowercased()).")
        }
        switch rule {
        case .varietal(let grape, let minimum):
            let share = shares[grape] ?? 0
            if cases > 0 && share < minimum {
                problems.append("Needs at least \(percent(minimum)) \(grape.name). Now \(percent(share)).")
            }
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
        let raw = 61 + 0.35 * quality + complexity - stylePenalty - hot
        let score = cases > 0 ? Int(min(100, max(70, raw)).rounded()) : 0

        return BlendAnalysis(cases: cases, profile: profile, quality: quality, alcohol: alcohol, color: color,
                             composition: composition, problems: problems, misses: misses, score: score)
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
    /// The winemaker's estimate. The critic may land a point either side.
    public var score: Int

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

        var flavours: [String] = []
        for part in analysis.composition where part.share >= 0.1 && flavours.count < 3 {
            let words = part.varietal.descriptors(for: spec.style).filter { !flavours.contains($0) }
            if let word = words.prefix(2).randomElement(using: &rng) { flavours.append(word) }
        }
        if spec.style == .red && p.spice >= 6 {
            flavours.append(["cracked pepper", "garrigue", "smoked meat"].randomElement(using: &rng) ?? "spice")
        } else if spec.style == .white && p.spice >= 3 {
            flavours.append("fresh-cut herbs")
        }
        if !flavours.isEmpty {
            let lead = ["lead the way", "jump from the glass", "fill the nose", "come first"].randomElement(using: &rng) ?? ""
            sentences.append("\(capitalized(list(flavours))) \(lead).")
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
        if faults.contains(.green) { sentences.append("Some green, stemmy edges.") }
        if analysis.alcohol > 15.5 { sentences.append("The alcohol runs hot on the finish.") }

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
