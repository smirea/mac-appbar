import Foundation

enum BartenderController {
    private static let itemID = "dev.stefan.MacAppBar-Item-0"

    static func showMenuBarItem() {
        Task.detached {
            let script = """
            try
                tell application id "com.surteesstudios.Bartender"
                    show "\(itemID)"
                end tell
            end try
            """

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = Pipe()
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return
            }
        }
    }
}
