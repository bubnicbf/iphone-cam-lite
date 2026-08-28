/// The result of running one `SystemCheck`: its status, a human-readable
/// detail explaining that status, and an optional actionable remediation
/// step (surfaced by the Diagnostics UI).
public struct SystemCheckResult: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: CheckStatus
    public let detail: String
    public let remediation: String?

    public init(id: String, title: String, status: CheckStatus, detail: String, remediation: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.remediation = remediation
    }
}
