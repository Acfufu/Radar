import Foundation

extension JSONEncoder {
    static var radar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    static var radar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

enum RepositoryIntegrityError: Error {
    case mismatchedSnapshot
}
