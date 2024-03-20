import SwiftUI

@main
struct Game_2048App: App {
    var body: some Scene {
        WindowGroup {
            LaunchScreen()
        }
    }
}

struct LaunchScreen: View {
    @State private var isActive = false

    var body: some View {
        if isActive {
            GameView()
        } else {
            VStack {
                Text("2048")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.black)
                    .padding()

                Text("Join the numbers and get to the 2048 tile!")
                    .font(.headline)
                    .foregroundColor(.black)
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}
