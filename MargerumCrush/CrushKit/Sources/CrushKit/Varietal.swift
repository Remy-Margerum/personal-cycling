/// The grapes in the game: Sauvignon Blanc for Sybarite, and the five Rhône
/// reds that make M5.
public enum Varietal: String, Codable, CaseIterable, Sendable, Identifiable {
    case sauvignonBlanc, grenache, syrah, mourvedre, counoise, cinsault

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .sauvignonBlanc: "Sauvignon Blanc"
        case .grenache: "Grenache"
        case .syrah: "Syrah"
        case .mourvedre: "Mourvèdre"
        case .counoise: "Counoise"
        case .cinsault: "Cinsault"
        }
    }

    public var isRed: Bool { self != .sauvignonBlanc }

    /// What the grape can be picked for. Red grapes picked early make rosé.
    public var styles: [WineStyle] { isRed ? [.red, .rose] : [.white] }

    /// The style it's normally grown for.
    public var mainStyle: WineStyle { isRed ? .red : .white }

    /// Sugar (°Brix) at which to pick for a style.
    public func window(for style: WineStyle) -> ClosedRange<Double> {
        if style == .rose { return 20.5...22.5 }
        switch self {
        case .sauvignonBlanc: return 21.5...23.5
        case .grenache: return 23.5...25.5
        case .syrah: return 24.0...26.0
        case .mourvedre: return 24.0...26.0
        case .counoise: return 22.5...24.5
        case .cinsault: return 22.0...24.0
        }
    }

    /// Typical sugar on Aug 25, when the harvest calendar starts.
    var startBrix: Double {
        switch self {
        case .sauvignonBlanc: 19.6
        case .grenache: 18.6
        case .syrah: 19.0
        case .mourvedre: 17.8
        case .counoise: 18.4
        case .cinsault: 18.8
        }
    }

    /// °Brix gained over five sunny days. Mourvèdre ripens last.
    var ripeningRate: Double {
        switch self {
        case .sauvignonBlanc, .grenache, .cinsault: 0.85
        case .syrah, .counoise: 0.8
        case .mourvedre: 0.75
        }
    }

    /// Titratable acidity (g/L) when the fruit reaches the middle of its
    /// window in an ordinary season.
    var acidAtIdeal: Double {
        switch self {
        case .sauvignonBlanc: 7.4
        case .grenache: 5.6
        case .syrah: 6.0
        case .mourvedre: 6.2
        case .counoise: 6.8
        case .cinsault: 6.0
        }
    }

    /// How readily rain turns into bunch rot. Tight clusters rot more.
    var rotSusceptibility: Double {
        switch self {
        case .sauvignonBlanc: 1.2
        case .grenache: 1.1
        case .syrah: 0.8
        case .mourvedre: 0.7
        case .counoise: 0.9
        case .cinsault: 1.0
        }
    }

    /// Grape price per ton.
    var pricePerTon: Double {
        switch self {
        case .sauvignonBlanc, .cinsault: 2_600
        case .grenache: 3_000
        case .syrah, .mourvedre: 3_200
        case .counoise: 2_800
        }
    }

    /// Flavour at the middle of the window, before any winemaking.
    var baseProfile: TasteProfile {
        switch self {
        case .sauvignonBlanc: TasteProfile(fruit: 6.5, acidity: 8, tannin: 0.5, body: 3.8, spice: 2.5)
        case .grenache: TasteProfile(fruit: 8, acidity: 4.8, tannin: 3.8, body: 6.5, spice: 4.2)
        case .syrah: TasteProfile(fruit: 7.5, acidity: 5, tannin: 7, body: 7.8, spice: 6)
        case .mourvedre: TasteProfile(fruit: 5.5, acidity: 5.2, tannin: 8, body: 7.2, spice: 7.2)
        case .counoise: TasteProfile(fruit: 7, acidity: 6.6, tannin: 3.4, body: 4.6, spice: 7)
        case .cinsault: TasteProfile(fruit: 8, acidity: 5.8, tannin: 2.4, body: 4.4, spice: 3.2)
        }
    }

    /// Ripe berry colour, for drawing clusters.
    public var berryColor: RGB {
        switch self {
        case .sauvignonBlanc: RGB(0.74, 0.80, 0.38)
        case .grenache: RGB(0.50, 0.12, 0.30)
        case .syrah: RGB(0.20, 0.10, 0.30)
        case .mourvedre: RGB(0.16, 0.08, 0.20)
        case .counoise: RGB(0.40, 0.12, 0.34)
        case .cinsault: RGB(0.58, 0.16, 0.30)
        }
    }

    /// Colour of the finished wine.
    public func wineColor(for style: WineStyle) -> RGB {
        switch style {
        case .white:
            return RGB(0.93, 0.88, 0.58)
        case .rose:
            switch self {
            case .syrah: return RGB(0.90, 0.45, 0.50)
            case .mourvedre: return RGB(0.92, 0.55, 0.48)
            case .counoise: return RGB(0.95, 0.52, 0.58)
            case .cinsault: return RGB(0.98, 0.70, 0.66)
            case .grenache, .sauvignonBlanc: return RGB(0.96, 0.62, 0.58)
            }
        case .red:
            switch self {
            case .syrah: return RGB(0.30, 0.04, 0.14)
            case .mourvedre: return RGB(0.28, 0.05, 0.12)
            case .counoise: return RGB(0.48, 0.07, 0.18)
            case .cinsault: return RGB(0.60, 0.12, 0.18)
            case .grenache, .sauvignonBlanc: return RGB(0.55, 0.08, 0.15)
            }
        }
    }

    /// Flavour words for tasting notes, most typical first.
    func descriptors(for style: WineStyle) -> [String] {
        if style == .rose {
            switch self {
            case .grenache, .sauvignonBlanc: return ["watermelon", "strawberry", "white peach"]
            case .syrah: return ["wild strawberry", "raspberry", "pink grapefruit"]
            case .mourvedre: return ["blood orange", "red plum", "dried herbs"]
            case .counoise: return ["cranberry", "red currant", "white pepper"]
            case .cinsault: return ["rose petal", "cherry", "citrus blossom"]
            }
        }
        switch self {
        case .sauvignonBlanc: return ["grapefruit", "lime zest", "passion fruit", "lemongrass"]
        case .grenache: return ["raspberry", "red cherry", "strawberry", "pomegranate"]
        case .syrah: return ["blackberry", "blueberry", "black olive", "violet"]
        case .mourvedre: return ["black plum", "leather", "earth", "black cherry"]
        case .counoise: return ["red currant", "white pepper", "cranberry"]
        case .cinsault: return ["cherry", "rose petal", "strawberry"]
        }
    }
}
