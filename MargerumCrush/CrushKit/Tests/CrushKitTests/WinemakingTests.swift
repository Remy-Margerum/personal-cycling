import XCTest
@testable import CrushKit

final class FloorTests: XCTestCase {
    func testDougCanReachEveryStation() {
        for station in StationID.allCases {
            let path = Floor.path(from: Floor.start, to: station)
            XCTAssertFalse(path.isEmpty, "\(station)")
            var from = Floor.start
            for point in path {
                XCTAssertTrue(Floor.clear(from, point), "\(station): \(from) to \(point)")
                from = point
            }
            XCTAssertLessThanOrEqual(Floor.station(station).footprint.distance(to: from), Floor.reach, "\(station)")
        }
    }

    func testDougWalksAndBumpsIntoThings() {
        var doug = Doug(at: FloorPoint(2.3, 10.0))
        // Straight down into the picking bins: he stops at their edge.
        for _ in 0..<60 { doug.walk(FloorPoint(0, 1), seconds: 1.0 / 30) }
        XCTAssertLessThan(doug.position.y, Floor.station(.bins).footprint.minY)
        XCTAssertEqual(doug.facing, .down)
        XCTAssertEqual(Floor.station(near: doug.position), .bins)
        // And he can't leave the room.
        for _ in 0..<200 { doug.walk(FloorPoint(-1, 0), seconds: 1.0 / 30) }
        XCTAssertGreaterThanOrEqual(doug.position.x, Doug.radius)
        XCTAssertEqual(doug.facing, .left)
        // A light touch on the stick does nothing.
        let before = doug.position
        doug.walk(FloorPoint(0.05, 0), seconds: 1)
        XCTAssertEqual(doug.position, before)
        XCTAssertFalse(doug.isWalking)
    }

    func testWalkerFollowsAPath() {
        var walker = Walker()
        walker.walk(to: .lab)
        for _ in 0..<600 where walker.destination != nil { walker.advance(by: 1.0 / 30) }
        XCTAssertNil(walker.destination)
        XCTAssertEqual(walker.station, .lab)
    }
}

final class WinemakingTests: XCTestCase {
    func testRipeDarkGrapesTurnPinkSooner() {
        let grenache = Winemaking(harvest: harvest(.grenache, style: .rose, brix: 21.5))
        let syrah = Winemaking(harvest: harvest(.syrah, style: .rose, brix: 22.4))
        XCTAssertLessThan(syrah.pinkHours.lowerBound, grenache.pinkHours.lowerBound)
        let ripeGrenache = Winemaking(harvest: harvest(.grenache, style: .rose, brix: 22.4))
        XCTAssertLessThan(ripeGrenache.pinkHours.lowerBound, grenache.pinkHours.lowerBound)
        let hot = Winemaking(harvest: harvest(.grenache, style: .rose, brix: 21.5, temperature: 31))
        XCTAssertLessThan(hot.pinkHours.lowerBound, grenache.pinkHours.lowerBound)
        XCTAssertLessThan(hot.freshFor, grenache.freshFor)
    }

    func testRipenessMovesEveryWindow() {
        let lean = Winemaking(harvest: harvest(.syrah, brix: 24.2))
        let ripe = Winemaking(harvest: harvest(.syrah, brix: 26))
        XCTAssertGreaterThan(ripe.macerationHours, lean.macerationHours + 15, "ripe tannins take more time on the skins")
        XCTAssertLessThan(ripe.yeastWindow.upperBound, lean.yeastWindow.upperBound, "ripe fruit spoils sooner")
        XCTAssertGreaterThan(ripe.expectedFermentation, lean.expectedFermentation, "more sugar, longer ferment")
        let earlySB = Winemaking(harvest: harvest(.sauvignonBlanc, brix: 21.7))
        let ripeSB = Winemaking(harvest: harvest(.sauvignonBlanc, brix: 23.4))
        XCTAssertLessThan(ripeSB.pressKnee, earlySB.pressKnee, "riper skins give up their bitterness sooner")
    }

