import XCTest
@testable import CrushKit

final class GameTests: XCTestCase {
    private let sb = VineyardBlock.happyCanyonSauvignonBlanc.id
    private let grenache = VineyardBlock.losOlivosGrenache.id
    private let syrah = VineyardBlock.ballardCanyonSyrah.id

    func testANewWineryStartsIn2001() {
        let game = Game(vintage: Game.firstVintage, seed: 1)
        XCTAssertEqual(game.vintage, 2001)
        XCTAssertEqual(game.phase, .harvest)
        XCTAssertEqual(game.blocks.map(\.varietal), [.sauvignonBlanc, .grenache, .syrah])
        XCTAssertEqual(game.season.count, HarvestCalendar.weeks)
        XCTAssertEqual(game.money, 25_000)
        XCTAssertEqual(game.date, "Aug 25")
        XCTAssertEqual(game.forecast.count, 1)
        XCTAssertEqual(game.monthsLeft, 0)
        XCTAssertTrue(game.blocks.allSatisfy { $0.tons > 3 && $0.brix > 17 })
    }

    func testOneCrewPicksOneBlockAWeek() throws {
        var game = Game(vintage: Game.firstVintage, seed: 2)
        var round = try XCTUnwrap(game.startPicking(sb, for: .white))
        XCTAssertNil(game.startPicking(sb, for: .red), "white grapes")
        play(&round)
        let fruit = try XCTUnwrap(game.bringIn(round, from: sb, for: .white))
        XCTAssertGreaterThan(fruit.tons, 1)
        XCTAssertEqual(game.crushPad, fruit)
        XCTAssertEqual(game.picksLeft, 0)
        XCTAssertFalse(game.canPick(grenache))
        game.nextWeek()
        XCTAssertEqual(game.week, 0, "can't leave fruit on the crush pad")
        let lots = game.crush(in: .stainless)
        XCTAssertEqual(lots.count, 1)
        XCTAssertNil(game.crushPad)
        game.nextWeek()
        XCTAssertEqual(game.week, 1)
        XCTAssertTrue(game.canPick(grenache))
        XCTAssertFalse(game.canPick(sb), "already picked")
        XCTAssertEqual(game.bill.picking, Game.pickingCost)
        XCTAssertEqual(game.bill.grapes, fruit.tons * Varietal.sauvignonBlanc.pricePerTon, accuracy: 1e-6)
    }

    func testWhatsInTheBinsIsWhatGetsMade() throws {
        var game = Game(vintage: Game.firstVintage, seed: 12)
        let block = try XCTUnwrap(game.block(syrah))
        var round = try XCTUnwrap(game.startPicking(syrah, for: .red))
        play(&round, picking: .smart)
        let fruit = try XCTUnwrap(game.bringIn(round, from: syrah, for: .red))
        let bin = round.bin
        XCTAssertEqual(fruit.brix - block.brix, bin.brix - round.expected.brix, accuracy: 1e-9)
        XCTAssertEqual(fruit.acid - block.acid, bin.acid - round.expected.acid, accuracy: 1e-9)
        XCTAssertEqual(fruit.tannin, bin.tannin - round.expected.tannin, accuracy: 1e-9)
        XCTAssertEqual(fruit.color, bin.color - round.expected.color, accuracy: 1e-9)
        XCTAssertEqual(fruit.green, bin.green, accuracy: 1e-9)
        XCTAssertEqual(fruit.complexity, bin.complexity, accuracy: 1e-9)
        XCTAssertEqual(fruit.mogShare, bin.mogShare, accuracy: 1e-9)
        XCTAssertEqual(fruit.picking, round.summary)
        XCTAssertEqual(fruit.temperature, game.season[0].actual.fruitTemperature)
        XCTAssertEqual(fruit.sortedOut, 0)
    }

    func testTheSortingTableCatchesRotAndLeaves() throws {
        var game = Game(vintage: Game.firstVintage, seed: 10)
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        while game.phase == .cellar { game.nextMonth() }
        game.setMoney(500_000)
        XCTAssertTrue(game.buy(.sortingTable))
        game.startNextVintage()
        game.setBlock(grenache) { $0.set(rot: 0.3) }
        var round = try XCTUnwrap(game.startPicking(grenache, for: .red))
        play(&round, mistakes: 1)
        let fruit = try XCTUnwrap(game.bringIn(round, from: grenache, for: .red))
        XCTAssertGreaterThan(fruit.sortedOut, 0)
        XCTAssertLessThan(fruit.rotShare, round.bin.rotShare / 2)
    }

