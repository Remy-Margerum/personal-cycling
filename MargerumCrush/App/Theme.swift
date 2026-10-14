import CrushKit
import SwiftUI
import UIKit

/// Colors for the whole game: Santa Barbara sun on old paper.
enum Theme {
    static let wine = Color(red: 0.45, green: 0.07, blue: 0.18)
    static let gold = Color(red: 0.76, green: 0.58, blue: 0.22)
    static let leaf = Color(red: 0.29, green: 0.46, blue: 0.21)
    static let paper = Color(red: 0.97, green: 0.95, blue: 0.90)
    static let ink = Color(red: 0.17, green: 0.11, blue: 0.10)
    static let stem = Color(red: 0.42, green: 0.30, blue: 0.16)
}

extension Color {
    init(_ rgb: RGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension View {
    /// A white card on the paper background.
    func card() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: .rect(cornerRadius: 18))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

/// A small-caps heading above a card.
struct SectionTitle: View {
    let text: String
    var detail: String?

    init(_ text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(Theme.wine)
            Spacer()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

enum Format {
    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }

    static func tons(_ value: Double) -> String { String(format: "%.1f tons", value) }

    static func one(_ value: Double) -> String { String(format: "%.1f", value) }

    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))%" }

    /// "TWO THOUSAND AND ONE", the way Margerum labels spell out the vintage.
    static func vintageWords(_ year: Int) -> String {
        let ones = ["", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN",
                    "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"]
        let tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY"]
        func words(_ n: Int) -> String {
            var parts: [String] = []
            if n >= 100 { parts.append("\(ones[n / 100]) HUNDRED") }
            let rest = n % 100
            if rest >= 20 {
                parts.append(tens[rest / 10] + (rest % 10 > 0 ? " \(ones[rest % 10])" : ""))
            } else if rest > 0 {
                parts.append(ones[rest])
            }
            return parts.joined(separator: " AND ")
        }
        guard year > 0, year < 10_000 else { return String(year) }
        let thousands = year / 1000
        let rest = year % 1000
        let head = thousands > 0 ? "\(ones[thousands]) THOUSAND" : ""
        if rest == 0 { return head }
        return head.isEmpty ? words(rest) : "\(head) AND \(words(rest))"
    }
}

/// Reputation as five stars.
struct Stars: View {
    /// 0...100
    let reputation: Double

    var body: some View {
        let stars = reputation / 20
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: symbol(Double(index), stars))
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.gold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reputation: \(Format.one(stars)) of 5 stars")
    }

    private func symbol(_ index: Double, _ stars: Double) -> String {
        if stars >= index + 0.75 { return "star.fill" }
        if stars >= index + 0.25 { return "star.leadinghalf.filled" }
        return "star"
    }
}

/// A score in a circle, colored by how good it is.
struct ScoreBadge: View {
    let score: Int
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(color)
            Text(String(score))
                .font(.system(size: size * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("\(score) points")
    }

    private var color: Color {
        switch score {
        case 95...: Theme.gold
        case 90..<95: Theme.wine
        case 85..<90: Color(red: 0.55, green: 0.35, blue: 0.40)
        default: Color.gray
        }
    }
}

/// Optional artwork. A PNG (or, for the big backdrops, a JPEG) with one of
/// these names anywhere under App/ (App/Art is the place) replaces the drawn
/// version; see App/Art/README.md.
enum Art {
    /// "Title" finds Title.png, or failing that Title.jpg.
    static func image(_ name: String) -> UIImage? {
        UIImage(named: name) ?? UIImage(named: name + ".jpg")
    }

    static let title = image("Title")
    static let vineyard = image("Vineyard")
    static let wasp = image("Wasp")
    static let floor = image("WineryFloor")
    private static let clusterRed = image("ClusterRed")
    private static let clusterRedUnripe = image("ClusterRedUnripe")
    private static let clusterWhite = image("ClusterWhite")
    private static let clusterWhiteUnripe = image("ClusterWhiteUnripe")
    private static let clusterRotten = image("ClusterRotten")
    private static let clusterGolden = image("ClusterGolden")
    private static let labelSybarite = image("LabelSybarite")
    private static let labelRose = image("LabelRose")
    private static let labelM5 = image("LabelM5")
    private static let labelUber = image("LabelUber")

    static func cluster(_ kind: PickingRound.Kind, red: Bool) -> UIImage? {
        switch kind {
        case .ripe: red ? clusterRed : clusterWhite
        case .unripe: red ? clusterRedUnripe : clusterWhiteUnripe
        case .rotten: clusterRotten
        case .golden: clusterGolden
        }
    }

    static func label(_ wine: WineID) -> UIImage? {
        switch wine {
        case .sybarite: labelSybarite
        case .rose: labelRose
        case .m5: labelM5
        case .uber: labelUber
        }
    }

    private static let stations: [StationID: UIImage] = {
        var images: [StationID: UIImage] = [:]
        let names: [StationID: String] = [
            .bins: "Bins", .destemmer: "Destemmer", .press: "Press", .fermenter: "Fermenter",
            .steelTank: "SteelTank", .barrels: "Barrels", .newBarrels: "NewBarrels", .chiller: "Chiller", .lab: "LabBench",
        ]
        for (id, name) in names { images[id] = image(name) }
        return images
    }()

    static func station(_ id: StationID) -> UIImage? { stations[id] }

    private static let doug: [String: UIImage] = {
        var images: [String: UIImage] = [:]
        for view in ["Front", "Side", "Back"] {
            for frame in ["", "Walk1", "Walk2"] {
                images[view + frame] = image("Doug" + view + frame)
            }
        }
        for pose in ["Punch", "Valve", "Taste"] { images[pose] = image("Doug" + pose) }
        return images
    }()

    /// Doug facing a way, mid-stride (frame 1 or 2) or standing (0).
    static func doug(_ facing: Doug.Facing, frame: Int) -> UIImage? {
        let view: String
        switch facing {
        case .down: view = "Front"
        case .up: view = "Back"
        case .left, .right: view = "Side"
        }
        return doug[view + (frame == 0 ? "" : "Walk\(frame)")]
    }

    static func doug(_ pose: Winemaking.Pose) -> UIImage? {
        switch pose {
        case .punch: doug["Punch"]
        case .valve: doug["Valve"]
        case .taste: doug["Taste"]
        }
    }
}

extension PickingRound.Kind {
    /// Berry color for the drawn clusters.
    func color(for varietal: Varietal) -> Color {
        let ripe = varietal.berryColor
        switch self {
        case .ripe:
            return Color(ripe)
        case .unripe:
            // Still green, with a blush of color on red grapes.
            let green = RGB(0.40, 0.66, 0.22)
            return Color(varietal.isRed ? green.mixed(with: ripe, 0.3) : green)
        case .rotten:
            return Color(red: 0.47, green: 0.42, blue: 0.37)
        case .golden:
            return Color(red: 0.97, green: 0.78, blue: 0.22)
        }
    }
}
