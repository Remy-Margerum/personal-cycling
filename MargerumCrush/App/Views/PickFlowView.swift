import CrushKit
import SwiftUI

/// A crew's trip into a block: the briefing, the picking game, what came
/// back, and the crush pad.
struct PickFlowView: View {
    enum Stage { case briefing, countdown, picking, results, crush }

    /// The screenshot tour (UITests) launches with -autopick: the app picks
    /// the good bunches itself, because UI tests can't keep up with a round.
    private static let autopick = ProcessInfo.processInfo.arguments.contains("-autopick")

    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: PickRequest
    @State private var round: PickingRound
    @State private var stage = Stage.briefing
    @State private var count = 3
    @State private var harvest: Harvest?
    @State private var confirmQuit = false

    init(request: PickRequest) {
        self.request = request
        _round = State(initialValue: request.round)
    }

    var body: some View {
        ZStack {
            switch stage {
            case .briefing:
                BriefingView(request: request, round: round, start: { stage = .countdown }, cancel: { dismiss() })
            case .countdown, .picking:
                MiniGameView(round: $round, varietal: request.block.varietal, quit: { confirmQuit = true })
                    .overlay {
                        if stage == .countdown {
                            Countdown(count: count)
                        } else if round.isOver {
                            Countdown(text: "Time!")
                        }
                    }
            case .results:
                PickResultsView(block: request.block, round: round, harvest: harvest) {
                    if harvest == nil { dismiss() } else { stage = .crush }
                }
            case .crush:
                if let harvest {
                    CrushFlowView(harvest: harvest) { dismiss() }
                }
            }
        }
        .task(id: stage) { await run(stage) }
        .statusBarHidden(stage == .countdown || stage == .picking)
        .confirmationDialog("Stop picking?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("Call the crew back", role: .destructive) { dismiss() }
        } message: {
            Text("Nothing gets picked and the fruit stays on the vine. The crew can go out again this week.")
        }
    }

    private func run(_ stage: Stage) async {
        switch stage {
        case .countdown:
            for n in [3, 2, 1] {
                count = n
                try? await Task.sleep(for: .milliseconds(700))
            }
            if !Task.isCancelled { self.stage = .picking }
        case .picking:
            var last = Date.now
            while !Task.isCancelled && !round.isOver {
                try? await Task.sleep(for: .milliseconds(16))
                let now = Date.now
                // Capped, so a pause (a phone call, the app in the background)
                // doesn't skip half the round.
                round.advance(by: min(0.1, now.timeIntervalSince(last)))
                last = now
                if Self.autopick {
                    for cluster in round.clusters where cluster.kind.isGood && cluster.age(at: round.time) > 0.5 {
                        round.pick(cluster.id)
                    }
                }
            }
            guard !Task.isCancelled else { return }
            harvest = store.play { $0.bringIn(round, from: request.block.id, for: request.style) } ?? nil
            try? await Task.sleep(for: .milliseconds(900))
            self.stage = .results
        case .briefing, .results, .crush:
            break
        }
    }
}

/// What the crew is about to do, what each bunch does to the wine, and how
/// to play.
struct BriefingView: View {
    let request: PickRequest
    let round: PickingRound
    let start: () -> Void
    let cancel: () -> Void

