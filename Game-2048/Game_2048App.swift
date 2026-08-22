import SwiftUI

@main
struct Game_2048App: App {
    private let viewModel: GameViewModel

    init() {
        let scenario = ProcessInfo.processInfo.environment["GAME2048_UI_TEST_STATE"]
        if let scenario {
            let model = GameViewModel(loadSavedGame: false, randomIndex: { _ in 0 }, randomUnit: { 0 })
            switch scenario {
            case "merge":
                model.setGameForTesting(grid: [[2, 2, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 32)
            case "won":
                model.setGameForTesting(grid: [[2048, 4, 2, 0], [0, 0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0]], score: 4096, hasWon: true)
            case "game-over":
                model.setGameForTesting(grid: [[2, 4, 2, 4], [4, 2, 4, 2], [2, 4, 2, 4], [4, 2, 4, 2]], score: 512)
            default:
                break
            }
            viewModel = model
        } else {
            viewModel = GameViewModel()
        }
    }

    var body: some Scene { WindowGroup { GameView(viewModel: viewModel).preferredColorScheme(.light) } }
}
