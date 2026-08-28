import Foundation

/// Reads Bluetooth's current power state, read-only. Mirrors
/// `scripts/check_prereqs.sh`'s original logic exactly: a preference read
/// that fails, or returns anything other than the documented 0/1 values,
/// is reported as `.unknown` -- never silently treated as "on".
public protocol BluetoothStateProviding: Sendable {
    func currentState() -> RadioState
}

#if os(macOS)
/// Reads `com.apple.Bluetooth`'s `ControllerPowerState` preference via
/// `/usr/bin/defaults read`, exactly reproducing the original shell
/// check's data source. Read-only: never writes a preference, never
/// toggles the radio.
public struct DefaultsBluetoothStateProvider: BluetoothStateProviding {
    public init() {}

    public func currentState() -> RadioState {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["read", "/Library/Preferences/com.apple.Bluetooth", "ControllerPowerState"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .unknown
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return .unknown }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "1": return .on
        case "0": return .off
        default: return .unknown
        }
    }
}
#endif

public struct BluetoothCheck: SystemCheck {
    public let id = "bluetooth"
    public let title = "Bluetooth"

    private let provider: BluetoothStateProviding

    public init(provider: BluetoothStateProviding) {
        self.provider = provider
    }

    public func run() async -> SystemCheckResult {
        switch provider.currentState() {
        case .on:
            return SystemCheckResult(id: id, title: title, status: .passed, detail: "Bluetooth is on.")
        case .off:
            return SystemCheckResult(
                id: id,
                title: title,
                status: .failed,
                detail: "Bluetooth appears to be off.",
                remediation: "Turn Bluetooth on in System Settings > Bluetooth."
            )
        case .unknown:
            return SystemCheckResult(
                id: id,
                title: title,
                status: .unknown,
                detail: "Bluetooth's state could not be determined (preference read failed or returned an unexpected value).",
                remediation: "Check Bluetooth status manually in System Settings > Bluetooth."
            )
        }
    }
}
