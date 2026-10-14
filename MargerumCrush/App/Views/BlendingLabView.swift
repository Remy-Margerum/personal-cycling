import CrushKit
import SwiftUI

/// Blend lots into one of the wines, watching the taste against the style
/// the critic expects, then bottle it. Anything in the cellar can go in, as
/// long as the label rules hold: 85% the wine's color, 85% one vintage.
struct BlendingLabView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let wine: WineID
    @State private var cases: [UUID: Int] = [:]
    @State private var review: BottledWine?

    var body: some View {
        Group {
            if let game = store.game {
                lab(game)
            }
        }
        .background(Theme.paper)
        .navigationTitle(wine.spec.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $review, onDismiss: { dismiss() }) { bottled in
            ReviewView(wine: bottled)
        }
        .onAppear {
            // Start with this year's wine of the right color (and grape, for
            // the varietal wines).
            if cases.isEmpty, let game = store.game {
                for lot in start(game) { cases[lot.id] = lot.cases }
            }
        }
    }

    private func start(_ game: Game) -> [Lot] {
        let own = game.lots(for: wine)
        let newest = own.map(\.vintage).max()
        let grapes = wine.spec.requiredVarietals
        return own.filter { $0.vintage == newest && (grapes.count != 1 || $0.varietal == grapes[0]) }
    }

    private func lab(_ game: Game) -> some View {
        let spec = wine.spec
        let lots = game.blendable(for: wine)
        let own = lots.filter { $0.style == spec.style }
        let others = lots.filter { $0.style != spec.style }
        let analysis = game.analyze(Blend(wine: wine, cases: cases))
        let nextMonth = game.monthsLeft > 0 ? game.analyze(Blend(wine: wine, cases: cases), monthsAhead: 1) : nil
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(spec.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                BlendPreview(wine: wine, vintage: analysis.vintage ?? game.vintage, analysis: analysis,
                             month: Aging.name(game.cellarMonth), nextMonth: nextMonth)
                ProfileChart(profile: analysis.profile, target: spec.target, empty: analysis.cases == 0)
                if !analysis.composition.isEmpty {
                    CompositionBar(composition: analysis.composition)
                }
                ForEach(analysis.cases > 0 ? analysis.problems : [], id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 4)
                }

                HStack {
                    SectionTitle("Lots")
                    Button("Use all") {
                        for lot in own { cases[lot.id] = lot.cases }
                    }
                    .font(.caption.weight(.semibold))
                    Button("Clear") { cases = [:] }
                        .font(.caption.weight(.semibold))
                        .padding(.leading, 8)
                }
                ForEach(own) { lot in
                    LotSlider(lot: lot, vintage: game.vintage, cases: binding(for: lot), share: share(of: lot, in: analysis))
                }
                if !others.isEmpty {
                    SectionTitle("Other wine in the cellar", detail: "Up to 15% of the blend")
                    ForEach(others) { lot in
                        LotSlider(lot: lot, vintage: game.vintage, cases: binding(for: lot), share: share(of: lot, in: analysis))
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                review = store.play { $0.bottle(Blend(wine: wine, cases: cases)) } ?? nil
            } label: {
                Text(analysis.canBottle ? "Bottle \(analysis.cases) cases in \(Aging.name(game.cellarMonth))" : "Bottle it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!analysis.canBottle)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func binding(for lot: Lot) -> Binding<Double> {
        Binding(get: { Double(cases[lot.id] ?? 0) },
                set: { cases[lot.id] = Int($0.rounded()) })
    }

    private func share(of lot: Lot, in analysis: BlendAnalysis) -> Double {
        guard analysis.cases > 0 else { return 0 }
        return Double(min(cases[lot.id] ?? 0, lot.cases)) / Double(analysis.cases)
    }
}

/// The bottle, its color and the winemaker's estimate, now and next month.
struct BlendPreview: View {
    let wine: WineID
    let vintage: Int
    let analysis: BlendAnalysis
    var month: String?
    /// The same blend a month on, while there's time to wait.
    var nextMonth: BlendAnalysis?

    var body: some View {
        HStack(spacing: 18) {
            BottleView(wine: wine, vintage: vintage, color: analysis.cases > 0 ? analysis.color : RGB(0.86, 0.86, 0.86))
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text(month.map { "Your estimate in \($0)" } ?? "Your estimate").font(.caption).foregroundStyle(.secondary)
                if analysis.cases > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(analysis.score))
                            .font(.system(size: 46, weight: .bold, design: .serif))
                            .contentTransition(.numericText())
                        Text("pts").font(.headline).foregroundStyle(.secondary)
                    }
                    Text(BottledWine.verdict(analysis.score))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.wine)
                    Text("\(analysis.cases) cases · \(Format.one(analysis.alcohol))% alcohol")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let next = nextMonth, next.cases > 0 {
                        let change = next.score - analysis.score
                        Text("A month from now: \(next.score)" + (change > 0 ? " (+\(change))" : change < 0 ? " (\(change))" : ""))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(change > 0 ? Theme.leaf : change < 0 ? Theme.wine : Color.secondary)
                    }
                    Text("The critic may land a point either side.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("–").font(.system(size: 46, weight: .bold, design: .serif))
                    Text("Add wine from the lots below.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .card()
        .animation(.snappy, value: analysis.score)
    }
}

/// The blend's taste against Doug's range for the wine (the gold bands).
struct ProfileChart: View {
    let profile: TasteProfile
    let target: [TasteProfile.Dimension: ClosedRange<Double>]
    var empty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Taste").font(.headline)
                Spacer()
                Capsule().fill(Theme.gold.opacity(0.45)).frame(width: 22, height: 8)
                Text("Doug's range").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(TasteProfile.Dimension.allCases) { dimension in
                ProfileRow(name: dimension.name, value: profile[dimension], target: target[dimension], empty: empty)
            }
        }
        .card()
    }
}

