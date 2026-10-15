import XCTest
@testable import CrushKit

/// Fruit picked at a chosen sugar, for cellar and blending tests. The rest is
/// an ordinary, clean bin unless a test says otherwise.
func harvest(_ varietal: Varietal, style: WineStyle? = nil, brix: Double? = nil, rot: Double = 0, sour: Double = 0,
             mog: Double = 0, green: Double = 0.2, tannin: Double = 0, color: Double = 0, complexity: Double = 0.1,
             tons: Double = 3, site: Double = 3, temperature: Double = 22) -> Harvest {
    let style = style ?? varietal.mainStyle
    let brix = brix ?? varietal.window(for: style).middle
    let acid = varietal.acidAtIdeal + 0.8 * (varietal.window(for: varietal.mainStyle).middle - brix)
    let summary = PickingRound.Summary(bin: PickingRound.Bin([.ripe: 30]), harvestedShare: 1, missed: 0, stings: 0)
    return Harvest(blockID: varietal.rawValue, blockName: "Test \(varietal.name)", varietal: varietal, style: style,
                   tons: tons, brix: brix, acid: acid, rotShare: rot, sourShare: sour, mogShare: mog, tannin: tannin,
                   color: color, green: green, complexity: complexity, sortedOut: 0, picking: summary, site: site,
                   character: TasteProfile(), temperature: temperature)
}

/// A lot as the crush pad made it, aged to the month its style is judged at.
func lot(_ fruit: Harvest, _ vessel: Vessel = .neutralOak, _ method: CrushMethod = .red) -> Lot {
    let made = fruit.lots(vessel: vessel, method: method)[0]
    return made.aged(by: Int(Aging.reference(made.style).rounded()))
}

final class CellarTests: XCTestCase {
    func testQualityPeaksMidWindowWithCleanFruit() {
        let perfect = harvest(.syrah).quality
        XCTAssertEqual(perfect, 50 + 50 - 11 + 3 + 0.4, accuracy: 1e-9)
        XCTAssertLessThan(harvest(.syrah, brix: 25.9).quality, perfect)
        XCTAssertLessThan(harvest(.syrah, brix: 27.5).quality, harvest(.syrah, brix: 25.9).quality - 10)
        XCTAssertLessThan(harvest(.syrah, rot: 0.1).quality, perfect - 9)
        XCTAssertLessThan(harvest(.syrah, sour: 0.05).quality, perfect - 9)
        XCTAssertLessThan(harvest(.syrah, mog: 0.05).quality, perfect - 4)
        XCTAssertLessThan(harvest(.syrah, green: 0.6).quality, perfect - 4)
        XCTAssertGreaterThan(harvest(.syrah, complexity: 0.4).quality, perfect + 2)
        XCTAssertEqual(harvest(.syrah, complexity: 1, site: 5).quality, 100 - 11 + 5 + 4, accuracy: 1e-9)
    }

    func testWhatGoesInTheBinsShapesTheWine() {
        let plain = harvest(.syrah).profile(as: .red)
        let green = harvest(.syrah, green: 0.7).profile(as: .red)
        XCTAssertGreaterThan(green.tannin, plain.tannin)
        XCTAssertGreaterThan(green.spice, plain.spice)
        XCTAssertLessThan(green.fruit, plain.fruit)

        let leafy = harvest(.syrah, mog: 0.06).profile(as: .red)
        XCTAssertGreaterThan(leafy.tannin, plain.tannin + 0.25)
        XCTAssertLessThan(leafy.fruit, plain.fruit - 0.3)

        let skins = harvest(.syrah, tannin: 0.5, color: 0.5).profile(as: .red)
        XCTAssertGreaterThan(skins.tannin, plain.tannin + 0.5)
        XCTAssertGreaterThan(skins.fruit, plain.fruit)

        // A little shaded fruit is grass and lemongrass in a Sauvignon Blanc.
        let sb = harvest(.sauvignonBlanc).profile(as: .white)
        let grassy = harvest(.sauvignonBlanc, green: 0.5).profile(as: .white)
        XCTAssertGreaterThan(grassy.spice, sb.spice + 0.2)
        XCTAssertEqual(harvest(.sauvignonBlanc, green: 0.5).faults, [])
        XCTAssertEqual(harvest(.syrah, green: 0.5).faults, [.green])
    }

