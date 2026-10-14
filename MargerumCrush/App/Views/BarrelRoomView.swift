import CrushKit
import SwiftUI

/// The cellar after the harvest, with Doug: top up the barrels, taste the
/// lots, and blend and bottle at the lab bench. A month passes when you say
/// so; each one changes the wine.
struct BarrelRoomView: View {
    /// The screenshot tour (UITests) launches with -autopick: Doug walks to
    /// the lab bench on his own.
    private static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopick")

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var walker = Walker()
    @State private var stick = FloorPoint.zero
    @State private var bench = false
    @State private var confirmMonth = false
    @State private var popups: [FloorPopup] = []
    @State private var nextPopup = 0
    @State private var clock = 0.0
    /// Bumped to start the walking loop; it stops once Doug stands still.
    @State private var moves = 0
    @State private var busy = 0.0

    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.14, blue: 0.13).ignoresSafeArea()
            if let game = store.game, game.phase == .cellar {
                VStack(spacing: 0) {
                    CellarHUD(game: game, nextMonth: nextMonth, close: { dismiss() })
                    FloorView(doug: walker.doug, pose: busy > 0 ? .taste : nil, badges: badges(game),
                              popups: popups, active: [.barrels, .newBarrels, .steelTank, .lab]) { station in
                        tap(station, game)
                    }
                    .padding(.vertical, 6)
                    if let station = walker.station, let card = info(station, game) {
                        card.padding(.horizontal, 12).padding(.bottom, 6)
                    }
                    controls(game)
                }
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .statusBarHidden()
        .task(id: moves) { await walk() }
        .onChange(of: stick) { _, new in
            if new != .zero { moves += 1 }
        }
        .onAppear {
            if Self.autopilot {
                walker.walk(to: .lab)
                moves += 1
            }
        }
        .sheet(isPresented: $bench) { BlendingBench() }
        .confirmationDialog("Some barrels need topping up", isPresented: $confirmMonth, titleVisibility: .visible) {
            Button("Let a month go by anyway", role: .destructive) { advanceMonth() }
        } message: {
            Text("Barrels left without topping get air in them, and the wine oxidizes.")
        }
    }

    // MARK: Walking

    private func walk() async {
        var last = Date.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date.now
            let dt = min(0.1, now.timeIntervalSince(last))
            last = now
            clock += dt
            if busy > 0 { busy = max(0, busy - dt) }
            walker.advance(by: dt, stick: stick)
            popups = popups.compactMap { popup in
                let age = popup.age + dt / 1.6
                return age < 1 ? FloorPopup(id: popup.id, text: popup.text, tint: popup.tint, station: popup.station, age: age) : nil
            }
            if stick == .zero && walker.destination == nil && popups.isEmpty && busy == 0 {
                walker.stop()
                break
            }
        }
    }

    private func tap(_ station: StationID, _ game: Game) {
        if walker.station == station, action(at: station, game) != nil {
            act(game)
        } else {
            walker.walk(to: station)
            moves += 1
        }
    }

    private func popup(_ text: String, at station: StationID, good: Bool = true) {
        popups.append(FloorPopup(id: nextPopup, text: text,
                                 tint: good ? Color(red: 0.7, green: 1, blue: 0.6) : Color(red: 1, green: 0.5, blue: 0.45),
                                 station: station, age: 0))
        nextPopup += 1
        moves += 1
    }

    // MARK: Actions

    private enum Action {
        case topUp(Vessel)
        case blend
        case taste

        var name: String {
            switch self {
            case .topUp: "Top up the barrels"
            case .blend: "Blend and bottle"
            case .taste: "Taste"
            }
        }

        var symbol: String {
            switch self {
            case .topUp: "drop.fill"
            case .blend: "flask.fill"
            case .taste: "wineglass.fill"
            }
        }
    }

    private func action(at station: StationID, _ game: Game) -> Action? {
        switch station {
        case .lab:
            return Action.blend
        case .barrels, .newBarrels:
            guard let vessel = station.vessel, game.lots.contains(where: { $0.vessel == vessel }) else { return nil }
            return game.lots.contains { $0.vessel == vessel && $0.sinceTopped > 0 } ? Action.topUp(vessel) : Action.taste
        case .steelTank:
            return game.lots.contains { $0.vessel == .stainless } ? Action.taste : nil
        case .bins, .destemmer, .press, .fermenter, .chiller:
            return nil
        }
    }

    private func act(_ game: Game) {
        guard let station = walker.station, let action = action(at: station, game) else { return }
        walker.face(station)
        switch action {
        case .blend:
            bench = true
        case .topUp(let vessel):
            let count = store.play { $0.topUp(vessel) } ?? 0
            busy = 0.8
            popup(count == 1 ? "Topped up" : "Topped up \(count) lots", at: station)
        case .taste:
            busy = 0.8
            popup("Tasting", at: station)
        }
    }

    private func nextMonth() {
        if let game = store.game, !game.needsTopping.isEmpty {
            confirmMonth = true
        } else {
            advanceMonth()
        }
    }

    private func advanceMonth() {
        store.play { $0.nextMonth() }
        if let game = store.game, game.phase == .cellar {
            for vessel in game.needsTopping {
                popup("Needs topping", at: vessel.station, good: false)
            }
        }
    }

    // MARK: Pieces

    private func controls(_ game: Game) -> some View {
        let action = walker.station.flatMap { self.action(at: $0, game) }
        return HStack(alignment: .center, spacing: 16) {
            Joystick(stick: $stick)
            Spacer(minLength: 0)
            Button {
                act(game)
            } label: {
                ZStack {
                    Circle()
                        .fill(action == nil ? Color.white.opacity(0.15) : Theme.wine)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    VStack(spacing: 3) {
                        Image(systemName: action?.symbol ?? "hand.raised.fill").font(.title3.weight(.bold))
                        Text(action?.name ?? "Walk to the barrels or the lab")
                            .font(.caption.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(10)
                }
                .foregroundStyle(.white.opacity(action == nil ? 0.6 : 1))
                .frame(width: 112, height: 112)
            }
            .buttonStyle(.plain)
            .disabled(action == nil)
            .accessibilityLabel(action?.name ?? "Nothing to do here")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private func badges(_ game: Game) -> [StationID: StationBadge] {
        var badges: [StationID: StationBadge] = [:]
        badges[.lab] = StationBadge(symbol: "flask.fill", tint: Theme.wine,
                                    urgent: game.monthsLeft == 0 && WineID.allCases.contains { game.blocker(for: $0) == nil })
        for vessel in Vessel.allCases {
            let lots = game.lots.filter { $0.vessel == vessel }
            guard !lots.isEmpty else { continue }
            let topping = lots.contains(where: \.needsTopping)
            let months = lots.map(\.sinceTopped).max() ?? 0
            badges[vessel.station] = StationBadge(
                symbol: topping ? "drop.fill" : "wineglass.fill", tint: topping ? Color.red : Theme.leaf,
                urgent: topping, text: "\(lots.reduce(0) { $0 + $1.cases }) cs",
                ring: vessel == .stainless ? nil : Double(min(3, months)) / 3)
        }
        return badges
    }

    /// The lots at the station Doug's next to, and where they're heading.
    private func info(_ station: StationID, _ game: Game) -> AnyView? {
        guard let vessel = station.vessel else {
            if station == .lab {
                return AnyView(Label("The lab bench: blend the lots into wines and bottle them.", systemImage: "flask.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.paper, in: .rect(cornerRadius: 12)))
            }
            return nil
        }
        let lots = game.lots.filter { $0.vessel == vessel }
        guard !lots.isEmpty else { return nil }
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            Text(vessel.name).font(.caption.weight(.bold)).foregroundStyle(Theme.wine)
            ForEach(lots.prefix(4)) { lot in
                HStack(spacing: 8) {
                    Circle().fill(Color(lot.color)).frame(width: 10, height: 10)
                    Text(lot.name).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(trend(lot)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if lots.count > 4 {
                Text("and \(lots.count - 4) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paper, in: .rect(cornerRadius: 12)))
    }

    /// "Tannin 7.8↓ Oak 3.1↑": what next month does.
    private func trend(_ lot: Lot) -> String {
        let now = lot.profile
        let next = lot.taste(in: 1)
        var parts: [String] = []
        let dimensions: [TasteProfile.Dimension] = lot.style == .red ? [.tannin, .oak, .fruit] : [.fruit, .acidity]
        for d in dimensions {
            let change = next[d] - now[d]
            let arrow = change > 0.02 ? "↑" : change < -0.02 ? "↓" : ""
            parts.append("\(d.name) \(Format.one(now[d]))\(arrow)")
        }
        if lot.vessel != .stainless && lot.sinceTopped >= 2 { parts.append("needs topping") }
        return parts.joined(separator: " · ")
    }
}

/// The month, the year and what's left before the release.
struct CellarHUD: View {
    let game: Game
    let nextMonth: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(Theme.ink)
                .accessibilityLabel("Leave the cellar")
                VStack(alignment: .leading, spacing: 0) {
                    Text("The cellar").font(.subheadline.weight(.bold))
                    Text("\(Aging.name(game.cellarMonth)) \(String(year))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button(action: nextMonth) {
                    Label(game.monthsLeft == 0 ? "Release in August" : "Next month", systemImage: "calendar")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Theme.gold.opacity(0.35), in: Capsule())
                }
                .tint(Theme.ink)
            }
            HStack(spacing: 4) {
                ForEach(Array(Aging.months.enumerated()), id: \.offset) { index, name in
                    VStack(spacing: 2) {
                        Capsule()
                            .fill(index < game.cellarMonth ? Theme.wine.opacity(0.5)
                                  : index == game.cellarMonth ? Theme.wine : Color.black.opacity(0.1))
                            .frame(height: 6)
                        Text(String(name.prefix(1)))
                            .font(.system(size: 9, weight: index == game.cellarMonth ? .bold : .regular))
                            .foregroundStyle(index == game.cellarMonth ? Theme.wine : Color.secondary)
                    }
                }
            }
            Text(hint)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper)
    }

    private var year: Int { game.cellarMonth >= 2 ? game.vintage + 1 : game.vintage }

    private var hint: String {
        if let vessel = game.needsTopping.first {
            return "The \(vessel.name.lowercased()) need topping up before air gets in."
        }
        if game.monthsLeft == 0 {
            return "Last month before the release. Bottle what you want to sell."
        }
        let ready = WineID.allCases.filter { game.blocker(for: $0) == nil }
        if ready.isEmpty { return "Everything's bottled. Let the months go by, or release it now." }
        return "Blend at the lab bench when the wines taste right. Rosé and Sybarite are best young; the reds want time."
    }
}

/// The lab bench: the four wines, each ready to blend or already bottled.
struct BlendingBench: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let game = store.game {
                    VStack(spacing: 14) {
                        SectionTitle("Make the wines", detail: "\(Aging.name(game.cellarMonth)) · one bottling of each")
                        ForEach(WineID.allCases) { wine in
                            WineRow(game: game, wine: wine)
                        }
                        SectionTitle("In the cellar", detail: "\(game.lots.reduce(0) { $0 + $1.cases }) cases")
                        ForEach(game.lots) { lot in
                            LotRow(lot: lot)
                        }
                    }
                    .padding(16)
                }
            }
            .background(Theme.paper)
            .navigationTitle("The lab bench")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WineID.self) { wine in
                BlendingLabView(wine: wine)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