struct ProfileRow: View {
    let name: String
    let value: Double
    let target: ClosedRange<Double>?
    let empty: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(name)
                .font(.caption.weight(.semibold))
                .frame(width: 58, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.07)).frame(height: 8)
                    if let target {
                        let start = w * CGFloat(target.lowerBound / 10)
                        let span = w * CGFloat((target.upperBound - target.lowerBound) / 10)
                        Capsule()
                            .fill(Theme.gold.opacity(0.45))
                            .frame(width: max(6, span), height: 8)
                            .offset(x: start)
                    }
                    if !empty {
                        Circle()
                            .fill(color)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .offset(x: w * CGFloat(min(10, max(0, value)) / 10) - 7)
                    }
                }
                .frame(height: 16)
            }
            .frame(height: 16)
            Text(empty ? "–" : Format.one(value))
                .font(.caption.monospacedDigit())
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(Format.one(value))")
    }

    private var color: Color {
        guard let target else { return Theme.ink }
        return target.contains(value) ? Theme.leaf : Theme.wine
    }
}

/// Grape shares as a stacked bar.
struct CompositionBar: View {
    let composition: [VarietalShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blend").font(.headline)
            GeometryReader { geo in
                let gaps = CGFloat(composition.count - 1) * 2
                HStack(spacing: 2) {
                    ForEach(composition) { part in
                        Rectangle()
                            .fill(Color(part.varietal.berryColor))
                            .frame(width: max(2, (geo.size.width - gaps) * CGFloat(part.share)))
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(composition) { part in
                    HStack(spacing: 6) {
                        Circle().fill(Color(part.varietal.berryColor)).frame(width: 10, height: 10)
                        Text("\(part.varietal.name) \(Format.percent(part.share))").font(.caption)
                    }
                }
            }
        }
        .card()
    }
}

struct LotSlider: View {
    let lot: Lot
    /// This year's vintage: older lots say which harvest they're from.
    let vintage: Int
    @Binding var cases: Double
    let share: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(Color(lot.color)).frame(width: 14, height: 14)
                Text(lot.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(cases)) of \(lot.cases) cases")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text((lot.vintage < vintage ? "\(String(lot.vintage)) · " : "")
                 + "\(lot.style.name) · \(lot.vessel.name) · quality \(Int(lot.quality.rounded())) · \(Format.one(lot.alcohol))%"
                 + (share > 0 ? " · \(Format.percent(share)) of the blend" : ""))
                .font(.caption)
                .foregroundStyle(lot.vintage < vintage ? Theme.wine : Color.secondary)
            Slider(value: $cases, in: 0...Double(lot.cases), step: lot.cases >= 50 ? 5 : 1)
                .tint(Theme.wine)
        }
        .card()
    }
}