    var body: some View {
        let block = request.block
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.style == .rose ? "Picking for rosé" : "Picking")
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.wine)
                    Text(block.name).font(.largeTitle.weight(.bold)).fontDesign(.serif)
                    Text("\(Format.tons(block.tons)) · \(Format.one(block.brix))° Brix · \(Format.one(block.acid)) g/L acid · "
                         + block.ripeness(for: request.style).label)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Aim for \(Format.one(round.window.lowerBound))–\(Format.one(round.window.upperBound))° Brix in the bins.",
                          systemImage: "target")
                        .font(.subheadline.weight(.semibold))
                    Text(advice)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("What each bunch does").font(.headline)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                              alignment: .leading, spacing: 12) {
                        ForEach(kinds, id: \.self) { kind in
                            HStack(alignment: .top, spacing: 8) {
                                ClusterSprite(kind: kind, varietal: block.varietal)
                                    .frame(width: 30, height: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(kind.name).font(.caption.weight(.semibold))
                                    Text(effect(kind)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    HStack(spacing: 14) {
                        WaspSprite().frame(width: 34, height: 34)
                        Text("Don't swat the wasps: a sting costs \(Int(PickingRound.sting)) seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()

                Text("Picking about seven bunches in ten brings in the whole crop. Skipping bunches makes less wine, "
                     + "but better wine.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button(action: start) {
                    Text("Start picking").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Not yet", action: cancel)
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    private var kinds: [PickingRound.Kind] {
        PickingRound.Kind.allCases.filter { (round.odds[$0] ?? 0) > 0.004 }
    }

    /// What the bin needs from this block.
    private var advice: String {
        let brix = round.baseBrix
        var lines: [String] = []
        if brix < round.window.lowerBound - 0.3 {
            lines.append("It's early: the block is under the window. Skip shaded, second-crop and green-stemmed bunches and "
                         + "the bins come in riper; sunny and raisined ones push it up.")
        } else if brix > round.window.upperBound + 0.3 {
            lines.append("It's late: the block is over the window. A few shaded bunches bring the sugar down and the "
                         + "acid up; leave the raisined ones.")
        } else {
            lines.append("Right in the window: pick the sunny, brown-stemmed bunches and the hens and chicks.")
        }
        if (round.odds[.rotten] ?? 0) + (round.odds[.sour] ?? 0) > 0.08 {
            lines.append("Rot is spreading: watch for gray mold and sour rot.")
        }
        if request.block.varietal == .sauvignonBlanc {
            lines.append("Sybarite likes a little green: a few shaded bunches add grass and lemongrass.")
        }
        return lines.joined(separator: " ")
    }

    private func effect(_ kind: PickingRound.Kind) -> String {
        switch kind {
        case .ripe: "Sunny, on a brown stem: sugar, color, ripe tannin."
        case .greenStem: "Not really ripe: stalky and green. No good for whole clusters."
        case .shaded: "Less sugar, more acid, green notes."
        case .secondCrop: "Weeks behind: hard, sour and green. Leave it."
        case .shot: "Small, sweet berries: color, tannin, complexity."
        case .raisined: "Lots of sugar, less acid and color. Jammy."
        case .rotten: "Gray mold: musty, and it eats the color. Leave it."
        case .sour: "Sour rot: vinegar. Leave it."
        case .golden: "Perfect. Complexity. Grab it."
        case .leaf: "Bitter, leafy and green. Two in the bins and it shows."
        case .cane: "Woody and bitter. Don't grab it."
        }
    }
}

/// 3, 2, 1, and "Time!".
struct Countdown: View {
    var count = 0
    var text: String?

    var body: some View {
        Text(text ?? String(count))
            .font(.system(size: 96, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 8)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: count)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.25))
            .allowsHitTesting(true)
    }
}

/// What came back in the bins: the bunches, and the must they make.
struct PickResultsView: View {
    let block: VineyardBlock
    let round: PickingRound
    let harvest: Harvest?
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(harvest == nil ? "Nothing in the bins" : "In the bins")
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.serif)
                    if let harvest {
                        Text("\(Format.tons(harvest.tons)) of \(block.name), about \(harvest.cases) cases of wine.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("The fruit is still on the vine. Try again next week.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let harvest {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("The must").font(.headline)
                        HStack(spacing: 12) {
                            Meter(title: "Sugar", value: harvest.brix,
                                  range: (round.window.lowerBound - 3)...(round.window.upperBound + 3), good: round.window,
                                  text: "\(Format.one(harvest.brix))°")
                            Meter(title: "Acid", value: harvest.acid, range: (round.idealAcid - 3)...(round.idealAcid + 3),
                                  good: (round.idealAcid - 0.9)...(round.idealAcid + 0.9), text: "\(Format.one(harvest.acid)) g/L")
                        }
                        HStack {
                            stat("Tannin", signed(harvest.tannin))
                            stat("Green", Format.one(harvest.green))
                            stat("Complexity", Format.one(harvest.complexity))
                            stat("Leaves & canes", Format.percent(harvest.mogShare))
                        }
                        Text("Brix and acid of the block: \(Format.one(block.brix))° and \(Format.one(block.acid)) g/L.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .card()
                }

                VStack(spacing: 10) {
                    ForEach(PickingRound.Kind.allCases.filter { round.bin.count($0) > 0 }, id: \.self) { kind in
                        HStack(spacing: 12) {
                            ClusterSprite(kind: kind, varietal: block.varietal).frame(width: 22, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.name)
                                if let note = note(for: kind) {
                                    Text(note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(String(round.bin.count(kind))).font(.headline.monospacedDigit())
                        }
                    }
                    if round.bin.bunches == 0 {
                        Text("No fruit picked.").foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Text("Good bunches left on the vine").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(round.missed)).monospacedDigit()
                    }
                    HStack {
                        Text("Wasp stings").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(round.stings)).monospacedDigit()
                    }
                }
                .card()

                if let harvest {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Fruit quality")
                            Spacer()
                            Text("\(Int(harvest.quality.rounded())) / 100").font(.headline.monospacedDigit())
                        }
                        ProgressView(value: harvest.quality, total: 100).tint(Theme.wine)
                    }
                    .card()
                }
            }
            .padding(20)
        }
        .background(Theme.paper)
        .safeAreaInset(edge: .bottom) {
            Button(action: next) {
                Text(harvest == nil ? "Back to the vineyard" : "To the crush pad").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }

    private func signed(_ value: Double) -> String {
        abs(value) < 0.05 ? "0" : (value > 0 ? "+" : "−") + Format.one(abs(value))
    }

    private func note(for kind: PickingRound.Kind) -> String? {
        guard let sorted = harvest?.sortedOut, sorted > 0,
              [.rotten, .sour, .leaf, .cane].contains(kind) else { return nil }
        return "The sorting table caught most of these"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
