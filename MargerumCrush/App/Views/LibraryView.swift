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
         "Every bunch you tap changes the wine. Sunny bunches on brown stems bring sugar, color and ripe tannin; "
            + "shaded and green-stemmed ones bring acid and a green edge (a little suits Sybarite); hens and chicks "
            + "add tannin and complexity; raisins push the sugar up; second-crop bunches are sour. Leave the gray mold, "
            + "the sour rot, and the leaves and canes, which make it bitter. Gold bunches are perfect. Watch the bins' "
            + "sugar and acid as you go: an early or late pick is rescued by what you leave. Seven bunches in ten "
            + "bring in the whole crop. Swatting a wasp costs three seconds."),
        Topic("Doug's crush", "figure.walk",
         "After each pick, Doug works the winery floor: tap a machine and he walks over and works it (or drag the "
            + "stick and use the big button). Reds: destem (or keep a third whole clusters when the stems are brown, for "
            + "spice and structure), bleed some pink juice off for saignée if you like, add the yeast after a cold "
            + "soak, punch down the cap before it dries out, keep it 24–31 °C with the chiller, "
            + "press, and barrel down. Rosé: crush into the press and press at pale salmon. Sybarite: whole-cluster "
            + "press and stop before the bitter press juice, then chill, settle and add yeast. Every best moment moves "
            + "with how ripe the fruit was: riper grapes color faster, ferment longer and run hotter. Or leave it to "
            + "the cellar crew, who do a decent job."),
        Topic("The cellar", "calendar.badge.clock",
         "From November to July the wine ages: new oak builds, red tannins soften, and fruit blooms and fades. "
            + "Top up the barrels every couple of months or air gets in. Doug blends and bottles at the lab bench "
            + "whenever a wine tastes right: rosé and Sybarite after a couple of months to settle, the reds after five "
            + "or so in barrel. Bottled sooner, a wine tastes raw. The lab shows what a month more would do. After "
            + "July the vintage is released."),
        Topic("Blending", "flask.fill",
         "Each wine has Doug's range, the gold bands on the taste chart: get the dots inside them. Blends of "
            + "several grapes score a little higher. M5 needs all five: Syrah, Grenache, Mourvèdre, Counoise and "
            + "Cinsault. Sybarite and ÜBER Syrah need at least 75% of their grape."),
        Topic("The critic and the money", "star.fill",
         "The critic scores each wine and writes a note. Scores and reputation set the price. Wine you don't bottle "
            + "is sold off in bulk. Costs are paid when the vintage is released."),
        Topic("Between vintages", "leaf.fill",
         "Spend the profits on new vineyard blocks (you'll need three more for M5), more picking crews, a sorting "
            + "table, a weather station, new French oak and a tasting room. It all starts with the 2001 vintage: "
            + "chase five stars and a 100-point M5."),
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
