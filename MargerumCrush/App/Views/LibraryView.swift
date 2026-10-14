import CrushKit
import SwiftUI

/// Every wine you've released, best first.
struct LibraryView: View {
    @Environment(GameStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BottledWine?

    var body: some View {
        NavigationStack {
            List {
                let library = store.game?.library ?? []
                if library.isEmpty {
                    ContentUnavailableView("No wines yet", systemImage: "wineglass",
                                           description: Text("Release a vintage and its wines land here."))
                } else {
                    Section("Best of each") {
                        ForEach(WineID.allCases) { wine in
                            if let best = library.filter({ $0.wine == wine }).max(by: { $0.score < $1.score }) {
                                row(best)
                            }
                        }
                    }
                    ForEach(Array(Set(library.map(\.vintage))).sorted(by: >), id: \.self) { vintage in
                        Section(String(vintage)) {
                            ForEach(library.filter { $0.vintage == vintage }) { wine in
                                row(wine)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Wine library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { wine in ReviewView(wine: wine) }
        }
    }

    private func row(_ wine: BottledWine) -> some View {
        Button {
            selected = wine
        } label: {
            HStack(spacing: 12) {
                ScoreBadge(score: wine.score, size: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(String(wine.vintage)) \(wine.spec.name)").font(.headline).foregroundStyle(Theme.ink)
                    Text("\(wine.cases) cases · \(wine.verdict)").font(.caption).foregroundStyle(Color.secondary)
                }
            }
        }
    }
}

struct HowToPlayView: View {
    private struct Topic: Identifiable {
        let title: String
        let symbol: String
        let text: String

        var id: String { title }

        init(_ title: String, _ symbol: String, _ text: String) {
            self.title = title
            self.symbol = symbol
            self.text = text
        }
    }

    @Environment(\.dismiss) private var dismiss

    private let topics: [Topic] = [
        Topic("The harvest", "calendar",
         "The harvest runs in five-day weeks from late August to mid-October. Watch each block's sugar (Brix), "
            + "acid and mold, check the forecast, and send a crew in when the fruit is in its window: green on the "
            + "gauge for red or white wine, pink for rosé. Each crew picks one block a week. After the last week the "
            + "rains come, and anything still hanging is lost."),
        Topic("Picking", "scissors",
         "Tap ripe bunches before they wither. Leave the green ones and the gray, moldy ones: whatever lands in the "
            + "bins ends up in the wine. Gold bunches are perfect fruit. Swatting a wasp costs three seconds. Pick "
            + "about three bunches in four to bring in the whole crop."),
        Topic("The crush pad", "drop.fill",
         "Stainless steel keeps wine fresh and fruity, neutral oak rounds it out, and new French oak adds toast and "
            + "grip. Saignée bleeds a fifth of a red's juice off as rosé, and the red left behind gets darker and "
            + "richer."),
        Topic("Blending", "flask.fill",
         "Each wine has a style, shown as gold bands on the taste chart: get the dots inside them. Blends of "
            + "several grapes score a little higher. M5 needs all five: Syrah, Grenache, Mourvèdre, Counoise and "
            + "Cinsault. Sybarite and ÜBER Syrah need at least 75% of their grape."),
        Topic("The critic and the money", "star.fill",
         "The critic scores each wine and writes a note. Scores and reputation set the price. Wine you don't bottle "
            + "is sold off in bulk. Costs are paid when the vintage is released."),
        Topic("Winter", "snowflake",
         "Spend the profits on new vineyard blocks (you'll need three more for M5), more picking crews, a sorting "
            + "table, a weather station, new French oak and a tasting room. Then chase five stars and a 100-point "
            + "M5."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(topics) { topic in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(topic.title, systemImage: topic.symbol)
                                .font(.headline)
                                .foregroundStyle(Theme.wine)
                            Text(topic.text).font(.subheadline)
                        }
                        .card()
                    }
                }
                .padding(16)
            }
            .background(Theme.paper)
            .navigationTitle("How to play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
