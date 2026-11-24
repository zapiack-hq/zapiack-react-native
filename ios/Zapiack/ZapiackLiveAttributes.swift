#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The Live Activity a Zapiack template push starts: a countdown, progress or counter that stays on the lock screen and in the
/// Dynamic Island and updates on its own. Zapiack fills it in from the template when it sends; the app only has to show it, by adding
/// `ZapiackLiveActivityWidget` to its widget extension.
///
/// The field names match what the Zapiack service sends (`liveContentState` on the server). Dates are plain numbers, seconds since
/// 1970, so they decode the same way whatever the decoder's date setting is.
@available(iOS 16.1, *)
public struct ZapiackLiveAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var body: String?
        /// The template's background, as #RRGGBB. Absent means the system's own lock screen look.
        public var background: String?

        public var timerEndsAt: Double?
        /// hmmss, mmss or dhm.
        public var timerFormat: String?
        public var timerColor: String?
        public var timerLabel: String?
        /// What happens when the timer ends: expired (show `expiredText`), hide (no timer) or keep (zeroes).
        public var timerOnEnd: String?
        public var expiredText: String?

        public var progressSteps: [String]?
        public var progressCurrent: Int?
        public var progressColor: String?

        public var counterValue: Double?
        public var counterLabel: String?

        public var badgeText: String?
        public var badgeColor: String?

        /// A grid design: the layout tree, its live elements and its button labels, so the activity draws the same layout.
        public var layout: String?
        public var live: String?
        public var actions: [String]?

        public init(title: String, body: String? = nil, background: String? = nil, timerEndsAt: Double? = nil, timerFormat: String? = nil, timerColor: String? = nil, timerLabel: String? = nil, timerOnEnd: String? = nil, expiredText: String? = nil, progressSteps: [String]? = nil, progressCurrent: Int? = nil, progressColor: String? = nil, counterValue: Double? = nil, counterLabel: String? = nil, badgeText: String? = nil, badgeColor: String? = nil) {
            self.title = title
            self.body = body
            self.background = background
            self.timerEndsAt = timerEndsAt
            self.timerFormat = timerFormat
            self.timerColor = timerColor
            self.timerLabel = timerLabel
            self.timerOnEnd = timerOnEnd
            self.expiredText = expiredText
            self.progressSteps = progressSteps
            self.progressCurrent = progressCurrent
            self.progressColor = progressColor
            self.counterValue = counterValue
            self.counterLabel = counterLabel
            self.badgeText = badgeText
            self.badgeColor = badgeColor
        }

        /// When the timer ends, if there is one.
        public var timerEnd: Date? { timerEndsAt.map { Date(timeIntervalSince1970: $0) } }
    }

    /// The Zapiack message and delivery this activity came from, so a tap can be reported.
    public var messageId: String
    public var deliveryId: String
    /// Where a tap takes the person: the template's link, already chosen for iOS.
    public var link: String?

    public init(messageId: String, deliveryId: String, link: String? = nil) {
        self.messageId = messageId
        self.deliveryId = deliveryId
        self.link = link
    }
}
#endif
