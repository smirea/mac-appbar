import AppKit
import SwiftUI

struct MenuBarIconView: View {
    let needsAttention: Bool

    var body: some View {
        Image(nsImage: Self.icon)
            .resizable()
            .frame(width: 18, height: 18)
            .saturation(needsAttention ? 1 : 0.35)
            .opacity(needsAttention ? 1 : 0.85)
            .accessibilityLabel("MacAppBar")
    }

    private static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "AppStoreMenuIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        return NSImage(systemSymbolName: "safari", accessibilityDescription: "MacAppBar") ?? NSImage()
    }()
}