    func testAdvice() throws {
        var game = Game(vintage: Game.firstVintage, seed: 9)
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
        var game = Game(vintage: Game.firstVintage, seed: 3)
        var round = try XCTUnwrap(game.startPicking(syrah, for: .red))
        play(&round, skill: 0, mistakes: 0)
        XCTAssertNil(game.bringIn(round, from: syrah, for: .red))
        XCTAssertNil(game.crushPad)
        XCTAssertEqual(game.block(syrah)?.picked, false)
        XCTAssertEqual(game.picksLeft, 0)
    }

    func testNewOakNeedsBarrels() throws {
        var game = Game(vintage: Game.firstVintage, seed: 4)
        var round = try XCTUnwrap(game.startPicking(syrah, for: .red))
        play(&round)
        game.bringIn(round, from: syrah, for: .red)
        XCTAssertEqual(game.vessels, [.stainless, .neutralOak])
        let lots = game.crush(in: .newOak)
        XCTAssertEqual(lots.first?.vessel, .neutralOak)
        XCTAssertEqual(game.bill.oak, 0)
    }

    func testRainEndsTheHarvestAfterTheLastWeek() {
        var game = Game(vintage: Game.firstVintage, seed: 5)
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        XCTAssertEqual(game.phase, .cellar)
        XCTAssertEqual(game.date, "Nov")
        XCTAssertEqual(game.monthsLeft, Aging.last)
        XCTAssertGreaterThan(game.lostTons, 10)
        XCTAssertTrue(game.diary.contains { $0.text.contains("Still on the vine") })
        XCTAssertEqual(game.blocker(for: .sybarite), "No white wine in the cellar")
    }

    func testDougsCrushGoesIntoTheCellar() throws {
        var game = Game(vintage: Game.firstVintage, seed: 6)
        var round = try XCTUnwrap(game.startPicking(grenache, for: .red))
        play(&round)
        let fruit = try XCTUnwrap(game.bringIn(round, from: grenache, for: .red))
        var session = try XCTUnwrap(game.startWinemaking())
        XCTAssertEqual(session.harvest, fruit)
        XCTAssertEqual(session.vessels, [.stainless, .neutralOak])
        XCTAssertEqual(game.finishWinemaking(session), [], "not finished yet")
        XCTAssertNotNil(game.crushPad)
        session.finish(with: CrushPlan(skill: 1, saignee: true))
        let lots = game.finishWinemaking(session)
        XCTAssertEqual(lots.map(\.style), [.red, .rose])
        XCTAssertNil(game.crushPad)
        XCTAssertEqual(game.lots, lots)
        XCTAssertEqual(game.finishWinemaking(session), [], "only once")
    }

