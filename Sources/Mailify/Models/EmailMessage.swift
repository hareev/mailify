import Foundation

struct EmailMessage: Codable, Identifiable, Equatable {
    let id: String // provider-native message id (e.g. Gmail message id)
    var accountID: UUID
    var threadID: String
    var from: String
    var fromName: String?
    var to: [String]
    var subject: String
    var snippet: String
    var bodyHTML: String? // fetched lazily on open, then cached
    var receivedAt: Date
    var isRead: Bool
    var categoryID: UUID?
    var categoryConfidence: Double?
    var needsReply: Bool
    var isArchivedOrDeleted: Bool
    var lastSyncedAt: Date

    init(id: String, accountID: UUID, threadID: String, from: String, fromName: String? = nil,
         to: [String] = [], subject: String, snippet: String, bodyHTML: String? = nil,
         receivedAt: Date, isRead: Bool = false, categoryID: UUID? = nil,
         categoryConfidence: Double? = nil, needsReply: Bool = false,
         isArchivedOrDeleted: Bool = false, lastSyncedAt: Date = Date()) {
        self.id = id
        self.accountID = accountID
        self.threadID = threadID
        self.from = from
        self.fromName = fromName
        self.to = to
        self.subject = subject
        self.snippet = snippet
        self.bodyHTML = bodyHTML
        self.receivedAt = receivedAt
        self.isRead = isRead
        self.categoryID = categoryID
        self.categoryConfidence = categoryConfidence
        self.needsReply = needsReply
        self.isArchivedOrDeleted = isArchivedOrDeleted
        self.lastSyncedAt = lastSyncedAt
    }
}
