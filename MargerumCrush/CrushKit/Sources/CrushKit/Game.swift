import Foundation

/// Things to spend the profits on between vintages.
public enum Upgrade: String, Codable, CaseIterable, Sendable, Identifiable {
    case cinsaultBlock, counoiseBlock, mourvedreBlock, santaMariaSyrah
    case secondCrew, thirdCrew, sortingTable, weatherStation, frenchOak, tastingRoom

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .cinsaultBlock: "Cinsault, Alisos Canyon"
        case .counoiseBlock: "Counoise, Los Olivos"
        case .mourvedreBlock: "Mourvèdre, Santa Ynez"
        case .santaMariaSyrah: "Syrah, Santa Maria"
        case .secondCrew: "Second picking crew"
        case .thirdCrew: "Third picking crew"
        case .sortingTable: "Sorting table"
        case .weatherStation: "Weather station"
        case .frenchOak: "New French oak barrels"
        case .tastingRoom: "Santa Barbara tasting room"
        }
    }

    public var blurb: String {
        switch self {
        case .cinsaultBlock: "Bright cherry and rose petal. One of the five grapes in M5."
        case .counoiseBlock: "Juicy and peppery. One of the five grapes in M5."
        case .mourvedreBlock: "Dark, savory and the last to ripen. The backbone of M5."
        case .santaMariaSyrah: "Cool-climate Syrah: peppery, bright and late. More Syrah for ÜBER."
        case .secondCrew: "Pick two blocks a week."
        case .thirdCrew: "Pick three blocks a week."
        case .sortingTable: "Catches most of the moldy clusters before they reach the press."
        case .weatherStation: "See three weeks ahead, and trust the forecast more."
        case .frenchOak: "New oak on the crush pad: toast, vanilla and grip, for $1,500 a ton."
        case .tastingRoom: "Sell more wine direct. Every bottle fetches 15% more."
        }
    }

    public var cost: Double {
        switch self {
        case .cinsaultBlock, .counoiseBlock: 35_000
        case .mourvedreBlock: 50_000
        case .santaMariaSyrah: 45_000
        case .secondCrew: 30_000
        case .thirdCrew: 80_000
        case .sortingTable: 25_000
        case .weatherStation: 20_000
        case .frenchOak: 40_000
        case .tastingRoom: 200_000
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .cinsaultBlock, .counoiseBlock, .mourvedreBlock, .santaMariaSyrah: "leaf.fill"
        case .secondCrew: "person.2.fill"
        case .thirdCrew: "person.3.fill"
        case .sortingTable: "line.3.horizontal.decrease.circle.fill"
        case .weatherStation: "cloud.sun.rain.fill"
        case .frenchOak: "cylinder.fill"
        case .tastingRoom: "wineglass.fill"
        }
    }

    /// Has to be bought first.
    public var requires: Upgrade? { self == .thirdCrew ? .secondCrew : nil }

    /// The vineyard block a lease adds.
    public var block: VineyardBlock? {
        switch self {
        case .cinsaultBlock: VineyardBlock.alisosCanyonCinsault
        case .counoiseBlock: VineyardBlock.losOlivosCounoise
        case .mourvedreBlock: VineyardBlock.santaYnezMourvedre
        case .santaMariaSyrah: VineyardBlock.santaMariaSyrah
        case .secondCrew, .thirdCrew, .sortingTable, .weatherStation, .frenchOak, .tastingRoom: nil
        }
    }
}

/// A vintage's costs, paid when the wine is released.
public struct Bill: Codable, Equatable, Sendable {
    public var grapes = 0.0
    public var picking = 0.0
    public var oak = 0.0
    public var bottling = 0.0

    public var total: Double { grapes + picking + oak + bottling }
}

/// How the vintage sold.
public struct VintageReport: Codable, Equatable, Sendable {
    public var vintage: Int
    public var wines: [BottledWine]
    /// Unblended wine sold off in bulk.
    public var bulkCases: Int
    public var bulkSales: Double
    /// Fruit the rain got.
    public var lostTons: Double
    public var bill: Bill
    public var reputationBefore: Double
    public var reputationAfter: Double

