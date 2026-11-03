import Foundation

/// The state and rules behind the app-side SDK, without anything that needs a running app.
public final class PushClient {
    public let config: ZapiackConfig
    public let queue: EventQueue
    private let storage: KeyValueStorage
    private let api: SdkApi
    private let now: () -> Date
    private let lock = NSLock()
    private var previousScreen: String?

    public init(config: ZapiackConfig, storage: KeyValueStorage, queue: EventQueue, transport: HTTPTransport = URLSessionTransport(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.storage = storage
        self.queue = queue
        self.api = SdkApi(config: config, transport: transport)
        self.now = now
    }

    // MARK: Device

    public var deviceToken: String? { storage.string(forKey: "zapiack.token") }

    public func setDeviceToken(_ data: Data) {
        storage.set(data.map { String(format: "%02x", $0) }.joined(), forKey: "zapiack.token")
    }

    private var tags: [String: JSONValue] {
        get {
            guard let raw = storage.string(forKey: SharedState.Key.tags), let data = raw.data(using: .utf8),
                  let value = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [:] }
            return value
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            storage.set(data.flatMap { String(data: $0, encoding: .utf8) }, forKey: SharedState.Key.tags)
        }
    }

    /// "set:<id>" or "clear": a change of user that has not reached the service yet.
    private var pendingUser: String? {
        get { storage.string(forKey: SharedState.Key.user) }
        set { storage.set(newValue, forKey: SharedState.Key.user) }
    }

    public func login(_ userId: String) { pendingUser = "set:\(userId)" }
    public func logout() { pendingUser = "clear" }

    public func addTags(_ new: [String: JSONValue]) {
        var current = tags
        for (key, value) in new { current[key] = value }
        tags = current
    }

    public func removeTags(_ keys: [String]) {
        var current = tags
        for key in keys { current.removeValue(forKey: key) }
        tags = current
    }

    /// Tells the service about this install. Sent on every start; a change of user goes once and is then forgotten.
    public func register(permission: String?, environment: String, appVersion: String?) async throws {
        guard let token = deviceToken else { return }
        let user = pendingUser
        var external: String?? = nil
        if let user {
            external = user == "clear" ? .some(nil) : .some(String(user.dropFirst(4)))
        }
        let registration = DeviceRegistration(
            installationId: config.installationId,
            token: token,
            externalUserId: external,
            tags: tags.isEmpty ? nil : tags,
            permission: permission,
            environment: environment,
            appVersion: appVersion
        )
        try await api.register(registration)
        // Only forget the change if it is still the one that was sent.
        if pendingUser == user { pendingUser = nil }
    }

    // MARK: Taps and what follows

    public var activeSession: ActiveSession? {
        get {
            guard let raw = storage.string(forKey: SharedState.Key.session), let data = raw.data(using: .utf8),
                  let session = try? JSONDecoder().decode(ActiveSession.self, from: data) else { return nil }
            return session.isOpen(at: now()) ? session : nil
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            storage.set(data.flatMap { String(data: $0, encoding: .utf8) }, forKey: SharedState.Key.session)
        }
    }

    /// Reports a tap and opens its window. Returns what the app needs to route, or nil when it was a dismissal or not ours.
    public func handleResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) -> Tap? {
        guard let block = PushBlock(userInfo: userInfo),
              let result = Processing.tap(block: block, actionIdentifier: actionIdentifier, at: now()) else { return nil }
        // Last tap wins: a new tap replaces the window of the one before it.
        activeSession = result.session
        lock.lock(); previousScreen = nil; lock.unlock()
        for event in result.events { queue.add(event, now: now()) }
        return result.tap
    }

    /// A screen the user reached. Only recorded while a tapped push's window is open and the push asked for screens.
    public func screen(_ name: String) {
        guard let session = activeSession, session.screens else { return }
        lock.lock()
        let from = previousScreen
        previousScreen = name
        lock.unlock()
        queue.add(SdkEvent(type: .screen, deliveryId: session.deliveryId, sessionId: session.sessionId, name: name, previousScreen: from, at: now()), now: now())
    }

    /// A named thing the user did. Credited to the tapped push while its window is open; otherwise there is nothing to credit.
    /// Returns whether there was a tapped push to credit it to.
    @discardableResult
    public func track(_ name: String, properties: [String: JSONValue]? = nil) -> Bool {
        guard let session = activeSession else { return false }
        queue.add(SdkEvent(type: .custom, deliveryId: session.deliveryId, sessionId: session.sessionId, name: name, properties: properties, at: now()), now: now())
        return true
    }

    @discardableResult
    public func flush() async -> Bool {
        await queue.flush(using: api, now: now())
    }
}
