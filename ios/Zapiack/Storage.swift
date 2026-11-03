import Foundation

/// Where the app and its notification extension keep what they share.
public protocol KeyValueStorage: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}

public final class MemoryStorage: KeyValueStorage {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
    }
}

/// Backed by an App Group, which is what lets the app and its extension see the same values.
public final class SharedDefaultsStorage: KeyValueStorage {
    private let defaults: UserDefaults

    public init?(appGroup: String) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return nil }
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? { defaults.string(forKey: key) }

    public func set(_ value: String?, forKey key: String) {
        if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
    }
}

public struct ZapiackConfig: Equatable {
    public var appKey: String
    public var baseUrl: URL
    public var installationId: String

    public init(appKey: String, baseUrl: URL, installationId: String) {
        self.appKey = appKey
        self.baseUrl = baseUrl
        self.installationId = installationId
    }
}

/// What the app writes at start-up and the extension reads when a push arrives.
public enum SharedState {
    public static let defaultBaseUrl = URL(string: "https://api.zapiack.com/v1")!

    enum Key {
        static let appKey = "zapiack.appKey"
        static let baseUrl = "zapiack.baseUrl"
        static let installationId = "zapiack.installationId"
        static let session = "zapiack.session"
        static let user = "zapiack.user"
        static let tags = "zapiack.tags"
    }

    /// A UUID made on first use and kept: it identifies this install even when its push address changes.
    public static func installationId(in storage: KeyValueStorage) -> String {
        if let existing = storage.string(forKey: Key.installationId), !existing.isEmpty { return existing }
        let created = UUID().uuidString.lowercased()
        storage.set(created, forKey: Key.installationId)
        return created
    }

    public static func save(appKey: String, baseUrl: URL, in storage: KeyValueStorage) {
        storage.set(appKey, forKey: Key.appKey)
        storage.set(baseUrl.absoluteString, forKey: Key.baseUrl)
    }

    public static func load(from storage: KeyValueStorage) -> ZapiackConfig? {
        guard let appKey = storage.string(forKey: Key.appKey), appKey.hasPrefix("pk_"),
              let base = storage.string(forKey: Key.baseUrl), let baseUrl = URL(string: base)
        else { return nil }
        return ZapiackConfig(appKey: appKey, baseUrl: baseUrl, installationId: installationId(in: storage))
    }
}
