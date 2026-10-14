import XCTest
@testable import CrushKit

final class BasicsTests: XCTestCase {
    func testSeededGeneratorRepeats() {
        var a = SeededGenerator(seed: 42)
        var b = SeededGenerator(seed: 42)
        var c = SeededGenerator(seed: 43)
        let first = (0..<5).map { _ in a.next() }
        XCTAssertEqual(first, (0..<5).map { _ in b.next() })
        XCTAssertNotEqual(first, (0..<5).map { _ in c.next() })
    }

    func testCalendar() {
        XCTAssertEqual(HarvestCalendar.date(week: 0), "Aug 25")
        XCTAssertEqual(HarvestCalendar.date(week: 1), "Aug 30")
        XCTAssertEqual(HarvestCalendar.date(week: 2), "Sep 4")
        XCTAssertEqual(HarvestCalendar.date(week: 7), "Sep 29")
        XCTAssertEqual(HarvestCalendar.date(week: 8), "Oct 4")
        XCTAssertEqual(HarvestCalendar.date(week: HarvestCalendar.weeks - 1), "Oct 19")
    }

    func testProfileBlendAndClamp() throws {
        let a = TasteProfile(fruit: 2, acidity: 8)
        let b = TasteProfile(fruit: 8, acidity: 4)
        let mix = try XCTUnwrap(TasteProfile.blend([(a, 1), (b, 3)]))
        XCTAssertEqual(mix.fruit, 6.5, accuracy: 1e-9)
        XCTAssertEqual(mix.acidity, 5, accuracy: 1e-9)
        XCTAssertNil(TasteProfile.blend([(a, 0)]))
        XCTAssertEqual(TasteProfile(fruit: 12, oak: -1).clamped(), TasteProfile(fruit: 10, oak: 0))
    }

    func testColorMix() {
        let mix = RGB.mix([(RGB(1, 0, 0), 1), (RGB(0, 0, 1), 1)])
        XCTAssertEqual(mix, RGB(0.5, 0, 0.5))
        XCTAssertEqual(RGB.mix([]), RGB(0, 0, 0))
    }

    func testListAndPercent() {
        XCTAssertEqual(list([]), "")
        XCTAssertEqual(list(["Syrah"]), "Syrah")
        XCTAssertEqual(list(["Syrah", "Grenache", "Cinsault"]), "Syrah, Grenache and Cinsault")
        XCTAssertEqual(percent(0.746), "75%")
    }
}

final class VineyardTests: XCTestCase {
    private func freshBlock(_ block: VineyardBlock = .ballardCanyonSyrah, seed: UInt64 = 1) -> VineyardBlock {
        var rng = SeededGenerator(seed: seed)
        var block = block
        block.startVintage(using: &rng)
        return block
    }

    func testSunshineRipensAndHeatBurnsAcid() {
        let start = freshBlock()
        var sunny = start
        var hot = start
        var foggy = start
        sunny.ripen(in: .sunny)
        hot.ripen(in: .heatWave)
        foggy.ripen(in: .fog)
        XCTAssertGreaterThan(sunny.brix, start.brix)
        XCTAssertGreaterThan(hot.brix, sunny.brix)
        XCTAssertLessThan(foggy.brix, sunny.brix)
        // Heat costs more acid for each degree of sugar; fog keeps it.
        let acidPerBrix = { (b: VineyardBlock) in (start.acid - b.acid) / (b.brix - start.brix) }
        XCTAssertGreaterThan(acidPerBrix(hot), acidPerBrix(sunny))
        XCTAssertLessThan(acidPerBrix(foggy), acidPerBrix(sunny))
    }

    func testRainDilutesAndRotSpreadsUntilItsHot() {
        var block = freshBlock(.losOlivosGrenache)
        let before = block.brix
        block.ripen(in: .rain)
        XCTAssertEqual(block.brix, before - 0.4, accuracy: 1e-9)
        XCTAssertGreaterThan(block.rot, 0)
        let afterRain = block.rot
        block.ripen(in: .sunny)
        XCTAssertGreaterThan(block.rot, afterRain)
        let afterSun = block.rot
        block.ripen(in: .heatWave)
        XCTAssertEqual(block.rot, afterSun)
    }

    func testPickedBlocksStopRipening() {
        var block = freshBlock()
        block.picked = true
        let brix = block.brix
        block.ripen(in: .heatWave)
        XCTAssertEqual(block.brix, brix)
    }

    func testAcidReachesItsTargetMidWindowInASunnySeason() {
        var block = freshBlock(.happyCanyonSauvignonBlanc)
        let middle = block.varietal.window(for: .white).middle
        while block.brix < middle { block.ripen(in: .sunny) }
        // Within one week's worth of acid of the target.
        XCTAssertEqual(block.acid, block.varietal.acidAtIdeal, accuracy: 0.8)
    }

