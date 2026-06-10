import AppKit
import SwiftUI

@MainActor
final class DeploymentDashboard: ObservableObject {
    @Published var rows: [AppRowState]
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    @Published var notice: String?

    private let apps = TrackedApp.apps

    init() {
        rows = apps.map { AppRowState(app: $0, snapshot: nil, error: nil, isStartingBuild: false) }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        var nextRows: [AppRowState] = []
        for app in apps {
            do {
                let credentials = try AppStoreConnectCredentials.load(defaultPrivateKeyPath: app.defaultPrivateKeyPath)
                let client = AppStoreConnectClient(credentials: credentials)
                let snapshot = try await client.status(for: app)
                nextRows.append(AppRowState(app: app, snapshot: snapshot, error: nil, isStartingBuild: false))
            } catch {
                nextRows.append(AppRowState(app: app, snapshot: nil, error: error.localizedDescription, isStartingBuild: false))
            }
        }
        rows = nextRows
        lastUpdated = Date()
    }

    func startBuild(for app: TrackedApp) async {
        updateRow(app) { $0.isStartingBuild = true }
        defer { updateRow(app) { $0.isStartingBuild = false } }

        do {
            let credentials = try AppStoreConnectCredentials.load(defaultPrivateKeyPath: app.defaultPrivateKeyPath)
            let client = AppStoreConnectClient(credentials: credentials)
            let build = try await client.startBuild(for: app)
            let suffix = build.number.map { " #\($0)" } ?? ""
            notice = "Started \(app.name)\(suffix)"
            await refresh()
        } catch {
            updateRow(app) { $0.error = error.localizedDescription }
        }
    }

    func openRepository(_ app: TrackedApp) {
        NSWorkspace.shared.open(URL(fileURLWithPath: app.repositoryPath))
    }

    private func updateRow(_ app: TrackedApp, _ mutate: (inout AppRowState) -> Void) {
        guard let index = rows.firstIndex(where: { $0.app.id == app.id }) else {
            return
        }
        mutate(&rows[index])
    }
}

struct AppRowState: Identifiable {
    var id: String { app.id }
    let app: TrackedApp
    var snapshot: AppBuildSnapshot?
    var error: String?
    var isStartingBuild: Bool
}

struct DeploymentDashboardView: View {
    @ObservedObject var model: DeploymentDashboard

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ForEach(model.rows) { row in
                AppStatusRow(
                    row: row,
                    onStart: {
                        Task { await model.startBuild(for: row.app) }
                    },
                    onOpenRepository: {
                        model.openRepository(row.app)
                    }
                )
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Refresh") {
                    Task { await model.refresh() }
                }
                .disabled(model.isRefreshing)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .task {
            if model.lastUpdated == nil {
                await model.refresh()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Deployments")
                    .font(.headline)
                Text(updatedText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var updatedText: String {
        guard let lastUpdated = model.lastUpdated else {
            return "Loading Xcode Cloud status"
        }
        return "Updated \(Self.relativeFormatter.localizedString(for: lastUpdated, relativeTo: Date()))"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct AppStatusRow: View {
    let row: AppRowState
    let onStart: () -> Void
    let onOpenRepository: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                statusDot

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.app.name)
                        .font(.system(size: 14, weight: .semibold))
                    Text(row.app.githubRepository)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    onStart()
                } label: {
                    if row.isStartingBuild {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                }
                .buttonStyle(.bordered)
                .help("Start Xcode Cloud build")
                .disabled(row.isStartingBuild)

                Button {
                    onOpenRepository()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Open local repository")
            }

            if let snapshot = row.snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    metadataGrid(snapshot)

                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(snapshot.rules, id: \.self) { rule in
                            Text(rule)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let error = row.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else {
                Text("Loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        guard let color = row.snapshot?.statusColor else {
            return row.error == nil ? .gray : .red
        }
        switch color {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        case .gray:
            return .gray
        }
    }

    private func metadataGrid(_ snapshot: AppBuildSnapshot) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("Build")
                    .foregroundStyle(.secondary)
                Text(snapshot.buildNumber.map { "#\($0)" } ?? "Unknown")
            }
            GridRow {
                Text("Status")
                    .foregroundStyle(.secondary)
                Text(snapshot.status)
            }
            GridRow {
                Text("Date")
                    .foregroundStyle(.secondary)
                Text(dateText(snapshot.finishedDate ?? snapshot.createdDate))
            }
            GridRow {
                Text("Branch")
                    .foregroundStyle(.secondary)
                Text(snapshot.branch ?? row.app.defaultBranch)
            }
            if let version = snapshot.appStoreBuildVersion {
                GridRow {
                    Text("App Store")
                        .foregroundStyle(.secondary)
                    Text("\(version) \(snapshot.appStoreBuildState ?? "")")
                }
            }
        }
        .font(.caption)
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
