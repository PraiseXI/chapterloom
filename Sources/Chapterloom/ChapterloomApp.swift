import SwiftUI

@main
struct ChapterloomApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ChapterloomView()
                .environmentObject(state)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audiobook…") { state.chooseSource() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
