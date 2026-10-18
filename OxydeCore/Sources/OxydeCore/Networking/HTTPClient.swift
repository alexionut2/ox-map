import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum APIError: Error, Equatable, LocalizedError, Sendable {
    /// The service has no base URL or key in this build.
    case notConfigured(String)
    case offline
    case timedOut
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    case client(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return "\(s) is not configured in this build."
        case .offline: return "You're offline."
        case .timedOut: return "The server took too long to respond."
        case .rateLimited: return "Too many requests. Try again shortly."
        case .server(let s): return "The server had a problem (\(s))."
        case .client(let s, let m): return m ?? "The request was rejected (\(s))."
        case .decoding: return "The server sent an unexpected response."
        case .transport(let s): return s
        }
    }

    var isRetryable: Bool {
        switch self {
        case .timedOut, .server, .rateLimited, .transport: return true
        default: return false
        }
    }
}

/// Exponential backoff with jitter.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int = 3, baseDelay: TimeInterval = 0.8, maxDelay: TimeInterval = 8) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let none = RetryPolicy(maxAttempts: 1)

    /// Delay before retry number `attempt` (1-based), honoring a server's Retry-After.
    public func delay(forAttempt attempt: Int, retryAfter: TimeInterval?, jitter: Double = Double.random(in: 0...0.25)) -> TimeInterval {
        if let retryAfter { return min(maxDelay * 4, max(0, retryAfter)) }
        let exp = baseDelay * pow(2, Double(attempt - 1))
        return min(maxDelay, exp * (1 + jitter))
    }
}

public struct HTTPRequest: Sendable {
    public var method: String
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var headers: [String: String]
    /// Only idempotent requests are retried automatically.
    public var isIdempotent: Bool

    public init(method: String = "GET", path: String, query: [URLQueryItem] = [], body: Data? = nil,
                headers: [String: String] = [:], isIdempotent: Bool? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.headers = headers
        self.isIdempotent = isIdempotent ?? (method == "GET" || method == "PUT" || method == "DELETE")
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
}

/// The network boundary, so tests can replace URLSession.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            // dataTask with a continuation rather than `data(for:)`, which Linux Foundation lacks.
            let (data, response): (Data, URLResponse) = try await withCheckedThrowingContinuation { cont in
                session.dataTask(with: request) { data, response, error in
                    if let error { cont.resume(throwing: error) }
                    else if let response { cont.resume(returning: (data ?? Data(), response)) }
                    else { cont.resume(throwing: URLError(.badServerResponse)) }
                }.resume()
            }
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("Not an HTTP response") }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw APIError.offline
            case .timedOut: throw APIError.timedOut
            default: throw APIError.transport(error.localizedDescription)
            }
        }
    }
}

/// A small JSON API client with typed errors and retries for idempotent requests.
public struct HTTPClient: Sendable {
    public var baseURL: URL
    public var transport: HTTPTransport
    public var retry: RetryPolicy
    public var defaultHeaders: [String: String]
    public var timeout: TimeInterval
    /// Injected so tests do not actually wait.
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(baseURL: URL, transport: HTTPTransport = URLSessionTransport(), retry: RetryPolicy = RetryPolicy(),
                defaultHeaders: [String: String] = [:], timeout: TimeInterval = 12,
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        self.baseURL = baseURL
        self.transport = transport
        self.retry = retry
        self.defaultHeaders = defaultHeaders
        self.timeout = timeout
        self.sleep = sleep
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    func urlRequest(for r: HTTPRequest) throws -> URLRequest {
        guard var c = URLComponents(url: baseURL.appendingPathComponent(r.path), resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Bad URL")
        }
        if !r.query.isEmpty { c.queryItems = r.query }
        guard let url = c.url else { throw APIError.transport("Bad URL") }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = r.method
        req.httpBody = r.body
        for (k, v) in defaultHeaders.merging(r.headers, uniquingKeysWith: { _, b in b }) { req.setValue(v, forHTTPHeaderField: k) }
        if r.body != nil, req.value(forHTTPHeaderField: "Content-Type") == nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    public func send(_ r: HTTPRequest) async throws -> HTTPResponse {
        let request = try urlRequest(for: r)
        let attempts = r.isIdempotent ? max(1, retry.maxAttempts) : 1
        var lastError: APIError = .transport("No attempt made")
        for attempt in 1...attempts {
            try Task.checkCancellation()
            do {
                let response = try await transport.send(request)
                switch response.status {
                case 200..<300:
                    return response
                case 429:
                    let after = response.headers["retry-after"].flatMap(TimeInterval.init)
                    lastError = .rateLimited(retryAfter: after)
                case 500..<600:
                    lastError = .server(status: response.status)
                default:
                    struct Message: Decodable { var error: String? }
                    let msg = (try? JSONDecoder().decode(Message.self, from: response.body))?.error
                    throw APIError.client(status: response.status, message: msg)
                }
            } catch let e as APIError {
                lastError = e
                if !e.isRetryable { throw e }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = .transport(error.localizedDescription)
            }
            if attempt < attempts {
                var after: TimeInterval?
                if case .rateLimited(let a) = lastError { after = a }
                try await sleep(retry.delay(forAttempt: attempt, retryAfter: after))
            }
        }
        throw lastError
    }

    public func decode<T: Decodable>(_ type: T.Type, from r: HTTPRequest) async throws -> T {
        let response = try await send(r)
        do {
            return try Self.makeDecoder().decode(T.self, from: response.body)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
