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
