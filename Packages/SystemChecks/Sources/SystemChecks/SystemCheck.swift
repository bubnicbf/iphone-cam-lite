/// A single, independently testable, read-only prerequisite check.
/// Conformances must never mutate system state, restart services, kill
/// processes, toggle radios, or change permissions -- `SystemChecksRunner`
/// and the Diagnostics UI both rely on that guarantee to run checks
/// automatically (e.g. on a view appearing) without side effects.
public protocol SystemCheck: Sendable {
    var id: String { get }
    var title: String { get }
    func run() async -> SystemCheckResult
}
