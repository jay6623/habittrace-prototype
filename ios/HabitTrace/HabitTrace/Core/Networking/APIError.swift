import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    /// Non-2xx status. `detail` is the backend's `{"detail": ...}` message
    /// when present, for example a 409 on starting a finished plan.
    case httpStatus(Int, detail: String? = nil)
    case decoding(Error)

    var statusCode: Int? {
        if case .httpStatus(let code, _) = self {
            return code
        }
        return nil
    }

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let statusCode, let detail):
            if let detail, !detail.isEmpty {
                return detail
            }
            return "The server returned HTTP \(statusCode)."
        case .decoding(let error):
            return "Failed to decode the server response: \(error.localizedDescription)"
        }
    }
}
