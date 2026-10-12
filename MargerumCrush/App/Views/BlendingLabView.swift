import CrushKit
import SwiftUI

/// Blend lots into one of the wines, watching the taste against the style
/// the critic expects, then bottle it.
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
            // One lot to choose from: start with all of it.
            if cases.isEmpty, let lots = store.game?.lots(for: wine), lots.count == 1 {
                cases[lots[0].id] = lots[0].cases
            }
        }
    }

    private func lab(_ game: Game) -> some View {
        let spec = wine.spec
        let lots = game.lots(for: wine)
        let analysis = game.analyze(Blend(wine: wine, cases: cases))
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(spec.blurb)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                BlendPreview(wine: wine, vintage: game.vintage, analysis: analysis)
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
                        for lot in lots { cases[lot.id] = lot.cases }
                    }
                    .font(.caption.weight(.semibold))
                    Button("Clear") { cases = [:] }
                        .font(.caption.weight(.semibold))
                        .padding(.leading, 8)
                }
                ForEach(lots) { lot in
                    LotSlider(lot: lot, cases: binding(for: lot), share: share(of: lot, in: analysis))
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                review = store.play { $0.bottle(Blend(wine: wine, cases: cases)) } ?? nil
            } label: {
                Text(analysis.canBottle ? "Bottle \(analysis.cases) cases" : "Bottle it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!analysis.canBottle || game.hasBottled(wine))
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

/// The bottle, its colour and the winemaker's estimate.
struct BlendPreview: View {
    let wine: WineID
    let vintage: Int
    let analysis: BlendAnalysis

    var body: some View {
        HStack(spacing: 18) {
            BottleView(wine: wine, vintage: vintage, color: analysis.cases > 0 ? analysis.color : RGB(0.86, 0.86, 0.86))
                .frame(height: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your estimate").font(.caption).foregroundStyle(.secondary)
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

/// The blend's taste against the style the critic expects (the gold bands).
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
                Text("the critic's style").font(.caption).foregroundStyle(.secondary)
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
            Text("\(lot.vessel.name) · quality \(Int(lot.quality.rounded())) · \(Format.one(lot.alcohol))%"
                 + (share > 0 ? " · \(Format.percent(share)) of the blend" : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: $cases, in: 0...Double(lot.cases), step: lot.cases >= 50 ? 5 : 1)
                .tint(Theme.wine)
        }
        .card()
    }
}
