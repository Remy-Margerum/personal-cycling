import CrushKit
import Foundation
import Observation

/// Holds the game and saves it after every move, as JSON in Application
/// Support. A picking round in progress isn't saved: quitting mid-round
/// just means the crew never went out.
@Observable
final class GameStore {
    private(set) var game: Game?
    var showTitle = true

    @ObservationIgnored private let url: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("MargerumCrush", isDirectory: true)
            .appendingPathComponent("game.json")
    }()

    init() {
        // The screenshot tour (UITests) launches with -resetGame to start
        // from the title screen, and -seed N for the same weather every time.
        if ProcessInfo.processInfo.arguments.contains("-resetGame") {
            try? FileManager.default.removeItem(at: url)
        }
        if let data = try? Data(contentsOf: url) {
            game = try? JSONDecoder().decode(Game.self, from: data)
        }
    }

    func newGame() {
        let year = Calendar.current.component(.year, from: Date())
        let seed = UserDefaults.standard.integer(forKey: "seed")
        game = Game(vintage: year, seed: seed > 0 ? UInt64(seed) : UInt64.random(in: 1...UInt64.max))
        save()
        showTitle = false
    }

    /// Makes a move and saves the result.
    @discardableResult
    func play<T>(_ move: (inout Game) -> T) -> T? {
        guard var game else { return nil }
        let result = move(&game)
        self.game = game
        save()
        return result
    }

    func startPicking(_ blockID: String, for style: WineStyle) -> PickingRound? {
        play { $0.startPicking(blockID, for: style) } ?? nil
    }

    private func save() {
        guard let game else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(game).write(to: url, options: .atomic)
        } catch {
            print("Couldn't save the game: \(error)")
        }
    }
}
