import Foundation

struct HealthResponse: Decodable {
    let status: String
    let ready: Bool
    let mlModelsLoaded: Bool
    let aiV2ModelsLoaded: Bool
    let supabaseConfigured: Bool
    let aiSupabaseConfigured: Bool
    let authSupabaseConfigured: Bool
}