    func testDougHasToBeThere() {
        var w = Winemaking(harvest: harvest(.syrah))
        XCTAssertNil(w.act(), "he starts by the door")
        XCTAssertEqual(w.stage, .waiting)
        w.walk(to: .destemmer)
        for _ in 0..<300 where w.destination != nil { w.advance(by: 1.0 / 30) }
        XCTAssertEqual(w.station, .destemmer)
        XCTAssertEqual(w.availableAction, .destem)
        XCTAssertEqual(w.act(), .destem)
        XCTAssertEqual(w.stage, .soaking)
        XCTAssertGreaterThan(w.busy, 0)
        XCTAssertNil(w.act(), "busy")
    }

    func testTheClockRunsSlowAtThePressAndFastInTheFerment() {
        var w = Winemaking(harvest: harvest(.sauvignonBlanc))
        w.perform(.loadPress)
        XCTAssertEqual(w.stage, .pressing)
        let press = w.hoursPerSecond
        w.perform(.cutPress)
        w.perform(.fill(.stainless))
        w.perform(.addYeast)
        while w.stage != .fermenting { w.advance(by: 0.1) }
        XCTAssertGreaterThan(w.hoursPerSecond, 10 * press)
        w.fastForward = true
        XCTAssertGreaterThan(w.hoursPerSecond, 25 * press)
    }

    func testStoppingThePressTradesJuiceForBitterness() throws {
        func pressed(until share: Double) -> WinemakingResult {
            var w = Winemaking(harvest: harvest(.sauvignonBlanc))
            w.perform(.loadPress)
            while w.stage == .pressing && w.pressProgress < share { w.advance(by: 0.1) }
            if w.stage == .pressing { w.perform(.cutPress) }
            w.finish(with: CrushPlan(skill: 1, vessel: .stainless))
            return w.result
        }
        let gentle = pressed(until: 0.3)
        let sweetSpot = pressed(until: 0.6)
        let hard = pressed(until: 1)
        XCTAssertLessThan(gentle.cases, sweetSpot.cases)
        XCTAssertLessThan(sweetSpot.cases, hard.cases)
        XCTAssertTrue(hard.faults.contains(.bitter))
        XCTAssertFalse(sweetSpot.faults.contains(.bitter))
        XCTAssertGreaterThan(hard.profile.tannin, sweetSpot.profile.tannin)
        XCTAssertLessThan(hard.quality, sweetSpot.quality)
    }

    func testRosePressedAtPaleSalmon() {
        func rose(pressAt target: Double) -> Winemaking {
            var w = Winemaking(harvest: harvest(.grenache, style: .rose))
            w.perform(.crush)
            while w.color < target { w.advance(by: 0.1) }
            w.perform(.press)
            w.finish(with: CrushPlan(skill: 1, vessel: .stainless))
            return w
        }
        let pale = rose(pressAt: 0.15)
        let salmon = rose(pressAt: 0.34)
        let dark = rose(pressAt: 0.6)
        XCTAssertTrue(Winemaking.pink.contains(salmon.result.roseColor ?? 0))
        XCTAssertGreaterThan(salmon.result.quality, pale.result.quality + 2)
        XCTAssertGreaterThan(salmon.result.quality, dark.result.quality + 2)
        XCTAssertGreaterThan(dark.result.profile.tannin, salmon.result.profile.tannin)
    }

    func testEveryStyleFinishes() {
        for fruit in [harvest(.syrah), harvest(.grenache, style: .rose), harvest(.sauvignonBlanc)] {
            for skill in [0.0, 0.5, 1.0] {
                let w = Winemaking.played(fruit, vessels: Vessel.allCases, plan: CrushPlan(skill: skill, saignee: true))
                XCTAssertTrue(w.isFinished, "\(fruit.style) at \(skill)")
                XCTAssertNotNil(w.vessel)
                XCTAssertLessThan(w.seconds, 400, "\(fruit.style) at \(skill) took \(w.seconds) s")
            }
        }
    }

