import CrushKit
import SwiftUI

/// A crew's trip into a block: the briefing, the picking game, what came
/// back, and the crush pad.
struct PickFlowView: View {
    enum Stage { case briefing, countdown, picking, results, crush }

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
                    CrushPadView(harvest: harvest) { dismiss() }
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

/// What the crew is about to do, and how to play.
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
                    Text("\(Format.tons(block.tons)) · \(Format.one(block.brix))° Brix · \(block.ripeness(for: request.style).label)")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    rule(.ripe, "Ripe bunches", "Tap them before they wither.")
                    rule(.golden, "Perfect bunches", "Rare and worth a lot. Grab them.")
                    rule(.unripe, "Green bunches", "Leave them. They make the wine taste green.")
                    rule(.rotten, "Moldy bunches", "Leave them. Mold ruins wine.")
                    HStack(spacing: 14) {
                        WaspSprite().frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Wasps").font(.headline)
                            Text("Don't swat them. A sting costs \(Int(PickingRound.sting)) seconds.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .card()

                if round.unripeShare > 0.2 {
                    tip("It's early: expect a lot of green bunches. Skip them, even if it means less wine.")
                }
                if round.rotShare > 0.1 {
                    tip("Mold is spreading in this block. Sort carefully.")
                }
                Text("Picking about three bunches in four brings in the whole crop.")
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

    private func rule(_ kind: PickingRound.Kind, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 14) {
            ClusterSprite(kind: kind, varietal: request.block.varietal)
                .frame(width: 34, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func tip(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Theme.wine)
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

/// What came back in the bins.
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

                let tally = round.tally
                VStack(spacing: 10) {
                    row(.ripe, "Ripe", tally.ripe)
                    row(.golden, "Perfect", tally.golden)
                    row(.unripe, "Green", tally.unripe)
                    row(.rotten, "Moldy", tally.rotten, note: sortedNote)
                    HStack {
                        Text("Withered on the vine").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(tally.missed)).monospacedDigit()
                    }
                    HStack {
                        Text("Wasp stings").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(tally.stings)).monospacedDigit()
                    }
                }
                .card()

                if let harvest {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Clean fruit")
                            Spacer()
                            Text(Format.percent(1 - harvest.unripeShare - harvest.rotShare))
                                .font(.headline.monospacedDigit())
                        }
                        HStack {
                            Text("Fruit quality")
                            Spacer()
                            Text("\(Int(harvest.quality.rounded())) / 100").font(.headline.monospacedDigit())
                        }
                        ProgressView(value: harvest.quality, total: 100).tint(Theme.wine)
                    }
                    .card()
                }

                HStack {
                    Label("\(round.points) points", systemImage: "star.fill")
                    Spacer()
                    Text("Best streak: \(round.bestStreak)")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 4)
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

    private var sortedNote: String? {
        guard let sorted = harvest?.sortedOut, sorted > 0 else { return nil }
        return "\(sorted) caught by the sorting table"
    }

    private func row(_ kind: PickingRound.Kind, _ title: String, _ count: Int, note: String? = nil) -> some View {
        HStack(spacing: 12) {
            ClusterSprite(kind: kind, varietal: block.varietal).frame(width: 22, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(String(count)).font(.headline.monospacedDigit())
        }
    }
}