    func testFullVintage() throws {
        var game = Game(vintage: Game.firstVintage, seed: 6)
        let picks: [(String, Double, Double, CrushMethod, Vessel)] = [
            (sb, 22.5, 7.4, .red, .stainless), (grenache, 24.5, 5.6, .saignee, .neutralOak),
            (syrah, 25, 6, .red, .neutralOak),
        ]
        for (id, brix, acid, method, vessel) in picks {
            // Each block picked in the middle of its window.
            game.setBlock(id) { $0.set(brix: brix, acid: acid) }
            let style = try XCTUnwrap(game.block(id)).varietal.mainStyle
            var round = try XCTUnwrap(game.startPicking(id, for: style))
            play(&round)
            XCTAssertNotNil(game.bringIn(round, from: id, for: style))
            game.crush(in: vessel, method: method)
            game.nextWeek()
        }
        game.finishHarvest()
        XCTAssertEqual(game.phase, .cellar)
        XCTAssertEqual(game.date, "Nov")
        XCTAssertEqual(game.lots.count, 4)
        XCTAssertEqual(game.blocker(for: .m5), "Needs Mourvèdre, Counoise and Cinsault")
        XCTAssertNil(game.blocker(for: .rose))

        // The white and the rosé go into bottle young.
        for wine in [WineID.sybarite, .rose] {
            let blend = Blend(wine: wine, cases: Dictionary(uniqueKeysWithValues: game.lots(for: wine).map { ($0.id, $0.cases) }))
            let bottled = try XCTUnwrap(game.bottle(blend))
            XCTAssertGreaterThanOrEqual(bottled.score, 88)
            XCTAssertEqual(bottled.month, 0)
            XCTAssertFalse(bottled.note.isEmpty)
        }
        XCTAssertNil(game.bottle(Blend(wine: .sybarite)), "nothing left to bottle")

        // Two months on, the barrels want topping up.
        game.nextMonth()
        game.nextMonth()
        XCTAssertEqual(game.date, "Jan")
        XCTAssertEqual(game.needsTopping, [.neutralOak])
        XCTAssertEqual(game.topUp(.neutralOak), 2)
        XCTAssertEqual(game.needsTopping, [])
        XCTAssertEqual(game.topUp(.stainless), 0)

        // The lab's projection is what the Syrah tastes like three months on.
        let syrahOnly = Blend(wine: .uber, cases: Dictionary(uniqueKeysWithValues: game.lots(for: .uber)
            .filter { $0.varietal == .syrah }.map { ($0.id, $0.cases) }))
        let projected = game.analyze(syrahOnly, monthsAhead: 3)
        for _ in 0..<3 {
            game.topUp(.neutralOak)
            game.nextMonth()
        }
        XCTAssertEqual(game.analyze(syrahOnly), projected)
        XCTAssertEqual(game.monthsLeft, 3)
        let everything = Blend(wine: .uber, cases: Dictionary(uniqueKeysWithValues: game.lots(for: .uber).map { ($0.id, $0.cases) }))
        XCTAssertFalse(game.analyze(everything).canBottle, "Grenache makes it under 75% Syrah")
        let uber = try XCTUnwrap(game.bottle(syrahOnly))
        XCTAssertEqual(uber.month, 5)
        XCTAssertEqual(game.lots.map(\.varietal), [.grenache], "the red Grenache is left over")
        let grenacheLot = game.lots[0]

        // August: the vintage is released.
        let moneyBefore = game.money
        while game.phase == .cellar { game.nextMonth() }
        let report = try XCTUnwrap(game.report)
        XCTAssertEqual(game.phase, .offseason)
        XCTAssertEqual(report.wines.count, 3)
        XCTAssertEqual(report.bulkCases, 0, "the Grenache stays in barrel")
        XCTAssertGreaterThan(report.profit, 50_000)
        XCTAssertEqual(game.money, moneyBefore + report.profit, accuracy: 1e-6)
        XCTAssertEqual(game.library.map(\.wine), [.sybarite, .rose, .uber])
        XCTAssertEqual(game.library.map(\.vintage), [2001, 2001, 2001])
        XCTAssertEqual(game.lots.map(\.id), [grenacheLot.id])
        XCTAssertEqual(game.lots[0].vintage, 2001)
        XCTAssertEqual(report.reputationAfter, game.reputation)
    }

    /// Plays 2001 without bottling anything: a white and a red go into the
    /// cellar and stay there.
    private func unbottledVintage(seed: UInt64) throws -> Game {
        var game = Game(vintage: Game.firstVintage, seed: seed)
        for (id, vessel) in [(sb, Vessel.stainless), (syrah, .neutralOak)] {
            let style = try XCTUnwrap(game.block(id)).varietal.mainStyle
            var round = try XCTUnwrap(game.startPicking(id, for: style))
            play(&round)
            XCTAssertNotNil(game.bringIn(round, from: id, for: style))
            game.crush(in: vessel)
            game.nextWeek()
        }
        game.finishHarvest()
        while game.phase == .cellar {
            game.topUp(.neutralOak)
            game.nextMonth()
        }
        return game
    }

    func testUnbottledWineAgesIntoTheNextYear() throws {
        var game = try unbottledVintage(seed: 9)
        let report = try XCTUnwrap(game.report)
        XCTAssertEqual(report.bulkCases, 0)
        XCTAssertEqual(report.bill.cellar, 0)
        XCTAssertEqual(game.lots.map(\.varietal), [.sauvignonBlanc, .syrah])
        XCTAssertTrue(game.diary.contains { $0.text.contains("stay in barrel for another year") })
        let kept = game.lots.reduce(0) { $0 + $1.cases }

        // A year in barrel isn't free.
        game.startNextVintage()
        XCTAssertEqual(game.vintage, 2002)
        XCTAssertEqual(game.bill.cellar, Double(kept) * Game.cellarCostPerCase)
        XCTAssertEqual(game.lots.map(\.months), [Aging.last, Aging.last])

        // It ages through the summer and the harvest, topped up by the crew:
        // the second November is month 12.
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        XCTAssertEqual(game.phase, .cellar)
        XCTAssertEqual(game.lots.map(\.months), [12, 12])
        XCTAssertTrue(game.lots.allSatisfy { !$0.faults.contains(.oxidized) && !$0.needsTopping })
        XCTAssertNil(game.blocker(for: .sybarite))

        // Last year's Sybarite goes out under its own vintage.
        let white = try XCTUnwrap(game.lots(for: .sybarite).first)
        let blend = Blend(wine: .sybarite, cases: [white.id: white.cases])
        XCTAssertEqual(game.analyze(blend).vintage, 2001)
        let sybarite = try XCTUnwrap(game.bottle(blend))
        XCTAssertEqual(sybarite.vintage, 2001)

        // The Syrah has had its second year: it goes for bulk at this release.
        let syrahCases = try XCTUnwrap(game.lots.first { $0.varietal == .syrah }).cases
        while game.phase == .cellar { game.nextMonth() }
        let second = try XCTUnwrap(game.report)
        XCTAssertEqual(second.bulkCases, syrahCases)
        XCTAssertEqual(second.bulkSales, Double(syrahCases) * Game.bulkPricePerCase)
        XCTAssertTrue(game.lots.isEmpty)
    }