    func testDougAtHisBestBeatsTheCrewAndNeglect() {
        for fruit in [harvest(.syrah, temperature: 28), harvest(.grenache, style: .rose), harvest(.sauvignonBlanc)] {
            let best = Winemaking.played(fruit, vessels: Vessel.allCases, plan: CrushPlan(skill: 1)).result
            let crew = Winemaking.played(fruit, vessels: Vessel.allCases, plan: .crew(saignee: false, vessel: .neutralOak)).result
            let sloppy = Winemaking.played(fruit, vessels: Vessel.allCases, plan: CrushPlan(skill: 0)).result
            XCTAssertGreaterThan(best.quality, crew.quality, "\(fruit.style): \(best.notes) vs \(crew.notes)")
            XCTAssertGreaterThan(crew.quality, sloppy.quality, "\(fruit.style): \(crew.notes) vs \(sloppy.notes)")
            XCTAssertGreaterThan(best.quality, 0, "\(fruit.style): \(best.notes)")
            XCTAssertLessThan(sloppy.quality, -2, "\(fruit.style): \(sloppy.notes)")
        }
    }

    func testHotRedsNeedTheChiller() {
        let hot = harvest(.syrah, brix: 25.8, temperature: 31)
        var neglected = Winemaking(harvest: hot)
        neglected.perform(.destem)
        while neglected.stage == .soaking { neglected.advance(by: 0.1) }
        while neglected.stage == .fermenting {
            if neglected.cap > 0.6 { neglected.perform(.punchDown) }
            neglected.advance(by: 0.1)
        }
        XCTAssertGreaterThan(neglected.hotHours, 10)
        let minded = Winemaking.played(hot, vessels: [.stainless, .neutralOak], plan: CrushPlan(skill: 1))
        XCTAssertEqual(minded.hotHours, 0)
        XCTAssertTrue(minded.result.notes.allSatisfy { $0.title != "Ran hot" })
    }

    func testADryCapTurnsToVinegar() {
        var w = Winemaking(harvest: harvest(.syrah))
        w.perform(.destem)
        w.perform(.addYeast)
        while w.stage != .dry {
            if !w.chilling && w.temperature > 30 { w.perform(.chill(true)) }
            if w.chilling && w.temperature < 27 { w.perform(.chill(false)) }
            w.advance(by: 0.1)
        }
        XCTAssertEqual(w.punchDowns, 0)
        w.perform(.press)
        w.perform(.fill(.neutralOak))
        XCTAssertTrue(w.result.faults.contains(.volatile), "\(w.volatile)")
    }

    func testPressingASweetRedSticks() {
        var w = Winemaking(harvest: harvest(.syrah))
        w.perform(.destem)
        w.perform(.addYeast)
        while w.stage != .fermenting { w.advance(by: 0.1) }
        while w.actions.firstIndex(of: .press) == nil { w.advance(by: 0.1) }
        XCTAssertGreaterThan(w.sugar, 4)
        w.perform(.press)
        w.perform(.fill(.neutralOak))
        XCTAssertTrue(w.result.faults.contains(.sweet))
    }

    func testSaigneeMakesARoseLot() throws {
        let fruit = harvest(.grenache, tons: 4)
        let w = Winemaking.played(fruit, vessels: [.stainless, .neutralOak], plan: CrushPlan(skill: 1, saignee: true))
        XCTAssertEqual(w.result.bleed, 0.2, accuracy: 0.03)
        let lots = fruit.lots(from: w.result)
        XCTAssertEqual(lots.count, 2)
        let rose = try XCTUnwrap(lots.first { $0.style == .rose })
        let red = try XCTUnwrap(lots.first { $0.style == .red })
        XCTAssertEqual(rose.vessel, .stainless)
        XCTAssertEqual(red.cases + rose.cases, fruit.cases)
        XCTAssertTrue(rose.name.hasSuffix("Saignée"))
    }

    func testTheAutopilotWalksTheFloor() {
        for fruit in [harvest(.syrah), harvest(.grenache, style: .rose), harvest(.sauvignonBlanc)] {
            var w = Winemaking(harvest: fruit, vessels: Vessel.allCases)
            let plan = CrushPlan(skill: 1, saignee: fruit.style == .red, vessel: .neutralOak)
            var frames = 0
            while !w.isFinished && frames < 30 * 400 {
                w.autopilot(plan)
                w.advance(by: 1.0 / 30)
                frames += 1
            }
            XCTAssertTrue(w.isFinished, "\(fruit.style) stuck in \(w.stage)")
            XCTAssertGreaterThan(w.doug.walked, 5, "he walked")
            XCTAssertGreaterThan(w.result.quality, -3, "\(fruit.style): \(w.result.notes)")
        }
    }
}
