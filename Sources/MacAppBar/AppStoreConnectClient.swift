import CryptoKit
import Foundation

struct AppStoreConnectCredentials: Sendable {
    let keyID: String
    let issuerID: String
    let privateKeyPEM: String

    static func load(defaultPrivateKeyPath: String?) throws -> AppStoreConnectCredentials {
        let fileValues = EnvFile.values()
        let env = ProcessInfo.processInfo.environment

        func value(_ keys: [String]) -> String? {
            for key in keys {
                if let found = env[key], !found.isEmpty {
                    return found
                }
                if let found = fileValues[key], !found.isEmpty {
                    return found
                }
            }
            return nil
        }

        let keyID = value(["ASC_KEY_ID", "APP_STORE_CONNECT_KEY_ID"])
        let issuerID = value(["ASC_ISSUER_ID", "APP_STORE_CONNECT_ISSUER_ID"])
        let privateKeyValue = value(["APP_STORE_CONNECT_PRIVATE_KEY"]).map {
            $0.replacingOccurrences(of: "\\n", with: "\n")
        }
        let privateKey = privateKeyValue?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----BEGIN") == true
            ? privateKeyValue
            : nil
        let keyPath = value([
            "ASC_KEY_PATH",
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH",
            "APP_STORE_CONNECT_API_KEY_PATH",
        ]) ?? privateKeyValue ?? defaultPrivateKeyPath

        var missing: [String] = []
        if keyID == nil {
            missing.append("APP_STORE_CONNECT_KEY_ID")
        }
        if issuerID == nil {
            missing.append("APP_STORE_CONNECT_ISSUER_ID")
        }
        if privateKey == nil, keyPath == nil {
            missing.append("APP_STORE_CONNECT_PRIVATE_KEY")
        }
        if !missing.isEmpty {
            throw AppStoreConnectError.missingCredentials(missing)
        }

        let privateKeyPEM: String
        if let privateKey {
            privateKeyPEM = privateKey
        } else if let keyPath {
            privateKeyPEM = try String(contentsOfFile: (keyPath as NSString).expandingTildeInPath, encoding: .utf8)
        } else {
            throw AppStoreConnectError.missingCredentials(["APP_STORE_CONNECT_PRIVATE_KEY"])
        }

        return AppStoreConnectCredentials(
            keyID: keyID!,
            issuerID: issuerID!,
            privateKeyPEM: privateKeyPEM
        )
    }
}

enum AppStoreConnectError: LocalizedError {
    case missingCredentials([String])
    case invalidURL(String)
    case invalidResponse
    case api(Int, String)
    case missingRepository(String)
    case missingBranch(String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let names):
            "Missing App Store Connect config: \(names.joined(separator: ", "))"
        case .invalidURL(let value):
            "Invalid App Store Connect URL: \(value)"
        case .invalidResponse:
            "App Store Connect returned an unreadable response."
        case .api(let status, let body):
            "App Store Connect returned HTTP \(status): \(body)"
        case .missingRepository(let workflowID):
            "Could not resolve the repository for workflow \(workflowID)."
        case .missingBranch(let branch):
            "Could not resolve branch \(branch) in Xcode Cloud."
        }
    }
}

struct AppBuildSnapshot: Sendable {
    let workflowName: String
    let workflowEnabled: Bool
    let buildNumber: Int?
    let status: String
    let statusColor: StatusColor
    let branch: String?
    let startReason: String?
    let createdDate: Date?
    let startedDate: Date?
    let finishedDate: Date?
    let appStoreBuildVersion: String?
    let appStoreBuildState: String?
    let appStoreConnectURL: String?
    let xcodeCloudBuildURL: String?
    let rules: [String]
}

enum StatusColor: Sendable {
    case green
    case yellow
    case red
    case gray
}

struct StartedBuild: Sendable {
    let id: String
    let number: Int?
}

struct AppStoreConnectClient: Sendable {
    private let credentials: AppStoreConnectCredentials
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    init(credentials: AppStoreConnectCredentials) {
        self.credentials = credentials
    }

