import Foundation

/// SplitMix64. Seedable and Codable, so a saved game keeps its weather and a
/// test can replay a picking round exactly.
public struct SeededGenerator: RandomNumberGenerator, Codable, Equatable, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A colour without SwiftUI, so berries and blends can be mixed (and tested)
/// here. Components are 0...1.
public struct RGB: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `amount` of the way from this colour to `other`.
    public func mixed(with other: RGB, _ amount: Double) -> RGB {
        RGB(red + (other.red - red) * amount,
            green + (other.green - green) * amount,
            blue + (other.blue - blue) * amount)
    }

    /// Weighted average; black when the weights add up to zero.
    public static func mix(_ parts: [(color: RGB, weight: Double)]) -> RGB {
        let total = parts.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return RGB(0, 0, 0) }
        return parts.reduce(RGB(0, 0, 0)) { sum, part in
            let w = part.weight / total
            return RGB(sum.red + part.color.red * w, sum.green + part.color.green * w, sum.blue + part.color.blue * w)
        }
    }
}

/// White, rosé or red. Red grapes can be picked for either of the last two.
public enum WineStyle: String, Codable, CaseIterable, Sendable {
    case white, rose, red

    public var name: String {
        switch self {
        case .white: "White"
        case .rose: "Rosé"
        case .red: "Red"
        }
    }
}

/// How a wine tastes, each dimension on a 0–10 scale.
public struct TasteProfile: Codable, Equatable, Sendable {
    public enum Dimension: String, CaseIterable, Codable, Sendable, Identifiable {
        case fruit, acidity, tannin, body, spice, oak

        public var id: String { rawValue }

        public var name: String {
            switch self {
            case .fruit: "Fruit"
            case .acidity: "Acidity"
            case .tannin: "Tannin"
            case .body: "Body"
            case .spice: "Spice"
            case .oak: "Oak"
            }
        }
    }

    public var fruit: Double
    public var acidity: Double
    public var tannin: Double
    public var body: Double
    public var spice: Double
    public var oak: Double

    public init(fruit: Double = 0, acidity: Double = 0, tannin: Double = 0,
                body: Double = 0, spice: Double = 0, oak: Double = 0) {
        self.fruit = fruit
        self.acidity = acidity
        self.tannin = tannin
        self.body = body
        self.spice = spice
        self.oak = oak
    }

    public subscript(dimension: Dimension) -> Double {
        get {
            switch dimension {
            case .fruit: fruit
            case .acidity: acidity
            case .tannin: tannin
            case .body: body
            case .spice: spice
            case .oak: oak
            }
        }
        set {
            switch dimension {
            case .fruit: fruit = newValue
            case .acidity: acidity = newValue
            case .tannin: tannin = newValue
            case .body: body = newValue
            case .spice: spice = newValue
            case .oak: oak = newValue
            }
        }
    }

    public static func + (lhs: TasteProfile, rhs: TasteProfile) -> TasteProfile {
        var sum = lhs
        for d in Dimension.allCases { sum[d] += rhs[d] }
        return sum
    }

    /// Every dimension kept within 0...10.
    public func clamped() -> TasteProfile {
        var p = self
        for d in Dimension.allCases { p[d] = min(10, max(0, p[d])) }
        return p
    }

    /// Volume-weighted average; nil when the weights add up to zero.
    public static func blend(_ parts: [(profile: TasteProfile, weight: Double)]) -> TasteProfile? {
        let total = parts.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var result = TasteProfile()
        for part in parts {
            for d in Dimension.allCases { result[d] += part.profile[d] * part.weight / total }
        }
        return result
    }
}

extension ClosedRange where Bound == Double {
    var middle: Double { (lowerBound + upperBound) / 2 }

    /// How far `value` lies outside the range; 0 inside it.
    func distance(to value: Double) -> Double {
        Swift.max(0, lowerBound - value, value - upperBound)
    }
}
