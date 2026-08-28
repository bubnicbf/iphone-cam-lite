import CameraCore

/// Reports a fixed, scripted sequence of running/not-running results, one
/// per call to `isRunning()`; once the sequence is exhausted, repeats the
/// last value. Lets `ApplicationReadiness` tests exercise "appears on the
/// Nth attempt" and "never appears" without any real process.
final class FakeProcessAvailabilityChecking: ProcessAvailabilityChecking, @unchecked Sendable {
    private var remaining: [Bool]
    private(set) var callCount = 0

    init(sequence: [Bool]) {
        self.remaining = sequence
    }

    func isRunning() async -> Bool {
        callCount += 1
        guard !remaining.isEmpty else { return false }
        return remaining.removeFirst()
    }
}
