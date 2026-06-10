import Foundation

struct BartenderStateStore {
    private var stateURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/mac-appbar/bartender-state.json")
    }

    func readNeedsAttention() -> Bool {
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return payload["needs_attention"] as? Bool ?? false
    }

    func write(needsAttention: Bool, rows: [AppRowState]) {
        let payload: [String: Any] = [
            "needs_attention": needsAttention,
            "updated_at": ISO8601DateFormatter().string(from: Date()),
            "apps": rows.map(appPayload),
        ]

        do {
            try FileManager.default.createDirectory(
                at: stateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            return
        }
    }

    private func appPayload(_ row: AppRowState) -> [String: Any] {
        [
            "id": row.app.id,
            "name": row.app.name,
            "build": row.snapshot?.buildNumber ?? NSNull(),
            "status": row.snapshot?.status ?? "Unknown",
            "app_store_state": row.snapshot?.appStoreBuildState ?? NSNull(),
            "error": row.error ?? NSNull(),
        ]
    }
}