    func status(for app: TrackedApp) async throws -> AppBuildSnapshot {
        let workflowPayload = try await request(path: "/v1/ciWorkflows/\(app.xcodeCloudWorkflowID)?include=repository,product")
        let workflow = try resource(from: workflowPayload)
        let workflowAttributes = workflow["attributes"] as? [String: Any] ?? [:]
        let workflowName = workflowAttributes["name"] as? String ?? "Xcode Cloud"
        let isEnabled = workflowAttributes["isEnabled"] as? Bool ?? true
        let rules = workflowRules(from: workflowAttributes)
        let appStoreConnectAppID = await appStoreConnectAppID(from: workflowPayload)
        let appStoreConnectURL = appStoreConnectAppID.map { "https://appstoreconnect.apple.com/apps/\($0)/appstore" }

        let runsPayload = try await request(path: "/v1/ciWorkflows/\(app.xcodeCloudWorkflowID)/buildRuns?limit=1&sort=-number&include=builds,sourceBranchOrTag")
        let runs = runsPayload["data"] as? [[String: Any]] ?? []
        guard let run = runs.first else {
            return AppBuildSnapshot(
                workflowName: workflowName,
                workflowEnabled: isEnabled,
                buildNumber: nil,
                status: "None",
                statusColor: .gray,
                branch: app.defaultBranch,
                startReason: nil,
                createdDate: nil,
                startedDate: nil,
                finishedDate: nil,
                appStoreBuildVersion: nil,
                appStoreBuildState: nil,
                appStoreConnectURL: appStoreConnectURL,
                xcodeCloudBuildURL: nil,
                rules: rules
            )
        }

        return snapshot(
            workflowName: workflowName,
            workflowEnabled: isEnabled,
            run: run,
            included: runsPayload["included"] as? [[String: Any]] ?? [],
            fallbackBranch: app.defaultBranch,
            appStoreConnectURL: appStoreConnectURL,
            appStoreConnectAppID: appStoreConnectAppID,
            rules: rules
        )
    }

    func startBuild(for app: TrackedApp) async throws -> StartedBuild {
        let repositoryID = try await repositoryID(for: app)
        let gitReferenceID = try await gitReferenceID(repositoryID: repositoryID, branch: app.defaultBranch)
        let body: [String: Any] = [
            "data": [
                "type": "ciBuildRuns",
                "attributes": [:],
                "relationships": [
                    "workflow": [
                        "data": [
                            "type": "ciWorkflows",
                            "id": app.xcodeCloudWorkflowID,
                        ],
                    ],
                    "sourceBranchOrTag": [
                        "data": [
                            "type": "scmGitReferences",
                            "id": gitReferenceID,
                        ],
                    ],
                ],
            ],
        ]

        let payload = try await request(path: "/v1/ciBuildRuns", method: "POST", body: body)
        let data = try resource(from: payload)
        let attributes = data["attributes"] as? [String: Any] ?? [:]
        return StartedBuild(id: data["id"] as? String ?? "", number: attributes["number"] as? Int)
    }

    private func repositoryID(for app: TrackedApp) async throws -> String {
        let payload = try await request(path: "/v1/ciWorkflows/\(app.xcodeCloudWorkflowID)?include=repository")
        let data = try resource(from: payload)
        if let id = relationshipID(named: "repository", in: data) {
            return id
        }
        throw AppStoreConnectError.missingRepository(app.xcodeCloudWorkflowID)
    }

    private func gitReferenceID(repositoryID: String, branch: String) async throws -> String {
        var nextPath: String? = "/v1/scmRepositories/\(repositoryID)/gitReferences?limit=200"
        while let path = nextPath {
            let payload = try await request(pathOrURL: path)
            let refs = payload["data"] as? [[String: Any]] ?? []
            for ref in refs {
                let attributes = ref["attributes"] as? [String: Any] ?? [:]
                guard attributes["kind"] as? String == "BRANCH" else {
                    continue
                }
                if attributes["name"] as? String == branch || attributes["canonicalName"] as? String == "refs/heads/\(branch)" {
                    return ref["id"] as? String ?? ""
                }
            }
            let links = payload["links"] as? [String: Any]
            nextPath = links?["next"] as? String
        }
        throw AppStoreConnectError.missingBranch(branch)
    }

    private func request(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        try await request(pathOrURL: path, method: method, body: body)
    }

    private func request(pathOrURL: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        let url: URL
        if pathOrURL.hasPrefix("http") {
            guard let parsed = URL(string: pathOrURL) else {
                throw AppStoreConnectError.invalidURL(pathOrURL)
            }
            url = parsed
        } else {
            guard let parsed = URL(string: pathOrURL, relativeTo: baseURL) else {
                throw AppStoreConnectError.invalidURL(pathOrURL)
            }
            url = parsed
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppStoreConnectError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "No response body"
            throw AppStoreConnectError.api(http.statusCode, text)
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppStoreConnectError.invalidResponse
        }
        return payload
    }

