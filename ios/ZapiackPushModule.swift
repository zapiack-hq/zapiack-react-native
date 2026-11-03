import Foundation
import React
import UserNotifications

/// Connects the JavaScript API to the iOS library.
@objc(ZapiackPushModule)
final class ZapiackPushModule: RCTEventEmitter, UNUserNotificationCenterDelegate {
    private var hasListeners = false
    /// The tap that opened the app, kept until JavaScript asks for it, because it is not listening yet when the app starts.
    private static var initialTap: Tap?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    @objc override static func requiresMainQueueSetup() -> Bool { true }

    override func supportedEvents() -> [String]! { ["zapiackTap"] }
    override func startObserving() { hasListeners = true }
    override func stopObserving() { hasListeners = false }

    /// Call from the app delegate's `didRegisterForRemoteNotificationsWithDeviceToken`, which React Native does not forward.
    @objc static func didRegisterForRemoteNotifications(deviceToken: Data) {
        ZapiackPush.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
    }

    @objc func configure(_ options: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let key = options["appKey"] as? String, key.hasPrefix("pk_") else { return reject("invalid_key", "The app key must start with pk_", nil) }
        guard let group = options["appGroup"] as? String, !group.isEmpty else {
            return reject("invalid_group", "On iOS, appGroup is required: it is how the app and its notification extension share what they need", nil)
        }
        let base = (options["baseUrl"] as? String).flatMap(URL.init(string:)) ?? SharedState.defaultBaseUrl
        ZapiackPush.shared.configure(appKey: key, appGroup: group, baseUrl: base)
        resolve(nil)
    }

    @objc func requestPermission(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        Task { resolve(await ZapiackPush.shared.requestPermission()) }
    }

    @objc func installationId(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(ZapiackPush.shared.installationId)
    }

    @objc func login(_ userId: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        ZapiackPush.shared.login(userId)
        resolve(nil)
    }

    @objc func logout(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        ZapiackPush.shared.logout()
        resolve(nil)
    }

    @objc func addTags(_ tags: NSDictionary, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        ZapiackPush.shared.addTags(Self.values(tags))
        resolve(nil)
    }

    @objc func removeTags(_ keys: NSArray, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        ZapiackPush.shared.removeTags(keys.compactMap { $0 as? String })
        resolve(nil)
    }

    @objc func screen(_ name: String, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        ZapiackPush.shared.screen(name)
        resolve(nil)
    }

    @objc func track(_ name: String, properties: NSDictionary?, resolver resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(ZapiackPush.shared.track(name, properties: properties.map(Self.values)))
    }

    @objc func flush(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        Task { await ZapiackPush.shared.flush(); resolve(nil) }
    }

    @objc func initialTap(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(Self.initialTap.map(Self.map))
        Self.initialTap = nil
    }

    // MARK: Taps and notifications in front

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let tap = ZapiackPush.shared.handle(response) {
            if hasListeners { sendEvent(withName: "zapiackTap", body: Self.map(tap)) } else { Self.initialTap = tap }
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound, .badge]) } else { completionHandler([.alert, .sound, .badge]) }
    }

    // MARK: Helpers

    private static func values(_ raw: NSDictionary) -> [String: JSONValue] {
        (raw as? [String: Any] ?? [:]).mapValues(json)
    }

    private static func json(_ value: Any) -> JSONValue {
        switch value {
        case let v as NSNumber where CFGetTypeID(v) == CFBooleanGetTypeID(): return .bool(v.boolValue)
        case let v as NSNumber: return .number(v.doubleValue)
        case let v as String: return .string(v)
        case let v as [Any]: return .array(v.map(json))
        case let v as [String: Any]: return .object(v.mapValues(json))
        default: return .null
        }
    }

    private static func map(_ tap: Tap) -> [String: Any] {
        var out: [String: Any] = ["messageId": tap.messageId, "deliveryId": tap.deliveryId, "sessionId": tap.sessionId]
        if let a = tap.actionId { out["actionId"] = a }
        if let e = tap.event { out["event"] = e }
        if let l = tap.link { out["link"] = l.absoluteString }
        return out
    }
}
