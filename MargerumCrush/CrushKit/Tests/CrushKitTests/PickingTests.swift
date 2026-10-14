import XCTest
@testable import CrushKit

/// How a simulated picker treats the bunches it can't simply take or leave.
enum Picking {
    /// Can't tell them apart: picks shaded, green-stemmed and raisined bunches
    /// like ripe ones.
    case everything
    /// Steers the bins into the window: shaded bunches when the sugar runs
    /// high, raisined ones when it's low, green stems never on reds.
    case smart
}

/// Plays a picking round like a person: each bunch gets one glance after
/// `reaction` seconds, and is picked or left.
func play(_ round: inout PickingRound, skill: Double = 0.9, mistakes: Double = 0.1,
          reaction: Double = 0.5, picking: Picking = .everything, red: Bool = true, seed: UInt64 = 99) {
    var rng = SeededGenerator(seed: seed)
    var seen = Set<Int>()
    while !round.isOver {
        round.advance(by: 1.0 / 30)
        for cluster in round.clusters where !seen.contains(cluster.id) && cluster.age(at: round.time) >= reaction {
            seen.insert(cluster.id)
            let roll = Double.random(in: 0..<1, using: &rng)
            let want: Bool
            switch cluster.kind {
            case .ripe, .shot, .golden:
                want = roll < skill
            case .rotten, .sour, .wing:
                want = roll < mistakes
            case .leaf, .cane:
                want = roll < mistakes / 2
            case .greenStem, .shaded, .raisined:
                switch picking {
                case .everything:
                    want = roll < skill
                case .smart:
                    let middle = round.window.lowerBound + (round.window.upperBound - round.window.lowerBound) / 2
                    switch cluster.kind {
                    case .shaded: want = (round.brix > middle + 0.3 || !red) && roll < skill
                    case .raisined: want = round.brix < middle - 0.3 && roll < skill
                    default: want = !red && roll < skill
                    }
                }
            }
            if want { round.pick(cluster.id) }
        }
    }
}

final class PickingTests: XCTestCase {
    private let usual: [PickingRound.Kind: Double] = [
        .ripe: 0.55, .greenStem: 0.08, .shaded: 0.12, .wing: 0.03, .shot: 0.06, .raisined: 0.03,
        .rotten: 0.02, .sour: 0.01, .golden: 0.03, .leaf: 0.05, .cane: 0.02,
    ]

    func testSameSeedSameRound() {
        var a = PickingRound(odds: usual, seed: 5)
        var b = PickingRound(odds: usual, seed: 5)
        play(&a)
        play(&b)
        XCTAssertEqual(a.bin, b.bin)
        XCTAssertGreaterThan(a.offered, 30)
    }

    func testGoodPickerBringsInTheWholeCrop() {
        var round = PickingRound(odds: [.ripe: 0.95, .shaded: 0.05], seed: 1)
        play(&round, skill: 0.9)
        XCTAssertTrue(round.isOver)
        XCTAssertEqual(round.harvestedShare, 1)
        XCTAssertGreaterThan(round.bin.count(.ripe), 30)
    }

    func testIdlePickerBringsInNothing() {
        var round = PickingRound(odds: usual, seed: 1)
        play(&round, skill: 0, mistakes: 0)
        XCTAssertEqual(round.harvestedShare, 0)
        XCTAssertEqual(round.bin.bunches, 0)
        XCTAssertGreaterThan(round.missed, 20)
        XCTAssertEqual(round.brix, round.baseBrix, "an empty bin reads like the block")
    }

    func testCarelessPickerGetsLessThanAFullBin() {
        var round = PickingRound(odds: [.ripe: 0.95, .shaded: 0.05], seed: 1)
        play(&round, skill: 0.4)
        XCTAssertLessThan(round.harvestedShare, 0.75)
        XCTAssertGreaterThan(round.harvestedShare, 0.3)
    }

    func testEachBunchShiftsTheBin() {
        let ripe = PickingRound.Bin([.ripe: 10])
        let shaded = PickingRound.Bin([.shaded: 10])
        let raisined = PickingRound.Bin([.raisined: 10])
        XCTAssertGreaterThan(ripe.brix, shaded.brix)
        XCTAssertLessThan(ripe.acid, shaded.acid)
        XCTAssertGreaterThan(raisined.brix, ripe.brix + 3)
        XCTAssertLessThan(raisined.acid, ripe.acid)
        XCTAssertGreaterThan(PickingRound.Bin([.shot: 10]).tannin, ripe.tannin)
        XCTAssertGreaterThan(PickingRound.Bin([.shot: 10]).complexity, ripe.complexity)
        XCTAssertGreaterThan(PickingRound.Bin([.greenStem: 10]).green, ripe.green)
        // Leaves and canes add no juice, only bitterness.
        let leafy = PickingRound.Bin([.ripe: 10, .leaf: 2])
        XCTAssertEqual(leafy.weight, ripe.weight)
        XCTAssertEqual(leafy.mog, 2)
        XCTAssertEqual(leafy.mogShare, 2.0 / 12, accuracy: 1e-9)
        // Weighted by juice: a wing cluster is small.
        let mixed = PickingRound.Bin([.ripe: 1, .wing: 1])
        XCTAssertEqual(mixed.weight, 1.4, accuracy: 1e-9)
        XCTAssertEqual(mixed.brix, (0.4 - 0.4 * 4.5) / 1.4, accuracy: 1e-9)
    }

