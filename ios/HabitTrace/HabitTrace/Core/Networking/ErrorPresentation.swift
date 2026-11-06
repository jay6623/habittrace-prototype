import Foundation

/// Maps errors to sentences the UI can show. Backend `detail` text is kept
/// verbatim because it carries validation rules; transport failures get
/// plain wording.
enum ErrorPresentation {
    static func message(for error: Error) -> String {
        if let validation = error as? OutcomeValidationError {
            return validation.errorDescription ?? "Check the outcome details and try again."
        }

        if let apiError = error as? APIError {
            switch apiError {
            case .httpStatus(let code, let detail):
                if let detail, !detail.isEmpty {
                    return detail
                }
                switch code {
                case 401: return "Your session has expired. Sign in again."
                case 404: return "This plan no longer exists."
                case 500...599: return "The server had a problem. Please try again."
                default: return "The request failed (HTTP \(code))."
                }
            case .invalidResponse:
                return "The server returned an unexpected response."
            case .decoding:
                return "The server response couldn't be read."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .timedOut:
                return "You're offline or the server can't be reached."
            default:
                break
            }
        }

        return error.localizedDescription
    }
}
