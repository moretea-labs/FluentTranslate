#if os(macOS)
import Foundation

enum StoragePaths {
    static let applicationSupport: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("TranslateDesk", isDirectory: true)
    }()

    static let configuration = applicationSupport.appendingPathComponent("config.json")
    static let cache = applicationSupport.appendingPathComponent("translation-cache.json")
    static let pronunciationCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        .appendingPathComponent("TranslateDesk/Pronunciations", isDirectory: true)
}
#endif
