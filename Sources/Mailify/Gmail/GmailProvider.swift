import Foundation

struct GmailProvider: MailProvider {
    let providerID = "gmail"
    let account: Account
    private let client: GmailAPIClient

    init(account: Account, oauth: GmailOAuthManager) {
        self.account = account
        self.client = GmailAPIClient(account: account, oauth: oauth)
    }

    func fetchNewMessages(accountID: UUID, since: Date?, filter: SyncSettings, pageToken: String?) async throws -> MailFetchPage {
        let query = Self.buildQuery(since: since, filter: filter)
        let listResponse = try await client.listMessageRefs(query: query, pageToken: pageToken)
        var messages: [EmailMessage] = []
        for ref in listResponse.messages ?? [] {
            let full = try await client.getMessage(id: ref.id, format: "metadata")
            messages.append(Self.makeEmailMessage(from: full, accountID: accountID))
        }
        return MailFetchPage(messages: messages, nextPageToken: listResponse.nextPageToken)
    }

    func fetchMessageBody(messageID: String) async throws -> String {
        let full = try await client.getMessage(id: messageID, format: "full")
        return Self.extractBody(from: full.payload) ?? "<p>(no readable body)</p>"
    }

    func createDraft(inReplyTo threadID: String?, to: [String], subject: String, body: String) async throws -> String {
        let raw = Self.buildRawMessage(to: to, subject: subject, body: body)
        return try await client.createDraft(rawMessage: raw, threadId: threadID)
    }

    func markSynced(messageIDs: [String]) async throws {
        // No server-side bookkeeping needed for Gmail v1 — local lastSyncedAt is
        // sufficient. Hook kept so provider-agnostic callers work unchanged when
        // a future provider (e.g. IMAP-based iCloud) needs to ack a sync batch.
    }

    // MARK: - Conversion helpers

    /// Combines the `newer_than:Xd` date bound with optional inbox-tab
    /// category exclusions.
    ///
    /// `filter.windowDays == SyncSettings.sinceLastSync` (the default) means
    /// "no fixed ceiling": use exactly whatever's elapsed since `since`
    /// (the account's last successful sync), or `initialBackfillDefaultDays`
    /// when there's no previous sync yet (`since == nil`, a brand-new
    /// account's first backfill).
    ///
    /// Otherwise `filter.windowDays` is a fixed ceiling: on the initial
    /// backfill (`since == nil`) it's used directly; on incremental syncs the
    /// elapsed-since-last-sync window is used *unless* it's wider than
    /// `windowDays`, in which case it's clamped. Without this clamp, once an
    /// account had synced even once, changing the History picker would
    /// silently stop doing anything — every later sync computes its own
    /// (usually much smaller) elapsed window and would just ignore the
    /// user's setting.
    static func buildQuery(since: Date?, filter: SyncSettings) -> String {
        let elapsedDays = since.map { max(1, Int(Date().timeIntervalSince($0) / 86400) + 1) }

        let days: Int
        if filter.windowDays == SyncSettings.sinceLastSync {
            days = elapsedDays ?? SyncSettings.initialBackfillDefaultDays
        } else {
            days = min(elapsedDays ?? filter.windowDays, filter.windowDays)
        }

        var clauses = ["newer_than:\(days)d"]
        if filter.excludeSocial { clauses.append("-category:social") }
        if filter.excludePromotions { clauses.append("-category:promotions") }
        return clauses.joined(separator: " ")
    }

    private static func makeEmailMessage(from message: GmailMessage, accountID: UUID) -> EmailMessage {
        let headers = message.payload?.headers ?? []
        let from = header(headers, "From") ?? ""
        let (fromName, fromAddress) = parseFromHeader(from)
        let to = (header(headers, "To") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let subject = header(headers, "Subject") ?? "(no subject)"
        let receivedAt = message.internalDate.flatMap { Double($0) }
            .map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        let isRead = !(message.labelIds?.contains("UNREAD") ?? false)

        return EmailMessage(
            id: message.id,
            accountID: accountID,
            threadID: message.threadId,
            from: fromAddress,
            fromName: fromName,
            to: to,
            subject: subject,
            snippet: message.snippet ?? "",
            receivedAt: receivedAt,
            isRead: isRead
        )
    }

    private static func header(_ headers: [GmailHeader], _ name: String) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func parseFromHeader(_ raw: String) -> (name: String?, address: String) {
        // "Jane Doe <jane@example.com>" or bare "jane@example.com"
        if let ltIndex = raw.firstIndex(of: "<"), let gtIndex = raw.firstIndex(of: ">") {
            let name = raw[raw.startIndex..<ltIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            let address = String(raw[raw.index(after: ltIndex)..<gtIndex])
            return (name.isEmpty ? nil : name, address)
        }
        return (nil, raw.trimmingCharacters(in: .whitespaces))
    }

    private static func extractBody(from root: GmailMessagePart?) -> String? {
        guard let root else { return nil }
        if let htmlPart = findPart(mimeType: "text/html", in: root),
           let data = htmlPart.body?.data, let decoded = decodeBase64URL(data) {
            return decoded
        }
        if let plainPart = findPart(mimeType: "text/plain", in: root),
           let data = plainPart.body?.data, let decoded = decodeBase64URL(data) {
            return "<pre style=\"white-space:pre-wrap;font-family:-apple-system;\">\(escapeHTML(decoded))</pre>"
        }
        return nil
    }

    private static func findPart(mimeType: String, in part: GmailMessagePart) -> GmailMessagePart? {
        if part.mimeType == mimeType { return part }
        for sub in part.parts ?? [] {
            if let found = findPart(mimeType: mimeType, in: sub) { return found }
        }
        return nil
    }

    private static func decodeBase64URL(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Builds a minimal RFC 2822 message and base64url-encodes it for drafts.create.
    /// threadId (passed separately to the API call) is what places this in-thread
    /// within Gmail; this stays a fresh top-level message otherwise.
    private static func buildRawMessage(to: [String], subject: String, body: String) -> String {
        let message = """
        To: \(to.joined(separator: ", "))\r
        Subject: \(subject)\r
        Content-Type: text/plain; charset="UTF-8"\r
        \r
        \(body)
        """
        return Data(message.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
