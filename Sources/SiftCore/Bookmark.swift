import Foundation

public struct Bookmark: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public var name: String
    public var url: String
    public var source: Source

    public enum Source: String, Codable, Sendable {
        case managed
        case zen
    }

    public init(id: String = UUID().uuidString, name: String, url: String, source: Source = .managed) {
        self.id = id
        self.name = name
        self.url = url
        self.source = source
    }
}
