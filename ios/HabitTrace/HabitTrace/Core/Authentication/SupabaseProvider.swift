import Foundation
import Supabase

enum SupabaseProvider {
    static let client = SupabaseClient(
        supabaseURL: SupabaseConfiguration.url,
        supabaseKey: SupabaseConfiguration.anonKey
    )
}