    func testRipenessLabels() {
        let window = 24.0...26.0
        XCTAssertEqual(Ripeness(brix: 21, window: window), .early)
        XCTAssertEqual(Ripeness(brix: 23.5, window: window), .almost)
        XCTAssertEqual(Ripeness(brix: 25, window: window), .ready)
        XCTAssertEqual(Ripeness(brix: 27, window: window), .late)
        XCTAssertEqual(Ripeness(brix: 28, window: window), .raisined)
    }

    func testWeatherTurnsWetterInOctober() {
        var rng = SeededGenerator(seed: 7)
        var earlyRain = 0
        var lateRain = 0
        for _ in 0..<2000 {
            if Weather.roll(week: 0, using: &rng) == .rain { earlyRain += 1 }
            if Weather.roll(week: HarvestCalendar.weeks - 1, using: &rng) == .rain { lateRain += 1 }
        }
        XCTAssertLessThan(earlyRain, 150)
        XCTAssertGreaterThan(lateRain, 400)
    }
}

/// Plays a picking round like a person: each cluster gets one glance after
/// `reaction` seconds, and is picked or left.
func play(_ round: inout PickingRound, skill: Double = 0.9, mistakes: Double = 0.1,
          reaction: Double = 0.5, seed: UInt64 = 99) {
    var rng = SeededGenerator(seed: seed)
    var seen = Set<Int>()
    while !round.isOver {
        round.advance(by: 1.0 / 30)
        for cluster in round.clusters where !seen.contains(cluster.id) && cluster.age(at: round.time) >= reaction {
            seen.insert(cluster.id)
            let roll = Double.random(in: 0..<1, using: &rng)
            switch cluster.kind {
            case .ripe, .golden: if roll < skill { round.pick(cluster.id) }
            case .unripe: if roll < mistakes { round.pick(cluster.id) }
            case .rotten: if roll < mistakes / 2 { round.pick(cluster.id) }
            }
        }
    }
}

final class PickingTests: XCTestCase {
    func testSameSeedSameRound() {
        var a = PickingRound(unripeShare: 0.1, rotShare: 0.1, seed: 5)
        var b = PickingRound(unripeShare: 0.1, rotShare: 0.1, seed: 5)
        play(&a)
        play(&b)
        XCTAssertEqual(a.tally, b.tally)
        XCTAssertEqual(a.points, b.points)
        XCTAssertGreaterThan(a.offered, 40)
    }

    func testGoodPickerBringsInTheWholeCrop() {
        var round = PickingRound(unripeShare: 0.04, rotShare: 0, seed: 1)
        play(&round, skill: 0.9)
        XCTAssertTrue(round.isOver)
        XCTAssertEqual(round.harvestedShare, 1)
        XCTAssertGreaterThan(round.tally.ripe, 30)
    }

    func testIdlePickerBringsInNothing() {
        var round = PickingRound(unripeShare: 0.04, rotShare: 0, seed: 1)
        play(&round, skill: 0, mistakes: 0)
        XCTAssertEqual(round.harvestedShare, 0)
        XCTAssertEqual(round.tally.picked, 0)
        XCTAssertGreaterThan(round.tally.missed, 30)
    }

    func testCarelessPickerGetsLessThanAFullBin() {
        var round = PickingRound(unripeShare: 0.04, rotShare: 0, seed: 1)
        play(&round, skill: 0.4)
        XCTAssertLessThan(round.harvestedShare, 0.7)
        XCTAssertGreaterThan(round.harvestedShare, 0.3)
    }

    func testStreakMultiplierAndMoldyPicks() throws {
        var round = PickingRound(unripeShare: 0, rotShare: 0, seed: 3)
        var points: [Int] = []
        while points.count < 6 {
            round.advance(by: 0.05)
            if let cluster = round.clusters.first {
                let before = round.points
                let kind = round.pick(cluster.id)
                // Golden clusters are worth five ripe ones.
                points.append((round.points - before) / (kind == .golden ? 5 : 1))
            }
        }
        XCTAssertEqual(points, [10, 10, 10, 10, 20, 20])
        XCTAssertEqual(round.streak, 6)

        var moldy = PickingRound(unripeShare: 0, rotShare: 0.6, seed: 4)
        while moldy.clusters.first(where: { $0.kind == .rotten }) == nil { moldy.advance(by: 0.05) }
        let cluster = try XCTUnwrap(moldy.clusters.first { $0.kind == .rotten })
        XCTAssertEqual(moldy.pick(cluster.id), .rotten)
        XCTAssertEqual(moldy.tally.rotten, 1)
        XCTAssertEqual(moldy.streak, 0)
        XCTAssertNil(moldy.pick(cluster.id), "already picked")
    }

