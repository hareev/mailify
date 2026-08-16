import Foundation

struct Account: Codable, Identifiable, Equatable {
    let id: UUID
    var provider: String // "gmail" (future: "icloud")
    var emailAddress: String
    var displayName: String?
    var connectedAt: Date
    var lastSyncedAt: Date?

    init(id: UUID = UUID(), provider: String, emailAddress: String, displayName: String? = nil,
         connectedAt: Date = Date(), lastSyncedAt: Date? = nil) {
        self.id = id
        self.provider = provider
        self.emailAddress = emailAddress
        self.displayName = displayName
        self.connectedAt = connectedAt
        self.lastSyncedAt = lastSyncedAt
    }
}
