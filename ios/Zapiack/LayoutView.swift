#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Everything a layout's references point at.
public struct ZapiackLayoutContent {
    public var title: String
    public var body: String?
    public var live: [ZapiackLiveItem]
    public var actions: [String]
    public var background: String?
    public var thumbnail: UIImage?
    public var picture: UIImage?
    /// When the push arrived: per-user timers count from here.
    public var received: Date
    /// Set by a Live Activity, which knows the timer's end exactly.
    public var timerEnd: Date?
    /// Leaves buttons out, where the system draws them itself (the notification content extension).
    public var hideActions: Bool

    public init(title: String, body: String? = nil, live: [ZapiackLiveItem] = [], actions: [String] = [], background: String? = nil, thumbnail: UIImage? = nil, picture: UIImage? = nil, received: Date = Date(), timerEnd: Date? = nil, hideActions: Bool = false) {
        self.title = title
        self.body = body
        self.live = live
        self.actions = actions
        self.background = background
        self.thumbnail = thumbnail
        self.picture = picture
        self.received = received
        self.timerEnd = timerEnd
        self.hideActions = hideActions
    }

    var dark: Bool {
        guard let bg = background.flatMap(Color.zapiackRGB) else { return true }
        return (bg.r * 299 + bg.g * 587 + bg.b * 114) / 1000 < 140
    }
}

/// Draws a Zapiack grid layout: rows share their width by weight, stacks take each element's height in grid rows. It is the same
/// tree Android and the dashboard draw, so a design looks the same everywhere.
@available(iOS 16.0, *)
public struct ZapiackLayoutView: View {
    let node: ZapiackLayoutNode
    let content: ZapiackLayoutContent

    public init(node: ZapiackLayoutNode, content: ZapiackLayoutContent) {
        self.node = node
        self.content = content
    }

    public var body: some View {
        GeometryReader { g in
            NodeView(node: node, width: g.size.width, content: content)
        }
        .frame(minHeight: CGFloat(node.rows) * ZapiackLayoutNode.rowPoints, alignment: .topLeading)
    }
}

@available(iOS 16.0, *)
struct NodeView: View {
    let node: ZapiackLayoutNode
    let width: CGFloat
    let content: ZapiackLayoutContent

    var body: some View {
        let total = max(1, node.children.map(\.weight).reduce(0, +))
        if node.row {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    cell(child, width: width * CGFloat(child.weight) / CGFloat(total))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
                    cell(child, width: width)
                }
            }
        }
    }

    @ViewBuilder
    func cell(_ child: ZapiackLayoutNode.Child, width: CGFloat) -> some View {
        switch child {
        case let .sub(_, n):
            NodeView(node: n, width: width, content: content).frame(width: width, alignment: .topLeading)
        case let .space(w):
            Color.clear.frame(width: width, height: node.row ? 1 : CGFloat(w) * ZapiackLayoutNode.rowPoints)
        case let .element(_, ref, rows):
            ElementView(ref: ref, content: content)
                .padding(2)
                .frame(width: width, alignment: .topLeading)
                .frame(minHeight: CGFloat(rows) * ZapiackLayoutNode.rowPoints, alignment: .topLeading)
        }
    }
}

@available(iOS 16.0, *)
struct ElementView: View {
    let ref: String
    let content: ZapiackLayoutContent

    private var ink: Color { content.dark ? .white : Color(red: 0.07, green: 0.07, blue: 0.07) }
    private var muted: Color { ink.opacity(0.7) }

    var body: some View {
        switch ref.first {
        case "t":
            Text(content.title).font(.headline).foregroundStyle(ink).lineLimit(2)
        case "b":
            Text(content.body ?? "").font(.subheadline).foregroundStyle(muted).lineLimit(4)
        case "i", "p":
            if let image = ref == "i" ? content.thumbnail : content.picture {
                Image(uiImage: image).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
            }
        case "a":
            if !content.hideActions, let i = Int(ref.dropFirst()), i < content.actions.count {
                Text(content.actions[i])
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(i == 0 ? (content.dark ? Color.black : Color.white) : ink)
                    .background(RoundedRectangle(cornerRadius: 10).fill(i == 0 ? ink : ink.opacity(0.14)))
            }
        case "l":
            if let i = Int(ref.dropFirst()), i < content.live.count {
                LiveItemView(item: content.live[i], content: content, ink: ink, muted: muted)
            }
        default:
            EmptyView()
        }
    }
}

@available(iOS 16.0, *)
struct LiveItemView: View {
    let item: ZapiackLiveItem
    let content: ZapiackLayoutContent
    let ink: Color
    let muted: Color

    var body: some View {
        let color = item.color.flatMap(Color.init(zapiackHex:)) ?? ink
        switch item.type {
        case "timer":
            if let end = content.timerEnd ?? item.timerEnd(received: content.received) {
                VStack(alignment: .leading, spacing: 2) {
                    if end <= Date() {
                        switch item.onEnd {
                        case "hide": EmptyView()
                        case "expired": Text(item.expiredText ?? "").font(.subheadline.weight(.semibold)).foregroundStyle(color)
                        default: Text(item.format == "mmss" ? "00:00" : "0:00:00").font(.title.bold()).monospacedDigit().foregroundStyle(color)
                        }
                    } else if item.format == "dhm" {
                        Text(end, style: .relative).font(.title3.bold()).foregroundStyle(color)
                    } else {
                        Text(timerInterval: Date()...end, countsDown: true).font(.title.bold()).monospacedDigit().foregroundStyle(color)
                    }
                    if let label = item.label, !label.isEmpty { Text(label).font(.caption.weight(.medium)).foregroundStyle(item.look == "pills" ? muted : color).lineLimit(2) }
                }
            }
        case "progress":
            if let steps = item.steps, steps.count >= 2 {
                let done = min(max(item.current ?? 0, 0), steps.count)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<steps.count, id: \.self) { i in Capsule().fill(i < done ? color : ink.opacity(0.18)).frame(height: 4) }
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<steps.count, id: \.self) { i in
                            Text(steps[i]).font(.caption2).foregroundStyle(muted).lineLimit(1).frame(maxWidth: .infinity, alignment: i == 0 ? .leading : i == steps.count - 1 ? .trailing : .center)
                        }
                    }
                }
            }
        case "counter":
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(item.value ?? "").font(.title3.bold()).foregroundStyle(color)
                Text(item.label ?? "").font(.footnote).foregroundStyle(muted)
            }
        case "badge":
            Text(item.text ?? "").font(.caption2.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(color)).foregroundStyle(.white)
        case "date":
            Text(item.value ?? "").font(.footnote).foregroundStyle(muted)
        default:
            EmptyView()
        }
    }
}

extension Color {
    /// A #RRGGBB colour, or nil.
    public init?(zapiackHex hex: String) {
        guard let rgb = Color.zapiackRGB(hex) else { return nil }
        self.init(red: rgb.r / 255, green: rgb.g / 255, blue: rgb.b / 255)
    }

    static func zapiackRGB(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard s.count == 7, s.hasPrefix("#"), let n = UInt32(s.dropFirst(), radix: 16) else { return nil }
        return (Double((n >> 16) & 0xFF), Double((n >> 8) & 0xFF), Double(n & 0xFF))
    }
}
#endif