    func testWaspStingCostsTime() throws {
        var round = PickingRound(unripeShare: 0, rotShare: 0, seed: 8)
        while round.wasps.first(where: { $0.position(at: round.time) != nil }) == nil { round.advance(by: 0.05) }
        let wasp = try XCTUnwrap(round.wasps.first)
        let left = round.timeLeft
        XCTAssertTrue(round.swat(wasp.id))
        XCTAssertEqual(round.timeLeft, left - PickingRound.sting, accuracy: 1e-9)
        XCTAssertEqual(round.tally.stings, 1)
        XCTAssertFalse(round.swat(wasp.id))
    }

    func testClustersStayOnFreeSpots() {
        var round = PickingRound(unripeShare: 0.2, rotShare: 0.2, seed: 11)
        while !round.isOver {
            round.advance(by: 0.1)
            XCTAssertLessThanOrEqual(round.clusters.count, PickingRound.maxClusters)
            XCTAssertEqual(Set(round.clusters.map(\.spot)).count, round.clusters.count)
        }
    }

    func testEarlyPickHasMoreGreenFruit() {
        var block = VineyardBlock.losOlivosGrenache
        var rng = SeededGenerator(seed: 1)
        block.startVintage(using: &rng)
        block.set(brix: 21.5)
        let forRed = PickingRound(block: block, style: .red, seed: 1)
        let forRose = PickingRound(block: block, style: .rose, seed: 1)
        XCTAssertGreaterThan(forRed.unripeShare, 0.3)
        XCTAssertEqual(forRose.unripeShare, 0.1, accuracy: 1e-9)
    }
}

/// Fruit picked at a chosen sugar, for cellar and blending tests.
func harvest(_ varietal: Varietal, style: WineStyle? = nil, brix: Double? = nil, unripe: Double = 0,
             rot: Double = 0, golden: Int = 0, tons: Double = 3, site: Double = 3) -> Harvest {
    let style = style ?? varietal.mainStyle
    let brix = brix ?? varietal.window(for: style).middle
    let acid = varietal.acidAtIdeal + 0.8 * (varietal.window(for: varietal.mainStyle).middle - brix)
    var tally = PickingRound.Tally()
    tally.golden = golden
    return Harvest(blockID: varietal.rawValue, blockName: "Test \(varietal.name)", varietal: varietal, style: style,
                   tons: tons, brix: brix, acid: acid, unripeShare: unripe, rotShare: rot, sortedOut: 0,
                   picking: PickingRound.Summary(tally: tally, harvestedShare: 1, points: 0, bestStreak: 0),
                   site: site, character: TasteProfile())
}

final class CellarTests: XCTestCase {
    func testQualityPeaksMidWindowWithCleanFruit() {
        let perfect = harvest(.syrah).quality
        XCTAssertEqual(perfect, 96, accuracy: 1e-9)
        XCTAssertLessThan(harvest(.syrah, brix: 25.9).quality, perfect)
        XCTAssertLessThan(harvest(.syrah, brix: 27.5).quality, harvest(.syrah, brix: 25.9).quality - 10)
        XCTAssertLessThan(harvest(.syrah, rot: 0.1).quality, perfect - 9)
        XCTAssertLessThan(harvest(.syrah, unripe: 0.1).quality, perfect - 4)
        XCTAssertEqual(harvest(.syrah, golden: 3).quality, 99, accuracy: 1e-9)
        XCTAssertEqual(harvest(.syrah, golden: 5, site: 4).quality, 100, "capped")
    }

    func testRoseGoesToStainlessSteel() throws {
        let lots = harvest(.grenache, style: .rose).lots(vessel: .newOak, method: .saignee)
        let lot = try XCTUnwrap(lots.first)
        XCTAssertEqual(lots.count, 1)
        XCTAssertEqual(lot.style, .rose)
        XCTAssertEqual(lot.vessel, .stainless)
        XCTAssertLessThan(lot.profile.tannin, 1)
    }

    func testSaigneeBleedsAFifthAsRose() throws {
        let fruit = harvest(.grenache, tons: 5)
        let lots = fruit.lots(vessel: .neutralOak, method: .saignee)
        XCTAssertEqual(lots.count, 2)
        let red = try XCTUnwrap(lots.first { $0.style == .red })
        let rose = try XCTUnwrap(lots.first { $0.style == .rose })
        XCTAssertEqual(red.cases + rose.cases, fruit.cases)
        XCTAssertEqual(rose.cases, 60)
        let plain = try XCTUnwrap(fruit.lots(vessel: .neutralOak, method: .red).first)
        XCTAssertGreaterThan(red.profile.tannin, plain.profile.tannin)
        XCTAssertGreaterThan(red.quality, plain.quality)
    }

