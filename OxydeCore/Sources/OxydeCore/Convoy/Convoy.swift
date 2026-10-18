import Foundation

/// A convoy code: six characters from an alphabet without look-alikes (no 0/O, 1/I/L).
public enum ConvoyCode {
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let length = 6

    public static func random() -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Uppercases and strips spaces and dashes; nil when it can't be a code.
    public static func normalize(_ input: String) -> String? {
        let s = input.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard s.count == length, s.allSatisfy(alphabet.contains) else { return nil }
        return s
    }
}

/// A friend in the convoy. Positions are shared only while the driver is in a convoy,
/// only with its members, and the server keeps them in memory for a few minutes at most.
public struct ConvoyMember: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Marker color as #RRGGBB.
    public var color: String
    public var coordinate: Coordinate?
    public var heading: Double?
    public var updatedAt: Date?
    public var isMe: Bool

    public init(id: String, name: String, color: String, coordinate: Coordinate?, heading: Double?, updatedAt: Date?, isMe: Bool) {
        self.id = id
        self.name = name
        self.color = color
        self.coordinate = coordinate
        self.heading = heading
        self.updatedAt = updatedAt
        self.isMe = isMe
    }

    /// No update for two minutes: the member may have parked or lost signal.
    public func isStale(now: Date = Date()) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince(updatedAt) > 120
    }
}

public struct ConvoySnapshot: Codable, Hashable, Sendable {
    public var code: String
    public var name: String
    public var members: [ConvoyMember]
    /// Optional shared destination set by whoever created the convoy.
    public var destination: Coordinate?
    public var destinationName: String?
    public var expiresAt: Date
}

public protocol ConvoyService: Sendable {
    var isConfigured: Bool { get }
    func create(name: String, displayName: String, color: String) async throws -> ConvoySnapshot
    func join(code: String, displayName: String, color: String) async throws -> ConvoySnapshot
    /// Sends the driver's position and returns everyone's latest positions.
    func update(code: String, coordinate: Coordinate, heading: Double?) async throws -> ConvoySnapshot
    func setDestination(code: String, coordinate: Coordinate, name: String) async throws -> ConvoySnapshot
    func leave(code: String) async throws
}

public struct UnconfiguredConvoyService: ConvoyService {
    public init() {}
    public var isConfigured: Bool { false }
    public func create(name: String, displayName: String, color: String) async throws -> ConvoySnapshot { throw APIError.notConfigured("Convoy") }
    public func join(code: String, displayName: String, color: String) async throws -> ConvoySnapshot { throw APIError.notConfigured("Convoy") }
    public func update(code: String, coordinate: Coordinate, heading: Double?) async throws -> ConvoySnapshot { throw APIError.notConfigured("Convoy") }
    public func setDestination(code: String, coordinate: Coordinate, name: String) async throws -> ConvoySnapshot { throw APIError.notConfigured("Convoy") }
    public func leave(code: String) async throws { throw APIError.notConfigured("Convoy") }
}

extension OxydeBackendClient: ConvoyService {
    struct ConvoyDTO: Decodable {
        struct Member: Decodable {
            var id: String; var name: String; var color: String
            var lat: Double?; var lon: Double?; var heading: Double?; var updatedAt: Date?; var me: Bool?
        }
        var code: String; var name: String; var members: [Member]
        var destination: [Double]?; var destinationName: String?; var expiresAt: Date

        var model: ConvoySnapshot {
            ConvoySnapshot(code: code, name: name, members: members.map { m in
                ConvoyMember(id: m.id, name: m.name, color: m.color,
                             coordinate: (m.lat != nil && m.lon != nil) ? Coordinate(latitude: m.lat!, longitude: m.lon!) : nil,
                             heading: m.heading, updatedAt: m.updatedAt, isMe: m.me ?? false)
            }, destination: destination.flatMap { $0.count == 2 ? Coordinate(latitude: $0[1], longitude: $0[0]) : nil },
               destinationName: destinationName, expiresAt: expiresAt)
        }
    }

    func convoyCall(_ method: String, _ path: String, _ body: [String: JSONValue]?) async throws -> ConvoySnapshot {
        let data = try body.map { try JSONEncoder().encode(JSONValue.object($0)) }
        let r = HTTPRequest(method: method, path: path, body: data, isIdempotent: method != "POST")
        return try await http.decode(ConvoyDTO.self, from: r).model
    }

    public func create(name: String, displayName: String, color: String) async throws -> ConvoySnapshot {
        try await convoyCall("POST", "v1/convoys", ["name": .string(name), "displayName": .string(displayName), "color": .string(color)])
    }

    public func join(code: String, displayName: String, color: String) async throws -> ConvoySnapshot {
        try await convoyCall("PUT", "v1/convoys/\(code)/members/me", ["displayName": .string(displayName), "color": .string(color)])
    }

    public func update(code: String, coordinate: Coordinate, heading: Double?) async throws -> ConvoySnapshot {
        var body: [String: JSONValue] = ["lat": .number(coordinate.latitude), "lon": .number(coordinate.longitude)]
        if let heading, heading.isFinite, heading >= 0 { body["heading"] = .number(heading) }
        return try await convoyCall("PUT", "v1/convoys/\(code)/members/me/position", body)
    }

    public func setDestination(code: String, coordinate: Coordinate, name: String) async throws -> ConvoySnapshot {
        try await convoyCall("PUT", "v1/convoys/\(code)/destination",
                             ["lat": .number(coordinate.latitude), "lon": .number(coordinate.longitude), "name": .string(name)])
    }

    public func leave(code: String) async throws {
        _ = try await http.send(HTTPRequest(method: "DELETE", path: "v1/convoys/\(code)/members/me"))
    }
}