    func testOldWineFadesWhileRedsSoften() throws {
        let game = try unbottledVintage(seed: 10)
        let white = try XCTUnwrap(game.lots.first { $0.style == .white })
        let red = try XCTUnwrap(game.lots.first { $0.style == .red })
        // Another year: the white loses its fruit, the red its edges.
        XCTAssertLessThan(white.taste(in: 4).fruit, white.profile.fruit - 0.3)
        XCTAssertLessThan(red.taste(in: 4).tannin, red.profile.tannin - 0.1)
    }

    func testSellingALotInBulk() throws {
        var game = try unbottledVintage(seed: 11)
        game.startNextVintage()
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        let syrahLot = try XCTUnwrap(game.lots.first { $0.varietal == .syrah })
        XCTAssertEqual(game.sellInBulk(syrahLot.id), syrahLot.cases)
        XCTAssertEqual(game.soldInBulk, syrahLot.cases)
        XCTAssertFalse(game.lots.contains { $0.id == syrahLot.id })
        XCTAssertEqual(game.sellInBulk(syrahLot.id), 0, "already sold")
        let white = try XCTUnwrap(game.lots.first).cases
        while game.phase == .cellar { game.nextMonth() }
        XCTAssertEqual(game.report?.bulkCases, syrahLot.cases + white)
    }

    func testAWineCanBeBottledMoreThanOnce() throws {
        var game = try unbottledVintage(seed: 12)
        game.startNextVintage()
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        let white = try XCTUnwrap(game.lots(for: .sybarite).first)
        let half = white.cases / 2
        XCTAssertNotNil(game.bottle(Blend(wine: .sybarite, cases: [white.id: half])))
        XCTAssertNotNil(game.bottle(Blend(wine: .sybarite, cases: [white.id: white.cases - half])))
        XCTAssertEqual(game.bottled.map(\.wine), [.sybarite, .sybarite])
        XCTAssertTrue(game.lots(for: .sybarite).isEmpty)
    }

    func testBlendingAcrossStylesAndVintages() throws {
        var game = try unbottledVintage(seed: 13)
        game.startNextVintage()
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        // Anything in the cellar can go to the bench, the wine's own style first.
        let red = try XCTUnwrap(game.lots.first { $0.style == .red })
        XCTAssertEqual(game.blendable(for: .uber).map(\.style), [.red, .white])
        XCTAssertEqual(game.blendable(for: .sybarite).map(\.style), [.white, .red])
        // A splash of white in a red is fine; a lot of it isn't.
        let white = try XCTUnwrap(game.lots.first { $0.style == .white })
        let splash = Blend(wine: .uber, cases: [red.id: 90, white.id: 10])
        XCTAssertFalse(game.analyze(splash).problems.contains { $0.contains("85% red") }, "\(game.analyze(splash).problems)")
        let half = Blend(wine: .uber, cases: [red.id: 50, white.id: 50])
        XCTAssertTrue(game.analyze(half).problems.contains { $0.contains("at least 85% red wine") })
    }

    func testUpgradesAndTheNextVintage() {
        var game = Game(vintage: Game.firstVintage, seed: 7)
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
        XCTAssertEqual(game.vintage, 2002)
        XCTAssertEqual(game.phase, .harvest)
        XCTAssertEqual(game.blocks.count, 4)
        XCTAssertTrue(game.blocks.allSatisfy { !$0.picked })
        XCTAssertEqual(game.crewSize, 3)
        XCTAssertEqual(game.forecast.count, 3)
        XCTAssertEqual(game.lostTons, 0)
    }

