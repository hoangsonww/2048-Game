import SwiftUI

struct ContentView: View {
    @ObservedObject var gameManager = GameManager(gridSize: 4)

    var body: some View {
        VStack {
            ScoreView(score: gameManager.score, highScore: gameManager.highScore)
            GridView(grid: gameManager.grid, gridSize: gameManager.gridSize)
                .gesture(DragGesture()
                    .onEnded { gesture in
                        handleSwipe(direction: gesture.direction)
                    }
                )
        }
        .padding()
        .alert(isPresented: $gameManager.showGameOver) {
            Alert(
                title: Text("Game Over"),
                message: Text("You scored \(gameManager.score) points!"),
                dismissButton: .default(Text("Restart")) {
                    gameManager.restartGame()
                }
            )
        }
    }

    private func handleSwipe(direction: SwipeDirection) {
        gameManager.swipe(direction: direction)
    }
}
