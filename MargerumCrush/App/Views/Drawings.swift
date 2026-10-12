import CrushKit
import SwiftUI
import UIKit

/// A bunch of grapes drawn from circles, hanging from its stem.
struct GrapeCluster: View {
    var color: Color
    var mold = false
    var sparkle = false

    var body: some View {
        Canvas { context, size in
            let r: CGFloat = min(size.width / 8.4, size.height / 11)
            let midX: CGFloat = size.width / 2

            var stem = Path()
            stem.move(to: CGPoint(x: midX, y: 0))
            stem.addQuadCurve(to: CGPoint(x: midX, y: r * 1.6), control: CGPoint(x: midX + r, y: r * 0.6))
            context.stroke(stem, with: .color(Theme.stem),
                           style: StrokeStyle(lineWidth: max(2, r * 0.35), lineCap: .round))

            var leaf = context.resolve(Image(systemName: "leaf.fill"))
            leaf.shading = .color(Theme.leaf)
            context.draw(leaf, in: CGRect(x: midX + r * 0.3, y: 0, width: r * 2.4, height: r * 2))

            let rows = [4, 4, 3, 3, 2, 1]
            var berries: [CGPoint] = []
            for (row, count) in rows.enumerated() {
                let y: CGFloat = r * 2.3 + CGFloat(row) * r * 1.5
                for i in 0..<count {
                    let x: CGFloat = midX + (CGFloat(i) - CGFloat(count - 1) / 2) * r * 1.8
                    berries.append(CGPoint(x: x, y: y))
                }
            }
            for center in berries {
                let berry = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                context.fill(berry, with: .color(color))
                context.fill(berry, with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.5), .white.opacity(0)]),
                    center: CGPoint(x: center.x - r * 0.35, y: center.y - r * 0.4),
                    startRadius: 0, endRadius: r * 1.2))
                context.stroke(berry, with: .color(.black.opacity(0.2)), lineWidth: 0.7)
            }
            if mold {
                // Grey fuzz on every other berry.
                for (index, center) in berries.enumerated() where index % 2 == 0 {
                    let fuzz = CGRect(x: center.x - r * 0.2, y: center.y - r * 0.6, width: r * 0.9, height: r * 0.8)
                    context.fill(Path(ellipseIn: fuzz), with: .color(.white.opacity(0.6)))
                }
            }
            if sparkle {
                for (index, center) in berries.enumerated() where index % 4 == 1 {
                    context.fill(Self.star(at: CGPoint(x: center.x + r * 0.4, y: center.y - r * 0.5), size: r * 0.9),
                                 with: .color(.white))
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// A four-pointed twinkle.
    static func star(at c: CGPoint, size s: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: c)
        return p
    }
}

/// A cluster in the picking game: the artwork if there is some, else drawn.
struct ClusterSprite: View {
    let kind: PickingRound.Kind
    let varietal: Varietal

    var body: some View {
        if let image = Art.cluster(kind, red: varietal.isRed) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            GrapeCluster(color: kind.color(for: varietal), mold: kind == .rotten, sparkle: kind == .golden)
        }
    }
}

/// A wasp facing right.
struct WaspDrawing: View {
    private static let yellow = Color(red: 0.98, green: 0.80, blue: 0.10)

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            for wing in [CGRect(x: w * 0.28, y: h * 0.06, width: w * 0.3, height: h * 0.42),
                         CGRect(x: w * 0.42, y: h * 0.1, width: w * 0.26, height: h * 0.36)] {
                context.fill(Path(ellipseIn: wing), with: .color(.white.opacity(0.8)))
                context.stroke(Path(ellipseIn: wing), with: .color(.black.opacity(0.35)), lineWidth: 1)
            }

            let abdomen = CGRect(x: w * 0.08, y: h * 0.44, width: w * 0.48, height: h * 0.34)
            var sting = Path()
            sting.move(to: CGPoint(x: abdomen.minX + 2, y: abdomen.midY - 3))
            sting.addLine(to: CGPoint(x: abdomen.minX - w * 0.08, y: abdomen.midY + 1))
            sting.addLine(to: CGPoint(x: abdomen.minX + 2, y: abdomen.midY + 3))
            sting.closeSubpath()
            context.fill(sting, with: .color(.black))

            var striped = context
            striped.clip(to: Path(ellipseIn: abdomen))
            striped.fill(Path(abdomen), with: .color(Self.yellow))
            for k in 0..<3 {
                let stripe = CGRect(x: abdomen.minX + abdomen.width * (0.16 + CGFloat(k) * 0.26), y: abdomen.minY,
                                    width: abdomen.width * 0.12, height: abdomen.height)
                striped.fill(Path(stripe), with: .color(.black))
            }
            context.stroke(Path(ellipseIn: abdomen), with: .color(.black), lineWidth: 1.2)