    func testFaults() {
        XCTAssertEqual(harvest(.syrah).faults, [])
        XCTAssertEqual(harvest(.syrah, rot: 0.1, sour: 0.05, mog: 0.08, green: 0.6).faults,
                       [.green, .moldy, .sour, .stemmy])
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

    func testVesselsShapeTheWine() {
        let fruit = harvest(.sauvignonBlanc)
        let steel = lot(fruit, .stainless)
        let neutral = lot(fruit, .neutralOak)
        let new = lot(fruit, .newOak)
        XCTAssertEqual(steel.profile.oak, 0)
        XCTAssertGreaterThan(neutral.profile.oak, steel.profile.oak)
        XCTAssertGreaterThan(new.profile.oak, neutral.profile.oak)
        XCTAssertGreaterThan(steel.profile.acidity, neutral.profile.acidity)
    }

    func testVesselSplitsAddUp() {
        let split = VesselSplit(stainless: 2, neutralOak: 1, newOak: 1)
        XCTAssertEqual(split.stainless, 0.5, accuracy: 1e-9)
        XCTAssertEqual(split[.newOak], 0.25, accuracy: 1e-9)
        XCTAssertEqual(split.main, .stainless)
        XCTAssertEqual(VesselSplit(), .only(.neutralOak))
        // Moving one slider shares the rest out as it was.
        let more = split.setting(.newOak, to: 0.5)
        XCTAssertEqual(more.newOak, 0.5, accuracy: 1e-9)
        XCTAssertEqual(more.stainless, 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(more.neutralOak, 1.0 / 6, accuracy: 1e-9)
        let steel = VesselSplit.only(.stainless).setting(.stainless, to: 0.6)
        XCTAssertEqual(steel.neutralOak, 0.2, accuracy: 1e-9)
        XCTAssertEqual(steel.newOak, 0.2, accuracy: 1e-9)
        // Without French oak, the sliders share between steel and neutral only.
        let twoWay = VesselSplit.only(.neutralOak).setting(.neutralOak, to: 0.3, among: [.stainless, .neutralOak])
        XCTAssertEqual(twoWay.stainless, 0.7, accuracy: 1e-9)
        XCTAssertEqual(twoWay.newOak, 0)
        // No French oak yet: its share goes to neutral barrels.
        let noOak = split.available(in: [.stainless, .neutralOak])
        XCTAssertEqual(noOak.neutralOak, 0.5, accuracy: 1e-9)
        XCTAssertEqual(noOak.newOak, 0)
        XCTAssertEqual(noOak.used, [.stainless, .neutralOak])
        // Cases are shared out whole and add up.
        for total in [1, 7, 100, 257] {
            XCTAssertEqual(split.cases(total).reduce(0) { $0 + $1.cases }, total)
        }
        XCTAssertEqual(VesselSplit(stainless: 0.7, neutralOak: 0.2, newOak: 0.1).cases(33).map { $0.cases }, [23, 7, 3])
        XCTAssertEqual(VesselSplit.only(.newOak).cases(40).map { $0.vessel }, [.newOak])
    }

    func testRoseColorGoesFromPaleToDark() {
        let pale = Varietal.grenache.roseColor(0.1)
        let salmon = Varietal.grenache.roseColor(0.36)
        let dark = Varietal.grenache.roseColor(0.8)
        let target = Varietal.grenache.wineColor(for: .rose)
        XCTAssertEqual(salmon.red, target.red, accuracy: 1e-9)
        XCTAssertEqual(salmon.green, target.green, accuracy: 1e-9)
        XCTAssertEqual(salmon.blue, target.blue, accuracy: 1e-9)
        XCTAssertGreaterThan(pale.green, salmon.green)
        XCTAssertLessThan(dark.green, salmon.green)
    }
}

final class BlendTests: XCTestCase {
    func testCleanStainlessSybariteScoresWell() {
        let analysis = WineSpec.sybarite.analyze([(lot(harvest(.sauvignonBlanc), .stainless), 180)])
        XCTAssertEqual(analysis.problems, [])
        XCTAssertEqual(analysis.misses, [:])
        XCTAssertGreaterThanOrEqual(analysis.score, 92)
        XCTAssertEqual(analysis.cases, 180)
        XCTAssertEqual(analysis.composition, [VarietalShare(varietal: .sauvignonBlanc, share: 1)])
    }

    func testOakedSybariteMissesDougsRange() {
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
        XCTAssertGreaterThanOrEqual(new.score, 91)
    }

    func testGreatFiveGrapeM5ReachesTheHighNineties() {
        let parts: [(Varietal, Int)] = [(.syrah, 40), (.grenache, 25), (.mourvedre, 20), (.counoise, 8), (.cinsault, 7)]
        // A little new oak, on the Syrah.
        let analysis = WineSpec.m5.analyze(parts.map {
            (lot(harvest($0.0, site: 4), $0.0 == .syrah ? .newOak : .neutralOak), $0.1 * 3)
        })
        XCTAssertTrue(analysis.canBottle, "\(analysis.problems)")
        XCTAssertGreaterThanOrEqual(analysis.score, 96, "\(analysis.misses)")
        XCTAssertEqual(analysis.composition.map(\.varietal), [.syrah, .grenache, .mourvedre, .counoise, .cinsault])
    }

    func testRoseFromEarlyGrenacheFitsDougsRange() {
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

    func testFaultsShowUpInTheNote() {
        let analysis = WineSpec.m5.analyze([Varietal.syrah, .grenache, .mourvedre, .counoise, .cinsault]
            .map { (lot(harvest($0)), 50) })
        var rng = SeededGenerator(seed: 1)
        let note = TastingNote.write(for: .m5, analysis: analysis, score: 84, faults: [.volatile, .stemmy], using: &rng)
        XCTAssertTrue(note.contains("vinegar"), note)
        XCTAssertTrue(note.contains("stemmy"), note)
    }

    func testSingleVarietalsScoreWithTheBlends() throws {
        let m5 = WineSpec.m5.analyze(Varietal.allCases.filter(\.isRed).map { (lot(harvest($0)), 50) })
        for wine in WineID.singles {
            let grape = try XCTUnwrap(wine.grape)
            XCTAssertEqual(WineID.single(grape), wine)
            let analysis = wine.spec.analyze([(lot(harvest(grape)), 100)])
            XCTAssertTrue(analysis.canBottle, "\(wine.spec.name): \(analysis.problems)")
            XCTAssertGreaterThanOrEqual(analysis.score, 95, "\(wine.spec.name): \(analysis.misses)")
            XCTAssertGreaterThanOrEqual(analysis.score, m5.score - 1, wine.spec.name)
        }
        // The purer, the better; under 75% it can't carry the grape's name.
        let grenache = lot(harvest(.grenache))
        let syrah = lot(harvest(.syrah))
        let scores = [100, 80, 75].map { WineSpec.grenache.analyze([(grenache, $0), (syrah, 100 - $0)]).score }
        XCTAssertEqual(scores, [96, 95, 94])
        let short = WineSpec.grenache.analyze([(grenache, 70), (syrah, 30)])
        XCTAssertFalse(short.canBottle)
        XCTAssertEqual(short.problems, ["Needs at least 75% Grenache. Now 70%."])
        XCTAssertNil(WineID.single(.sauvignonBlanc))
        XCTAssertNil(WineID.m5.grape)
    }

    func testOverripeWineRunsHot() {
        let raisins = lot(harvest(.syrah, brix: 28.5), .newOak)
        let analysis = WineSpec.uber.analyze([(raisins, 100)])
        XCTAssertGreaterThan(analysis.alcohol, 15.5)
        XCTAssertLessThan(analysis.score, 90)
    }
}
