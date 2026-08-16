import Foundation

/// The seam that lets a second provider (e.g. iCloud, via IMAP) be added later
/// without touching SyncCoordinator, the UI, or the data model. Everything above
/// this protocol talks only in terms of MailProvider / Account / EmailMessage —
/// never provider-specific types.
protocol MailProvider {
    var providerID: String { get }
    func fetchNewMessages(accountID: UUID, since: Date?, filter: SyncSettings, pageToken: String?) async throws -> MailFetchPage
    func fetchMessageBody(messageID: String) async throws -> String
    func createDraft(inReplyTo threadID: String?, to: [String], subject: String, body: String) async throws -> String
    func markSynced(messageIDs: [String]) async throws
}

struct MailFetchPage {
    let messages: [EmailMessage]
    let nextPageToken: String?
}
