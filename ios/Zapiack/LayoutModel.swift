import Foundation

/// A push template's grid layout, as Zapiack sends it in `zp_layout`: rows and stacks that share their space by weight, cut from a
/// 24-column grid on the server so every platform draws the same thing.
///
/// Elements are named by short references: `t` the title, `b` the body, `i` the small picture, `p` the big picture, `l<n>` the
/// n-th live element (`zp_live`) and `a<n>` the n-th button.
public struct ZapiackLayoutNode: Decodable, Hashable {
    public let row: Bool
    public let children: [Child]

    public enum Child: Hashable {
        case sub(weight: Int, node: ZapiackLayoutNode)
        case element(weight: Int, ref: String, rows: Int)
        case space(weight: Int)

        public var weight: Int {
            switch self {
            case let .sub(w, _), let .element(w, _, _), let .space(w): return w
            }
        }
    }

    /// How tall one grid row is drawn, in points.
    public static let rowPoints: CGFloat = 8

    private enum Keys: String, CodingKey { case d, c }
    private enum ChildKeys: String, CodingKey { case w, n, e, h, s }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        row = (try c.decode(String.self, forKey: .d)) == "r"
        var list = try c.nestedUnkeyedContainer(forKey: .c)
        var out: [Child] = []
        while !list.isAtEnd {
            let item = try list.nestedContainer(keyedBy: ChildKeys.self)
            let w = min(max(try item.decodeIfPresent(Int.self, forKey: .w) ?? 0, 0), 80)
            guard w > 0 else { continue }
            if let n = try item.decodeIfPresent(ZapiackLayoutNode.self, forKey: .n) {
                out.append(.sub(weight: w, node: n))
            } else if let e = try item.decodeIfPresent(String.self, forKey: .e), e.range(of: "^(t|b|i|p|l[0-9]{1,2}|a[0-9])$", options: .regularExpression) != nil {
                out.append(.element(weight: w, ref: e, rows: min(max(try item.decodeIfPresent(Int.self, forKey: .h) ?? 1, 1), 80)))
            } else {
                out.append(.space(weight: w))
            }
        }
        children = out
    }

    /// Reads the tree from the JSON text Zapiack sends, or nil.
    public static func parse(_ json: String?) -> ZapiackLayoutNode? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ZapiackLayoutNode.self, from: data)
    }

    /// How tall it draws, in grid rows: a stack adds its parts up, a row is as tall as its tallest part.
    public var rows: Int {
        row ? children.map(Self.rows(of:)).max() ?? 0 : children.map(Self.rows(of:)).reduce(0, +)
    }

    private static func rows(of child: Child) -> Int {
        switch child {
        case let .sub(_, n): return n.rows
        case let .element(_, _, r): return r
        case let .space(w): return w
        }
    }
}

/// One live element (`zp_live`): a timer, progress, counter, date or badge, as the server filled it in.
public struct ZapiackLiveItem: Decodable, Hashable {
    public let type: String
    public let mode: String?
    public let source: String?
    public let format: String?
    public let look: String?
    public let color: String?
    public let label: String?
    public let onEnd: String?
    public let expiredText: String?
    public let steps: [String]?
    public let current: Int?
    public let value: String?
    public let style: String?
    public let text: String?

    private enum Keys: String, CodingKey { case type, mode, source, format, look, color, label, onEnd, expiredText, steps, current, value, style, text }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        type = try c.decode(String.self, forKey: .type)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        format = try c.decodeIfPresent(String.self, forKey: .format)
        look = try c.decodeIfPresent(String.self, forKey: .look)
        color = try c.decodeIfPresent(String.self, forKey: .color)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        onEnd = try c.decodeIfPresent(String.self, forKey: .onEnd)
        expiredText = try c.decodeIfPresent(String.self, forKey: .expiredText)
        steps = try c.decodeIfPresent([String].self, forKey: .steps)
        current = (try? c.decodeIfPresent(Int.self, forKey: .current)) ?? (try? c.decodeIfPresent(Double.self, forKey: .current)).flatMap { $0.map(Int.init) }
        // A counter's value is a number; a date's is text. Both are kept as text to show.
        if let n = try? c.decodeIfPresent(Double.self, forKey: .value) {
            value = n.rounded() == n ? String(Int(n)) : String(n)
        } else {
            value = try c.decodeIfPresent(String.self, forKey: .value)
        }
        style = try c.decodeIfPresent(String.self, forKey: .style)
        text = try c.decodeIfPresent(String.self, forKey: .text)
    }

    public static func parse(_ json: String?) -> [ZapiackLiveItem] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ZapiackLiveItem].self, from: data)) ?? []
    }

    /// When a timer ends: its date for a fixed timer, its minutes after `received` for the others.
    public func timerEnd(received: Date) -> Date? {
        guard type == "timer", let source else { return nil }
        if mode == "fixed" {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return f.date(from: source) ?? ISO8601DateFormatter().date(from: source)
        }
        guard let minutes = Double(source), minutes > 0 else { return nil }
        return received.addingTimeInterval(minutes * 60)
    }
}
