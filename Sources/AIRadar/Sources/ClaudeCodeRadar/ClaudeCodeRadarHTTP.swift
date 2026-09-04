import Foundation

extension RadarHTTPSource {
    func request(url: URL, validators: HTTPValidators) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue("AIRadar/0.3.0 (macOS; +https://github.com/Acfufu/Radar)", forHTTPHeaderField: "User-Agent")
        if let etag = validators.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return request
    }

    func validate(_ payload: HTTPTransportResponse) throws -> HTTPValidators {
        let response = payload.response
        let validators = HTTPValidators(
            etag: response.value(forHTTPHeaderField: "ETag"),
            lastModified: response.value(forHTTPHeaderField: "Last-Modified")
        )
        if response.statusCode == 304 {
            throw RadarHTTPError(kind: .notModified, validators: validators)
        }
        if response.statusCode == 429 || response.statusCode == 503 {
            throw RadarHTTPError(
                kind: .retryableStatus,
                validators: validators,
                retryAfter: Self.parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            )
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SegmentError(kind: .authorization, message: "\(descriptor.displayName) access was denied")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw RadarHTTPError(kind: .status(response.statusCode), validators: validators)
        }
        guard !payload.bodyWasTruncated, payload.data.count <= maximumResponseBytes else {
            throw RadarHTTPError(kind: .oversized, validators: validators)
        }
        let mime = response.mimeType?.lowercased() ?? ""
        guard allowedMIMETypes.contains(mime) || mime.hasSuffix("+json") else {
            throw RadarHTTPError(kind: .mime, validators: validators)
        }
        return validators
    }

    private static func parseRetryAfter(_ value: String?) -> RetryAfter? {
        guard let value else { return nil }
        if let seconds = Int(value.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            return .seconds(seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map(RetryAfter.date)
    }
}
