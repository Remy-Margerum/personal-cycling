import SwiftUI

@main
struct CrushApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.wine)
                // The game is drawn in daylight colours; dark mode would
                // fight the paper and the vineyard.
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if store.game == nil || store.showTitle {
            TitleView()
        } else {
            WineryView()
        }
    }
}
