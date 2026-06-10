import AppKit
import SwiftUI

@main
struct MacAppBarApp: App {
    @StateObject private var dashboard = DeploymentDashboard()

    var body: some Scene {
        MenuBarExtra("MacAppBar", systemImage: "a.circle") {
            DeploymentDashboardView(model: dashboard)
                .frame(width: 460)
        }
        .menuBarExtraStyle(.window)
    }
}
