import Foundation

enum SupabaseConfiguration {
    static var url: URL {
        guard
            let rawURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
            let url = URL(string: rawURL)
        else {
            fatalError("SUPABASE_URL is not configured.")
        }

        return url
    }

    static var anonKey: String {
        guard
            let key = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"],
            !key.isEmpty
        else {
            fatalError("SUPABASE_ANON_KEY is not configured.")
        }

        return key
    }
}
