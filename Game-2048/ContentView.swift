import SwiftUI

struct ContentView: View {
    var body: some View { GameView() }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Application root-view maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. Keep this wrapper intentionally small so GameView remains the single composition root.
//
// 02. Do not introduce alternate game state here; ownership belongs to GameView and
//     GameViewModel.
//
// 03. Pass dependencies explicitly when previews or tests need controlled behavior.
//
// 04. Avoid navigation or scrolling wrappers that could steal the board's swipe gesture.
//
// 05. Keep launch behavior identical for guest and authenticated profiles until session restore
//     resolves.
//
// 06. Treat any future environment injection as wiring, never as a second rules layer.
//
// Symbol and scenario index
//
// 01. `struct ContentView: View`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