    func testVesselsShapeTheWine() throws {
        let fruit = harvest(.sauvignonBlanc)
        let steel = try XCTUnwrap(fruit.lots(vessel: .stainless, method: .red).first)
        let neutral = try XCTUnwrap(fruit.lots(vessel: .neutralOak, method: .red).first)
        let new = try XCTUnwrap(fruit.lots(vessel: .newOak, method: .red).first)
        XCTAssertEqual(steel.profile.oak, 0)
        XCTAssertGreaterThan(neutral.profile.oak, steel.profile.oak)
        XCTAssertGreaterThan(new.profile.oak, neutral.profile.oak)
        XCTAssertGreaterThan(steel.profile.acidity, neutral.profile.acidity)
    }

    func testFaults() {
        XCTAssertEqual(harvest(.syrah).faults, [])
        XCTAssertEqual(harvest(.syrah, unripe: 0.2, rot: 0.1).faults, [.green, .moldy])
    }
}

final class BlendTests: XCTestCase {
    private func lot(_ fruit: Harvest, _ vessel: Vessel = .neutralOak, _ method: CrushMethod = .red) -> Lot {
        fruit.lots(vessel: vessel, method: method)[0]
    }

    func testCleanStainlessSybariteScoresWell() {
        let analysis = WineSpec.sybarite.analyze([(lot(harvest(.sauvignonBlanc), .stainless), 180)])
        XCTAssertEqual(analysis.problems, [])
        XCTAssertEqual(analysis.misses, [:])
        XCTAssertGreaterThanOrEqual(analysis.score, 93)
        XCTAssertEqual(analysis.cases, 180)
        XCTAssertEqual(analysis.composition, [VarietalShare(varietal: .sauvignonBlanc, share: 1)])
    }

    func testOakedSybariteMissesTheStyle() {
        let steel = WineSpec.sybarite.analyze([(lot(harvest(.sauvignonBlanc), .stainless), 180)])
        let oaky = WineSpec.sybarite.analyze([(lot(harvest(.sauvignonBlanc), .newOak), 180)])
        XCTAssertNotNil(oaky.misses[.oak])
        XCTAssertLessThan(oaky.score, steel.score - 4)
    }

    func testM5NeedsAllFive() {
        let lots = [Varietal.syrah, .grenache, .mourvedre, .counoise].map { lot(harvest($0)) }
        let analysis = WineSpec.m5.analyze(lots.map { ($0, 50) })
        XCTAssertFalse(analysis.canBottle)
        XCTAssertEqual(analysis.problems.count, 1)
        XCTAssertTrue(analysis.problems[0].contains("Cinsault"))
    }

    func testUberNeedsThreeQuartersSyrah() {
        let syrah = lot(harvest(.syrah), .newOak)
        let grenache = lot(harvest(.grenache), .newOak)
        XCTAssertFalse(WineSpec.uber.analyze([(syrah, 60), (grenache, 40)]).canBottle)
        XCTAssertTrue(WineSpec.uber.analyze([(syrah, 80), (grenache, 20)]).canBottle)
    }

    func testWrongStyleCantGoIn() {
        let red = lot(harvest(.grenache))
        let analysis = WineSpec.rose.analyze([(red, 50)])
        XCTAssertFalse(analysis.canBottle)
    }

    func testNewOakMakesABetterUber() {
        let ripe = harvest(.syrah, brix: 25.5)
        let neutral = WineSpec.uber.analyze([(lot(ripe, .neutralOak), 200)])
        let new = WineSpec.uber.analyze([(lot(ripe, .newOak), 200)])
        XCTAssertGreaterThan(new.score, neutral.score + 3)
        XCTAssertGreaterThanOrEqual(new.score, 92)
    }

    func testGreatFiveGrapeM5ReachesTheHighNineties() {
        let parts: [(Varietal, Int)] = [(.syrah, 40), (.grenache, 25), (.mourvedre, 20), (.counoise, 8), (.cinsault, 7)]
        // A little new oak, on the Syrah.
        let analysis = WineSpec.m5.analyze(parts.map {
            (lot(harvest($0.0, site: 4), $0.0 == .syrah ? .newOak : .neutralOak), $0.1 * 3)
        })
        XCTAssertTrue(analysis.canBottle, "\(analysis.problems)")
        XCTAssertGreaterThanOrEqual(analysis.score, 97, "\(analysis.misses)")
        XCTAssertEqual(analysis.composition.map(\.varietal), [.syrah, .grenache, .mourvedre, .counoise, .cinsault])
    }

