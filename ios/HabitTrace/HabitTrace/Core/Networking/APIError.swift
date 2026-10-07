import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let statusCode):
            return "The server returned HTTP \(statusCode)."
        case .decoding(let error):
            return "Failed to decode the server response: \(error.localizedDescription)"
        }
    }
}
