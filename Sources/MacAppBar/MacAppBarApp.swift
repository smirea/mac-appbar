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
            MenuBarIconView(needsAttention: dashboard.needsAttention)
        }
        .menuBarExtraStyle(.window)
    }
}
