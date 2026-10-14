import Foundation

/// How wine changes in tank and barrel through the months after the harvest:
/// oak builds, red tannins soften, fruit blooms and then fades. Each style
/// tastes the way the crush pad made it at its reference month, so when to
/// bottle depends on how the wine started out: riper, more tannic fruit wants
/// longer in barrel; delicate whites and rosé want bottling early.
public enum Aging {
    /// The cellar year, from the end of the harvest to the release.
    public static let months = ["Nov", "Dec", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul"]
    public static var last: Int { months.count - 1 }

    public static func name(_ month: Int) -> String {
        months[min(max(month, 0), last)]
    }

    /// The month a style tastes the way it did on the crush pad.
    static func reference(_ style: WineStyle) -> Double {
        switch style {
        case .white: 2
        case .rose: 1.5
        case .red: 5
        }
    }

    /// The change after `month` months, compared with the reference month.
    public static func delta(_ month: Int, style: WineStyle, vessel: Vessel) -> TasteProfile {
        let now = curve(Double(month), style: style, vessel: vessel)
        let then = curve(reference(style), style: style, vessel: vessel)
        var d = TasteProfile()
        for dimension in TasteProfile.Dimension.allCases { d[dimension] = now[dimension] - then[dimension] }
        return d
    }

    private static func bell(_ m: Double, _ peak: Double, _ width: Double) -> Double {
        exp(-pow((m - peak) / width, 2))
    }

    static func curve(_ m: Double, style: WineStyle, vessel: Vessel) -> TasteProfile {
        var p = TasteProfile()
        switch style {
        case .white:
            // A few months on the lees round it out; then the fruit fades.
            p.fruit = 0.35 * bell(m, 2.5, 2) - 0.15 * max(0, m - 3.5)
            p.acidity = -0.03 * m
            p.body = (vessel == .stainless ? 0.02 : 0.07) * m
        case .rose:
            // Rosé is at its best young.
            p.fruit = 0.3 * bell(m, 1.5, 1.5) - 0.2 * max(0, m - 2.5)
            p.acidity = -0.03 * m
            p.body = 0.02 * m
        case .red:
            p.fruit = 0.25 * bell(m, 4, 2.5) - 0.06 * max(0, m - 6)
            p.tannin = -0.12 * m
            p.body = 0.05 * m
            p.spice = 0.05 * m
            p.acidity = -0.04 * min(m, 8)
        }
        switch vessel {
        case .stainless: break
        case .neutralOak: p.oak = min(1.6, 0.16 * m)
        case .newOak: p.oak = min(3.6, 0.42 * m)
        }
        return p
    }
}