            let thorax = CGRect(x: w * 0.52, y: h * 0.46, width: w * 0.18, height: h * 0.26)
            context.fill(Path(ellipseIn: thorax), with: .color(Color(red: 0.25, green: 0.18, blue: 0.05)))
            let head = CGRect(x: w * 0.68, y: h * 0.43, width: w * 0.22, height: h * 0.28)
            context.fill(Path(ellipseIn: head), with: .color(Self.yellow))
            context.stroke(Path(ellipseIn: head), with: .color(.black), lineWidth: 1.2)
            context.fill(Path(ellipseIn: CGRect(x: w * 0.79, y: h * 0.47, width: w * 0.08, height: h * 0.1)),
                         with: .color(.black))

            var lines = Path()
            lines.move(to: CGPoint(x: w * 0.84, y: h * 0.45))
            lines.addQuadCurve(to: CGPoint(x: w * 0.97, y: h * 0.28), control: CGPoint(x: w * 0.88, y: h * 0.3))
            for x in [0.5, 0.58, 0.64] {
                lines.move(to: CGPoint(x: w * x, y: h * 0.7))
                lines.addLine(to: CGPoint(x: w * (x - 0.04), y: h * 0.88))
            }
            context.stroke(lines, with: .color(.black), lineWidth: 1.2)
        }
    }
}

struct WaspSprite: View {
    var body: some View {
        if let image = Art.wasp {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            WaspDrawing()
        }
    }
}

/// Rolling hills along the bottom of a rect.
struct Hills: Shape {
    /// Height of the ridge, as a fraction of the rect from the top.
    var ridge: CGFloat
    var amplitude: CGFloat
    var phase: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        let steps = 48
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let wave = sin(t * .pi * 2 + phase) + 0.4 * sin(t * .pi * 5.3 + phase * 2)
            p.addLine(to: CGPoint(x: rect.minX + rect.width * t,
                                  y: rect.minY + rect.height * (ridge + amplitude * wave)))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Sky and hills behind the picking game.
struct VineyardBackdrop: View {
    var body: some View {
        if let image = Art.vineyard {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.55, green: 0.76, blue: 0.93),
                                        Color(red: 0.93, green: 0.90, blue: 0.80)],
                               startPoint: .top, endPoint: .center)
                Hills(ridge: 0.12, amplitude: 0.025, phase: 1)
                    .fill(Color(red: 0.62, green: 0.66, blue: 0.55))
                Hills(ridge: 0.2, amplitude: 0.02, phase: 3.2)
                    .fill(Color(red: 0.80, green: 0.70, blue: 0.45))
                Hills(ridge: 0.3, amplitude: 0.012, phase: 0.5)
                    .fill(Color(red: 0.87, green: 0.80, blue: 0.58))
            }
        }
    }
}

/// Trellis wires and posts, with leaves along each wire.
struct Trellis: View {
    private static let leafColors = [
        Color(red: 0.29, green: 0.46, blue: 0.21),
        Color(red: 0.38, green: 0.56, blue: 0.25),
        Color(red: 0.24, green: 0.38, blue: 0.18),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ForEach([0.03, 0.5, 0.97], id: \.self) { (x: Double) in
                    Rectangle()
                        .fill(Color(red: 0.45, green: 0.33, blue: 0.2))
                        .frame(width: 7, height: h * 0.72)
                        .position(x: w * x, y: h * 0.46)
                }
                ForEach(Array(PickingRound.wires.enumerated()), id: \.offset) { row, wire in
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h * wire))
                        p.addLine(to: CGPoint(x: w, y: h * wire))
                    }
                    .stroke(Color(red: 0.32, green: 0.28, blue: 0.24), lineWidth: 1.5)
                    ForEach(0..<10, id: \.self) { (k: Int) in
                        leaf(k, row)
                            .position(x: w * (CGFloat(k) + 0.25 + 0.5 * CGFloat(row % 2)) / 10, y: h * wire - 4)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func leaf(_ k: Int, _ row: Int) -> some View {
        let size = CGFloat(20 + (k * 7 + row * 3) % 5 * 4)
        let angle = Double((k * 47 + row * 31) % 120 - 60)
        return Image(systemName: "leaf.fill")
            .font(.system(size: size))
            .foregroundStyle(Self.leafColors[(k + row) % 3])
            .rotationEffect(.degrees(angle))
    }
}

