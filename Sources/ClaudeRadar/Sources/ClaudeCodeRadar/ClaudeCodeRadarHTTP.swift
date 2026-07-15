import Foundation

extension ClaudeCodeRadarSource {
    static func request(url: URL, validators: HTTPValidators) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ClaudeRadar/0.1 (macOS; +https://github.com/acfufu/ClaudeRadar)", forHTTPHeaderField: "User-Agent")
        if let etag = validators.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = validators.lastModified {
            request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        return request
    }

    static func validate(_ payload: HTTPTransportResponse) throws -> HTTPValidators {
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
                retryAfter: parseRetryAfter(response.value(forHTTPHeaderField: "Retry-After"))
            )
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw SegmentError(kind: .authorization, message: "Claude Radar access was denied")
        }
        guard (200..<300).contains(response.statusCode) else {
            throw RadarHTTPError(kind: .status(response.statusCode), validators: validators)
        }
        guard !payload.bodyWasTruncated, payload.data.count <= 5 * 1_024 * 1_024 else {
            throw RadarHTTPError(kind: .oversized, validators: validators)
        }
        let mime = response.mimeType?.lowercased() ?? ""
        guard mime == "application/json" || mime.hasSuffix("+json") else {
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
