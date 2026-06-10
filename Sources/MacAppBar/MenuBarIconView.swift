import AppKit
import SwiftUI

struct MenuBarIconView: View {
    let needsAttention: Bool

    var body: some View {
        Image(nsImage: needsAttention ? Self.unreadIcon : Self.icon)
            .renderingMode(.template)
            .resizable()
            .frame(width: 18, height: 18)
            .foregroundStyle(.primary)
            .opacity(needsAttention ? 1 : 0.78)
            .accessibilityLabel("MacAppBar")
    }

    private static let icon: NSImage = {
        image(named: "AppStoreMenuIcon") ?? fallback
    }()

    private static let unreadIcon: NSImage = {
        image(named: "AppStoreMenuIconUnread") ?? fallback
    }()

    private static let fallback = NSImage(systemSymbolName: "app", accessibilityDescription: "MacAppBar") ?? NSImage()

    private static func image(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
