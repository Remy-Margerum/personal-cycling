import CrushKit
import SwiftUI

/// The cellar crew makes the wine: pick red or saignée and the vessel, and
/// they do the rest. Decent, never inspired: Doug does better on the floor.
struct CrushPadView: View {
    @Environment(GameStore.self) private var store
    let harvest: Harvest
    let done: () -> Void
    @State private var vessel: Vessel
    @State private var method = CrushMethod.red

    init(harvest: Harvest, done: @escaping () -> Void) {
        self.harvest = harvest
        self.done = done
        _vessel = State(initialValue: harvest.style == .white ? .stainless : .neutralOak)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    if harvest.style == .rose {
                        Label("Rosé is pressed off the skins after a few hours and goes straight into stainless steel.",
                              systemImage: "drop.fill")
                            .font(.subheadline)
                            .card()
                    } else {
                        if harvest.style == .red {
                            SectionTitle("Method")
                            ForEach(CrushMethod.allCases, id: \.self) { option in
                                ChoiceCard(title: option.name, detail: option.blurb, selected: method == option) {
                                    method = option
                                }
                            }
                        }
                        SectionTitle(harvest.style == .red ? "Barrels" : "Vessel")
                        ForEach(vessels, id: \.self) { option in
                            ChoiceCard(title: option.name, detail: option.blurb, note: cost(of: option),
                                       selected: vessel == option) {
                                vessel = option
                            }
                        }
                        if !(store.game?.owns(.frenchOak) ?? false) {
                            Text("New French oak barrels are in the winter shop.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.paper)
            .navigationTitle("The cellar crew")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.play { $0.crush(in: vessel, method: method) }
                    done()
                } label: {
                    Text("The crew makes it").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled()
    }

    private var vessels: [Vessel] {
        store.game?.vessels ?? [.stainless, .neutralOak]
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(harvest.blockName).font(.title2.weight(.bold)).fontDesign(.serif)
            Text("\(Format.tons(harvest.tons)) at \(Format.one(harvest.brix))° Brix, \(Format.one(harvest.acid)) g/L acid. "
                 + "About \(harvest.cases) cases, \(Format.one(harvest.alcohol))% alcohol.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                Text("Fruit quality")
                Spacer()
                Text("\(Int(harvest.quality.rounded())) / 100").font(.headline.monospacedDigit())
            }
            ProgressView(value: harvest.quality, total: 100).tint(Theme.wine)
        }
        .card()
    }

    private func cost(of vessel: Vessel) -> String? {
        guard vessel.costPerTon > 0 else { return nil }
        return "\(Format.money(vessel.costPerTon * harvest.tons)) for this lot"
    }
}

/// A tappable card with a radio button.
struct ChoiceCard: View {
    let title: String
    let detail: String
    var note: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.wine : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    if let note {
                        Text(note).font(.caption.weight(.semibold)).foregroundStyle(Theme.wine)
                    }
                }
                Spacer(minLength: 0)
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(selected ? Theme.wine : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