/// Sunset over the Santa Ynez Valley, behind the title.
struct TitleBackdrop: View {
    var body: some View {
        if let image = Art.title {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                LinearGradient(colors: [Color(red: 0.24, green: 0.13, blue: 0.30),
                                        Color(red: 0.78, green: 0.33, blue: 0.30),
                                        Color(red: 0.98, green: 0.74, blue: 0.40)],
                               startPoint: .top, endPoint: .bottom)
                GeometryReader { geo in
                    Circle()
                        .fill(Color(red: 1, green: 0.88, blue: 0.62))
                        .frame(width: geo.size.width * 0.42)
                        .position(x: geo.size.width * 0.66, y: geo.size.height * 0.66)
                        .blur(radius: 1)
                }
                Hills(ridge: 0.66, amplitude: 0.025, phase: 0.6)
                    .fill(Color(red: 0.45, green: 0.22, blue: 0.32))
                Hills(ridge: 0.74, amplitude: 0.02, phase: 2.4)
                    .fill(Color(red: 0.30, green: 0.14, blue: 0.22))
                Hills(ridge: 0.84, amplitude: 0.012, phase: 4)
                    .fill(Color(red: 0.16, green: 0.10, blue: 0.12))
                VineRows()
            }
        }
    }
}

/// Rows of vines on the nearest hill.
private struct VineRows: View {
    var body: some View {
        Canvas { context, size in
            for row in 0..<7 {
                let t = CGFloat(row) / 6
                let y = size.height * (0.87 + 0.12 * t)
                let r = 2 + 3 * t
                var x: CGFloat = -r
                while x < size.width + r {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y - r, width: r * 2, height: r * 1.6)),
                                 with: .color(Color(red: 0.10, green: 0.16, blue: 0.08)))
                    x += r * 3.2
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A wine bottle silhouette.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let neck = w * 0.15
        var p = Path()
        p.move(to: CGPoint(x: rect.midX - neck, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + neck, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX + neck, y: rect.minY + h * 0.22))
        p.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.4),
                   control1: CGPoint(x: rect.midX + neck, y: rect.minY + h * 0.3),
                   control2: CGPoint(x: rect.maxX, y: rect.minY + h * 0.29))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - w * 0.08))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - w * 0.08, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + w * 0.08, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - w * 0.08), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.4))
        p.addCurve(to: CGPoint(x: rect.midX - neck, y: rect.minY + h * 0.22),
                   control1: CGPoint(x: rect.minX, y: rect.minY + h * 0.29),
                   control2: CGPoint(x: rect.midX - neck, y: rect.minY + h * 0.3))
        p.closeSubpath()
        return p
    }
}

/// A bottle of one of the wines, with its label.
struct BottleView: View {
    let wine: WineID
    let vintage: Int
    let color: RGB

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                BottleShape().fill(glass)
                BottleShape().fill(LinearGradient(colors: [.white.opacity(0.35), .clear, .black.opacity(0.2)],
                                                  startPoint: .leading, endPoint: .trailing))
                Rectangle()
                    .fill(wine.spec.style == .red ? Theme.wine : Theme.gold)
                    .frame(width: w * 0.32, height: h * 0.15)
                    .position(x: w / 2, y: h * 0.075)
                WineLabel(wine: wine, vintage: vintage, scale: w / 100)
                    .frame(width: w * 0.86, height: h * 0.36)
                    .clipShape(.rect(cornerRadius: 2))
                    .position(x: w / 2, y: h * 0.7)
            }
        }
        .aspectRatio(0.33, contentMode: .fit)
        .accessibilityLabel("A bottle of \(wine.spec.name)")
    }

    /// Reds come in dark green glass; whites and rosé in clear glass.
    private var glass: Color {
        wine.spec.style == .red ? Color(red: 0.1, green: 0.17, blue: 0.11) : Color(color)
    }
}

/// The front label: the artwork if there is some, else plain type.
struct WineLabel: View {
    let wine: WineID
    let vintage: Int
    /// 1 for a label on a 100-point-wide bottle.
    var scale: CGFloat = 1

    var body: some View {
        if let image = Art.label(wine) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            VStack(spacing: 2 * scale) {
                Text("MARGERUM")
                    .font(.system(size: 8 * scale, weight: .semibold, design: .serif))
                    .tracking(1.5 * scale)
                Text(wine.spec.name)
                    .font(.system(size: (wine == .m5 ? 34 : 15) * scale, weight: .bold, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(String(vintage))
                    .font(.system(size: 9 * scale, design: .serif))
            }
            .foregroundStyle(Theme.ink)
            .padding(4 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.paper)
        }
    }
}
