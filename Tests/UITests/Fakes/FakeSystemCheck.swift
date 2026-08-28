import SystemChecks

/// Returns a fixed `SystemCheckResult`, so Diagnostics view-model tests
/// can present a mocked failure (with remediation) deterministically.
struct FakeSystemCheck: SystemCheck {
    let id: String
    let title: String
    let result: SystemCheckResult

    init(id: String, title: String, status: CheckStatus, detail: String, remediation: String? = nil) {
        self.id = id
        self.title = title
        self.result = SystemCheckResult(id: id, title: title, status: status, detail: detail, remediation: remediation)
    }

    func run() async -> SystemCheckResult { result }
}
