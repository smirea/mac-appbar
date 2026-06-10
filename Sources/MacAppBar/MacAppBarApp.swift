import AppKit
import SwiftUI

@main
struct MacAppBarApp: App {
    var body: some Scene {
        MenuBarExtra("MacAppBar", systemImage: "a.circle") {
            Text("Todo: add your first menu bar action")
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
