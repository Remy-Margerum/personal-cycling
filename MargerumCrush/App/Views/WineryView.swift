import CrushKit
import SwiftUI

/// The winery: the harvest, the cellar or the winter, depending on the time
/// of year.
struct WineryView: View {
    @Environment(GameStore.self) private var store
    @State private var showLibrary = false
    @State private var showHelp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let game = store.game {
                    VStack(spacing: 14) {
                        WineryHeader(game: game)
                        switch game.phase {
                        case .harvest: HarvestSection(game: game)
                        case .cellar: CellarSection(game: game)
                        case .offseason: OffseasonSection(game: game)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(Theme.paper)
            .navigationTitle("Margerum Crush")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: WineID.self) { wine in
                BlendingLabView(wine: wine)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Title screen", systemImage: "house") { store.showTitle = true }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Wine library", systemImage: "books.vertical") { showLibrary = true }
                    Button("How to play", systemImage: "questionmark.circle") { showHelp = true }
                }
            }
            .sheet(isPresented: $showLibrary) { LibraryView() }
            .sheet(isPresented: $showHelp) { HowToPlayView() }
        }
    }
}

struct WineryHeader: View {
    let game: Game

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Vintage \(String(game.vintage))")
                    .font(.title2.weight(.bold))
                    .fontDesign(.serif)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.money(game.money))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(game.money < 0 ? Color.red : Theme.ink)
                Stars(reputation: game.reputation)
            }
        }
        .card()
    }

    private var subtitle: String {
        switch game.phase {
        case .harvest: "Harvest · \(game.date) · week \(game.week + 1) of \(HarvestCalendar.weeks)"
        case .cellar: "In the cellar · \(Aging.name(game.cellarMonth)) \(String(game.cellarMonth >= 2 ? game.vintage + 1 : game.vintage))"
        case .offseason: "Between vintages · the wine is out"
        }
    }
}
