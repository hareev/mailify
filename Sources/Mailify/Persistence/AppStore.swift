import Foundation

struct AppStore: Codable {
    var version: Int = 1
    var accounts: [Account] = []
    var categories: [Category] = []
    var messages: [EmailMessage] = []
    var suggestions: [DraftSuggestion] = []
    var syncSettings: SyncSettings = SyncSettings()
    var categorySuggestions: [CategorySuggestion] = []
    var actionItems: [ActionItem] = []

    var pendingSuggestionCount: Int {
        suggestions.filter { $0.status == .pending }.count
    }

    var pendingCategorySuggestionCount: Int {
        categorySuggestions.filter { $0.status == .pending }.count
    }

    var pendingActionItemCount: Int {
        actionItems.filter { $0.status == .pending }.count
    }

    /// Mail that's been fetched but never successfully categorized — what
    /// the "Categorize" toolbar button and Settings → Sync act on.
    var uncategorizedMessageCount: Int {
        messages.filter { $0.categoryID == nil && !$0.isArchivedOrDeleted }.count
    }

    /// Per-category needs-reply count (active mail only) — the sidebar's
    /// importance sort/badge signal. Single pass over messages, O(n) not
    /// O(n × categories).
    var needsReplyCountByCategory: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for message in messages where message.needsReply && !message.isArchivedOrDeleted {
            guard let categoryID = message.categoryID else { continue }
            counts[categoryID, default: 0] += 1
        }
        return counts
    }

    init() {}

    /// Custom decoding so older store.json files (written before a field was
    /// added) load with that field defaulted instead of being treated as
    /// corrupt and backed up/discarded by AppStorePersistence.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        accounts = try container.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        messages = try container.decodeIfPresent([EmailMessage].self, forKey: .messages) ?? []
        suggestions = try container.decodeIfPresent([DraftSuggestion].self, forKey: .suggestions) ?? []
        syncSettings = try container.decodeIfPresent(SyncSettings.self, forKey: .syncSettings) ?? SyncSettings()
        categorySuggestions = try container.decodeIfPresent([CategorySuggestion].self, forKey: .categorySuggestions) ?? []
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
    }

    /// Reassigns any message whose `accountID` doesn't match a currently
    /// known account to the account for `provider`. Disconnecting Gmail
    /// (`AppState.disconnectGmail`) removes its account row entirely, so
    /// reconnecting — even to the exact same mailbox — creates a fresh
    /// `Account.id` via `AppState.connectGmail`'s "no existing row" branch.
    /// Every message synced before that point is left pointing at an
    /// account id that no longer exists, which silently excludes them from
    /// every account-scoped filter (categorization, draft-suggestion,
    /// staleness detection) forever — this is exactly what happened to a
    /// real user's 153-message backlog after two reconnects. Self-healing
    /// on every load/reconnect, rather than trying to prevent the id from
    /// ever changing, stays correct no matter how many times it happens or
    /// whether it happens mid-session vs. across a relaunch.
    mutating func reassignOrphanedMessages(toAccountMatchingProvider provider: String) {
        guard let currentAccountID = accounts.first(where: { $0.provider == provider })?.id else { return }
        let knownAccountIDs = Set(accounts.map(\.id))
        for idx in messages.indices where !knownAccountIDs.contains(messages[idx].accountID) {
            messages[idx].accountID = currentAccountID
        }
    }
}
