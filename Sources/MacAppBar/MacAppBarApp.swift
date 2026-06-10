import AppKit
import SwiftUI

@main
struct MacAppBarApp: App {
    @StateObject private var dashboard = DeploymentDashboard()

    var body: some Scene {
        MenuBarExtra {
            DeploymentDashboardView(model: dashboard)
                .frame(width: 460)
        } label: {
            Label("MacAppBar", systemImage: dashboard.menuBarSystemImage)
        }
        .menuBarExtraStyle(.window)
    }
}
