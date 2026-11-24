#if canImport(ActivityKit) && canImport(WidgetKit) && os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Draws Zapiack Live Activities. Add it to your widget extension's bundle:
///
/// ```swift
/// @main struct Widgets: WidgetBundle {
///     var body: some Widget { ZapiackLiveActivityWidget() }
/// }
/// ```
///
/// The countdown is the system's own timer text, so it ticks every second on the lock screen with no work from the app and no
/// further push. When the timer ends the activity goes stale, and it shows what the template asked for at the end.
@available(iOS 16.2, *)
public struct ZapiackLiveActivityWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: ZapiackLiveAttributes.self) { context in
            ActivityBody(state: context.state, stale: context.isStale)
                .activityBackgroundTint(context.state.background.flatMap(Color.init(hex:)))
                .widgetURL(context.attributes.link.flatMap(URL.init(string:)))
        } dynamicIsland: { context in
            let state = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(state: state, stale: stale, size: 22)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let label = state.timerLabel, !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                        ProgressSteps(state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: state.timerEnd != nil ? "timer" : "shippingbox")
                    .foregroundStyle(Color(hex: state.timerColor ?? state.progressColor ?? "") ?? .accentColor)
            } compactTrailing: {
                TimerText(state: state, stale: stale, size: 14)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(context.attributes.link.flatMap(URL.init(string:)))
        }
    }
}

/** A grid design draws its own layout; anything else, the standard Zapiack card. */
@available(iOS 16.2, *)
struct ActivityBody: View {
    let state: ZapiackLiveAttributes.ContentState
    let stale: Bool

    var body: some View {
        if let tree = ZapiackLayoutNode.parse(state.layout) {
            ZapiackLayoutView(
                node: tree,
                content: ZapiackLayoutContent(title: state.title, body: state.body, live: ZapiackLiveItem.parse(state.live), actions: state.actions ?? [], background: state.background, timerEnd: state.timerEnd)
            )
            .padding(14)
        } else {
            LockScreenView(state: state, stale: stale)
        }
    }
}

@available(iOS 16.2, *)
struct LockScreenView: View {
    let state: ZapiackLiveAttributes.ContentState
    let stale: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let badge = state.badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: state.badgeColor ?? "") ?? .green))
                        .foregroundStyle(.white)
                }
                Text(state.title).font(.headline).lineLimit(1)
                TimerText(state: state, stale: stale, size: 34)
                if let label = state.timerLabel, !label.isEmpty, !(stale && state.timerOnEnd == "expired") {
                    Text(label).font(.footnote.weight(.medium)).foregroundStyle(Color(hex: state.timerColor ?? "") ?? .secondary).lineLimit(2)
                } else if state.timerEnd == nil, let body = state.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                ProgressSteps(state: state)
                if let value = state.counterValue {
                    Text("\(value.formatted()) \(state.counterLabel ?? "")").font(.subheadline.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}

/// The countdown. Before the end it is the system timer; after, it is the template's ended state.
@available(iOS 16.2, *)
struct TimerText: View {
    let state: ZapiackLiveAttributes.ContentState
    let stale: Bool
    let size: CGFloat

    var body: some View {
        if let end = state.timerEnd {
            let color = Color(hex: state.timerColor ?? "") ?? .primary
            let over = stale || end <= Date()
            if over {
                switch state.timerOnEnd {
                case "hide": EmptyView()
                case "expired": Text(state.expiredText ?? "").font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(color)
                default: Text(state.timerFormat == "mmss" ? "00:00" : "0:00:00").font(.system(size: size, weight: .bold)).monospacedDigit().foregroundStyle(color)
                }
            } else if state.timerFormat == "dhm" {
                // Days are too long to tick by the second: the system writes how long is left and keeps it current.
                Text(end, style: .relative).font(.system(size: size * 0.7, weight: .bold)).foregroundStyle(color)
            } else {
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.system(size: size, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .multilineTextAlignment(.leading)
            }
        }
    }
}

@available(iOS 16.2, *)
struct ProgressSteps: View {
    let state: ZapiackLiveAttributes.ContentState

    var body: some View {
        if let steps = state.progressSteps, steps.count >= 2 {
            let done = min(max(state.progressCurrent ?? 0, 0), steps.count)
            let tint = Color(hex: state.progressColor ?? "") ?? .green
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule().fill(i < done ? tint : Color.secondary.opacity(0.25)).frame(height: 4)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Text(steps[i]).font(.caption2).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: i == 0 ? .leading : i == steps.count - 1 ? .trailing : .center)
                    }
                }
            }
        }
    }
}

extension Color {
    /// A #RRGGBB colour, or nil for anything else.
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces)
        guard s.count == 7, s.hasPrefix("#"), let n = UInt32(s.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((n >> 16) & 0xFF) / 255, green: Double((n >> 8) & 0xFF) / 255, blue: Double(n & 0xFF) / 255)
    }
}
#endif
