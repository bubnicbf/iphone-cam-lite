/// The functional area a log message belongs to. Each category maps to its
/// own `os.Logger` category (see `AppLogger`) so Console.app / `log stream`
/// can filter by subsystem area without grepping message text.
public enum LogCategory: String, CaseIterable, Sendable {
    case app
    case automation
    case adapters
    case diagnostics
    case systemChecks

    /// Reverse-DNS subsystem shared by every category. Kept in one place so
    /// the app's bundle identifier only needs to change here if it ever does.
    public static let subsystem = "com.iphonecamlite.app"
}
