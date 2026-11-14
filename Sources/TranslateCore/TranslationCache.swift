import Foundation

public actor TranslationCache {
    private var memory: [String: TranslationResult] = [:]
    private let fileURL: URL?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var loaded = false
    private var pendingPersistTask: Task<Void, Never>?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL
    }

    deinit {
        pendingPersistTask?.cancel()
    }

    public func result(for key: String) -> TranslationResult? {
        loadIfNeeded()
        guard var result = memory[key] else { return nil }
        result.fromCache = true
        result.latencyMilliseconds = 0
        return result
    }

    public func store(_ result: TranslationResult, for key: String) {
        loadIfNeeded()
        memory[key] = result
        schedulePersist()
    }

    public func clear() {
        memory.removeAll()
        schedulePersist(delayNanoseconds: 0)
    }

    public static func key(request: TranslationRequest, providerID: String) -> String {
        [providerID, request.sourceLanguage, request.targetLanguage, request.text, request.context ?? ""]
            .joined(separator: "\u{001F}")
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([String: TranslationResult].self, from: data) else {
            return
        }
        memory = decoded
    }

    private func schedulePersist(delayNanoseconds: UInt64 = 180_000_000) {
        guard let fileURL else { return }
        let snapshot = memory
        pendingPersistTask?.cancel()
        pendingPersistTask = Task.detached(priority: .utility) {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(snapshot)
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: fileURL, options: [.atomic])
            } catch {
                // Cache persistence must never delay or block translation output.
            }
        }
    }
}