    func testRoseFromEarlyGrenacheFitsTheStyle() {
        let analysis = WineSpec.rose.analyze([(lot(harvest(.grenache, style: .rose)), 120)])
        XCTAssertEqual(analysis.misses, [:])
        XCTAssertTrue(analysis.canBottle)
    }

    func testTastingNoteVerbsAgree() {
        let single = WineSpec.sybarite.analyze([(lot(harvest(.sauvignonBlanc), .stainless), 100)])
        let blend = WineSpec.m5.analyze([Varietal.syrah, .grenache, .mourvedre, .counoise, .cinsault]
            .map { (lot(harvest($0)), 50) })
        for seed in 1...20 {
            var rng = SeededGenerator(seed: UInt64(seed))
            let one = TastingNote.write(for: .sybarite, analysis: single, score: 93, faults: [], using: &rng)
            let many = TastingNote.write(for: .m5, analysis: blend, score: 96, faults: [], using: &rng)
            XCTAssertTrue(["leads", "jumps", "fills", "comes"].contains { one.contains(" \($0) ") }, one)
            XCTAssertTrue(["lead", "jump", "fill", "come"].contains { many.contains(" \($0) ") }, many)
        }
    }

    func testOverripeWineRunsHot() {
        let raisins = lot(harvest(.syrah, brix: 28.5), .newOak)
        let analysis = WineSpec.uber.analyze([(raisins, 100)])
        XCTAssertGreaterThan(analysis.alcohol, 15.5)
        XCTAssertLessThan(analysis.score, 90)
    }
}

final class GameTests: XCTestCase {
    func testNewGame() {
        let game = Game(vintage: 2026, seed: 1)
        XCTAssertEqual(game.phase, .harvest)
        XCTAssertEqual(game.blocks.map(\.varietal), [.sauvignonBlanc, .grenache, .syrah])
        XCTAssertEqual(game.season.count, HarvestCalendar.weeks)
        XCTAssertEqual(game.money, 25_000)
        XCTAssertEqual(game.date, "Aug 25")
        XCTAssertEqual(game.forecast.count, 1)
        XCTAssertTrue(game.blocks.allSatisfy { $0.tons > 3 && $0.brix > 17 })
    }

    func testOneCrewPicksOneBlockAWeek() throws {
        var game = Game(vintage: 2026, seed: 2)
        var round = try XCTUnwrap(game.startPicking(VineyardBlock.happyCanyonSauvignonBlanc.id, for: .white))
        XCTAssertNil(game.startPicking(VineyardBlock.happyCanyonSauvignonBlanc.id, for: .red), "white grapes")
        play(&round)
        let fruit = try XCTUnwrap(game.bringIn(round, from: VineyardBlock.happyCanyonSauvignonBlanc.id, for: .white))
        XCTAssertGreaterThan(fruit.tons, 1)
        XCTAssertEqual(game.crushPad, fruit)
        XCTAssertEqual(game.picksLeft, 0)
        XCTAssertFalse(game.canPick(VineyardBlock.losOlivosGrenache.id))
        game.nextWeek()
        XCTAssertEqual(game.week, 0, "can't leave fruit on the crush pad")
        let lots = game.crush(in: .stainless)
        XCTAssertEqual(lots.count, 1)
        XCTAssertNil(game.crushPad)
        game.nextWeek()
        XCTAssertEqual(game.week, 1)
        XCTAssertTrue(game.canPick(VineyardBlock.losOlivosGrenache.id))
        XCTAssertFalse(game.canPick(VineyardBlock.happyCanyonSauvignonBlanc.id), "already picked")
        XCTAssertEqual(game.bill.picking, Game.pickingCost)
        XCTAssertEqual(game.bill.grapes, fruit.tons * Varietal.sauvignonBlanc.pricePerTon, accuracy: 1e-6)
    }

    func testAdvice() throws {
        var game = Game(vintage: 2026, seed: 9)
        let sb = VineyardBlock.happyCanyonSauvignonBlanc.id
        let grenache = VineyardBlock.losOlivosGrenache.id
        let syrah = VineyardBlock.ballardCanyonSyrah.id
        game.setBlock(sb) { $0.set(brix: 19) }
        game.setBlock(grenache) { $0.set(brix: 18) }
        game.setBlock(syrah) { $0.set(brix: 18) }
        XCTAssertEqual(game.advice, "Nothing's ripe yet. Wait a week and watch the forecast.")
        game.setBlock(grenache) { $0.set(brix: 21.5) }
        XCTAssertEqual(game.advice, "Los Olivos Grenache is in the pink: pick it now for rosé, or wait for red.")
        game.setBlock(sb) { $0.set(brix: 22.5) }
        XCTAssertTrue(try XCTUnwrap(game.advice).contains("Happy Canyon Sauvignon Blanc is ready"))
        game.setBlock(syrah) { $0.set(brix: 27.5) }
        XCTAssertEqual(game.advice, "Ballard Canyon Syrah is getting overripe. Pick it soon.")
        var round = try XCTUnwrap(game.startPicking(sb, for: .white))
        play(&round)
        game.bringIn(round, from: sb, for: .white)
        XCTAssertNil(game.advice, "fruit on the crush pad")
        game.crush(in: .stainless)
        XCTAssertEqual(game.advice, "The crews are busy until next week.")
    }

