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
        XCTAssertNil(game.bottle(Blend(wine: .sybarite)), "one bottling per wine")

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
        let bulk = game.lots[0].cases

        // August: the vintage is released.
        let moneyBefore = game.money
        while game.phase == .cellar { game.nextMonth() }
        let report = try XCTUnwrap(game.report)
        XCTAssertEqual(game.phase, .offseason)
        XCTAssertEqual(report.wines.count, 3)
        XCTAssertEqual(report.bulkCases, bulk)
        XCTAssertGreaterThan(report.profit, 50_000)
        XCTAssertEqual(game.money, moneyBefore + report.profit, accuracy: 1e-6)
        XCTAssertEqual(game.library.map(\.wine), [.sybarite, .rose, .uber])
        XCTAssertTrue(game.lots.isEmpty)
        XCTAssertEqual(report.reputationAfter, game.reputation)
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
