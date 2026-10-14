import Foundation

/// The harvest runs in five-day weeks from Aug 25 to Oct 19. After the last
/// one the rains come and whatever is still hanging is lost.
public enum HarvestCalendar {
    public static let weeks = 12

    /// "Sep 14" for week 4.
    public static func date(week: Int) -> String {
        var day = 25 + 5 * week
        if day <= 31 { return "Aug \(day)" }
        day -= 31
        if day <= 30 { return "Sep \(day)" }
        return "Oct \(day - 30)"
    }
}

public enum Weather: String, Codable, CaseIterable, Sendable {
    case sunny, heatWave, fog, rain

    public var name: String {
        switch self {
        case .sunny: "Sunny"
        case .heatWave: "Heat wave"
        case .fog: "Coastal fog"
        case .rain: "Rain"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .sunny: "sun.max.fill"
        case .heatWave: "thermometer.sun.fill"
        case .fog: "cloud.fog.fill"
        case .rain: "cloud.rain.fill"
        }
    }

    /// What it does to the fruit.
    public var effect: String {
        switch self {
        case .sunny: "Steady ripening."
        case .heatWave: "Sugar shoots up and acid drops."
        case .fog: "Slow ripening; acid holds."
        case .rain: "Sugar dips and rot spreads."
        }
    }

    /// How warm the fruit comes in, °C: picked at dawn, but a heat wave
    /// still means hot bins.
    public var fruitTemperature: Double {
        switch self {
        case .sunny: 24
        case .heatWave: 31
        case .fog: 17
        case .rain: 16
        }
    }

    /// Multiplier on a grape's usual five-day sugar gain.
    var ripening: Double {
        switch self {
        case .sunny: 1
        case .heatWave: 1.7
        case .fog: 0.45
        case .rain: 0
        }
    }

    /// Acid lost (g/L) per °Brix gained.
    var acidLoss: Double {
        switch self {
        case .sunny: 0.8
        case .heatWave: 1.3
        case .fog: 0.5
        case .rain: 0
        }
    }

    /// The weather for one week. Rain gets likelier as the harvest runs into
    /// October; heat waves belong to late summer.
    static func roll(week: Int, using rng: inout SeededGenerator) -> Weather {
        let progress = Double(week) / Double(HarvestCalendar.weeks - 1)
        let rain = 0.03 + 0.25 * progress * progress
        let heat = 0.26 - 0.14 * progress
        let fog = 0.18
        let x = Double.random(in: 0..<1, using: &rng)
        if x < rain { return .rain }
        if x < rain + heat { return .heatWave }
        if x < rain + heat + fog { return .fog }
        return .sunny
    }
}

/// One week of the harvest: the weather that happens, and what the forecast
/// said it would be.
public struct SeasonWeek: Codable, Equatable, Sendable {
    public var actual: Weather
    public var forecast: Weather
}

/// How ripe a block is for the style it's being picked for.
public enum Ripeness: String, Sendable {
    case early, almost, ready, late, raisined

    public var label: String {
        switch self {
        case .early: "Too early"
        case .almost: "Almost there"
        case .ready: "Ready to pick"
        case .late: "Overripe"
        case .raisined: "Raisins"
        }
    }

    init(brix: Double, window: ClosedRange<Double>) {
        switch brix {
        case ..<(window.lowerBound - 1.2): self = .early
        case ..<window.lowerBound: self = .almost
        case ...window.upperBound: self = .ready
        case ...(window.upperBound + 1.5): self = .late
        default: self = .raisined
        }
    }
}

