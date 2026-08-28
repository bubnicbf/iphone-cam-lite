import Foundation

/// Reads Wi-Fi's current connection state, read-only. Mirrors
/// `scripts/check_prereqs.sh`'s original logic: probing hardware ports
/// dynamically (never hardcoded to `en0`) rather than assuming a fixed
/// interface name, and reporting `.unknown` -- never "on" -- if no Wi-Fi
/// interface can be identified or its status cannot be read.
public protocol WiFiStateProviding: Sendable {
    func currentState() -> RadioState
}

#if os(macOS)
/// Discovers the active Wi-Fi hardware interface via
/// `networksetup -listallhardwareports` and checks its link status via
/// `ifconfig`. Read-only: never disables/enables an interface.
public struct NetworksetupWiFiStateProvider: WiFiStateProviding {
    public init() {}

    public func currentState() -> RadioState {
        guard let device = wifiDeviceName() else { return .unknown }
        return interfaceIsActive(device) ? .on : .off
    }

    private func wifiDeviceName() -> String? {
        guard let output = run("/usr/sbin/networksetup", ["-listallhardwareports"]) else { return nil }
        let lines = output.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() where line.contains("Wi-Fi") || line.contains("AirPort") {
            guard index + 1 < lines.count else { continue }
            let deviceLine = lines[index + 1]
            if let range = deviceLine.range(of: "Device: ") {
                return String(deviceLine[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func interfaceIsActive(_ device: String) -> Bool {
        guard let output = run("/sbin/ifconfig", [device]) else { return false }
        return output.contains("status: active")
    }

    private func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
#endif

public struct WiFiCheck: SystemCheck {
    public let id = "wifi"
    public let title = "Wi-Fi"

    private let provider: WiFiStateProviding

    public init(provider: WiFiStateProviding) {
        self.provider = provider
    }

    public func run() async -> SystemCheckResult {
        switch provider.currentState() {
        case .on:
            return SystemCheckResult(id: id, title: title, status: .passed, detail: "Wi-Fi is connected.")
        case .off:
            return SystemCheckResult(
                id: id,
                title: title,
                status: .failed,
                detail: "A Wi-Fi interface was found but is not active.",
                remediation: "Turn Wi-Fi on and join a network in System Settings > Wi-Fi."
            )
        case .unknown:
            return SystemCheckResult(
                id: id,
                title: title,
                status: .unknown,
                detail: "No Wi-Fi hardware interface could be identified, or its status could not be read.",
                remediation: "Confirm Wi-Fi hardware is present and check its status manually in System Settings > Wi-Fi."
            )
        }
    }
}