    func testEmptyHandedCrewLeavesTheBlockHanging() throws {
        var game = Game(vintage: 2026, seed: 3)
        let id = VineyardBlock.ballardCanyonSyrah.id
        var round = try XCTUnwrap(game.startPicking(id, for: .red))
        play(&round, skill: 0, mistakes: 0)
        XCTAssertNil(game.bringIn(round, from: id, for: .red))
        XCTAssertNil(game.crushPad)
        XCTAssertEqual(game.block(id)?.picked, false)
        XCTAssertEqual(game.picksLeft, 0)
    }

    func testNewOakNeedsBarrels() throws {
        var game = Game(vintage: 2026, seed: 4)
        let id = VineyardBlock.ballardCanyonSyrah.id
        var round = try XCTUnwrap(game.startPicking(id, for: .red))
        play(&round)
        game.bringIn(round, from: id, for: .red)
        XCTAssertEqual(game.vessels, [.stainless, .neutralOak])
        let lots = game.crush(in: .newOak)
        XCTAssertEqual(lots.first?.vessel, .neutralOak)
        XCTAssertEqual(game.bill.oak, 0)
    }

    func testRainEndsTheHarvestAfterTheLastWeek() {
        var game = Game(vintage: 2026, seed: 5)
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        XCTAssertEqual(game.phase, .cellar)
        XCTAssertGreaterThan(game.lostTons, 10)
        XCTAssertTrue(game.diary.contains { $0.text.contains("Still on the vine") })
        XCTAssertEqual(game.blocker(for: .sybarite), "No white wine in the cellar")
    }

    func testFullVintage() throws {
        var game = Game(vintage: 2026, seed: 6)
        let sb = VineyardBlock.happyCanyonSauvignonBlanc.id
        let grenache = VineyardBlock.losOlivosGrenache.id
        let syrah = VineyardBlock.ballardCanyonSyrah.id
        game.setBlock(sb) { $0.set(brix: 22.5, acid: 7.4) }
        game.setBlock(grenache) { $0.set(brix: 24.5, acid: 5.6) }
        game.setBlock(syrah) { $0.set(brix: 25, acid: 6) }
        for (id, method) in [(sb, CrushMethod.red), (grenache, .saignee), (syrah, .red)] {
            let style = game.block(id)?.varietal.mainStyle ?? .red
            var round = try XCTUnwrap(game.startPicking(id, for: style))
            play(&round)
            _ = try XCTUnwrap(game.bringIn(round, from: id, for: style))
            game.crush(in: id == sb ? .stainless : .neutralOak, method: method)
            game.nextWeek()
        }
        game.finishHarvest()
        XCTAssertEqual(game.phase, .cellar)
        XCTAssertEqual(game.lots.count, 4)
        XCTAssertEqual(game.blocker(for: .m5), "Needs Mourvèdre, Counoise and Cinsault")
        XCTAssertNil(game.blocker(for: .rose))

        for wine in [WineID.sybarite, .rose, .uber] {
            let blend = Blend(wine: wine, cases: Dictionary(uniqueKeysWithValues: game.lots(for: wine).map { ($0.id, $0.cases) }))
            let analysis = game.analyze(blend)
            if wine == .uber {
                XCTAssertFalse(analysis.canBottle, "Grenache makes it under 75% Syrah")
                let syrahOnly = Blend(wine: wine, cases: Dictionary(uniqueKeysWithValues: game.lots(for: wine)
                    .filter { $0.varietal == .syrah }.map { ($0.id, $0.cases) }))
                _ = try XCTUnwrap(game.bottle(syrahOnly))
            } else {
                let bottled = try XCTUnwrap(game.bottle(blend))
                XCTAssertGreaterThanOrEqual(bottled.score, 85)
                XCTAssertFalse(bottled.note.isEmpty)
            }
        }
        XCTAssertNil(game.bottle(Blend(wine: .sybarite)), "one bottling per wine")
        XCTAssertEqual(game.lots.map(\.varietal), [.grenache], "the red Grenache is left over")
        let bulk = game.lots[0].cases

        let moneyBefore = game.money
        let report = try XCTUnwrap(game.release())
        XCTAssertEqual(game.phase, .offseason)
        XCTAssertEqual(report.wines.count, 3)
        XCTAssertEqual(report.bulkCases, bulk)
        XCTAssertGreaterThan(report.profit, 50_000)
        XCTAssertEqual(game.money, moneyBefore + report.profit, accuracy: 1e-6)
        XCTAssertEqual(game.library.count, 3)
        XCTAssertTrue(game.lots.isEmpty)
        XCTAssertEqual(report.reputationAfter, game.reputation)
    }

