import CrushKit
import SwiftUI

/// A marker over a station: what wants doing there.
struct StationBadge: Equatable {
    var symbol: String
    var tint: Color
    /// Pulses when it can't wait.
    var urgent = false
    /// A small reading under the icon, such as "27°".
    var text: String?
    /// 0...1 ring around the icon, such as the press cycle.
    var ring: Double?
}

/// A word floating up from a station.
struct FloorPopup: Identifiable, Equatable {
    let id: Int
    let text: String
    let tint: Color
    let station: StationID
    /// 0 when it appears, 1 when it's gone.
    let age: Double
}

/// The winery floor seen from above: the floor, the machines and Doug, drawn
/// back to front. Tapping a station sends Doug there.
struct FloorView: View {
    let doug: Doug
    /// What Doug's doing, if he's busy.
    var pose: Winemaking.Pose?
    var badges: [StationID: StationBadge] = [:]
    var popups: [FloorPopup] = []
    /// Stations that are part of what's happening (the rest are dimmed a little).
    var active: Set<StationID> = Set(StationID.allCases)
    let tap: (StationID) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = min(Double(geo.size.width) / Floor.width, Double(geo.size.height) / Floor.height)
            let size = CGSize(width: Floor.width * scale, height: Floor.height * scale)
            ZStack(alignment: .topLeading) {
                FloorBackground()
                    .frame(width: size.width, height: size.height)
                ForEach(drawOrder, id: \.self) { item in
                    switch item {
                    case .station(let id):
                        station(id, scale: scale)
                    case .doug:
                        dougView(scale: scale)
                    }
                }
                ForEach(StationID.allCases) { id in
                    if let badge = badges[id] {
                        badgeView(badge, for: id, scale: scale)
                    }
                }
                ForEach(popups) { popup in
                    popupView(popup, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private enum Item: Hashable {
        case station(StationID)
        case doug
    }

    /// Back to front: whatever stands lower on the screen is drawn on top.
    private var drawOrder: [Item] {
        var items: [(Item, Double)] = Floor.stations.map { (.station($0.id), $0.footprint.maxY) }
        items.append((.doug, doug.position.y))
        return items.sorted { $0.1 < $1.1 }.map { $0.0 }
    }

    private func station(_ id: StationID, scale: Double) -> some View {
        let station = Floor.station(id)
        let width = station.drawWidth * scale
        let image = Art.station(id)
        let aspect = image.map { Double($0.size.width / $0.size.height) } ?? 1.2
        let height = width / aspect
        let foot = station.footprint
        return Group {
            if let image {
                Image(uiImage: image).resizable()
            } else {
                StationDrawing(id: id)
            }
        }
        .frame(width: width, height: height)
        .saturation(active.contains(id) ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { tap(id) }
        .position(x: foot.center.x * scale, y: foot.maxY * scale - height / 2)
        .accessibilityLabel(id.name)
        .accessibilityAddTraits(.isButton)
    }

    private func dougView(scale: Double) -> some View {
        let height = 2.05 * scale
        let width = height * 300 / 440
        let bob = doug.isWalking ? abs(sin(doug.walked * 4.5)) * 0.04 * scale : 0
        return DougSprite(facing: doug.facing, frame: frame, pose: pose)
            .frame(width: width, height: height)
            .offset(y: -bob)
            .position(x: doug.position.x * scale, y: doug.position.y * scale - height / 2 + 0.08 * scale)
            .allowsHitTesting(false)
            .accessibilityLabel("Doug")
    }

    /// Walk1, stand, Walk2, stand, as he walks.
    private var frame: Int {
        guard doug.isWalking else { return 0 }
        switch Int(doug.walked / 0.32) % 4 {
        case 0: return 1
        case 2: return 2
        default: return 0
        }
    }

    private func badgeView(_ badge: StationBadge, for id: StationID, scale: Double) -> some View {
        let station = Floor.station(id)
        let image = Art.station(id)
        let aspect = image.map { Double($0.size.width / $0.size.height) } ?? 1.2
        let top = station.footprint.maxY * scale - station.drawWidth * scale / aspect
        return BadgeBubble(badge: badge)
            .position(x: station.footprint.center.x * scale, y: max(22, top + 6))
            .allowsHitTesting(false)
    }

    private func popupView(_ popup: FloorPopup, scale: Double) -> some View {
        let station = Floor.station(popup.station)
        return Text(popup.text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(popup.tint)
            .shadow(color: .black.opacity(0.7), radius: 2)
            .fixedSize()
            .opacity(max(0, 1 - popup.age))
            .position(x: station.footprint.center.x * scale,
                      y: station.footprint.minY * scale - 18 - popup.age * 40)
            .allowsHitTesting(false)
    }
}

/// The concrete floor, or a drawn one.
struct FloorBackground: View {
    var body: some View {
        if let image = Art.floor {
            Image(uiImage: image).resizable()
        } else {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    Color(red: 0.80, green: 0.79, blue: 0.75)
                    Rectangle()
                        .fill(Color(red: 0.93, green: 0.88, blue: 0.78))
                        .frame(height: geo.size.height * Floor.wall / Floor.height)
                    Rectangle()
                        .fill(Color(red: 0.62, green: 0.63, blue: 0.64))
                        .frame(height: 6)
                        .offset(y: geo.size.height * 0.51)
                }
            }
        }
    }
}

/// Doug: the artwork if there is some, else a simple drawing.
struct DougSprite: View {
    let facing: Doug.Facing
    var frame = 0
    var pose: Winemaking.Pose?

    var body: some View {
        if let pose, let image = Art.doug(pose) {
            Image(uiImage: image).resizable().scaledToFit()
        } else if let image = Art.doug(facing, frame: frame) {
            Image(uiImage: image).resizable().scaledToFit()
                .scaleEffect(x: facing == .left ? -1 : 1, y: 1)
        } else {
            DougDrawing(facing: facing)
        }
    }
}

/// A stand-in Doug: silver hair, glasses, navy polo, khakis, boots.
struct DougDrawing: View {
    let facing: Doug.Facing

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let skin = Color(red: 0.93, green: 0.72, blue: 0.58)
            // Boots and legs
            context.fill(Path(roundedRect: CGRect(x: w * 0.32, y: h * 0.62, width: w * 0.36, height: h * 0.26),
                              cornerRadius: 4), with: .color(Color(red: 0.72, green: 0.62, blue: 0.42)))
            context.fill(Path(roundedRect: CGRect(x: w * 0.3, y: h * 0.86, width: w * 0.4, height: h * 0.12),
                              cornerRadius: 4), with: .color(Color(red: 0.15, green: 0.15, blue: 0.15)))
            // Polo
            context.fill(Path(roundedRect: CGRect(x: w * 0.26, y: h * 0.36, width: w * 0.48, height: h * 0.3),
                              cornerRadius: 8), with: .color(Color(red: 0.20, green: 0.25, blue: 0.42)))
            // Head and hair
            let head = CGRect(x: w * 0.3, y: h * 0.06, width: w * 0.4, height: h * 0.3)
            context.fill(Path(ellipseIn: head), with: .color(skin))
            var hair = Path()
            hair.addArc(center: CGPoint(x: head.midX, y: head.minY + head.height * 0.42), radius: head.width * 0.52,
                        startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            context.fill(hair, with: .color(Color(red: 0.82, green: 0.82, blue: 0.82)))
            if facing != .up {
                let glasses = CGRect(x: head.minX + head.width * (facing == .down ? 0.12 : 0.4), y: head.midY - 2,
                                     width: head.width * (facing == .down ? 0.76 : 0.5), height: head.height * 0.16)
                context.stroke(Path(roundedRect: glasses, cornerRadius: 2), with: .color(.black), lineWidth: 2)
                // Gray beard
                context.fill(Path(ellipseIn: CGRect(x: head.minX + head.width * 0.2, y: head.maxY - head.height * 0.3,
                                                    width: head.width * 0.6, height: head.height * 0.28)),
                             with: .color(Color(red: 0.75, green: 0.75, blue: 0.75)))
            }
        }
        .scaleEffect(x: facing == .left ? -1 : 1, y: 1)
    }
}

/// A plain machine, when there's no artwork for it.
struct StationDrawing: View {
    let id: StationID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.35), lineWidth: 1.5))
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.title3)
                Text(id.name).font(.system(size: 9, weight: .semibold)).multilineTextAlignment(.center)
            }
            .foregroundStyle(Color.black.opacity(0.7))
            .padding(4)
        }
    }

    private var fill: Color {
        switch id {
        case .barrels, .newBarrels, .lab: Color(red: 0.72, green: 0.52, blue: 0.32)
        case .chiller: Color(red: 0.45, green: 0.62, blue: 0.82)
        case .bins: Color(red: 0.35, green: 0.35, blue: 0.38)
        case .destemmer, .press, .fermenter, .steelTank: Color(red: 0.80, green: 0.82, blue: 0.84)
        }
    }

    private var symbol: String {
        switch id {
        case .bins: "shippingbox.fill"
        case .destemmer: "gearshape.fill"
        case .press: "rectangle.compress.vertical"
        case .fermenter: "drop.fill"
        case .steelTank: "cylinder.fill"
        case .barrels, .newBarrels: "cylinder.split.1x2.fill"
        case .chiller: "snowflake"
        case .lab: "flask.fill"
        }
    }
}

