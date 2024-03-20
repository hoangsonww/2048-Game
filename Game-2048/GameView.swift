import SwiftUI

struct GameView: View {
    @ObservedObject var viewModel = GameViewModel()
    
    @State private var showingGameOver = false
    @State private var showingWinAlert = false
    
    var body: some View {
        VStack {
            Text("2048")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

            Text("Join the numbers and get to the 2048 tile!")
                .font(.subheadline)
                .padding(.bottom)

            Spacer(minLength: 20)
            
            VStack {
                VStack {
                    Text("Score: \(viewModel.score)")
                        .font(.title)
                        .bold()
                    Text("High Score: \(viewModel.highScore)")
                        .font(.title2)
                }
                .padding()

                VStack(spacing: 5) {
                    ForEach(0..<viewModel.gridSize, id: \.self) { row in
                        HStack(spacing: 5) {
                            ForEach(0..<viewModel.gridSize, id: \.self) { column in
                                CellView(number: viewModel.grid[row][column])
                                    .animation(.easeInOut, value: viewModel.grid[row][column])
                            }
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .shadow(radius: 5)
            }
            .padding()

            Spacer()
            Spacer()
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    let horizontalAmount = gesture.translation.width as CGFloat
                    let verticalAmount = gesture.translation.height as CGFloat
                    if abs(horizontalAmount) > abs(verticalAmount) {
                        viewModel.swipe(direction: horizontalAmount > 0 ? .right : .left)
                    } 
                    else {
                        viewModel.swipe(direction: verticalAmount > 0 ? .down : .up)
                    }
                    if viewModel.isGameOver() {
                        showingGameOver = true
                    }
                    if viewModel.grid.contains(where: { $0.contains(2048) }) {
                        showingWinAlert = true
                    }
                }
        )
        .alert(isPresented: $showingGameOver) {
            Alert(
                title: Text("Game Over"),
                message: Text("Your score: \(viewModel.score)"),
                dismissButton: .default(Text("Restart")) {
                    restartGame()
                }
            )
        }
        .alert("Congratulations!", isPresented: $showingWinAlert) {
               Button("Continue", role: .cancel) { showingWinAlert = false }
           } message: {
               Text("You've reached 2048!")
           }
        .background(Color(.systemBackground))
    }
    
    private func restartGame() {
            viewModel.grid = Array(repeating: Array(repeating: 0, count: viewModel.gridSize), count: viewModel.gridSize)
            viewModel.score = 0
            viewModel.addNewNumber()
            viewModel.addNewNumber()
            showingGameOver = false
        }

}

struct CellView: View {
    let number: Int

    var body: some View {
        Text(number == 0 ? "" : "\(number)")
            .frame(width: 70, height: 70)
            .background(colorForValue(number))
            .foregroundColor(.white)
            .font(.title.bold())
            .cornerRadius(10)
            .scaleEffect(number > 0 ? 1.0 : 0.8)
            .opacity(number > 0 ? 1 : 0.5)
    }

    private func colorForValue(_ value: Int) -> Color {
        switch value {
        case 2:
            return Color.yellow
        case 4:
            return Color.orange
        case 8:
            return Color.pink
        case 16:
            return Color.purple
        case 32:
            return Color.red
        case 64:
            return Color.red.opacity(0.8)
        case 128:
            return Color.blue
        case 256:
            return Color.blue.opacity(0.8)
        case 512:
            return Color.green
        case 1024:
            return Color.green.opacity(0.8)
        case 2048:
            return Color.gold
        case 4096:
            return Color.indigo
        case 8192:
            return Color.purple.opacity(0.5)
        default:
            return Color.gray.opacity(0.3)
        }
    }

}

extension Color {
    static let gold = Color(red: 1, green: 215/255, blue: 0)
}

struct GameView_Previews: PreviewProvider {
    static var previews: some View {
        GameView()
    }
}
