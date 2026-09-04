import Foundation

struct SegmentState<Value: Sendable>: Sendable {
    let value: Value?
    let lastSuccessfulAt: Date?
    let lastAttemptedAt: Date?
    let error: SegmentError?
    let isStale: Bool
}

struct SegmentError: Error, Hashable, Sendable {
    let kind: Kind
    let message: String

    enum Kind: String, Codable, Sendable {
        case network
        case http
        case decoding
        case validation
        case authorization
        case disabled
    }
}

struct SegmentProjection<Value: Sendable>: Sendable {
    let value: Value?
    let error: SegmentError?

    static func success(_ value: Value) -> Self {
        Self(value: value, error: nil)
    }

    static func failure(_ error: SegmentError) -> Self {
        Self(value: nil, error: error)
    }
}