    func testASplitBarrelDownPaysOnlyForTheNewOak() throws {
        var game = Game(vintage: Game.firstVintage, seed: 14)
        for _ in 0..<HarvestCalendar.weeks { game.nextWeek() }
        game.release()
        game.setMoney(100_000)
        XCTAssertTrue(game.buy(.frenchOak))
        game.startNextVintage()
        var round = try XCTUnwrap(game.startPicking(syrah, for: .red))
        play(&round)
        let fruit = try XCTUnwrap(game.bringIn(round, from: syrah, for: .red))
        let lots = game.crush(split: VesselSplit(neutralOak: 0.6, newOak: 0.4))
        XCTAssertEqual(lots.map(\.vessel), [.neutralOak, .newOak])
        XCTAssertTrue(lots.allSatisfy { $0.vintage == 2002 })
        XCTAssertEqual(game.bill.oak, fruit.tons * 0.4 * Vessel.newOak.costPerTon, accuracy: 1e-6)
    }

    func testDougsBarrelNotesSharpenWithEachVintage() throws {
        func uber(oakMiss: Double) -> BottledWine {
            BottledWine(id: UUID(), wine: .uber, vintage: 2001, cases: 100, score: 90, note: "", alcohol: 14.5,
                        color: RGB(0.4, 0.05, 0.1), composition: [], oakMiss: oakMiss)
        }
        // At first, only a hunch.
        let first = Game.barrelNotes(for: .syrah, after: [])
        XCTAssertEqual(first.map(\.wine), [.uber, .m5])
        XCTAssertTrue(first.allSatisfy { $0.margin == nil && $0.text.contains("hunch") }, "\(first.map(\.text))")
        XCTAssertEqual(Game.barrelNotes(for: .grenache, after: []).map(\.wine), [.m5])
        XCTAssertEqual(Game.barrelNotes(for: .sauvignonBlanc, after: []).map(\.wine), [.sybarite])

        // Each ÜBER bottled narrows it, and the last one's oak says which way to go.
        var history = [uber(oakMiss: -0.8)]
        var note = Game.barrelNotes(for: .syrah, after: history)[0]
        XCTAssertEqual(note.margin, 0.25)
        XCTAssertTrue(note.text.contains("60%–100% new oak"), note.text)
        XCTAssertTrue(note.text.contains("came up short"), note.text)
        history.append(uber(oakMiss: 0.5))
        note = Game.barrelNotes(for: .syrah, after: history)[0]
        XCTAssertEqual(note.margin, 0.15)
        XCTAssertTrue(note.text.contains("70%–100% new oak"), note.text)
        XCTAssertTrue(note.text.contains("too oaky"), note.text)
        history.append(uber(oakMiss: 0))
        note = Game.barrelNotes(for: .syrah, after: history)[0]
        XCTAssertEqual(note.margin, 0.05)
        XCTAssertTrue(note.text.contains("about 85% new oak, the rest neutral oak"), note.text)
        XCTAssertTrue(note.text.contains("was right"), note.text)
        // The M5 note still knows nothing.
        XCTAssertNil(Game.barrelNotes(for: .syrah, after: history)[1].margin)
    }

    func testTheCrewCanPickWithoutYou() throws {
        var game = Game(vintage: Game.firstVintage, seed: 2)
        var twin = game
        let block = try XCTUnwrap(game.block(syrah))
        let fruit = try XCTUnwrap(game.crewPick(syrah, for: .rose))
        XCTAssertEqual(fruit.style, .rose)
        XCTAssertEqual(fruit.tons, block.tons, accuracy: 0.06, "they bring in the whole crop")
        XCTAssertLessThan(fruit.mogShare, 0.05, "and not much else")
        XCTAssertEqual(game.picksLeft, 0)
        XCTAssertEqual(game.block(syrah)?.picked, true)
        XCTAssertEqual(game.crushPad, fruit)
        XCTAssertNil(game.crewPick(sb, for: .white), "one crew, one block a week")
        XCTAssertEqual(twin.crewPick(syrah, for: .rose), fruit, "same seed, same pick")
    }

    func testSavesAndLoads() throws {
        var game = Game(vintage: Game.firstVintage, seed: 8)
        var round = try XCTUnwrap(game.startPicking(grenache, for: .rose))
        play(&round)
        game.bringIn(round, from: grenache, for: .rose)
        var loaded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(loaded, game)
        // Same seed, same future.
        game.crush(in: .stainless)
        loaded.crush(in: .stainless)
        game.nextWeek()
        loaded.nextWeek()
        XCTAssertEqual(loaded.blocks, game.blocks)
        XCTAssertEqual(loaded.diary, game.diary)
        // And in the cellar, with the wine part way through its aging.
        game.finishHarvest()
        game.nextMonth()
        let cellar = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(cellar, game)
        XCTAssertEqual(cellar.cellarMonth, 1)
        XCTAssertEqual(cellar.lots.first?.months, 1)
    }
}
