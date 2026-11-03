import Foundation

public protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public struct EventsResult: Decodable, Equatable {
    public struct Rejection: Decodable, Equatable {
        public var index: Int
        public var reason: String
    }

    public var accepted: Int
    public var ignored: Int
    public var rejected: [Rejection]
}

public enum SendOutcome: Equatable {
    case sent(EventsResult)
    /// The request did not get through, or the service was busy: keep the events and try again.
    case retry
    /// The request was refused for good: repeating it will be refused again.
    case refused(status: Int)
}

public struct DeviceRegistration: Encodable {
    public var installationId: String
    public var platform: String
    public var token: String
    public var externalUserId: String??
    public var tags: [String: JSONValue]?
    public var permission: String?
    public var environment: String?
    public var appVersion: String?

    public init(installationId: String, platform: String = "ios", token: String, externalUserId: String?? = nil, tags: [String: JSONValue]? = nil, permission: String? = nil, environment: String? = nil, appVersion: String? = nil) {
        self.installationId = installationId
        self.platform = platform
        self.token = token
        self.externalUserId = externalUserId
        self.tags = tags
        self.permission = permission
        self.environment = environment
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case installationId, platform, token, externalUserId, tags, permission, environment, appVersion
    }

    // An absent user leaves the link alone, a string links it, and an explicit null unlinks it, so all three are kept apart.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(installationId, forKey: .installationId)
        try c.encode(platform, forKey: .platform)
        try c.encode(token, forKey: .token)
        switch externalUserId {
        case .none: break
        case .some(.none): try c.encodeNil(forKey: .externalUserId)
        case .some(.some(let id)): try c.encode(id, forKey: .externalUserId)
        }
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(permission, forKey: .permission)
        try c.encodeIfPresent(environment, forKey: .environment)
        try c.encodeIfPresent(appVersion, forKey: .appVersion)
    }
}

public struct SdkApi {
    private let config: ZapiackConfig
    private let transport: HTTPTransport

    public init(config: ZapiackConfig, transport: HTTPTransport = URLSessionTransport()) {
        self.config = config
        self.transport = transport
    }

    func request(_ path: String, method: String, body: Data?) -> URLRequest {
        var url = config.baseUrl
        for part in ["push", "sdk", path] { url.appendPathComponent(part) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.appKey, forHTTPHeaderField: "X-Zapiack-App-Key")
        return request
    }

    public func register(_ registration: DeviceRegistration) async throws {
        let body = try JSONEncoder().encode(registration)
        let (_, response) = try await transport.send(request("devices", method: "PUT", body: body))
        guard (200..<300).contains(response.statusCode) else { throw ZapiackError.registrationFailed(status: response.statusCode) }
    }

    public func sendEvents(_ events: [SdkEvent]) async -> SendOutcome {
        guard let body = try? JSONEncoder().encode(["events": events]) else { return .refused(status: 0) }
        do {
            let (data, response) = try await transport.send(request("events", method: "POST", body: body))
            if (200..<300).contains(response.statusCode) {
                let result = (try? JSONDecoder().decode(EventsResult.self, from: data)) ?? EventsResult(accepted: events.count, ignored: 0, rejected: [])
                return .sent(result)
            }
            // Busy or down: try again. Anything else (a wrong key, a bad request) will not improve by repeating it.
            if response.statusCode == 429 || response.statusCode == 408 || response.statusCode >= 500 { return .retry }
            return .refused(status: response.statusCode)
        } catch {
            return .retry
        }
    }
}

public enum ZapiackError: Error, Equatable {
    case notConfigured
    case registrationFailed(status: Int)
}
