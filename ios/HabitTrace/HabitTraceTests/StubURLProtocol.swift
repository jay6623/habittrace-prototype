import Foundation
import Testing

/// Parent for every suite that talks to `StubURLProtocol`. The stub's
/// handler is process-global, so these suites must never run in parallel
/// with each other; the serialized trait applies to all nested suites.
@Suite(.serialized)
struct StubbedNetworkSuites {}

/// Serves canned HTTP responses to `URLSession` and records every request,
/// so `APIClient` can be exercised without a server.
nonisolated final class StubURLProtocol: URLProtocol {
    struct RecordedRequest: Sendable {
        let method: String
        let path: String
        let query: String?
        let bodyData: Data?

        /// Query string parsed into a dictionary (last value wins).
        var queryParameters: [String: String] {
            guard let query else { return [:] }
            var result: [String: String] = [:]
            for pair in query.split(separator: "&") {
                let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
                result[parts[0].removingPercentEncoding ?? parts[0]] =
                    parts.count > 1 ? (parts[1].removingPercentEncoding ?? parts[1]) : ""
            }
            return result
        }

        /// Decoded JSON body, when the request had one.
        var body: [String: Any]? {
            guard let bodyData, !bodyData.isEmpty else { return nil }
            return try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
        }
    }

    struct Response: Sendable {
        let statusCode: Int
        let body: Data

        static func json(_ statusCode: Int, _ data: Data) -> Response {
            Response(statusCode: statusCode, body: data)
        }

        static func detail(_ statusCode: Int, _ message: String) -> Response {
            let data = try! JSONSerialization.data(withJSONObject: ["detail": message])
            return Response(statusCode: statusCode, body: data)
        }
    }

    /// Return a response, or throw to simulate a transport failure.
    typealias Handler = @Sendable (RecordedRequest) throws -> Response

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var requests: [RecordedRequest] = []

    static func install(_ handler: @escaping Handler) {
        lock.withLock {
            Self.handler = handler
            Self.requests = []
        }
    }

    static func reset() {
        lock.withLock {
            handler = nil
            requests = []
        }
    }

    static var recordedRequests: [RecordedRequest] {
        lock.withLock { requests }
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    /// Encodes a JSON fixture once so handlers capture only `Data`.
    static func encode(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let recorded = RecordedRequest(
            method: request.httpMethod ?? "GET",
            path: request.url?.path ?? "",
            query: request.url?.query,
            bodyData: Self.bodyData(of: request)
        )

        let handler = Self.lock.withLock { () -> Handler? in
            Self.requests.append(recorded)
            return Self.handler
        }

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }

        do {
            let response = try handler(recorded)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: response.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream, not `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }

        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var collected = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: bufferSize)
            if count <= 0 { break }
            collected.append(buffer, count: count)
        }
        return collected
    }
}
