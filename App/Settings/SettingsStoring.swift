import Foundation

/// The minimal persistence seam every setting in this app is written
/// through. Nothing outside this file (and `AppSettingsStore`, which is
/// the only thing that touches this protocol) reads or writes
/// `UserDefaults` directly -- this is what keeps persistence injectable
/// and replaceable in tests instead of scattered across the app.
public protocol SettingsStoring: AnyObject, Sendable {
    func string(forKey key: String) -> String?
    func setString(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double?
    func setDouble(_ value: Double?, forKey key: String)
    func integer(forKey key: String) -> Int?
    func setInteger(_ value: Int?, forKey key: String)
    func bool(forKey key: String) -> Bool
    func setBool(_ value: Bool, forKey key: String)
}

/// Production store backed by `UserDefaults.standard`.
public final class UserDefaultsSettingsStore: SettingsStoring, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }
    public func setString(_ value: String?, forKey key: String) { defaults.set(value, forKey: key) }
    public func double(forKey key: String) -> Double? { defaults.object(forKey: key) != nil ? defaults.double(forKey: key) : nil }
    public func setDouble(_ value: Double?, forKey key: String) { defaults.set(value, forKey: key) }
    public func integer(forKey key: String) -> Int? { defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : nil }
    public func setInteger(_ value: Int?, forKey key: String) { defaults.set(value, forKey: key) }
    public func bool(forKey key: String) -> Bool { defaults.bool(forKey: key) }
    public func setBool(_ value: Bool, forKey key: String) { defaults.set(value, forKey: key) }
}

/// In-memory store for previews and tests: no disk I/O, always starts
/// empty, and never leaks state between test cases.
public final class InMemorySettingsStore: SettingsStoring, @unchecked Sendable {
    private var strings: [String: String] = [:]
    private var doubles: [String: Double] = [:]
    private var integers: [String: Int] = [:]
    private var bools: [String: Bool] = [:]

    public init() {}

    public func string(forKey key: String) -> String? { strings[key] }
    public func setString(_ value: String?, forKey key: String) { strings[key] = value }
    public func double(forKey key: String) -> Double? { doubles[key] }
    public func setDouble(_ value: Double?, forKey key: String) { doubles[key] = value }
    public func integer(forKey key: String) -> Int? { integers[key] }
    public func setInteger(_ value: Int?, forKey key: String) { integers[key] = value }
    public func bool(forKey key: String) -> Bool { bools[key] ?? false }
    public func setBool(_ value: Bool, forKey key: String) { bools[key] = value }
}
