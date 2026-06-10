import Foundation

struct TrackedApp: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let repositoryPath: String
    let githubRepository: String
    let githubWorkflowFile: String
    let xcodeCloudWorkflowID: String
    let defaultBranch: String
    let defaultPrivateKeyPath: String?

    static let apps = [
        TrackedApp(
            id: "memeforge",
            name: "Memeforge",
            repositoryPath: "/Users/stefan/code/ios-keyboard",
            githubRepository: "smirea/memeforge",
            githubWorkflowFile: "testflight-internal.yml",
            xcodeCloudWorkflowID: "8A2FE4FD-B115-4866-A097-B6D5247F8ED0",
            defaultBranch: "master",
            defaultPrivateKeyPath: "/Users/stefan/code/app-store-connect-api-key.p8"
        )
    ]
}