/// The round marker over a station.
struct BadgeBubble: View {
    let badge: StationBadge
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                if let ring = badge.ring {
                    Circle()
                        .trim(from: 0, to: min(1, max(0, ring)))
                        .stroke(badge.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(2)
                }
                Image(systemName: badge.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(badge.tint)
            }
            .frame(width: 34, height: 34)
            .scaleEffect(badge.urgent && pulse ? 1.18 : 1)
            if let text = badge.text {
                Text(text)
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.55), in: Capsule())
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// A thumb stick: drag anywhere in it to walk Doug that way.
struct Joystick: View {
    @Binding var stick: FloorPoint
    var size: CGFloat = 120
    @State private var knob = CGSize.zero

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 2))
            Circle()
                .fill(Theme.wine.opacity(0.85))
                .frame(width: size * 0.42, height: size * 0.42)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .offset(knob)
            Image(systemName: "figure.walk")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .offset(knob)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let radius = size * 0.36
                    var dx = value.location.x - size / 2
                    var dy = value.location.y - size / 2
                    let length = (dx * dx + dy * dy).squareRoot()
                    if length > radius {
                        dx *= radius / length
                        dy *= radius / length
                    }
                    knob = CGSize(width: dx, height: dy)
                    stick = FloorPoint(Double(dx / radius), Double(dy / radius))
                }
                .onEnded { _ in
                    withAnimation(.snappy(duration: 0.15)) { knob = .zero }
                    stick = .zero
                }
        )
        .accessibilityLabel("Walk")
        .accessibilityHint("Drag to walk Doug around the winery, or tap a machine to send him to work it.")
    }
}