    func testUpgradesAndTheNextVintage() {
        var game = Game(vintage: 2026, seed: 7)
        XCTAssertFalse(game.canBuy(.weatherStation), "only in the offseason")
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        game.release()
        game.setMoney(500_000)
        XCTAssertFalse(game.canBuy(.thirdCrew), "second crew first")
        XCTAssertTrue(game.buy(.secondCrew))
        XCTAssertTrue(game.buy(.thirdCrew))
        XCTAssertTrue(game.buy(.weatherStation))
        XCTAssertTrue(game.buy(.mourvedreBlock))
        XCTAssertFalse(game.buy(.mourvedreBlock), "already owned")
        let spent = [Upgrade.secondCrew, .thirdCrew, .weatherStation, .mourvedreBlock].reduce(0) { $0 + $1.cost }
        XCTAssertEqual(game.money, 500_000 - spent)
        game.startNextVintage()
        XCTAssertEqual(game.vintage, 2027)
        XCTAssertEqual(game.phase, .harvest)
        XCTAssertEqual(game.blocks.count, 4)
        XCTAssertTrue(game.blocks.allSatisfy { !$0.picked })
        XCTAssertEqual(game.crewSize, 3)
        XCTAssertEqual(game.forecast.count, 3)
        XCTAssertEqual(game.lostTons, 0)
    }

    func testSavesAndLoads() throws {
        var game = Game(vintage: 2026, seed: 8)
        var round = try XCTUnwrap(game.startPicking(VineyardBlock.losOlivosGrenache.id, for: .rose))
        play(&round)
        game.bringIn(round, from: VineyardBlock.losOlivosGrenache.id, for: .rose)
        let data = try JSONEncoder().encode(game)
        var loaded = try JSONDecoder().decode(Game.self, from: data)
        XCTAssertEqual(loaded, game)
        // Same seed, same future.
        game.crush(in: .stainless)
        loaded.crush(in: .stainless)
        game.nextWeek()
        loaded.nextWeek()
        XCTAssertEqual(loaded.blocks, game.blocks)
        XCTAssertEqual(loaded.diary, game.diary)
    }
}

/// A simulated player, used to check the game's balance: scores, money and
/// reputation over several vintages.
struct Bot {
    var skill: Double
    var mistakes: Double
    var reaction: Double
    /// Waits for the middle of the window instead of picking as soon as it's ready.
    var patient: Bool
    var seed: UInt64 = 1
    private(set) var profits: [Double] = []

    static let casual = Bot(skill: 0.75, mistakes: 0.2, reaction: 0.7, patient: false)
    static let expert = Bot(skill: 0.95, mistakes: 0.03, reaction: 0.45, patient: true)

    private static let wishlist: [Upgrade] = [
        .cinsaultBlock, .counoiseBlock, .mourvedreBlock, .secondCrew, .frenchOak, .sortingTable,
        .weatherStation, .santaMariaSyrah, .thirdCrew, .tastingRoom,
    ]

    mutating func playVintage(_ game: inout Game) {
        while game.phase == .harvest {
            for block in game.blocks.filter({ !$0.picked }) where game.picksLeft > 0 && shouldPick(block, game) {
                let style = block.varietal.mainStyle
                guard var round = game.startPicking(block.id, for: style) else { continue }
                seed += 1
                play(&round, skill: skill, mistakes: mistakes, reaction: reaction, seed: seed)
                guard game.bringIn(round, from: block.id, for: style) != nil else { continue }
                let vessel: Vessel = style == .white ? .stainless
                    : block.varietal == .syrah && game.vessels.contains(.newOak) ? .newOak : .neutralOak
                game.crush(in: vessel, method: block.varietal == .grenache ? .saignee : .red)
            }
            if game.blocks.allSatisfy(\.picked) { game.finishHarvest() } else { game.nextWeek() }
        }

        bottleAll(.sybarite, &game)
        bottleAll(.rose, &game)
        if game.blocker(for: .m5) == nil {
            let recipe: [Varietal: Double] = [.syrah: 0.35, .grenache: 0.25, .mourvedre: 0.2, .counoise: 0.1, .cinsault: 0.1]
            let lots = game.lots(for: .m5)
            var available: [Varietal: Int] = [:]
            for lot in lots { available[lot.varietal, default: 0] += lot.cases }
            let total = recipe.map { Double(available[$0.key] ?? 0) / $0.value }.min() ?? 0
            var cases: [UUID: Int] = [:]
            for (grape, share) in recipe {
                var wanted = Int(total * share)
                for lot in lots where lot.varietal == grape && wanted > 0 {
                    cases[lot.id] = min(lot.cases, wanted)
                    wanted -= lot.cases
                }
            }
            game.bottle(Blend(wine: .m5, cases: cases))
        }
        // ÜBER: start from the best Syrah, and add the others if they don't hurt.
        var uber = Blend(wine: .uber)
        let syrah = game.lots(for: .uber).filter { $0.varietal == .syrah }.sorted { $0.quality > $1.quality }
        for lot in syrah {
            var bigger = uber
            bigger.cases[lot.id] = lot.cases
            if uber.cases.isEmpty || game.analyze(bigger).score >= game.analyze(uber).score { uber = bigger }
        }
        game.bottle(uber)
        if let report = game.release() { profits.append(report.profit) }

        for upgrade in Self.wishlist { game.buy(upgrade) }
        game.startNextVintage()
    }

