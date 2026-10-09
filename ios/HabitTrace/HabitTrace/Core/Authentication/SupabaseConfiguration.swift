import Foundation

/// Supabase connection settings.
///
/// Values are resolved in this order:
/// 1. `SUPABASE_URL` / `SUPABASE_ANON_KEY` in the process environment.
///    The Xcode scheme sets these, but they exist only when Xcode launches
///    the app.
/// 2. `SupabaseConfig.plist` bundled with the app. The file is gitignored;
///    copy `SupabaseConfig.example.plist` (next to the project) to
///    `HabitTrace/Configuration/SupabaseConfig.plist` and fill it in.
enum SupabaseConfiguration {
    static var url: URL {
        guard
            let rawURL = value(for: "SUPABASE_URL"),
            let url = URL(string: rawURL)
        else {
            fatalError(missingValueMessage("SUPABASE_URL"))
        }

        return url
    }

    static var anonKey: String {
        guard let key = value(for: "SUPABASE_ANON_KEY") else {
            fatalError(missingValueMessage("SUPABASE_ANON_KEY"))
        }

        return key
    }

    // MARK: - Resolution

    /// Contents of the bundled `SupabaseConfig.plist`, or empty if absent.
    private static let bundledValues: [String: Any] = {
        guard
            let fileURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: fileURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let values = plist as? [String: Any]
        else {
            return [:]
        }

        return values
    }()

    /// Non-empty value for `key` from the environment, then the bundled plist.
    private static func value(for key: String) -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment[key],
            bundledValues[key] as? String,
        ]

        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private static func missingValueMessage(_ key: String) -> String {
        """
        \(key) is not configured. Set it as an environment variable in the \
        Xcode scheme, or add it to HabitTrace/Configuration/SupabaseConfig.plist \
        (see SupabaseConfig.example.plist).
        """
    }
}
