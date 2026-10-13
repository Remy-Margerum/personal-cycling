import CrushKit
import SwiftUI

struct TitleView: View {
    @Environment(GameStore.self) private var store
    @State private var confirmNewGame = false
    @State private var showHelp = false

    var body: some View {
        ZStack {
            TitleBackdrop().ignoresSafeArea()
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("MARGERUM")
                        .font(.system(size: 42, weight: .bold, design: .serif))
                        .tracking(5)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text("CRUSH")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .tracking(14)
                        .foregroundStyle(Color(red: 1, green: 0.85, blue: 0.55))
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 6)
                .padding(.top, 48)

                Text("Pick the grapes. Blend the wine.\nChase the 100-point M5.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.4), radius: 4)

                GrapeCluster(color: Color(Varietal.syrah.berryColor))
                    .frame(width: 96, height: 126)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.top, 8)

                Spacer()

                VStack(spacing: 12) {
                    if let game = store.game {
                        Button {
                            store.showTitle = false
                        } label: {
                            Text("Continue the \(String(game.vintage)) vintage")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            confirmNewGame = true
                        } label: {
                            Text("New winery").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    } else {
                        Button {
                            store.newGame()
                        } label: {
                            Text("Start the harvest").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("How to play") { showHelp = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                }
                .controlSize(.large)
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .statusBarHidden()
        .confirmationDialog("Start a new winery? Your cellar, upgrades and wine library will be gone.",
                            isPresented: $confirmNewGame, titleVisibility: .visible) {
            Button("Start over", role: .destructive) { store.newGame() }
        }
        .sheet(isPresented: $showHelp) { HowToPlayView() }
    }
}
