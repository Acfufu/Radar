import Foundation

struct HTTPTransportResponse: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let bodyWasTruncated: Bool

    init(data: Data, response: HTTPURLResponse, bodyWasTruncated: Bool = false) {
        self.data = data
        self.response = response
        self.bodyWasTruncated = bodyWasTruncated
    }
}

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> HTTPTransportResponse
    func cancelAll() async
}

extension HTTPTransport {
    func cancelAll() async {}
}

final class URLSessionHTTPTransport: NSObject, HTTPTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private let maxBodyBytes: Int
    private let sessionLock = NSLock()
    private var storedSession: URLSession?
    private var session: URLSession {
        sessionLock.withLock {
            if let storedSession { return storedSession }
            let session = makeSession()
            storedSession = session
            return session
        }
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    init(maxBodyBytes: Int = 5 * 1_024 * 1_024) {
        self.maxBodyBytes = maxBodyBytes
        super.init()
    }

    func data(for request: URLRequest) async throws -> HTTPTransportResponse {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        data.reserveCapacity(min(maxBodyBytes + 1, response.expectedContentLength > 0 ? Int(response.expectedContentLength) : maxBodyBytes + 1))
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBodyBytes {
                return HTTPTransportResponse(data: data, response: response, bodyWasTruncated: true)
            }
        }
        return HTTPTransportResponse(data: data, response: response)
    }

    func cancelAll() async {
        sessionLock.withLock { storedSession }?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest?.url,
              let redirected = request.url,
              original.scheme?.lowercased() == "https",
              redirected.scheme?.lowercased() == "https",
              original.host?.lowercased() == redirected.host?.lowercased(),
              Self.effectivePort(original) == Self.effectivePort(redirected) else {
            completionHandler(nil)
            return
        }
        var safeRequest = request
        safeRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        safeRequest.setValue(nil, forHTTPHeaderField: "Cookie")
        completionHandler(safeRequest)
    }

    private static func effectivePort(_ url: URL) -> Int? {
        url.port ?? (url.scheme?.lowercased() == "https" ? 443 : nil)
    }
}

struct HTTPValidators: Equatable, Sendable {
    let etag: String?
    let lastModified: String?

    static let empty = Self(etag: nil, lastModified: nil)
}

enum RetryAfter: Equatable, Sendable {
    case seconds(Int)
    case date(Date)
}

struct RadarHTTPError: Error, Sendable {
    enum Kind: Equatable, Sendable {
        case notModified
        case retryableStatus
        case status(Int)
        case mime
        case oversized
        case network
    }

    let kind: Kind
    let validators: HTTPValidators
    let retryAfter: RetryAfter?

    init(kind: Kind, validators: HTTPValidators = .empty, retryAfter: RetryAfter? = nil) {
        self.kind = kind
        self.validators = validators
        self.retryAfter = retryAfter
    }
}
