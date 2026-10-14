import CrushKit
import SwiftUI

/// How the wine is shared out at barrel-down: a slider each for steel, neutral
/// oak and new French oak, linked so they always add up to the whole lot, and
/// Doug's notes on where to aim.
struct SplitPicker: View {
    @Binding var split: VesselSplit
    /// What the winery has: new oak only after it's bought.
    let vessels: [Vessel]
    let tons: Double
    let notes: [BarrelNote]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Vessel.allCases, id: \.self) { vessel in
                    row(vessel)
                }
                if split.newOak > 0 {
                    Text("New oak: \(Format.money(tons * split.newOak * Vessel.newOak.costPerTon)) for this lot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.wine)
                }
                if !vessels.contains(.newOak) {
                    Text("New French oak barrels are in the winter shop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        DougSprite(facing: .down).frame(width: 34, height: 48)
                        Text("Doug's notes").font(.headline)
                    }
                    ForEach(notes) { note in
                        Text(note.text).font(.subheadline)
                    }
                    Text(notes.contains(where: { $0.margin == nil })
                         ? "Only a hunch so far: every vintage of a wine you bottle, he gets surer."
                         : "Each lot goes into the cellar on its own, to blend at the lab bench.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()
            }
        }
    }

    private func row(_ vessel: Vessel) -> some View {
        let available = vessels.contains(vessel)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(vessel.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(Format.percent(split[vessel]))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Slider(value: binding(vessel), in: 0...1, step: 0.05)
                .tint(Theme.wine)
                .disabled(!available)
                .accessibilityLabel(vessel.name)
                .accessibilityValue(Format.percent(split[vessel]))
            ForEach(aims(for: vessel)) { aim in
                Label("\(aim.wine.spec.name): \(Format.percent(aim.range.lowerBound))–\(Format.percent(aim.range.upperBound))",
                      systemImage: aim.range.contains(split[vessel]) ? "checkmark.circle.fill" : "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(aim.range.contains(split[vessel]) ? Theme.leaf : Color.secondary)
            }
        }
        .opacity(available ? 1 : 0.45)
    }

    private struct Aim: Identifiable {
        let wine: WineID
        let range: ClosedRange<Double>
        var id: WineID { wine }
    }

    /// Where Doug would aim this vessel, once he's sure enough to say.
    private func aims(for vessel: Vessel) -> [Aim] {
        notes.compactMap { note in
            guard let margin = note.margin, note.target.main == vessel else { return nil }
            let share = note.target[vessel]
            return Aim(wine: note.wine, range: max(0, share - margin)...min(1, share + margin))
        }
    }

    private func binding(_ vessel: Vessel) -> Binding<Double> {
        Binding(get: { split[vessel] },
                set: { split = split.setting(vessel, to: $0, among: vessels) })
    }
}

/// Doug at the barrels: how to share the wine out before it goes in. The
/// clock waits while you decide.
struct BarrelDownSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var split: VesselSplit
    let harvest: Harvest
    let vessels: [Vessel]
    let notes: [BarrelNote]
    let confirm: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("About \(harvest.cases) cases of \(harvest.blockName). Each kind of vessel becomes its own lot "
                         + "in the cellar: steel keeps it fresh, neutral barrels round it out, new oak adds toast and grip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                    SplitPicker(split: $split, vessels: vessels, tons: harvest.tons, notes: notes)
                }
                .padding(16)
            }
            .background(Theme.paper)
            .navigationTitle("Barrel down")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not yet") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: confirm) {
                    Text("Barrel down").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }
}