    private func shouldPick(_ block: VineyardBlock, _ game: Game) -> Bool {
        let window = block.varietal.window(for: block.varietal.mainStyle)
        let coming = game.forecast.first?.weather
        switch block.ripeness(for: block.varietal.mainStyle) {
        case .early, .almost:
            return game.isLastWeek
        case .ready:
            return !patient || block.brix >= window.middle - 0.3 || coming == .rain || coming == .heatWave
                || game.isLastWeek
        case .late, .raisined:
            return true
        }
    }

    private func bottleAll(_ wine: WineID, _ game: inout Game) {
        let lots = game.lots(for: wine)
        game.bottle(Blend(wine: wine, cases: Dictionary(uniqueKeysWithValues: lots.map { ($0.id, $0.cases) })))
    }
}

final class BalanceTests: XCTestCase {
    struct Result {
        var scores: [WineID: [Int]] = [:]
        /// Each vintage's profit, every game.
        var profits: [Double] = []
        /// Upgrades owned after five vintages, every game.
        var upgrades: [Int] = []
    }

    /// Plays five vintages with a dozen seeds.
    private func simulate(_ player: Bot) -> Result {
        var result = Result()
        for seed in 1...12 {
            var game = Game(vintage: 2026, seed: UInt64(seed))
            var bot = player
            bot.seed = UInt64(seed) * 1000
            for _ in 0..<5 { bot.playVintage(&game) }
            for wine in game.library { result.scores[wine.wine, default: []].append(wine.score) }
            result.profits += bot.profits
            result.upgrades.append(game.upgrades.count)
        }
        return result
    }

    private func averages(_ name: String, _ result: Result) -> [WineID: Double] {
        var averages: [WineID: Double] = [:]
        for wine in WineID.allCases {
            let s = result.scores[wine] ?? []
            averages[wine] = Double(s.reduce(0, +)) / Double(max(1, s.count))
            print("\(name) \(wine.spec.name): \(s.count) wines, average \(oneDecimal(averages[wine] ?? 0)), "
                + "range \(s.min() ?? 0)–\(s.max() ?? 0)")
        }
        print("\(name) profits: \(result.profits.map { Int($0 / 1000) }) k; upgrades after 5 vintages: \(result.upgrades)")
        return averages
    }

    func testCasualPlayersMakeGoodWineAndMoney() {
        let result = simulate(.casual)
        let average = averages("Casual", result)
        XCTAssertGreaterThan(result.profits.filter { $0 > 0 }.count, result.profits.count * 9 / 10)
        XCTAssertTrue(result.upgrades.allSatisfy { $0 >= 4 }, "\(result.upgrades)")
        XCTAssertGreaterThan(result.scores[.m5, default: []].count, 20, "should get to M5")
        XCTAssertTrue((89...94).contains(average[.sybarite] ?? 0))
        XCTAssertTrue((85...92).contains(average[.rose] ?? 0))
        XCTAssertTrue((91...97).contains(average[.m5] ?? 0))
        XCTAssertTrue((84...92).contains(average[.uber] ?? 0))
    }

    func testExpertsDoBetterButHundredsStayRare() {
        let casual = averages("Casual", simulate(.casual))
        let result = simulate(.expert)
        let expert = averages("Expert", result)
        for wine in WineID.allCases {
            XCTAssertGreaterThan(expert[wine] ?? 0, (casual[wine] ?? 0) + 0.5, wine.spec.name)
        }
        let all = result.scores.values.flatMap { $0 }
        XCTAssertLessThan(all.filter { $0 == 100 }.count, all.count / 10)
    }
}