    func testPickingEverythingMatchesTheBlock() {
        // Over many rounds, taking whatever turns up averages out to the block.
        var total = 0.0
        for seed in 1...20 {
            var round = PickingRound(odds: usual, baseBrix: 24, seed: UInt64(seed))
            play(&round, skill: 1, mistakes: 1, reaction: 0.2, seed: UInt64(seed))
            total += round.brix
        }
        XCTAssertEqual(total / 20, 24, accuracy: 0.25)
    }

    func testSortingTheBunchesSteersTheSugar() {
        // An underripe block: skipping the shaded and green fruit brings the bins up.
        let odds: [PickingRound.Kind: Double] = [.ripe: 0.4, .shaded: 0.3, .greenStem: 0.15, .raisined: 0.15]
        var all = PickingRound(odds: odds, baseBrix: 23, window: 24...26, seed: 3)
        var choosy = PickingRound(odds: odds, baseBrix: 23, window: 24...26, seed: 3)
        play(&all, skill: 0.95, mistakes: 0)
        play(&choosy, skill: 0.95, mistakes: 0, picking: .smart)
        XCTAssertGreaterThan(choosy.brix, all.brix + 0.4)
        XCTAssertLessThan(choosy.acid, all.acid)
        XCTAssertLessThan(choosy.bin.weight, all.bin.weight, "less fruit, better fruit")

        // An overripe block: a few shaded bunches freshen it up.
        var late = PickingRound(odds: odds, baseBrix: 27.5, window: 24...26, seed: 3)
        var lateAll = PickingRound(odds: odds, baseBrix: 27.5, window: 24...26, seed: 3)
        play(&late, skill: 0.95, mistakes: 0, picking: .smart)
        play(&lateAll, skill: 0.95, mistakes: 0)
        XCTAssertLessThan(late.brix, lateAll.brix)
        XCTAssertGreaterThan(late.acid, lateAll.acid)
    }

    func testTheBlockDecidesWhatTurnsUp() {
        var block = VineyardBlock.ballardCanyonSyrah
        var rng = SeededGenerator(seed: 1)
        block.startVintage(using: &rng)
        block.set(brix: 22.5, rot: 0)
        let early = PickingRound.odds(block: block, style: .red, weather: .sunny)
        block.set(brix: 27.5)
        let late = PickingRound.odds(block: block, style: .red, weather: .sunny)
        let heat = PickingRound.odds(block: block, style: .red, weather: .heatWave)
        block.set(rot: 0.15)
        let wet = PickingRound.odds(block: block, style: .red, weather: .rain)
        XCTAssertGreaterThan(early[.wing] ?? 0, late[.wing] ?? 0)
        XCTAssertGreaterThan(early[.greenStem] ?? 0, late[.greenStem] ?? 0)
        XCTAssertGreaterThan(late[.raisined] ?? 0, early[.raisined] ?? 0)
        XCTAssertGreaterThan(heat[.raisined] ?? 0, late[.raisined] ?? 0)
        XCTAssertGreaterThan(wet[.rotten] ?? 0, 0.1)
        XCTAssertGreaterThan(wet[.sour] ?? 0, late[.sour] ?? 0)
    }

    func testPicksSayWhatTheyDo() throws {
        var round = PickingRound(odds: [.shot: 1], seed: 3)
        while round.clusters.isEmpty { round.advance(by: 0.05) }
        let cluster = try XCTUnwrap(round.clusters.first)
        XCTAssertEqual(round.pick(cluster.id), .shot)
        XCTAssertEqual(round.popups.last?.text, "+Tannin +Complexity")
        XCTAssertNil(round.pick(cluster.id), "already picked")
        XCTAssertEqual(round.bin.count(.shot), 1)
    }

    func testWaspStingCostsTime() throws {
        var round = PickingRound(odds: usual, seed: 8)
        while round.wasps.first(where: { $0.position(at: round.time) != nil }) == nil { round.advance(by: 0.05) }
        let wasp = try XCTUnwrap(round.wasps.first)
        let left = round.timeLeft
        XCTAssertTrue(round.swat(wasp.id))
        XCTAssertEqual(round.timeLeft, left - PickingRound.sting, accuracy: 1e-9)
        XCTAssertEqual(round.stings, 1)
        XCTAssertFalse(round.swat(wasp.id))
    }

    func testClustersStayOnFreeSpots() {
        var round = PickingRound(odds: usual, seed: 11)
        while !round.isOver {
            round.advance(by: 0.1)
            XCTAssertLessThanOrEqual(round.clusters.count, PickingRound.maxClusters)
            XCTAssertEqual(Set(round.clusters.map(\.spot)).count, round.clusters.count)
        }
    }

    func testBinsSaveAndLoad() throws {
        let bin = PickingRound.Bin([.ripe: 12, .shot: 2, .leaf: 1, .rotten: 1])
        let loaded = try JSONDecoder().decode(PickingRound.Bin.self, from: JSONEncoder().encode(bin))
        XCTAssertEqual(loaded, bin)
        XCTAssertEqual(loaded.brix, bin.brix, accuracy: 1e-12)
    }
}
