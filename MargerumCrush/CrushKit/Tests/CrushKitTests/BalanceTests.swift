import XCTest
@testable import CrushKit

/// A simulated player, used to check the game's balance: scores, money and
/// reputation over several vintages.
struct Bot {
    enum Bottling {
        /// Everything in the same month.
        case month(Int)
        /// Each wine in the month the lab says it will taste best.
        case best
    }

    var skill: Double
    var mistakes: Double
    var reaction: Double
    /// Waits for the middle of the window instead of picking as soon as it's ready.
    var patient: Bool
    var picking: Picking
    /// How well Doug's crush is played (1 is perfect), or nil to leave it to
    /// the cellar crew.
    var crush: Double?
    var bottling: Bottling
    /// Tops up the barrels every this many months.
    var topping: Int
    var seed: UInt64 = 1
    private(set) var profits: [Double] = []

    static let casual = Bot(skill: 0.75, mistakes: 0.2, reaction: 0.7, patient: false, picking: .everything,
                            crush: nil, bottling: .month(3), topping: 2)
    static let expert = Bot(skill: 0.95, mistakes: 0.03, reaction: 0.45, patient: true, picking: .smart,
                            crush: 1, bottling: .best, topping: 1)

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
                play(&round, skill: skill, mistakes: mistakes, reaction: reaction, picking: picking,
                     red: style == .red, seed: seed)
                guard game.bringIn(round, from: block.id, for: style) != nil else { continue }
                let vessel: Vessel = style == .white ? .stainless
                    : block.varietal == .syrah && game.vessels.contains(.newOak) ? .newOak : .neutralOak
                game.crush(in: vessel, method: block.varietal == .grenache ? .saignee : .red, skill: crush)
            }
            if game.blocks.allSatisfy(\.picked) { game.finishHarvest() } else { game.nextWeek() }
        }

        // The cellar, a month at a time, until the release in August.
        while game.phase == .cellar {
            for wine in WineID.allCases where !game.hasBottled(wine) && game.blocker(for: wine) == nil {
                let blend = recipe(for: wine, game)
                guard !blend.cases.isEmpty else { continue }
                switch bottling {
                case .month(let month):
                    if game.cellarMonth >= min(month, Aging.last) { game.bottle(blend) }
                case .best:
                    let now = game.analyze(blend).score
                    let later = stride(from: 1, through: game.monthsLeft, by: 1)
                        .map { game.analyze(blend, monthsAhead: $0).score }.max() ?? 0
                    if now >= later { game.bottle(blend) }
                }
            }
            if game.cellarMonth % topping == 0 {
                game.topUp(.neutralOak)
                game.topUp(.newOak)
            }
            game.nextMonth()
        }
        if let report = game.report { profits.append(report.profit) }

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

    private func recipe(for wine: WineID, _ game: Game) -> Blend {
        let available = game.lots(for: wine)
        switch wine {
        case .sybarite, .rose:
            return Blend(wine: wine, cases: Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0.cases) }))
        case .m5:
            let shares: [Varietal: Double] = [.syrah: 0.35, .grenache: 0.25, .mourvedre: 0.2, .counoise: 0.1, .cinsault: 0.1]
            var byGrape: [Varietal: Int] = [:]
            for made in available { byGrape[made.varietal, default: 0] += made.cases }
            let total = shares.map { Double(byGrape[$0.key] ?? 0) / $0.value }.min() ?? 0
            var cases: [UUID: Int] = [:]
            for (grape, share) in shares {
                var wanted = Int(total * share)
                for made in available where made.varietal == grape && wanted > 0 {
                    cases[made.id] = min(made.cases, wanted)
                    wanted -= made.cases
                }
            }
            return Blend(wine: .m5, cases: cases)
        case .uber:
            // The best Syrah, and the others if they don't hurt.
            var uber = Blend(wine: .uber)
            for made in available.filter({ $0.varietal == .syrah }).sorted(by: { $0.quality > $1.quality }) {
                var bigger = uber
                bigger.cases[made.id] = made.cases
                if uber.cases.isEmpty || game.analyze(bigger).score >= game.analyze(uber).score { uber = bigger }
            }
            return uber
        }
    }
}

final class BalanceTests: XCTestCase {
    struct Result {
        var scores: [WineID: [Int]] = [:]
        /// The cellar month each wine was bottled.
        var months: [WineID: [Int]] = [:]
        /// Each vintage's profit, every game.
        var profits: [Double] = []
        /// Upgrades owned after five vintages, every game.
        var upgrades: [Int] = []
    }

    /// Plays five vintages with a dozen seeds.
    private func simulate(_ player: Bot) -> Result {
        var result = Result()
        for seed in 1...12 {
            var game = Game(vintage: Game.firstVintage, seed: UInt64(seed))
            var bot = player
            bot.seed = UInt64(seed) * 1000
            for _ in 0..<5 { bot.playVintage(&game) }
            for wine in game.library {
                result.scores[wine.wine, default: []].append(wine.score)
                result.months[wine.wine, default: []].append(wine.month ?? -1)
            }
            result.profits += bot.profits
            result.upgrades.append(game.upgrades.count)
        }
        return result
    }

    private func average(_ values: [Int]) -> Double {
        Double(values.reduce(0, +)) / Double(max(1, values.count))
    }

    private func averages(_ name: String, _ result: Result) -> [WineID: Double] {
        var averages: [WineID: Double] = [:]
        for wine in WineID.allCases {
            let s = result.scores[wine] ?? []
            averages[wine] = average(s)
            print("\(name) \(wine.spec.name): \(s.count) wines, average \(oneDecimal(averages[wine] ?? 0)), "
                + "range \(s.min() ?? 0)–\(s.max() ?? 0), bottled in month \(oneDecimal(average(result.months[wine] ?? [])))")
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
        XCTAssertTrue((85...91).contains(average[.rose] ?? 0))
        XCTAssertTrue((91...97).contains(average[.m5] ?? 0))
        XCTAssertTrue((83...90).contains(average[.uber] ?? 0))
    }

    func testExpertsDoBetterButHundredsStayRare() {
        let casual = averages("Casual", simulate(.casual))
        let result = simulate(.expert)
        let expert = averages("Expert", result)
        for wine in WineID.allCases {
            XCTAssertGreaterThan(expert[wine] ?? 0, (casual[wine] ?? 0) + 0.3, wine.spec.name)
        }
        let all = result.scores.values.flatMap { $0 }
        XCTAssertLessThan(all.filter { $0 == 100 }.count, all.count / 10)
        // Experts give ÜBER its months in new oak, and bottle the white young.
        XCTAssertGreaterThan(average(result.months[.uber] ?? []), average(result.months[.sybarite] ?? []) + 2)
    }
}
