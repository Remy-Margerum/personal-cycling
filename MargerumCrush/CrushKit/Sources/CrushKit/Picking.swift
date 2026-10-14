import Foundation

/// The picking mini-game. Clusters pop up on the vines for a moment: tap the
/// ripe ones before they wither, leave the green and moldy ones, and don't
/// swat the wasps. The view advances the clock, so a round plays out the
/// same way for a given seed and the same taps.
public struct PickingRound: Sendable {
    public enum Kind: String, Codable, Sendable {
        case ripe, unripe, rotten, golden

        /// Fruit you want in the bin.
        public var isGood: Bool { self == .ripe || self == .golden }
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

    /// "+10" or "Moldy!" floating up from whatever was tapped.
    public struct Popup: Identifiable, Equatable, Sendable {
        public enum Tone: Sendable { case good, bonus, bad }

        public let id: Int
        public let text: String
        public let tone: Tone
        public let x: Double
        public let y: Double
        public let born: Double
    }

    /// What went into the picking bins.
    public struct Tally: Codable, Equatable, Sendable {
        public var ripe = 0
        public var unripe = 0
        public var rotten = 0
        public var golden = 0
        /// Ripe and golden clusters that withered before anyone picked them.
        public var missed = 0
        public var stings = 0

        public init() {}

        public var picked: Int { ripe + unripe + rotten + golden }
    }

    /// What the game keeps once the round is over.
    public struct Summary: Codable, Equatable, Sendable {
        public var tally: Tally
        public var harvestedShare: Double
        public var points: Int
        public var bestStreak: Int
    }

    /// Three trellis wires, as fractions of the vine area's height.
    public static let wires: [Double] = [0.16, 0.44, 0.72]
    /// Where clusters hang from: four spots on each wire.
    public static let spots: [(x: Double, y: Double)] = wires.flatMap { y in
        [0.13, 0.38, 0.62, 0.87].map { x in (x: x, y: y) }
    }
    /// Picking this share of the fruit on offer brings in the whole crop:
    /// nobody gets every last bunch.
    public static let fullCrop = 0.75
    /// Seconds a wasp sting takes off the clock.
    public static let sting = 3.0
    static let maxClusters = 7

    public let duration: Double
    public let unripeShare: Double
    public let rotShare: Double

    public private(set) var time: Double = 0
    /// Seconds lost to stings.
    public private(set) var lostTime: Double = 0
    public private(set) var clusters: [Cluster] = []
    public private(set) var wasps: [Wasp] = []
    public private(set) var popups: [Popup] = []
    public private(set) var tally = Tally()
    public private(set) var points = 0
    /// Good picks in a row.
    public private(set) var streak = 0
    public private(set) var bestStreak = 0
    /// Ripe, golden and unripe clusters shown so far: the fruit on offer.
    public private(set) var offered = 0

    private var rng: SeededGenerator
    private var nextClusterAt = 0.4
    private var nextWaspAt: Double
    private var nextID = 0

    public init(unripeShare: Double, rotShare: Double, duration: Double = 30, seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        nextWaspAt = Double.random(in: 3...5, using: &rng)
        self.rng = rng
        self.duration = duration
        self.unripeShare = min(0.6, max(0, unripeShare))
        self.rotShare = min(0.6, max(0, rotShare))
    }

    /// A round on a block, with as much green and moldy fruit as it has.
    public init(block: VineyardBlock, style: WineStyle, duration: Double = 30, seed: UInt64) {
        let window = block.varietal.window(for: style)
        // Every block has some laggards and a little mold; picking early
        // means many more green clusters, rain much more mold.
        let unripe = 0.1 + 0.15 * max(0, window.lowerBound - block.brix)
        self.init(unripeShare: unripe, rotShare: 0.03 + block.rot, duration: duration, seed: seed)
    }

    public var endTime: Double { duration - lostTime }
    public var isOver: Bool { time >= endTime }
    public var timeLeft: Double { max(0, endTime - time) }

    /// Points multiplier: ×1, plus one for every five good picks in a row, up to ×4.
    public var multiplier: Int { min(4, 1 + streak / 5) }

    /// Share of the block's crop that made it into the bins, 0...1.
    public var harvestedShare: Double {
        guard offered > 0 else { return 0 }
        let fruit = Double(tally.ripe + tally.golden + tally.unripe)
        return min(1, fruit / (Self.fullCrop * Double(offered)))
    }

    public var summary: Summary {
        Summary(tally: tally, harvestedShare: harvestedShare, points: points, bestStreak: bestStreak)
    }

    /// Moves the clock on: clusters wither, new ones appear, wasps fly.
    public mutating func advance(by seconds: Double) {
        guard seconds > 0, !isOver else { return }
        time = min(endTime, time + seconds)
        for cluster in clusters where cluster.remaining(at: time) <= 0 && cluster.kind.isGood {
            tally.missed += 1
            streak = 0
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

    /// Picks a cluster. Returns what it was, or nil if it had already gone.
    @discardableResult
    public mutating func pick(_ id: Int) -> Kind? {
        guard !isOver, let index = clusters.firstIndex(where: { $0.id == id }) else { return nil }
        let cluster = clusters.remove(at: index)
        let spot = Self.spots[cluster.spot]
        switch cluster.kind {
        case .ripe:
            tally.ripe += 1
            streak += 1
            let gain = 10 * multiplier
            points += gain
            popup("+\(gain)", .good, at: spot)
        case .golden:
            tally.golden += 1
            streak += 1
            let gain = 50 * multiplier
            points += gain
            popup("Perfect! +\(gain)", .bonus, at: spot)
        case .unripe:
            tally.unripe += 1
            streak = 0
            points += 2
            popup("Green!", .bad, at: spot)
        case .rotten:
            tally.rotten += 1
            streak = 0
            points = max(0, points - 20)
            popup("Moldy!", .bad, at: spot)
        }
        bestStreak = max(bestStreak, streak)
        return cluster.kind
    }

    /// Swats a wasp. It stings, and the clock loses a few seconds.
    @discardableResult
    public mutating func swat(_ id: Int) -> Bool {
        guard !isOver, let index = wasps.firstIndex(where: { $0.id == id }),
              let position = wasps[index].position(at: time) else { return false }
        wasps.remove(at: index)
        tally.stings += 1
        streak = 0
        lostTime += Self.sting
        popup("Ouch! −\(Int(Self.sting))s", .bad, at: position)
        return true
    }

    private mutating func spawnCluster(at born: Double) {
        let busy = Set(clusters.map(\.spot))
        let free = Self.spots.indices.filter { !busy.contains($0) }
        guard clusters.count < Self.maxClusters, let spot = free.randomElement(using: &rng) else { return }
        let x = Double.random(in: 0..<1, using: &rng)
        let kind: Kind
        if x < rotShare {
            kind = .rotten
        } else if x < rotShare + unripeShare {
            kind = .unripe
        } else if Double.random(in: 0..<1, using: &rng) < 0.04 {
            kind = .golden
        } else {
            kind = .ripe
        }
        if kind != .rotten { offered += 1 }
        // Clusters hang around for less time as the round goes on.
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
