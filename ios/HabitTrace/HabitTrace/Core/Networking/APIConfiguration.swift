import Foundation

enum APIConfiguration {
    /// Base URL of the HabitTrace API, resolved once per launch:
    /// 1. `HABITTRACE_API_URL` in the process environment (Xcode scheme or
    ///    a test run). Present only when Xcode launches the app.
    /// 2. `API_BASE_URL` in the bundled, gitignored `SupabaseConfig.plist`,
    ///    which also applies to home-screen launches.
    /// 3. The local development default.
    static let baseURL: URL = {
        if let url = url(from: ProcessInfo.processInfo.environment["HABITTRACE_API_URL"]) {
            return url
        }

        if let url = url(from: bundledConfigValue(for: "API_BASE_URL")) {
            return url
        }

        return URL(string: "http://127.0.0.1:8000")!
    }()

    private static func url(from raw: String?) -> URL? {
        guard
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else {
            return nil
        }
        return URL(string: trimmed)
    }

    private static func bundledConfigValue(for key: String) -> String? {
        guard
            let fileURL = Bundle.main.url(forResource: "SupabaseConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: fileURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let values = plist as? [String: Any]
        else {
            return nil
        }
        return values[key] as? String
    }
}