    private func token() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header: [String: Any] = [
            "alg": "ES256",
            "kid": credentials.keyID,
            "typ": "JWT",
        ]
        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
        ]
        let signingInput = "\(try base64URLJSON(header)).\(try base64URLJSON(payload))"
        let key = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let signature = try key.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64URL(signature.rawRepresentation))"
    }

    private func resource(from payload: [String: Any]) throws -> [String: Any] {
        guard let data = payload["data"] as? [String: Any] else {
            throw AppStoreConnectError.invalidResponse
        }
        return data
    }

    private func relationshipID(named name: String, in resource: [String: Any]) -> String? {
        let relationships = resource["relationships"] as? [String: Any]
        let relationship = relationships?[name] as? [String: Any]
        let data = relationship?["data"] as? [String: Any]
        return data?["id"] as? String
    }

    private func snapshot(
        workflowName: String,
        workflowEnabled: Bool,
        run: [String: Any],
        included: [[String: Any]],
        fallbackBranch: String,
        appStoreConnectURL: String?,
        appStoreConnectAppID: String?,
        rules: [String]
    ) -> AppBuildSnapshot {
        let attributes = run["attributes"] as? [String: Any] ?? [:]
        let progress = attributes["executionProgress"] as? String
        let completion = attributes["completionStatus"] as? String
        let status = statusText(progress: progress, completion: completion)
        let sourceID = relationshipID(named: "sourceBranchOrTag", in: run)
        let buildID = firstRelationshipID(named: "builds", in: run)
        let runID = run["id"] as? String
        let source = included.first { $0["type"] as? String == "scmGitReferences" && $0["id"] as? String == sourceID }
        let build = included.first { $0["type"] as? String == "builds" && $0["id"] as? String == buildID }
        let buildAttributes = build?["attributes"] as? [String: Any] ?? [:]

        return AppBuildSnapshot(
            workflowName: workflowName,
            workflowEnabled: workflowEnabled,
            buildNumber: attributes["number"] as? Int,
            status: status,
            statusColor: statusColor(progress: progress, completion: completion),
            branch: (source?["attributes"] as? [String: Any])?["name"] as? String ?? fallbackBranch,
            startReason: attributes["startReason"] as? String,
            createdDate: date(attributes["createdDate"] as? String),
            startedDate: date(attributes["startedDate"] as? String),
            finishedDate: date(attributes["finishedDate"] as? String),
            appStoreBuildVersion: buildAttributes["version"] as? String,
            appStoreBuildState: buildAttributes["processingState"] as? String,
            appStoreConnectURL: appStoreConnectURL,
            xcodeCloudBuildURL: xcodeCloudBuildURL(appID: appStoreConnectAppID, runID: runID),
            rules: rules
        )
    }

    private func appStoreConnectAppID(from workflowPayload: [String: Any]) async -> String? {
        guard let included = workflowPayload["included"] as? [[String: Any]],
              let product = included.first(where: { $0["type"] as? String == "ciProducts" }),
              let relationships = product["relationships"] as? [String: Any],
              let app = relationships["app"] as? [String: Any],
              let links = app["links"] as? [String: Any],
              let related = links["related"] as? String,
              let appPayload = try? await request(pathOrURL: related),
              let data = appPayload["data"] as? [String: Any],
              let appID = data["id"] as? String else {
            return nil
        }
        return appID
    }

    private func xcodeCloudBuildURL(appID: String?, runID: String?) -> String? {
        guard let appID, let runID else {
            return nil
        }
        return "https://appstoreconnect.apple.com/apps/\(appID)/ci/builds/\(runID)"
    }

    private func firstRelationshipID(named name: String, in resource: [String: Any]) -> String? {
        let relationships = resource["relationships"] as? [String: Any]
        let relationship = relationships?[name] as? [String: Any]
        let data = relationship?["data"] as? [[String: Any]]
        return data?.first?["id"] as? String
    }

    private func workflowRules(from attributes: [String: Any]) -> [String] {
        var rules: [String] = []
        if let condition = attributes["scheduledStartCondition"] as? [String: Any] {
            rules.append(scheduleRule(condition))
        }
        if let condition = attributes["branchStartCondition"] as? [String: Any] {
            rules.append("Branch changes: \(branchDescription(condition["source"]))")
        }
        if let actions = attributes["actions"] as? [[String: Any]] {
            for action in actions {
                guard let type = action["actionType"] as? String else {
                    continue
                }
                if type != "ARCHIVE" {
                    rules.append("\(display(type)): \(action["scheme"] as? String ?? "scheme")")
                }
            }
        }
        return rules.isEmpty ? ["No workflow rules returned"] : rules
    }

    private func scheduleRule(_ condition: [String: Any]) -> String {
        let schedule = condition["schedule"] as? [String: Any] ?? [:]
        let frequency = display(schedule["frequency"] as? String ?? "SCHEDULED")
        var suffix = branchDescription(condition["source"])
        if let hour = schedule["hour"] as? Int, let minute = schedule["minute"] as? Int {
            suffix += String(format: " at %02d:%02d", hour, minute)
        }
        if let timezone = schedule["timezone"] as? String, !timezone.isEmpty {
            suffix += " \(timezone)"
        }
        return "\(frequency): \(suffix)"
    }

    private func branchDescription(_ source: Any?) -> String {
        guard let source = source as? [String: Any] else {
            return "configured refs"
        }
        if source["isAllMatch"] as? Bool == true {
            return "all branches"
        }
        let patterns = source["patterns"] as? [[String: Any]] ?? []
        let names = patterns.compactMap { $0["pattern"] as? String }
        return names.isEmpty ? "configured branches" : names.joined(separator: ", ")
    }

    private func statusText(progress: String?, completion: String?) -> String {
        if progress == "COMPLETE" {
            return display(completion ?? "COMPLETE")
        }
        return display(progress ?? completion ?? "UNKNOWN")
    }

    private func statusColor(progress: String?, completion: String?) -> StatusColor {
        if progress == "RUNNING" || progress == "PENDING" {
            return .yellow
        }
        if completion == "SUCCEEDED" {
            return .green
        }
        if completion == "FAILED" || completion == "ERRORED" || completion == "CANCELED" {
            return .red
        }
        return .gray
    }

    private func date(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private func display(_ value: String) -> String {
        value
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func base64URLJSON(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return base64URL(data)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum EnvFile {
    static func values() -> [String: String] {
        [
            "~/.config/mac-appbar/app-store-connect.env",
            "/Users/stefan/code/mac-appbar/.env.local",
            "/Users/stefan/code/mac-appbar/.env",
        ].reduce(into: [:]) { values, rawPath in
            let path = (rawPath as NSString).expandingTildeInPath
            guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
                return
            }
            for (key, value) in parse(content) where values[key] == nil {
                values[key] = resolvedValue(value, for: key, envFilePath: path)
            }
        }
    }

    private static func resolvedValue(_ value: String, for key: String, envFilePath: String) -> String {
        guard shouldResolveAsPath(key, value) else {
            return value
        }
        if value.hasPrefix("/") || value.hasPrefix("~") {
            return (value as NSString).expandingTildeInPath
        }
        return URL(fileURLWithPath: envFilePath)
            .deletingLastPathComponent()
            .appendingPathComponent(value)
            .standardizedFileURL
            .path
    }

    private static func shouldResolveAsPath(_ key: String, _ value: String) -> Bool {
        guard !value.isEmpty else {
            return false
        }
        if value.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("-----BEGIN") {
            return false
        }
        return [
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "ASC_KEY_PATH",
            "APP_STORE_CONNECT_PRIVATE_KEY_PATH",
            "APP_STORE_CONNECT_API_KEY_PATH",
        ].contains(key)
    }

    private static func parse(_ content: String) -> [String: String] {
        return content.split(whereSeparator: \.isNewline).reduce(into: [:]) { values, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                return
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            values[String(key)] = stripQuotes(stripInlineComment(String(value)))
        }
    }

    private static func stripInlineComment(_ value: String) -> String {
        var quotedBy: Character?
        for index in value.indices {
            let character = value[index]
            if character == "'" || character == "\"" {
                if quotedBy == character {
                    quotedBy = nil
                } else if quotedBy == nil {
                    quotedBy = character
                }
            } else if character == "#", quotedBy == nil {
                return value[..<index].trimmingCharacters(in: .whitespaces)
            }
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }
}
