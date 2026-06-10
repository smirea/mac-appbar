import Foundation

struct StoredBartenderState {
    let needsAttention: Bool
    let currentSignature: String?
    let seenSignature: String?
}

struct BartenderStateStore {
    private var stateURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/mac-appbar/bartender-state.json")
    }

    func read() -> StoredBartenderState {
        guard let data = try? Data(contentsOf: stateURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return StoredBartenderState(needsAttention: false, currentSignature: nil, seenSignature: nil)
        }
        return StoredBartenderState(
            needsAttention: payload["needs_attention"] as? Bool ?? false,
            currentSignature: payload["current_signature"] as? String,
            seenSignature: payload["seen_signature"] as? String
        )
    }

    func write(needsAttention: Bool, currentSignature: String, seenSignature: String?, rows: [AppRowState]) {
        let payload: [String: Any] = [
            "needs_attention": needsAttention,
            "current_signature": currentSignature,
            "seen_signature": seenSignature ?? NSNull(),
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