    public var sales: Double { wines.reduce(0) { $0 + ($1.revenue ?? 0) } + bulkSales }
    public var profit: Double { sales - bill.total }
}

public struct DiaryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var date: String
    public var text: String
}

public struct Forecast: Identifiable, Equatable, Sendable {
    public var week: Int
    public var date: String
    public var weather: Weather

    public var id: Int { week }
}

/// The whole winery: one value, saved after every move.
public struct Game: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// Picking, week by week.
        case harvest
        /// Blending and bottling.
        case cellar
        /// The vintage report, then upgrades before the next harvest.
        case offseason
    }

    public static let casesPerTon = 60.0
    public static let pickingCost = 1_200.0
    public static let bottlingCostPerCase = 45.0
    public static let bulkPricePerCase = 30.0
    /// The share of the shelf price the winery keeps after distributors and shops.
    public static let wineryShare = 0.5

    public private(set) var vintage: Int
    public private(set) var phase = Phase.harvest
    public private(set) var money: Double
    /// 0...100. Unknown at 50, famous at 100. Sells wine.
    public private(set) var reputation = 50.0
    public private(set) var week = 0
    public private(set) var season: [SeasonWeek] = []
    public private(set) var blocks: [VineyardBlock]
    public private(set) var picksThisWeek = 0
    /// Fruit that's been picked but not yet made into wine.
    public private(set) var crushPad: Harvest?
    public private(set) var lots: [Lot] = []
    /// Bottled this vintage.
    public private(set) var bottled: [BottledWine] = []
    /// Every wine ever released.
    public private(set) var library: [BottledWine] = []
    public private(set) var upgrades: [Upgrade] = []
    public private(set) var bill = Bill()
    /// Tons the rain got this vintage.
    public private(set) var lostTons = 0.0
    /// What happened this harvest, oldest first.
    public private(set) var diary: [DiaryEntry] = []
    /// Last vintage's results, shown in the offseason.
    public private(set) var report: VintageReport?
    private var rng: SeededGenerator

    public init(vintage: Int, seed: UInt64, money: Double = 25_000) {
        self.vintage = vintage
        self.money = money
        blocks = VineyardBlock.starters
        rng = SeededGenerator(seed: seed)
        startHarvest()
    }

    public func owns(_ upgrade: Upgrade) -> Bool { upgrades.contains(upgrade) }

    public func block(_ id: String) -> VineyardBlock? { blocks.first { $0.id == id } }

    // MARK: Harvest

    public var date: String { HarvestCalendar.date(week: week) }

    public var crewSize: Int { 1 + (owns(.secondCrew) ? 1 : 0) + (owns(.thirdCrew) ? 1 : 0) }

    public var picksLeft: Int { max(0, crewSize - picksThisWeek) }

    /// What the forecast says: this week, or the next three with the weather station.
    public var forecast: [Forecast] {
        guard phase == .harvest else { return [] }
        let span = owns(.weatherStation) ? 3 : 1
        return (week..<min(HarvestCalendar.weeks, week + span)).map {
            Forecast(week: $0, date: HarvestCalendar.date(week: $0), weather: season[$0].forecast)
        }
    }

    public var isLastWeek: Bool { week == HarvestCalendar.weeks - 1 }

    /// The cellar master's advice for this week of the harvest.
    public var advice: String? {
        guard phase == .harvest, crushPad == nil else { return nil }
        let hanging = blocks.filter { !$0.picked }
        if hanging.isEmpty { return "Everything's picked. Time for the cellar." }
        if picksLeft == 0 { return "The crews are busy until next week." }
        if isLastWeek { return "Last week before the rains. Pick whatever you can." }
        let ripeness = { (block: VineyardBlock) in block.ripeness(for: block.varietal.mainStyle) }
        if let late = hanging.first(where: { ripeness($0) == .late || ripeness($0) == .raisined }) {
            return "\(late.name) is getting overripe. Pick it soon."
        }
        if let ready = hanging.first(where: { ripeness($0) == .ready }) {
            switch season[week].forecast {
            case .rain: return "Rain is forecast. Pick \(ready.name) before mold sets in."
            case .heatWave: return "A heat wave is coming, and sugar will jump. \(ready.name) is ready now."
            case .sunny, .fog: return "\(ready.name) is ready to pick."
            }
        }
        if let pink = hanging.first(where: { $0.varietal.isRed && $0.ripeness(for: .rose) == .ready }) {
            return "\(pink.name) is in the pink: pick it now for rosé, or wait for red."
        }
        return "Nothing's ripe yet. Wait a week and watch the forecast."
    }

    public func canPick(_ blockID: String) -> Bool {
        guard phase == .harvest, crushPad == nil, picksLeft > 0, let block = block(blockID) else { return false }
        return !block.picked
    }

    /// Sends a crew into a block. Nil if no crew is free or it's been picked.
    public mutating func startPicking(_ blockID: String, for style: WineStyle, duration: Double = 30) -> PickingRound? {
        guard canPick(blockID), let block = block(blockID), block.varietal.styles.contains(style) else { return nil }
        return PickingRound(block: block, style: style, duration: duration, seed: rng.next())
    }

    /// Brings in the fruit from a finished round. It waits on the crush pad
    /// until `crush` decides what to make of it. Picking nothing leaves the
    /// block hanging, but the crew's week is still spent.
    @discardableResult
    public mutating func bringIn(_ round: PickingRound, from blockID: String, for style: WineStyle) -> Harvest? {
        guard canPick(blockID), let index = blocks.firstIndex(where: { $0.id == blockID }) else { return nil }
        let block = blocks[index]
        picksThisWeek += 1
        bill.picking += Self.pickingCost
        let tons = (block.tons * round.harvestedShare * 10).rounded() / 10
        guard tons > 0 else {
            note("The crew came back from \(block.name) empty-handed.")
            return nil
        }
        blocks[index].picked = true
        let tally = round.tally
        let sortedOut = owns(.sortingTable) ? Int((Double(tally.rotten) * 0.75).rounded()) : 0
        let rotten = Double(tally.rotten - sortedOut)
        let fruit = Double(tally.ripe + tally.golden + tally.unripe) + rotten
        bill.grapes += tons * block.varietal.pricePerTon
        let harvest = Harvest(blockID: block.id, blockName: block.name, varietal: block.varietal, style: style,
                              tons: tons, brix: block.brix, acid: block.acid,
                              unripeShare: Double(tally.unripe) / fruit, rotShare: rotten / fruit,
                              sortedOut: sortedOut, picking: round.summary, site: block.site,
                              character: block.character)
        crushPad = harvest
        let purpose = style == .rose ? " for rosé" : ""
        note("Picked \(oneDecimal(tons)) tons of \(block.name)\(purpose) at \(oneDecimal(block.brix))° Brix.")
        return harvest
    }

    /// Vessels on the crush pad. New oak needs the barrels first.
    public var vessels: [Vessel] { owns(.frenchOak) ? Vessel.allCases : [.stainless, .neutralOak] }

    /// Makes wine from the fruit on the crush pad. Rosé goes straight into
    /// stainless steel; reds and whites into the vessel chosen.
    @discardableResult
    public mutating func crush(in vessel: Vessel, method: CrushMethod = .red) -> [Lot] {
        guard let harvest = crushPad else { return [] }
        let vessel: Vessel = harvest.style == .rose ? .stainless : vessels.contains(vessel) ? vessel : .neutralOak
        let made = harvest.lots(vessel: vessel, method: harvest.style == .red ? method : .red)
        bill.oak += harvest.tons * vessel.costPerTon
        lots += made
        crushPad = nil
        return made
    }

    /// Five days pass, and the fruit ripens (or rots) in the week's weather.
    /// After the last week the harvest is over.
    public mutating func nextWeek() {
        guard phase == .harvest, crushPad == nil else { return }
        let weather = season[week]
        if weather.forecast != weather.actual {
            note("The forecast said \(weather.forecast.name.lowercased()). It was \(weather.actual.name.lowercased()).")
        }
        let before = blocks
        for i in blocks.indices { blocks[i].ripen(in: weather.actual) }
        switch weather.actual {
        case .sunny:
            note("Sunshine all week. Sugars climbing.")
        case .heatWave:
            note("Heat wave! Sugars jumped and acids fell.")
        case .fog:
            note("Fog rolled in from the coast. Ripening slowed.")
        case .rain:
            let rotting = blocks.filter { !$0.picked && $0.rot >= 0.08 }.map(\.name)
            note(rotting.isEmpty ? "Rain. The fruit swelled but held up."
                                 : "Rain. Rot is setting in: \(list(rotting)).")
        }
        for (old, new) in zip(before, blocks) where !new.picked {
            let style = new.varietal.mainStyle
            if old.ripeness(for: style) != .raisined && new.ripeness(for: style) == .raisined {
                note("\(new.name) is turning to raisins.")
            }
        }
        week += 1
        picksThisWeek = 0
        if week >= HarvestCalendar.weeks { finishHarvest() }
    }

    /// Ends the harvest. Anything still on the vine is lost to the rain.
    public mutating func finishHarvest() {
        guard phase == .harvest, crushPad == nil else { return }
        let left = blocks.filter { !$0.picked }
        lostTons = left.reduce(0) { $0 + $1.tons }
        if !left.isEmpty { note("The rains came. Still on the vine: \(list(left.map(\.name))).") }
        note("The harvest is in. Time to blend.")
        phase = .cellar
    }

    // MARK: Cellar

    /// Lots that can go into a wine: the right style, with wine left.
    public func lots(for wine: WineID) -> [Lot] {
        lots.filter { $0.style == wine.spec.style && $0.cases > 0 }
    }

    public func hasBottled(_ wine: WineID) -> Bool { bottled.contains { $0.wine == wine } }

    /// Why a wine can't be made this vintage, or nil if it can.
    public func blocker(for wine: WineID) -> String? {
        let spec = wine.spec
        if hasBottled(wine) { return "Bottled" }
        let available = lots(for: wine)
        if available.isEmpty { return "No \(spec.style.name.lowercased()) wine in the cellar" }
        let missing = spec.requiredVarietals.filter { grape in !available.contains { $0.varietal == grape } }
        if !missing.isEmpty { return "Needs \(list(missing.map(\.name)))" }
        return nil
    }

    public func analyze(_ blend: Blend) -> BlendAnalysis {
        blend.wine.spec.analyze(parts(of: blend))
    }

    /// Bottles a blend. The critic tastes it, and the lots are used up.
    @discardableResult
    public mutating func bottle(_ blend: Blend) -> BottledWine? {
        guard phase == .cellar, !hasBottled(blend.wine) else { return nil }
        let parts = parts(of: blend)
        let spec = blend.wine.spec
        let analysis = spec.analyze(parts)
        guard analysis.canBottle else { return nil }
        // The critic's mood: a point either way.
        let score = min(100, max(70, analysis.score + Int.random(in: -1...1, using: &rng)))
        var faults = Set<Fault>()
        for part in parts where Double(part.cases) >= 0.15 * Double(analysis.cases) {
            faults.formUnion(part.lot.faults)
        }
        let note = TastingNote.write(for: spec, analysis: analysis, score: score, faults: faults, using: &rng)
        let wine = BottledWine(id: UUID(), wine: blend.wine, vintage: vintage, cases: analysis.cases, score: score,
                               note: note, alcohol: analysis.alcohol, color: analysis.color,
                               composition: analysis.composition)
        for part in parts {
            if let i = lots.firstIndex(where: { $0.id == part.lot.id }) { lots[i].cases -= part.cases }
        }
        lots.removeAll { $0.cases <= 0 }
        bill.bottling += Double(analysis.cases) * Self.bottlingCostPerCase
        bottled.append(wine)
        return wine
    }

    /// Shelf price per bottle. Scores and reputation sell wine.
    public func price(of wine: WineID, score: Int) -> Double {
        let scoreFactor = max(0.2, 0.4 + 0.05 * Double(score - 80)) // 90 points: list price
        let fame = 0.85 + 0.003 * reputation
        let tastingRoom = owns(.tastingRoom) ? 1.15 : 1
        return (wine.spec.price * scoreFactor * fame * tastingRoom).rounded()
    }

    /// Sells the vintage: bottled wine at its price, anything left over as
    /// bulk wine. Pays the bill, and the offseason begins.
    @discardableResult
    public mutating func release() -> VintageReport? {
        guard phase == .cellar else { return nil }
        let sold = bottled.map { wine -> BottledWine in
            var wine = wine
            wine.revenue = Double(wine.cases * 12) * price(of: wine.wine, score: wine.score) * Self.wineryShare
            return wine
        }
        let bulkCases = lots.reduce(0) { $0 + $1.cases }
        var report = VintageReport(vintage: vintage, wines: sold, bulkCases: bulkCases,
                                   bulkSales: Double(bulkCases) * Self.bulkPricePerCase, lostTons: lostTons,
                                   bill: bill, reputationBefore: reputation, reputationAfter: reputation)
        // Reputation follows the scores, weighted by how much of each wine people drank.
        let cases = sold.reduce(0) { $0 + $1.cases }
        if cases > 0 {
            let average = Double(sold.reduce(0) { $0 + $1.score * $1.cases }) / Double(cases)
            reputation = min(100, max(0, reputation + min(12, max(-10, 1.5 * (average - 89)))))
        }
        report.reputationAfter = reputation
        money += report.profit
        library += sold
        lots = []
        bottled = []
        self.report = report
        phase = .offseason
        return report
    }

    // MARK: Offseason

    public func canBuy(_ upgrade: Upgrade) -> Bool {
        guard phase == .offseason, !owns(upgrade), money >= upgrade.cost else { return false }
        return upgrade.requires.map { owns($0) } ?? true
    }

    @discardableResult
    public mutating func buy(_ upgrade: Upgrade) -> Bool {
        guard canBuy(upgrade) else { return false }
        money -= upgrade.cost
        upgrades.append(upgrade)
        if let block = upgrade.block { blocks.append(block) }
        return true
    }

    public mutating func startNextVintage() {
        guard phase == .offseason else { return }
        vintage += 1
        startHarvest()
    }

    // MARK: Private

    private mutating func startHarvest() {
        phase = .harvest
        week = 0
        picksThisWeek = 0
        crushPad = nil
        lots = []
        bottled = []
        bill = Bill()
        lostTons = 0
        diary = []
        for i in blocks.indices { blocks[i].startVintage(using: &rng) }
        let accuracy = owns(.weatherStation) ? 0.92 : 0.75
        season = []
        for w in 0..<HarvestCalendar.weeks {
            let actual = Weather.roll(week: w, using: &rng)
            var forecast = actual
            if Double.random(in: 0..<1, using: &rng) > accuracy {
                forecast = Weather.allCases.filter { $0 != actual }.randomElement(using: &rng) ?? actual
            }
            season.append(SeasonWeek(actual: actual, forecast: forecast))
        }
        note("Harvest \(vintage) begins: \(blocks.count) blocks to bring in before the October rains.")
    }

    private func parts(of blend: Blend) -> [(lot: Lot, cases: Int)] {
        lots.compactMap { lot in
            guard let cases = blend.cases[lot.id], cases > 0 else { return nil }
            return (lot: lot, cases: min(cases, lot.cases))
        }
    }

    private mutating func note(_ text: String) {
        diary.append(DiaryEntry(id: diary.count, date: date, text: text))
    }

    /// For tests.
    mutating func setBlock(_ id: String, _ change: (inout VineyardBlock) -> Void) {
        if let i = blocks.firstIndex(where: { $0.id == id }) { change(&blocks[i]) }
    }

    /// For tests.
    mutating func setMoney(_ value: Double) { money = value }
}

func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
