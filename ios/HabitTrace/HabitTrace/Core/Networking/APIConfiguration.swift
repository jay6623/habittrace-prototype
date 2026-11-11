import Foundation
import OSLog

enum APIConfiguration {
    /// The deployed FastAPI backend, the same origin the production PWA is
    /// built against. Physical devices fall back to it whenever the
    /// configured URL points at the Mac's loopback interface.
    static let productionURL = URL(string: "https://habittrace-api.onrender.com")!

    /// Local backend for simulator development. Only the simulator shares the
    /// Mac's loopback interface, so this is never used on a real device.
    static let localDevelopmentURL = URL(string: "http://127.0.0.1:8000")!

    /// Base URL of the HabitTrace API, resolved once per launch:
    /// 1. `HABITTRACE_API_URL` in the process environment (Xcode scheme or
    ///    a test run). Present only when Xcode launches the app.
    /// 2. `API_BASE_URL` in the bundled, gitignored `SupabaseConfig.plist`,
    ///    which also applies to home-screen launches.
    /// 3. `localDevelopmentURL`.
    ///
    /// The chosen value then passes through `normalize(_:isSimulator:)` so a
    /// real device always ends up on an HTTPS origin that App Transport
    /// Security accepts.
    static let baseURL: URL = {
        let resolved = resolve(
            environmentValue: ProcessInfo.processInfo.environment["HABITTRACE_API_URL"],
            bundledValue: bundledConfigValue(for: "API_BASE_URL"),
            isSimulator: isSimulator
        )
        logger.info("API base URL: \(resolved.absoluteString, privacy: .public)")
        return resolved
    }()

    /// Pure resolution step, separated from `baseURL` so it can be tested
    /// with explicit inputs.
    static func resolve(environmentValue: String?, bundledValue: String?, isSimulator: Bool) -> URL {
        let configured = url(from: environmentValue)
            ?? url(from: bundledValue)
            ?? localDevelopmentURL
        return normalize(configured, isSimulator: isSimulator)
    }

    /// Keeps requests inside App Transport Security without disabling it:
    /// - Loopback hosts stay as configured on the simulator but become
    ///   `productionURL` on a physical device, which cannot reach the Mac.
    /// - Plain `http://` to any other host is upgraded to `https://`. ATS
    ///   rejects cleartext to remote hosts, and the deployed backend serves
    ///   TLS only, so the cleartext form can never succeed.
    static func normalize(_ url: URL, isSimulator: Bool) -> URL {
        if isLoopback(url) {
            return isSimulator ? url : productionURL
        }

        guard
            url.scheme?.lowercased() == "http",
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return url
        }

        components.scheme = "https"
        if components.port == 80 {
            components.port = nil
        }
        return components.url ?? url
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased(), !host.isEmpty else {
            return false
        }
        return host == "localhost"
            || host == "127.0.0.1"
            || host == "::1"
            || host == "[::1]"
            || host.hasSuffix(".localhost")
    }

    // MARK: - Private

    private static let logger = Logger(subsystem: "edu.utah.habittrace", category: "APIConfiguration")

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

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
