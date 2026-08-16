import Foundation

/// User-configurable sync scope. `windowDays` bounds how far back the initial
/// backfill for an account looks (subsequent incremental syncs are already
/// bounded by lastSyncedAt regardless of this value). The two `exclude*`
/// flags map to Gmail's inbox-tab categories and are applied as query
/// filters, not as a filter on already-synced local data — see MailProvider.
/// `periodicSync*` are persisted (unlike the old SyncCoordinator-only
/// `@Published` flag) so the schedule survives a relaunch.
struct SyncSettings: Codable, Equatable {
    var windowDays: Int = 30
    var excludeSocial: Bool = false
    var excludePromotions: Bool = false
    var periodicSyncEnabled: Bool = false
    var periodicSyncIntervalMinutes: Int = 60

    // Explicit memberwise init: a custom init(from:) below suppresses Swift's
    // automatic memberwise-init synthesis, so this has to be spelled out or
    // every existing `SyncSettings(windowDays:...)` call site breaks.
    init(
        windowDays: Int = 30,
        excludeSocial: Bool = false,
        excludePromotions: Bool = false,
        periodicSyncEnabled: Bool = false,
        periodicSyncIntervalMinutes: Int = 60
    ) {
        self.windowDays = windowDays
        self.excludeSocial = excludeSocial
        self.excludePromotions = excludePromotions
        self.periodicSyncEnabled = periodicSyncEnabled
        self.periodicSyncIntervalMinutes = periodicSyncIntervalMinutes
    }

    /// Custom decoding, same reasoning as AppStore's: a store.json written
    /// before `periodicSync*` existed must still load, with those fields
    /// defaulted, instead of failing this nested decode and taking down the
    /// whole AppStore load with it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowDays = try container.decodeIfPresent(Int.self, forKey: .windowDays) ?? 30
        excludeSocial = try container.decodeIfPresent(Bool.self, forKey: .excludeSocial) ?? false
        excludePromotions = try container.decodeIfPresent(Bool.self, forKey: .excludePromotions) ?? false
        periodicSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .periodicSyncEnabled) ?? false
        periodicSyncIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .periodicSyncIntervalMinutes) ?? 60
    }

    static let availableWindowDays = [7, 30, 60]

    /// 15 min, 1 hour, 8 hours, 24 hours.
    static let availableSyncIntervalMinutes = [15, 60, 480, 1440]

    static func label(forIntervalMinutes minutes: Int) -> String {
        switch minutes {
        case 15: return "Every 15 minutes"
        case 60: return "Every hour"
        case 480: return "Every 8 hours"
        case 1440: return "Every 24 hours"
        default: return minutes < 60 ? "Every \(minutes) minutes" : "Every \(minutes / 60) hours"
        }
    }
}
