import Foundation

/// Loads/saves AppStore as a JSON document under Application Support.
/// Deliberately not SwiftData/Core Data: this is a solo, fast-iterating personal
/// project where the ability to `cat`/`jq`/hand-edit the store while tuning
/// prompts and schema matters more than relational query performance.
enum AppStorePersistence {
    static var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mailify", isDirectory: true)
        return base.appendingPathComponent("store.json")
    }

    static func load() -> AppStore {
        guard let data = try? Data(contentsOf: fileURL) else {
            return seeded(AppStore())
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var store = try decoder.decode(AppStore.self, from: data)
            store = migrate(store)
            return seeded(store)
        } catch {
            // Corrupt/unreadable — back up the bad file and start fresh rather than crash.
            let backupURL = fileURL.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: fileURL, to: backupURL)
            print("AppStorePersistence: failed to decode store.json (\(error)); backed up to \(backupURL.lastPathComponent) and starting fresh")
            return seeded(AppStore())
        }
    }

    @discardableResult
    static func save(_ store: AppStore) -> Bool {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(store)
            let tmp = fileURL.appendingPathExtension("tmp")
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: fileURL)
            }
            return true
        } catch {
            print("AppStorePersistence: save failed: \(error)")
            return false
        }
    }

    /// Seed default categories on first run only.
    private static func seeded(_ store: AppStore) -> AppStore {
        var store = store
        if store.categories.isEmpty {
            store.categories = Category.seedDefaults()
        }
        return store
    }

    private static func migrate(_ store: AppStore) -> AppStore {
        var store = store
        // if store.version < 2 { ...transform...; store.version = 2 }
        store.reassignOrphanedMessages(toAccountMatchingProvider: "gmail")
        return store
    }
}
