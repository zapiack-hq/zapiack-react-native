import Foundation

/// Events waiting to be sent, one file each. The app and its extension both write here, and a file is only ever created whole
/// and removed whole, so neither can overwrite the other's events the way a shared list would.
public final class EventQueue {
    public static let maxEvents = 500
    public static let batchSize = 100
    private static let maxAge: TimeInterval = 6 * 24 * 3600

    private let directory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var sequence = 0

    public init(directory: URL) {
        self.directory = directory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    public func add(_ event: SdkEvent, now: Date = Date()) -> Bool {
        guard let data = try? JSONEncoder().encode(event) else { return false }
        lock.lock()
        sequence += 1
        let seq = sequence
        lock.unlock()
        // The time first so files list in the order events happened, then a counter for events in the same millisecond.
        let name = String(format: "%015ld-%06ld-%@.json", Int(now.timeIntervalSince1970 * 1000), seq, event.clientEventId)
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        trim()
        return true
    }

    public func pending() -> [(url: URL, event: SdkEvent)] {
        let urls = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url), let event = try? JSONDecoder().decode(SdkEvent.self, from: data) else {
                    // A file nothing can read is never going to be sent.
                    try? fileManager.removeItem(at: url)
                    return nil
                }
                return (url, event)
            }
    }

    public var count: Int { pending().count }

    /// Sends what is waiting, a batch at a time. Stops at the first batch that has to be retried, leaving it in place.
    @discardableResult
    public func flush(using api: SdkApi, now: Date = Date()) async -> Bool {
        discardExpired(now: now)
        while true {
            let batch = Array(pending().prefix(Self.batchSize))
            if batch.isEmpty { return true }
            switch await api.sendEvents(batch.map(\.event)) {
            case .retry:
                return false
            case .refused, .sent:
                // Sent, or refused for good: either way these events are finished with. Rejected ones are malformed, so dropped too.
                for item in batch { try? fileManager.removeItem(at: item.url) }
            }
        }
    }

    private func discardExpired(now: Date) {
        for item in pending() {
            guard let at = ISO8601DateFormatter.withFraction.date(from: item.event.at) else {
                try? fileManager.removeItem(at: item.url)
                continue
            }
            if now.timeIntervalSince(at) > Self.maxAge { try? fileManager.removeItem(at: item.url) }
        }
    }

    private func trim() {
        let all = pending()
        guard all.count > Self.maxEvents else { return }
        for item in all.prefix(all.count - Self.maxEvents) { try? fileManager.removeItem(at: item.url) }
    }
}

extension ISO8601DateFormatter {
    static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
