import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif


/// Push notifications for an app: ask permission, register this install, and follow what happens after a tap.
public final class ZapiackPush {
    public static let shared = ZapiackPush()

    private var client: PushClient?
    private var appVersion: String?

    private init() {}

    /// Call once at launch, before anything else. `appGroup` is the App Group shared with the notification extension.
    public func configure(appKey: String, appGroup: String, baseUrl: URL = SharedState.defaultBaseUrl) {
        guard appKey.hasPrefix("pk_"), let storage = SharedDefaultsStorage(appGroup: appGroup),
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            assertionFailure("ZapiackPush: the app key must start with pk_ and the App Group must be enabled for this target")
            return
        }
        SharedState.save(appKey: appKey, baseUrl: baseUrl, in: storage)
        guard let config = SharedState.load(from: storage) else { return }
        client = PushClient(config: config, storage: storage, queue: EventQueue(directory: container.appendingPathComponent("zapiack-events", isDirectory: true)))
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        Task { await self.syncRegistration() }
        Task { await self.client?.flush() }
    }

    /// The identifier that ties this install to the service.
    public var installationId: String? { client?.config.installationId }

    /// Shows the system permission prompt, then registers for push when it is allowed.
    @discardableResult
    public func requestPermission(options: UNAuthorizationOptions = [.alert, .badge, .sound]) async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: options)) ?? false
        if granted { await registerForRemoteNotifications() }
        await syncRegistration()
        return granted
    }

    /// Hand over the token from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        client?.setDeviceToken(deviceToken)
        Task { await self.syncRegistration() }
    }

    public func login(_ userId: String) {
        client?.login(userId)
        Task { await self.syncRegistration() }
    }

    public func logout() {
        client?.logout()
        Task { await self.syncRegistration() }
    }

    public func addTags(_ tags: [String: JSONValue]) {
        client?.addTags(tags)
        Task { await self.syncRegistration() }
    }

    public func removeTags(_ keys: [String]) {
        client?.removeTags(keys)
        Task { await self.syncRegistration() }
    }

    /// Call from `userNotificationCenter(_:didReceive:withCompletionHandler:)`. Returns what was tapped so the app can route, or
    /// nil when the notification is not from Zapiack or was only dismissed.
    @discardableResult
    public func handle(_ response: UNNotificationResponse) -> Tap? {
        guard let client else { return nil }
        let tap = client.handleResponse(userInfo: response.notification.request.content.userInfo, actionIdentifier: response.actionIdentifier)
        if tap != nil { Task { await client.flush() } }
        return tap
    }

    /// A screen the user reached, credited to the push they tapped while its window is open.
    public func screen(_ name: String) { client?.screen(name) }

    /// A named goal or event, credited to the push they tapped while its window is open.
    /// Returns whether there was a tapped push to credit it to.
    @discardableResult
    public func track(_ name: String, properties: [String: JSONValue]? = nil) -> Bool {
        let credited = client?.track(name, properties: properties) ?? false
        Task { await self.client?.flush() }
        return credited
    }

    /// Sends anything waiting. Call when the app comes to the foreground.
    public func flush() async { await client?.flush() }

    private func syncRegistration() async {
        guard let client, client.deviceToken != nil else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let permission: String?
        switch settings.authorizationStatus {
        case .authorized, .ephemeral: permission = "granted"
        case .provisional: permission = "provisional"
        case .denied: permission = "denied"
        default: permission = nil
        }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        try? await client.register(permission: permission, environment: environment, appVersion: appVersion)
    }

    @MainActor
    private func registerForRemoteNotifications() {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}
