import CrushKit
import SwiftUI

/// Doug's crush, played on the winery floor: walk him to each machine (drag
/// the stick, or tap a machine) and do each job at the right moment.
struct WinemakingView: View {
    /// The screenshot tour (UITests) launches with -autopick: Doug plays himself.
    private static let autopilot = ProcessInfo.processInfo.arguments.contains("-autopick")

    @Environment(GameStore.self) private var store
    @State private var session: Winemaking
    @State private var stick = FloorPoint.zero
    @State private var confirmQuit = false
    @State private var made: [Lot]?
    @State private var result: WinemakingResult?
    /// How the crew (or the autopilot) would do it.
    let plan: CrushPlan
    let done: () -> Void

    init(session: Winemaking, plan: CrushPlan, done: @escaping () -> Void) {
        _session = State(initialValue: session)
        self.plan = plan
        self.done = done
    }

    var body: some View {
        ZStack {
            Color(red: 0.16, green: 0.14, blue: 0.13).ignoresSafeArea()
            VStack(spacing: 0) {
                CrushHUD(session: session, fastForward: $session.fastForward) { confirmQuit = true }
                FloorView(doug: session.doug, pose: session.busyWith?.pose, badges: badges, popups: popups,
                          active: activeStations) { station in
                    tap(station)
                }
                .padding(.vertical, 6)
                controls
            }
            if let made, let result {
                CrushResultsView(harvest: session.harvest, result: result, lots: made, done: done)
                    .transition(.move(edge: .bottom))
            }
        }
        .statusBarHidden()
        .task { await run() }
        .sensoryFeedback(.impact(weight: .medium), trigger: session.punchDowns)
        .confirmationDialog("Leave it to the crew?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("The crew can finish it") {
                session.finish(with: .crew(saignee: false, vessel: plan.vessel))
            }
        } message: {
            Text("They'll get it into tank or barrel, but they won't fuss over it like Doug.")
        }
    }

    // MARK: Playing

    private func run() async {
        var last = Date.now
        while !Task.isCancelled && !session.isFinished {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date.now
            // Capped, so a pause (a phone call, the app in the background)
            // doesn't skip the fermentation.
            let dt = min(0.1, now.timeIntervalSince(last))
            last = now
            if Self.autopilot { session.autopilot(plan) }
            session.advance(by: dt, stick: stick)
        }
        guard !Task.isCancelled else { return }
        finish()
    }

    private func finish() {
        let result = session.result
        let lots = store.play { $0.finishWinemaking(session) } ?? []
        withAnimation(.snappy) {
            self.result = result
            made = lots
        }
    }

    private func tap(_ station: StationID) {
        if session.station == station, session.availableAction != nil {
            session.act()
        } else {
            session.walk(to: station)
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(alignment: .center, spacing: 16) {
            Joystick(stick: $stick)
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                if let other = otherAction {
                    Button {
                        session.act(other)
                    } label: {
                        Label(other.name, systemImage: symbol(other))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Theme.gold, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 170)
                }
                actionButton
                if let station = session.station {
                    Text(station.name)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var actionButton: some View {
        let action = session.availableAction
        return Button {
            session.act()
        } label: {
            ZStack {
                Circle()
                    .fill(action == nil ? Color.white.opacity(0.15) : Theme.wine)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                if session.busy > 0, let doing = session.busyWith {
                    VStack(spacing: 2) {
                        ProgressView().tint(.white)
                        Text(doing.name).font(.caption2.weight(.semibold))
                    }
                } else {
                    VStack(spacing: 3) {
                        Image(systemName: action.map(symbol) ?? "hand.raised.fill").font(.title3.weight(.bold))
                        Text(action?.name ?? "Walk to a machine")
                            .font(.caption.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(10)
                }
            }
            .foregroundStyle(.white.opacity(action == nil ? 0.6 : 1))
            .frame(width: 112, height: 112)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(action?.name ?? "Nothing to do here")
    }

    /// A second job at this machine, if it has one: whole clusters at the
    /// destemmer.
    private var otherAction: Winemaking.Action? {
        guard session.busy <= 0, let station = session.station else { return nil }
        return session.actions(at: station).dropFirst().first
    }

    private func symbol(_ action: Winemaking.Action) -> String {
        switch action {
        case .destem, .crush: "gearshape.2.fill"
        case .wholeCluster: "leaf.fill"
        case .loadPress, .press: "rectangle.compress.vertical"
        case .cutPress: "stop.fill"
        case .fill: "arrow.down.to.line"
        case .openBleed: "drop.fill"
        case .closeBleed: "drop.triangle"
        case .addYeast: "flask.fill"
        case .punchDown: "arrow.down.circle.fill"
        case .chill(let on): on ? "snowflake" : "snowflake.slash"
        }
    }

    // MARK: Markers

    /// Stations in play for this wine.
    private var activeStations: Set<StationID> {
        var stations: Set<StationID> = [.lab, .chiller, .steelTank, .barrels]
        switch session.harvest.style {
        case .red: stations.formUnion([.destemmer, .fermenter, .press, .bins])
        case .rose: stations.formUnion([.destemmer, .press, .bins])
        case .white: stations.formUnion([.press, .bins])
        }
        if session.vessels.contains(.newOak) { stations.insert(.newBarrels) }
        return stations
    }

    private var badges: [StationID: StationBadge] {
        var badges: [StationID: StationBadge] = [:]
        for job in session.jobs.reversed() {
            badges[job.station] = StationBadge(symbol: icon(for: job.station),
                                               tint: job.urgent ? Color.red : Theme.wine, urgent: job.urgent)
        }
        let s = session
        switch s.stage {
        case .pressing:
            badges[.press] = StationBadge(symbol: "rectangle.compress.vertical",
                                          tint: s.pressProgress > s.pressKnee ? .red : Theme.leaf,
                                          urgent: s.pressProgress > s.pressKnee - 0.05,
                                          text: "\(Format.one(s.pressProgress * 2)) bar",
                                          ring: s.pressProgress)
        case .skinContact:
            badges[.press] = StationBadge(symbol: "drop.fill", tint: Color(s.harvest.varietal.roseColor(s.color)),
                                          urgent: s.color >= Winemaking.pink.lowerBound,
                                          text: "\(Int(s.hours.rounded())) h", ring: s.color / Winemaking.pink.upperBound)
        case .soaking, .fermenting:
            if s.harvest.style == .red {
                var fermenter = badges[.fermenter] ?? StationBadge(symbol: "thermometer.medium", tint: Theme.ink)
                fermenter.text = "\(Int(s.temperature.rounded()))°"
                if s.stage == .fermenting { fermenter.ring = s.cap }
                if s.bleeding { fermenter.symbol = "drop.fill"; fermenter.text = "\(Int((s.bleed * 100).rounded()))%" }
                badges[.fermenter] = fermenter
            } else {
                var tank = badges[.steelTank] ?? StationBadge(symbol: "thermometer.medium", tint: Theme.ink)
                tank.text = "\(Int(s.temperature.rounded()))°"
                badges[s.vessel?.station ?? .steelTank] = tank
            }
        case .settling:
            var tank = badges[s.vessel?.station ?? .steelTank] ?? StationBadge(symbol: "hourglass", tint: Theme.ink)
            tank.ring = s.clarity
            tank.text = "\(Int(s.temperature.rounded()))°"
            badges[s.vessel?.station ?? .steelTank] = tank
        case .dry:
            badges[.fermenter] = StationBadge(symbol: "checkmark", tint: Theme.leaf)
        default:
            break
        }
        if s.chilling {
            var chiller = badges[.chiller] ?? StationBadge(symbol: "snowflake", tint: .blue)
            chiller.symbol = "snowflake"
            chiller.text = "On"
            badges[.chiller] = chiller
        }
        return badges
    }

    private func icon(for station: StationID) -> String {
        switch station {
        case .destemmer: "gearshape.2.fill"
        case .press: "rectangle.compress.vertical"
        case .fermenter: "arrow.down.circle.fill"
        case .chiller: "snowflake"
        case .lab: "flask.fill"
        case .steelTank, .barrels, .newBarrels: "arrow.down.to.line"
        case .bins: "shippingbox.fill"
        }
    }

    private var popups: [FloorPopup] {
        session.events.compactMap { event in
            let age = (session.seconds - event.time) / 1.6
            guard age < 1 else { return nil }
            let tint: Color
            switch event.tone {
            case .good: tint = Color(red: 0.7, green: 1, blue: 0.6)
            case .bad: tint = Color(red: 1, green: 0.5, blue: 0.45)
            case .info: tint = .white
            }
            return FloorPopup(id: event.id, text: event.text, tint: tint, station: event.station, age: age)
        }
    }
}

/// The clock, the block, the gauges for this stage and the job at hand.
struct CrushHUD: View {
    let session: Winemaking
    @Binding var fastForward: Bool
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button(action: quit) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(Theme.ink)
                .accessibilityLabel("Leave it to the crew")
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.harvest.blockName).font(.subheadline.weight(.bold)).lineLimit(1)
                    Text("\(styleName) · \(clock)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    fastForward.toggle()
                } label: {
                    Label(fastForward ? "3×" : "1×", systemImage: "forward.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(fastForward ? Theme.gold.opacity(0.35) : Color.white.opacity(0.5), in: Capsule())
                }
                .tint(Theme.ink)
                .accessibilityLabel(fastForward ? "Normal speed" : "Fast forward")
            }
            gauges
            if let job = session.jobs.first {
                Label(job.text, systemImage: job.urgent ? "exclamationmark.circle.fill" : "lightbulb.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(job.urgent ? Color.red : Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.paper)
    }

    /// White: juice so far, as a share of the usual.
    private var pressYield: Double { Winemaking.pressYield(session.pressProgress) }

    private var sinceDry: Double { session.hours - (session.dryAt ?? session.hours) }

    /// Red: hours on the skins before the yeast went in (or so far).
    private var soaked: Double {
        guard let crushed = session.crushedAt else { return 0 }
        return (session.yeastAt ?? session.hours) - crushed
    }

    private var styleName: String {
        switch session.harvest.style {
        case .red: "Red"
        case .rose: "Rosé"
        case .white: "White"
        }
    }

    /// "Day 2 · 3 PM": the fruit came in at 8 in the morning.
    private var clock: String {
        let total = 8 + session.hours
        let day = Int(total / 24) + 1
        let hour = Int(total.truncatingRemainder(dividingBy: 24))
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        return "Day \(day) · \(twelve) \(hour < 12 ? "AM" : "PM")"
    }

    @ViewBuilder private var gauges: some View {
        let s = session
        HStack(spacing: 10) {
            switch s.stage {
            case .waiting:
                Meter(title: "Waiting", value: s.hours, range: 0...12, good: 0...s.freshFor, text: "\(Int(s.hours)) h")
                Meter(title: "Fruit", value: s.harvest.fruitTemperature, range: 10...35, good: 10...24,
                      text: "\(Int(s.harvest.fruitTemperature.rounded()))°C")
            case .pressing:
                Meter(title: "Press", value: s.pressProgress, range: 0...1, good: 0...s.pressKnee,
                      text: "\(Format.one(s.pressProgress * 2)) bar")
                Meter(title: "Juice", value: pressYield, range: 0...1.05, good: 0.55...1.05, text: Format.percent(pressYield))
            case .skinContact:
                Meter(title: "Color", value: s.color, range: 0...0.7, good: Winemaking.pink, text: "\(Int(s.hours.rounded())) h",
                      tint: Color(s.harvest.varietal.roseColor(s.color)))
                Meter(title: "Juice", value: s.temperature, range: 5...35, good: 8...18, text: "\(Int(s.temperature.rounded()))°C")
            case .juice, .pressed:
                Meter(title: "Waiting", value: s.hours - s.juiceSince, range: 0...12, good: 0...3,
                      text: "\(Int((s.hours - s.juiceSince).rounded())) h")
                Meter(title: "Sugar", value: s.sugar, range: -2...28, good: -2...0, text: "\(Format.one(s.sugar))°")
            case .settling:
                Meter(title: "Settled", value: s.clarity, range: 0...1, good: 0.7...1, text: Format.percent(s.clarity))
                Meter(title: "Temp", value: s.temperature, range: 5...35, good: 10...16, text: "\(Int(s.temperature.rounded()))°C")
            case .soaking:
                Meter(title: "Juice color", value: s.color, range: 0...0.7, good: Winemaking.pink,
                      text: s.bleed > 0 ? "Bled \(Format.percent(s.bleed))" : "\(Int(s.hours.rounded())) h",
                      tint: Color(s.harvest.varietal.roseColor(s.color)))
                Meter(title: "Cold soak", value: soaked, range: 0...(s.yeastWindow.upperBound + 12), good: s.yeastWindow,
                      text: s.yeastAt == nil ? "\(Int(soaked.rounded())) h" : "Yeast in")
                Meter(title: "Temp", value: s.temperature, range: 5...35, good: 10...24, text: "\(Int(s.temperature.rounded()))°C")
            case .fermenting:
                Meter(title: "Sugar", value: s.sugar, range: -2...28, good: -2...0, text: "\(Format.one(s.sugar))°")
                Meter(title: "Temp", value: s.temperature, range: 5...36,
                      good: s.harvest.style == .red ? 24...31 : 10...16, text: "\(Int(s.temperature.rounded()))°C")
                if s.harvest.style == .red {
                    Meter(title: "Cap", value: s.cap, range: 0...1, good: 0...0.6, text: s.cap > 0.8 ? "Dry!" : "Wet")
                }
            case .dry:
                Meter(title: "On skins", value: sinceDry, range: 0...max(24, s.macerationHours + 24),
                      good: max(0, s.macerationHours - 8)...(s.macerationHours + 8), text: "\(Int(sinceDry.rounded())) h")
                Meter(title: "Temp", value: s.temperature, range: 5...36, good: 18...31, text: "\(Int(s.temperature.rounded()))°C")
            case .done:
                EmptyView()
            }
        }
    }
}

/// A labeled bar with its good range shaded.
struct Meter: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let good: ClosedRange<Double>
    let text: String
    var tint: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.8).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(text).font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(good.contains(value) ? Theme.leaf : Theme.wine)
            }
            GeometryReader { geo in
                let w = Double(geo.size.width)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule()
                        .fill(Theme.leaf.opacity(0.3))
                        .frame(width: max(4, w * fraction(good.upperBound) - w * fraction(good.lowerBound)))
                        .offset(x: w * fraction(good.lowerBound))
                    Circle()
                        .fill(tint ?? (good.contains(value) ? Theme.leaf : Theme.wine))
                        .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                        .frame(width: 12, height: 12)
                        .offset(x: w * fraction(value) - 6)
                }
            }
            .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(text)")
    }

    private func fraction(_ v: Double) -> Double {
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

/// What came of the crush: the breakdown, and the lots in the cellar.
struct CrushResultsView: View {
    let harvest: Harvest
    let result: WinemakingResult
    let lots: [Lot]
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Into the cellar").font(.largeTitle.weight(.bold)).fontDesign(.serif)
                        Text(harvest.blockName).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 10) {
                        ForEach(lots) { lot in
                            LotRow(lot: lot)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How Doug did").font(.headline)
                        ForEach(result.notes) { note in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: note.quality > 0.05 ? "plus.circle.fill"
                                      : note.quality < -0.05 ? "minus.circle.fill" : "circle.fill")
                                    .foregroundStyle(note.quality > 0.05 ? Theme.leaf
                                                     : note.quality < -0.05 ? Color.red : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(note.title).font(.subheadline.weight(.semibold))
                                    Text(note.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                if abs(note.quality) >= 0.05 {
                                    Text(String(format: "%+.1f", note.quality))
                                        .font(.subheadline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(note.quality > 0 ? Theme.leaf : Color.red)
                                }
                            }
                        }
                        Divider()
                        HStack {
                            Text("Winemaking").font(.headline)
                            Spacer()
                            Text(String(format: "%+.1f", result.quality))
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(result.quality >= 0 ? Theme.leaf : Color.red)
                        }
                    }
                    .card()
                }
                .padding(20)
            }
            Button(action: done) {
                Text("Back to the vineyard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
        .background(Theme.paper)
    }
}
