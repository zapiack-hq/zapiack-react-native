import Foundation

/// The decisions the app and the extension share, kept apart from UIKit so they can be tested.
public enum Processing {
    /// The actions in a notification response that mean "the user did not choose anything".
    public static let dismissIdentifier = "com.apple.UNNotificationDismissActionIdentifier"
    public static let defaultIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

    /// A picture is only fetched from a secure address.
    public static func imageURL(from block: PushBlock) -> URL? {
        guard let raw = block.i, let url = URL(string: raw), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Only links the app can route are handed over; a script address is never one.
    public static func link(from raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else { return nil }
        if ["javascript", "data", "file", "vbscript"].contains(scheme) { return nil }
        return url
    }

    public static func receivedEvent(for block: PushBlock, at date: Date = Date()) -> SdkEvent {
        SdkEvent(type: .received, deliveryId: block.d, at: date)
    }

    /// Turns a tap into the events to report and the session it opens. `actionIdentifier` is the system's, or a button's id.
    public static func tap(block: PushBlock, actionIdentifier: String, at date: Date = Date()) -> (tap: Tap, session: ActiveSession, events: [SdkEvent])? {
        if actionIdentifier == dismissIdentifier { return nil }
        let sessionId = UUID().uuidString.lowercased()
        let isDefault = actionIdentifier == defaultIdentifier
        let action = isDefault ? nil : block.a?.first { $0.id == actionIdentifier }
        // A button this push did not declare is not reported as one.
        if !isDefault && action == nil { return nil }

        let event: SdkEvent
        if let action {
            event = SdkEvent(type: .action, deliveryId: block.d, sessionId: sessionId, name: action.event, actionId: action.id, at: date)
        } else {
            event = SdkEvent(type: .clicked, deliveryId: block.d, sessionId: sessionId, name: block.e, at: date)
        }
        let session = ActiveSession(
            sessionId: sessionId,
            deliveryId: block.d,
            messageId: block.m,
            startedAt: date,
            windowMinutes: block.t?.w ?? 30,
            screens: block.t?.s ?? false
        )
        let tap = Tap(
            messageId: block.m,
            deliveryId: block.d,
            sessionId: sessionId,
            actionId: action?.id,
            event: action?.event ?? block.e,
            link: link(from: action?.link ?? block.l)
        )
        return (tap, session, [event])
    }
}