/// A block of vines the winery buys fruit from, and how it's ripening this
/// vintage.
public struct VineyardBlock: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    /// "Ballard Canyon"
    public let place: String
    /// "Ballard Canyon AVA"
    public let appellation: String
    public let varietal: Varietal
    /// Crop in a normal year, in tons.
    public let normalTons: Double
    /// Added to the quality (out of 100) of every lot from this block.
    public let site: Double
    /// What the site adds to the wine: a cool site gives more pepper and acid.
    let character: TasteProfile
    /// Cool sites ripen slower and start behind.
    let pace: Double
    let head: Double

    // This vintage
    public private(set) var tons: Double = 0
    public private(set) var brix: Double = 0
    /// Titratable acidity, g/L.
    public private(set) var acid: Double = 0
    /// Share of clusters with rot, 0...0.6.
    public private(set) var rot: Double = 0
    public var picked = false
    private var speed: Double = 1

    init(id: String, place: String, appellation: String, varietal: Varietal, normalTons: Double, site: Double,
         character: TasteProfile = TasteProfile(), pace: Double = 1, head: Double = 0) {
        self.id = id
        self.place = place
        self.appellation = appellation
        self.varietal = varietal
        self.normalTons = normalTons
        self.site = site
        self.character = character
        self.pace = pace
        self.head = head
    }

    /// "Ballard Canyon Syrah"
    public var name: String { "\(place) \(varietal.name)" }

    public func ripeness(for style: WineStyle) -> Ripeness {
        Ripeness(brix: brix, window: varietal.window(for: style))
    }

    /// New crop, new sugar: every vintage starts a little differently.
    mutating func startVintage(using rng: inout SeededGenerator) {
        tons = (normalTons * Double.random(in: 0.85...1.15, using: &rng) * 10).rounded() / 10
        brix = varietal.startBrix + head + Double.random(in: -0.6...0.6, using: &rng)
        speed = pace * Double.random(in: 0.9...1.1, using: &rng)
        // In an ordinary season acid reaches its target at the window's middle.
        acid = varietal.acidAtIdeal + 0.8 * (varietal.window(for: varietal.mainStyle).middle - brix)
        rot = 0
        picked = false
    }

    /// Five days of weather.
    mutating func ripen(in weather: Weather) {
        guard !picked else { return }
        let gain = varietal.ripeningRate * speed * weather.ripening
        brix += gain
        acid = max(3.5, acid - gain * weather.acidLoss)
        switch weather {
        case .rain:
            brix -= 0.4 // swollen, diluted berries
            rot += 0.09 * varietal.rotSusceptibility
        case .heatWave:
            break // dry heat stops rot spreading
        case .sunny, .fog:
            if rot > 0 { rot += 0.025 * varietal.rotSusceptibility }
        }
        // Overripe berries split and rot.
        if brix > varietal.window(for: varietal.mainStyle).upperBound + 1 { rot += 0.02 }
        rot = min(rot, 0.6)
    }

    /// For tests: set the fruit directly.
    mutating func set(tons: Double? = nil, brix: Double? = nil, acid: Double? = nil, rot: Double? = nil) {
        if let tons { self.tons = tons }
        if let brix { self.brix = brix }
        if let acid { self.acid = acid }
        if let rot { self.rot = rot }
    }
}

extension VineyardBlock {
    public static let happyCanyonSauvignonBlanc = VineyardBlock(
        id: "happy-canyon-sb", place: "Happy Canyon", appellation: "Happy Canyon of Santa Barbara",
        varietal: .sauvignonBlanc, normalTons: 4, site: 3)
    public static let losOlivosGrenache = VineyardBlock(
        id: "los-olivos-grenache", place: "Los Olivos", appellation: "Los Olivos District",
        varietal: .grenache, normalTons: 5, site: 1)
    public static let ballardCanyonSyrah = VineyardBlock(
        id: "ballard-canyon-syrah", place: "Ballard Canyon", appellation: "Ballard Canyon",
        varietal: .syrah, normalTons: 4.5, site: 3)
    public static let alisosCanyonCinsault = VineyardBlock(
        id: "alisos-canyon-cinsault", place: "Alisos Canyon", appellation: "Alisos Canyon",
        varietal: .cinsault, normalTons: 2.5, site: 1)
    public static let losOlivosCounoise = VineyardBlock(
        id: "los-olivos-counoise", place: "Los Olivos", appellation: "Los Olivos District",
        varietal: .counoise, normalTons: 2, site: 1)
    public static let santaYnezMourvedre = VineyardBlock(
        id: "santa-ynez-mourvedre", place: "Santa Ynez", appellation: "Santa Ynez Valley",
        varietal: .mourvedre, normalTons: 3, site: 2)
    public static let santaMariaSyrah = VineyardBlock(
        id: "santa-maria-syrah", place: "Santa Maria", appellation: "Santa Maria Valley",
        varietal: .syrah, normalTons: 4, site: 2,
        character: TasteProfile(acidity: 0.6, body: -0.5, spice: 1.2), pace: 0.9, head: -0.3)

    /// The blocks a new winery starts with.
    static let starters = [happyCanyonSauvignonBlanc, losOlivosGrenache, ballardCanyonSyrah]
}
