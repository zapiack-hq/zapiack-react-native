import Foundation

/// What every push carries so a tap can be reported and followed.
public struct PushBlock: Codable, Equatable {
    public struct Tracking: Codable, Equatable {
        public var w: Int?
        public var s: Bool?
    }

    public struct Action: Codable, Equatable {
        public var id: String
        public var title: String
        public var event: String?
        public var link: String?
    }

    public var m: String
    public var d: String
    public var l: String?
    public var i: String?
    public var e: String?
    public var t: Tracking?
    public var a: [Action]?

    public init(m: String, d: String, l: String? = nil, i: String? = nil, e: String? = nil, t: Tracking? = nil, a: [Action]? = nil) {
        self.m = m
        self.d = d
        self.l = l
        self.i = i
        self.e = e
        self.t = t
        self.a = a
    }

    /// Reads the block from a notification's `userInfo`, or returns nil when the push is not from Zapiack.
    public init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["zapiack"], JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let block = try? JSONDecoder().decode(PushBlock.self, from: data),
              !block.m.isEmpty, !block.d.isEmpty
        else { return nil }
        self = block
    }
}

/// A value of the app's own, sent along with an event.
public enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

public enum EventType: String, Codable {
    case clicked, action, screen, custom, received
}

public struct SdkEvent: Codable, Equatable {
    public var clientEventId: String
    public var type: EventType
    public var deliveryId: String
    public var sessionId: String?
    public var name: String?
    public var actionId: String?
    public var properties: [String: JSONValue]?
    public var previousScreen: String?
    public var at: String

    public init(type: EventType, deliveryId: String, sessionId: String? = nil, name: String? = nil, actionId: String? = nil, properties: [String: JSONValue]? = nil, previousScreen: String? = nil, at: Date = Date()) {
        self.clientEventId = UUID().uuidString.lowercased()
        self.type = type
        self.deliveryId = deliveryId
        self.sessionId = sessionId
        self.name = name
        self.actionId = actionId
        self.properties = properties
        self.previousScreen = previousScreen
        self.at = Timestamps.string(from: at)
    }
}

/// The window after a tap in which screens and events are credited to the push.
public struct ActiveSession: Codable, Equatable {
    public var sessionId: String
    public var deliveryId: String
    public var messageId: String
    public var startedAt: Date
    public var windowMinutes: Int
    public var screens: Bool

    public init(sessionId: String, deliveryId: String, messageId: String, startedAt: Date, windowMinutes: Int, screens: Bool) {
        self.sessionId = sessionId
        self.deliveryId = deliveryId
        self.messageId = messageId
        self.startedAt = startedAt
        self.windowMinutes = windowMinutes
        self.screens = screens
    }

    public func isOpen(at now: Date) -> Bool {
        now <= startedAt.addingTimeInterval(TimeInterval(windowMinutes) * 60)
    }
}

/// What was tapped, handed to the app so it can route.
public struct Tap: Equatable {
    public var messageId: String
    public var deliveryId: String
    public var sessionId: String
    /// The button that was tapped, when it was a button.
    public var actionId: String?
    /// The event name set on the notification or the button.
    public var event: String?
    public var link: URL?
}

public enum Timestamps {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}
