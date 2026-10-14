import Foundation

/// The picking mini-game. Bunches pop up on the vines for a moment, and every
/// one is different: sunny and ripe on a brown stem, shaded and tart, a
/// green-stemmed one that isn't really ripe, a tiny second-crop wing, a
/// concentrated hens-and-chicks bunch, a raisined one from the sunny side,
/// gray mold, sour rot. Whatever goes into the bins makes the wine: its sugar,
/// acid, tannin, green character and complexity. Leaves and canes get grabbed
/// too, and make it bitter. Don't swat the wasps.
///
/// The view advances the clock, so a round plays out the same way for a given
/// seed and the same taps.
public struct PickingRound: Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Sun-exposed, fully colored, on a brown, woody stem.
        case ripe
        /// Colored berries, but a green stem: not physiologically ripe.
        case greenStem
        /// From inside the canopy: less sugar, more acid, green notes.
        case shaded
        /// Second crop on a side shoot: small, hard and sour.
        case wing
        /// "Hens and chicks": small berries, all skin and flavor.
        case shot
        /// Sunburned and shriveled: lots of sugar, little acid.
        case raisined
        /// Gray mold (botrytis).
        case rotten
        /// Sour rot: vinegar and fruit flies.
        case sour
        /// Doug's perfect bunch.
        case golden
        /// A vine leaf, grabbed with the fruit.
        case leaf
        /// A piece of cane.
        case cane

        public var name: String {
            switch self {
            case .ripe: "Ripe bunch"
            case .greenStem: "Green-stemmed bunch"
            case .shaded: "Shaded bunch"
            case .wing: "Wing cluster"
            case .shot: "Hens and chicks"
            case .raisined: "Raisined bunch"
            case .rotten: "Moldy bunch"
            case .sour: "Sour rot"
            case .golden: "Perfect bunch"
            case .leaf: "Vine leaf"
            case .cane: "Cane"
            }
        }

        /// Fruit, as opposed to leaves and canes.
        public var isFruit: Bool { self != .leaf && self != .cane }

        /// Always worth picking. (The others depend on what the wine needs.)
        public var isGood: Bool { self == .ripe || self == .shot || self == .golden }

        /// Never wanted in the bins.
        public var isBad: Bool { self == .rotten || self == .sour || self == .leaf || self == .cane || self == .wing }

        /// What it adds to the bins.
        public var traits: Traits {
            switch self {
            case .ripe: Traits(weight: 1, brix: 0.4, acid: -0.2, tannin: 0.2, green: 0, complexity: 0.05, color: 0.2)
            case .greenStem: Traits(weight: 1, brix: -0.2, acid: 0.3, tannin: 0, green: 0.7, complexity: 0, color: 0)
            case .shaded: Traits(weight: 0.9, brix: -1.6, acid: 1.4, tannin: -0.2, green: 0.8, complexity: 0, color: -0.6)
            case .wing: Traits(weight: 0.4, brix: -4.5, acid: 3.5, tannin: 0, green: 1.6, complexity: 0, color: -1.2)
            case .shot: Traits(weight: 0.6, brix: 1.2, acid: 0.4, tannin: 1.2, green: 0, complexity: 1, color: 1)
            case .raisined: Traits(weight: 0.5, brix: 5, acid: -1.6, tannin: 0.3, green: 0, complexity: 0.3, color: 0.3)
            case .rotten: Traits(weight: 0.8, brix: 0.3, acid: 0.4, tannin: -0.4, green: 0, complexity: 0, color: -1.5)
            case .sour: Traits(weight: 0.6, brix: 0, acid: 0.8, tannin: -0.3, green: 0, complexity: 0, color: -0.8)
            case .golden: Traits(weight: 1, brix: 0.4, acid: 0, tannin: 0.6, green: 0, complexity: 2, color: 0.6)
            case .leaf, .cane: Traits(weight: 0, brix: 0, acid: 0, tannin: 0, green: 0, complexity: 0, color: 0)
            }
        }
    }

    /// What a bunch does to the bins, against an average one.
    public struct Traits: Equatable, Sendable {
        /// Juice it gives, against a ripe bunch.
        public var weight: Double
        /// °Brix above or below the block's average bunch.
        public var brix: Double
        /// Acid (g/L) above or below.
        public var acid: Double
        /// Ripe skin tannin: structure.
        public var tannin: Double
        /// Green, bitter, herbaceous: unripe stems and shaded skins.
        public var green: Double
        public var complexity: Double
        /// Skin color and fruit.
        public var color: Double
    }

    /// What's in the picking bins, as it fills.
    public struct Bin: Codable, Equatable, Sendable {
        public private(set) var counts: [String: Int] = [:]
        /// Fruit by weight, in ripe bunches.
        public private(set) var weight = 0.0
        private var sums = Sums()
        /// Leaves and canes.
        public private(set) var mog = 0
        private var rotWeight = 0.0
        private var sourWeight = 0.0

        private struct Sums: Codable, Equatable, Sendable {
            var brix = 0.0
            var acid = 0.0
            var tannin = 0.0
            var green = 0.0
            var complexity = 0.0
            var color = 0.0
        }

        public init() {}

        /// A bin with these bunches in it, for tests and previews.
        public init(_ counts: [Kind: Int]) {
            for (kind, n) in counts {
                for _ in 0..<n { add(kind) }
            }
        }

        public mutating func add(_ kind: Kind) {
            counts[kind.rawValue, default: 0] += 1
            guard kind.isFruit else {
                mog += 1
                return
            }
            let t = kind.traits
            weight += t.weight
            sums.brix += t.weight * t.brix
            sums.acid += t.weight * t.acid
            sums.tannin += t.weight * t.tannin
            sums.green += t.weight * t.green
            sums.complexity += t.weight * t.complexity
            sums.color += t.weight * t.color
            if kind == .rotten { rotWeight += t.weight }
            if kind == .sour { sourWeight += t.weight }
        }

        /// Takes a bunch back out (the sorting table).
        mutating func remove(_ kind: Kind) {
            guard count(kind) > 0 else { return }
            counts[kind.rawValue, default: 0] -= 1
            guard kind.isFruit else {
                mog -= 1
                return
            }
            let t = kind.traits
            weight -= t.weight
            sums.brix -= t.weight * t.brix
            sums.acid -= t.weight * t.acid
            sums.tannin -= t.weight * t.tannin
            sums.green -= t.weight * t.green
            sums.complexity -= t.weight * t.complexity
            sums.color -= t.weight * t.color
            if kind == .rotten { rotWeight -= t.weight }
            if kind == .sour { sourWeight -= t.weight }
        }

        public func count(_ kind: Kind) -> Int { counts[kind.rawValue] ?? 0 }

        /// Bunches of fruit.
        public var bunches: Int { Kind.allCases.filter(\.isFruit).reduce(0) { $0 + count($1) } }

        private func average(_ sum: Double) -> Double { weight > 0 ? sum / weight : 0 }

        /// °Brix above or below the block's average bunch.
        public var brix: Double { average(sums.brix) }
        public var acid: Double { average(sums.acid) }
        public var tannin: Double { average(sums.tannin) }
        public var green: Double { average(sums.green) }
        public var complexity: Double { average(sums.complexity) }
        public var color: Double { average(sums.color) }
        /// Leaves and canes for every bunch of fruit.
        public var mogShare: Double { Double(mog) / Double(max(1, bunches + mog)) }
        public var rotShare: Double { weight > 0 ? rotWeight / weight : 0 }
        public var sourShare: Double { weight > 0 ? sourWeight / weight : 0 }
    }

    public struct Cluster: Identifiable, Equatable, Sendable {
        public let id: Int
        /// Index into `PickingRound.spots`.
        public let spot: Int
        public let kind: Kind
        public let born: Double
        public let lifetime: Double

        public func age(at time: Double) -> Double { time - born }
        public func remaining(at time: Double) -> Double { born + lifetime - time }
    }

    public struct Wasp: Identifiable, Equatable, Sendable {
        public let id: Int
        public let born: Double
        public let duration: Double
        public let fromLeft: Bool
        let startY: Double
        let endY: Double

        /// Where it is in the vine area (0...1 each way), or nil before it
        /// arrives and after it has gone.
        public func position(at time: Double) -> (x: Double, y: Double)? {
            let p = (time - born) / duration
            guard p >= 0, p <= 1 else { return nil }
            let x = fromLeft ? -0.08 + 1.16 * p : 1.08 - 1.16 * p
            let y = startY + (endY - startY) * p + 0.04 * sin(p * .pi * 5)
            return (x, y)
        }
    }

    /// "+Sugar" or "Moldy!" floating up from whatever was tapped.
    public struct Popup: Identifiable, Equatable, Sendable {
        public enum Tone: Sendable { case good, bonus, bad, info }

        public let id: Int
        public let text: String
        public let tone: Tone
        public let x: Double
        public let y: Double
        public let born: Double
    }

    /// What the game keeps once the round is over.
    public struct Summary: Codable, Equatable, Sendable {
        public var bin: Bin
        public var harvestedShare: Double
        /// Good bunches that withered before anyone picked them.
        public var missed: Int
        public var stings: Int
    }

    /// Three trellis wires, as fractions of the vine area's height.
    public static let wires: [Double] = [0.16, 0.44, 0.72]
    /// Where bunches hang from: four spots on each wire.
    public static let spots: [(x: Double, y: Double)] = wires.flatMap { y in
        [0.13, 0.38, 0.62, 0.87].map { x in (x: x, y: y) }
    }
    /// Picking this share of the fruit on offer brings in the whole crop:
    /// nobody gets every last bunch.
    public static let fullCrop = 0.7
    /// Seconds a wasp sting takes off the clock.
    public static let sting = 3.0
    static let maxClusters = 7

    public let duration: Double
    /// How likely each kind is to turn up.
    public let odds: [Kind: Double]
    /// The block's average bunch: what a bin of everything would hold.
    public let expected: Traits
    /// The block's sugar and acid, the window it's being picked for, and the
    /// acid the style wants.
    public let baseBrix: Double
    public let baseAcid: Double
    public let window: ClosedRange<Double>
    public let idealAcid: Double

    public private(set) var time: Double = 0
    /// Seconds lost to stings.
    public private(set) var lostTime: Double = 0
    public private(set) var clusters: [Cluster] = []
    public private(set) var wasps: [Wasp] = []
    public private(set) var popups: [Popup] = []
    public private(set) var bin = Bin()
    /// Good bunches that withered before anyone picked them.
    public private(set) var missed = 0
    public private(set) var stings = 0
    /// Fruit offered so far, by weight: what a picker could have taken.
    public private(set) var offered = 0.0

    private var rng: SeededGenerator
    private var nextClusterAt = 0.4
    private var nextWaspAt: Double
    private var nextID = 0

    public init(odds: [Kind: Double], baseBrix: Double = 24, baseAcid: Double = 6, window: ClosedRange<Double> = 23...25,
                idealAcid: Double = 6, duration: Double = 30, seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        nextWaspAt = Double.random(in: 3...5, using: &rng)
        self.rng = rng
        self.duration = duration
        let total = odds.values.reduce(0) { $0 + max(0, $1) }
        var normalized: [Kind: Double] = [:]
        for (kind, p) in odds where p > 0 { normalized[kind] = p / max(total, 1e-9) }
        self.odds = normalized
        self.baseBrix = baseBrix
        self.baseAcid = baseAcid
        self.window = window
        self.idealAcid = idealAcid
        expected = Self.average(of: normalized)
    }

    /// A round on a block: early fruit means more shade, wings and green
    /// stems; late fruit, raisins; rain, rot; a heat wave, sunburn.
    public init(block: VineyardBlock, style: WineStyle, weather: Weather = .sunny, duration: Double = 30, seed: UInt64) {
        self.init(odds: Self.odds(block: block, style: style, weather: weather), baseBrix: block.brix, baseAcid: block.acid,
                  window: block.varietal.window(for: style),
                  idealAcid: block.varietal.acidAtIdeal + (style == .rose ? 0.8 : 0), duration: duration, seed: seed)
    }

    /// The mix of bunches on a block this week.
    public static func odds(block: VineyardBlock, style: WineStyle, weather: Weather) -> [Kind: Double] {
        let main = block.varietal.window(for: block.varietal.mainStyle)
        // -1 early, 0 in the middle of the main window, +1 late.
        let r = max(-2, min(2, (block.brix - main.middle) / ((main.upperBound - main.lowerBound) / 2)))
        let early = max(0, -r)
        let late = max(0, r)
        var odds: [Kind: Double] = [
            .ripe: 0.52 - 0.1 * early,
            .greenStem: 0.08 + 0.07 * early - 0.03 * late,
            .shaded: 0.11 + 0.04 * early,
            .wing: 0.03 + 0.04 * early,
            .shot: block.varietal == .cinsault ? 0.03 : 0.06,
            .raisined: 0.02 + 0.06 * late + (weather == .heatWave ? 0.06 : 0),
            .rotten: 0.015 + 0.8 * block.rot,
            .sour: 0.005 + 0.3 * block.rot + 0.01 * late,
            .golden: 0.03,
            .leaf: 0.06,
            .cane: 0.02,
        ]
        if block.varietal == .syrah { odds[.raisined, default: 0] += 0.02 }
        for (kind, p) in odds { odds[kind] = max(0.001, p) }
        return odds
    }

    /// The average bunch, by weight, for a mix.
    static func average(of odds: [Kind: Double]) -> Traits {
        var weight = 0.0
        var t = Traits(weight: 1, brix: 0, acid: 0, tannin: 0, green: 0, complexity: 0, color: 0)
        for (kind, p) in odds where kind.isFruit {
            let k = kind.traits
            let w = p * k.weight
            weight += w
            t.brix += w * k.brix
            t.acid += w * k.acid
            t.tannin += w * k.tannin
            t.green += w * k.green
            t.complexity += w * k.complexity
            t.color += w * k.color
        }
        guard weight > 0 else { return t }
        t.brix /= weight
        t.acid /= weight
        t.tannin /= weight
        t.green /= weight
        t.complexity /= weight
        t.color /= weight
        return t
    }

    public var endTime: Double { duration - lostTime }
    public var isOver: Bool { time >= endTime }
    public var timeLeft: Double { max(0, endTime - time) }

    /// The bins' sugar so far (the block's, until something's picked).
    public var brix: Double { bin.weight > 0 ? baseBrix + bin.brix - expected.brix : baseBrix }
    public var acid: Double { bin.weight > 0 ? baseAcid + bin.acid - expected.acid : baseAcid }

    /// Share of the block's crop that made it into the bins, 0...1.
    public var harvestedShare: Double {
        guard offered > 0 else { return 0 }
        return min(1, bin.weight / (Self.fullCrop * offered))
    }

    public var summary: Summary {
        Summary(bin: bin, harvestedShare: harvestedShare, missed: missed, stings: stings)
    }

    /// Moves the clock on: bunches wither, new ones appear, wasps fly.
    public mutating func advance(by seconds: Double) {
        guard seconds > 0, !isOver else { return }
        time = min(endTime, time + seconds)
        for cluster in clusters where cluster.remaining(at: time) <= 0 && cluster.kind.isGood {
            missed += 1
        }
        clusters.removeAll { $0.remaining(at: time) <= 0 }
        wasps.removeAll { time > $0.born + $0.duration }
        popups.removeAll { time - $0.born > 0.9 }
        while nextClusterAt <= time {
            spawnCluster(at: nextClusterAt)
            // Faster towards the end.
            let pace = 0.5 - 0.14 * nextClusterAt / duration
            nextClusterAt += pace * Double.random(in: 0.8...1.2, using: &rng)
        }
        while nextWaspAt <= time {
            spawnWasp(at: nextWaspAt)
            nextWaspAt += Double.random(in: 3.5...6, using: &rng)
        }
    }

    /// Picks a bunch (or grabs a leaf). Returns what it was, or nil if it had
    /// already gone.
    @discardableResult
    public mutating func pick(_ id: Int) -> Kind? {
        guard !isOver, let index = clusters.firstIndex(where: { $0.id == id }) else { return nil }
        let cluster = clusters.remove(at: index)
        bin.add(cluster.kind)
        let (text, tone) = Self.popup(for: cluster.kind)
        popup(text, tone, at: Self.spots[cluster.spot])
        return cluster.kind
    }

    /// What a pick says as it goes into the bin.
    public static func popup(for kind: Kind) -> (String, Popup.Tone) {
        switch kind {
        case .ripe: ("Ripe", .good)
        case .greenStem: ("Green stem", .info)
        case .shaded: ("+Acid −Sugar", .info)
        case .wing: ("Sour & green!", .bad)
        case .shot: ("+Tannin +Complexity", .bonus)
        case .raisined: ("+Sugar −Acid", .info)
        case .rotten: ("Moldy!", .bad)
        case .sour: ("Vinegar!", .bad)
        case .golden: ("Perfect! +Complexity", .bonus)
        case .leaf: ("Leaf! Bitter", .bad)
        case .cane: ("Cane! Bitter", .bad)
        }
    }

    /// Swats a wasp. It stings, and the clock loses a few seconds.
    @discardableResult
    public mutating func swat(_ id: Int) -> Bool {
        guard !isOver, let index = wasps.firstIndex(where: { $0.id == id }),
              let position = wasps[index].position(at: time) else { return false }
        wasps.remove(at: index)
        stings += 1
        lostTime += Self.sting
        popup("Ouch! −\(Int(Self.sting))s", .bad, at: position)
        return true
    }

    private mutating func spawnCluster(at born: Double) {
        let busy = Set(clusters.map(\.spot))
        let free = Self.spots.indices.filter { !busy.contains($0) }
        guard clusters.count < Self.maxClusters, let spot = free.randomElement(using: &rng) else { return }
        var x = Double.random(in: 0..<1, using: &rng)
        var kind = Kind.ripe
        for candidate in Kind.allCases {
            let p = odds[candidate] ?? 0
            if x < p {
                kind = candidate
                break
            }
            x -= p
        }
        if kind.isFruit && kind != .rotten && kind != .sour { offered += kind.traits.weight }
        // Bunches hang around for less time as the round goes on.
        let lifetime = 2.6 - 0.8 * born / duration
        clusters.append(Cluster(id: nextID, spot: spot, kind: kind, born: born, lifetime: lifetime))
        nextID += 1
    }

    private mutating func spawnWasp(at born: Double) {
        let wasp = Wasp(id: nextID, born: born, duration: Double.random(in: 2.2...3, using: &rng),
                        fromLeft: Bool.random(using: &rng),
                        startY: Double.random(in: 0.12...0.85, using: &rng),
                        endY: Double.random(in: 0.12...0.85, using: &rng))
        wasps.append(wasp)
        nextID += 1
    }

    private mutating func popup(_ text: String, _ tone: Popup.Tone, at point: (x: Double, y: Double)) {
        popups.append(Popup(id: nextID, text: text, tone: tone, x: point.x, y: point.y, born: time))
        nextID += 1
    }
}
