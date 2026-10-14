import XCTest
@testable import CrushKit

private func assertSame(_ a: TasteProfile, _ b: TasteProfile, _ message: String = "") {
    for dimension in TasteProfile.Dimension.allCases {
        XCTAssertEqual(a[dimension], b[dimension], accuracy: 1e-9, "\(dimension.name) \(message)")
    }
}

final class AgingTests: XCTestCase {
    func testMonthNames() {
        XCTAssertEqual(Aging.name(0), "Nov")
        XCTAssertEqual(Aging.name(Aging.last), "Jul")
        XCTAssertEqual(Aging.name(99), "Jul")
    }

    func testEachStyleTastesLikeTheCrushPadAtItsReferenceMonth() {
        let wines: [(Harvest, Vessel)] = [(harvest(.sauvignonBlanc), .stainless), (harvest(.syrah), .newOak),
                                          (harvest(.grenache), .neutralOak)]
        for (fruit, vessel) in wines {
            let made = fruit.lots(vessel: vessel, method: .red)[0]
            assertSame(made.taste(in: Int(Aging.reference(made.style))), made.base.clamped(), made.name)
        }
    }

    func testOakBuildsAndRedTanninsSoften() {
        let uber = harvest(.syrah).lots(vessel: .newOak, method: .red)[0]
        for month in 1...Aging.last {
            XCTAssertGreaterThan(uber.taste(in: month).oak, uber.taste(in: month - 1).oak)
            XCTAssertLessThan(uber.taste(in: month).tannin, uber.taste(in: month - 1).tannin)
        }
        let steel = harvest(.sauvignonBlanc).lots(vessel: .stainless, method: .red)[0]
        XCTAssertTrue((0...Aging.last).allSatisfy { steel.taste(in: $0).oak == 0 })
    }

    func testWinesBottledTooSoonTasteRaw() {
        func score(_ wine: WineSpec, _ made: Lot, after months: Int) -> Int {
            wine.analyze([(made.aged(by: months), 100)]).score
        }
        // Whites and rosé want a couple of months to settle...
        let sybarite = harvest(.sauvignonBlanc).lots(vessel: .stainless, method: .red)[0]
        XCTAssertEqual(score(.sybarite, sybarite, after: 0), score(.sybarite, sybarite, after: 2) - 2)
        XCTAssertEqual(WineSpec.sybarite.analyze([(sybarite, 100)]).young, 2)
        // ...and the rosé fades by summer.
        let rose = harvest(.grenache, style: .rose).lots(vessel: .stainless, method: .red)[0]
        XCTAssertLessThan(rose.taste(in: Aging.last).fruit, rose.taste(in: 2).fruit - 1)
        // ÜBER wants its months in new oak.
        let uber = harvest(.syrah, brix: 25.5).lots(vessel: .newOak, method: .red)[0]
        XCTAssertGreaterThan(score(.uber, uber, after: 5), score(.uber, uber, after: 0) + 4)
        XCTAssertEqual(Aging.youth(.red, months: 0), 3, accuracy: 1e-9)
        XCTAssertEqual(Aging.youth(.red, months: 5), 0)
        XCTAssertEqual(Aging.youth(.rose, months: 1), 1)
    }

    func testBarrelsNeedToppingUp() {
        var barrel = harvest(.syrah).lots(vessel: .neutralOak, method: .red)[0]
        let quality = barrel.quality
        XCTAssertFalse(barrel.needsTopping)
        barrel.age()
        barrel.age()
        XCTAssertTrue(barrel.needsTopping)
        barrel.topUp()
        XCTAssertFalse(barrel.needsTopping)
        barrel.age()
        barrel.age()
        barrel.age()
        XCTAssertEqual(barrel.quality, quality - 1.5, accuracy: 1e-9)
        XCTAssertFalse(barrel.faults.contains(.oxidized))
        barrel.age()
        XCTAssertEqual(barrel.quality, quality - 3, accuracy: 1e-9)
        XCTAssertTrue(barrel.faults.contains(.oxidized))
        XCTAssertEqual(barrel.months, 6)

        var tank = harvest(.sauvignonBlanc).lots(vessel: .stainless, method: .red)[0]
        for _ in 0..<Aging.last { tank.age() }
        XCTAssertFalse(tank.needsTopping)
        XCTAssertEqual(tank.quality, harvest(.sauvignonBlanc).quality)
    }

    func testProjectionsMatchTheMonthsInTheCellar() {
        var barrel = harvest(.grenache).lots(vessel: .neutralOak, method: .red)[0]
        let projected = barrel.aged(by: 3)
        for _ in 0..<3 {
            barrel.age()
            barrel.topUp()
        }
        XCTAssertEqual(barrel.profile, projected.profile)
        XCTAssertEqual(barrel.quality, projected.quality)
        XCTAssertEqual(barrel.months, projected.months)
    }
}
