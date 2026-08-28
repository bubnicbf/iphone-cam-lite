import AppAutomationCore

/// Reports whether a process is "running" using an explicit allow-set of
/// exact names, so a test can assert that a helper/decoy process name
/// (present in the set) never satisfies a check for the real target name
/// -- exact matching, never substring matching.
final class FakeProcessProbe: ProcessProbe, @unchecked Sendable {
    private var runningNamesBySequence: [Set<String>]
    private(set) var queriedNames: [String] = []

    /// `sequence` lets a test simulate "the decoy process is running from
    /// the start, but the real target only appears after N polls".
    init(sequence: [Set<String>]) {
        self.runningNamesBySequence = sequence
    }

    convenience init(alwaysRunning names: Set<String>) {
        self.init(sequence: Array(repeating: names, count: 1_000))
    }

    func isRunning(exactProcessName: String) async -> Bool {
        queriedNames.append(exactProcessName)
        let current = runningNamesBySequence.isEmpty ? [] : runningNamesBySequence.removeFirst()
        return current.contains(exactProcessName)
    }
}
