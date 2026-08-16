import Foundation

/// Orchestrates "Sync Now" (manual button / menu item) and an optional periodic
/// timer. Owns the fetch → categorize → draft-suggest → persist → index pipeline,
/// plus the user-triggered accept/dismiss actions on suggestions.
@MainActor
final class SyncCoordinator: ObservableObject {
    @Published var isSyncing = false
    @Published var lastError: String?
    @Published var lastCategorizeSummary: String?

    private unowned let appState: AppState
    private var timer: Timer?

    init(appState: AppState) {
        self.appState = appState
        // Resume the persisted schedule on launch — the old design kept
        // "enabled" as a SyncCoordinator-only @Published flag that silently
        // reset to off on every relaunch, which defeats the point of
        // configuring a periodic schedule at all.
        applyPeriodicSchedule()
    }

    var periodicSyncEnabled: Bool { appState.store.syncSettings.periodicSyncEnabled }
    var periodicSyncIntervalMinutes: Int { appState.store.syncSettings.periodicSyncIntervalMinutes }

    func setPeriodicSyncEnabled(_ enabled: Bool) {
        appState.mutateStore { $0.syncSettings.periodicSyncEnabled = enabled }
        applyPeriodicSchedule()
    }

    func setPeriodicSyncIntervalMinutes(_ minutes: Int) {
        appState.mutateStore { $0.syncSettings.periodicSyncIntervalMinutes = minutes }
        applyPeriodicSchedule()
    }

    private func applyPeriodicSchedule() {
        timer?.invalidate()
        timer = nil
        guard appState.store.syncSettings.periodicSyncEnabled else { return }
        let interval = TimeInterval(appState.store.syncSettings.periodicSyncIntervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.syncNow() }
        }
    }

    func syncNow() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        lastCategorizeSummary = nil
        defer { isSyncing = false }

        guard let account = appState.store.accounts.first(where: { $0.provider == "gmail" }) else {
            lastError = "Connect Gmail in Settings → Accounts to sync."
            return
        }

        let provider = GmailProvider(account: account, oauth: appState.oauth)

        // Fetch and categorize are independent concerns, deliberately not
        // gated on each other: a fetch failure (transient Gmail API/token
        // hiccup) used to `return` here before categorization ever ran,
        // silently skipping categorization of mail already sitting in the
        // store from prior syncs. Now a fetch failure is recorded but
        // doesn't block categorizing what's already there.
        var staleIDs: [String] = []
        var fetchSucceeded = false
        do {
            staleIDs = try await fetchAndCacheMessages(account: account, provider: provider)
            fetchSucceeded = true
        } catch {
            lastError = error.localizedDescription
        }

        if let result = await runCategorization(account: account, provider: provider) {
            lastCategorizeSummary = Self.summary(for: result)
        }

        if fetchSucceeded {
            reindexSpotlight(staleIDs: staleIDs)
            appState.mutateStore { store in
                if let idx = store.accounts.firstIndex(where: { $0.id == account.id }) {
                    store.accounts[idx].lastSyncedAt = Date()
                }
            }
        }
    }

    /// Categorizes + drafts for whatever mail is already in the store —
    /// no Gmail fetch at all. Powers the toolbar "Categorize" button so it
    /// works even if a fetch would currently fail, and completes much
    /// faster than a full sync when you just want existing mail processed.
    func categorizeExistingMail() async {
        guard !isSyncing else { return }
        isSyncing = true
        lastError = nil
        lastCategorizeSummary = nil
        defer { isSyncing = false }

        guard let account = appState.store.accounts.first(where: { $0.provider == "gmail" }) else {
            lastError = "Connect Gmail in Settings → Accounts first."
            return
        }
        let provider = GmailProvider(account: account, oauth: appState.oauth)

        guard let result = await runCategorization(account: account, provider: provider) else {
            lastError = "Add an Anthropic API key in Settings → AI first."
            return
        }
        lastCategorizeSummary = Self.summary(for: result)
    }

    /// Shared by syncNow() and categorizeExistingMail(): reads the API key
    /// once, runs categorize+draft, fires notifications. Returns nil (no
    /// error set — the caller decides what that means for its own flow) if
    /// there's no API key configured.
    private func runCategorization(account: Account, provider: GmailProvider) async -> (categorized: Int, draftSuggestions: Int, categorySuggestions: Int, actionItems: Int)? {
        // Read the key once per run, not once per message: ClaudeAPIClient
        // used to re-read Keychain on every single categorize/draft call,
        // and repeated rapid reads of the same item from this app's ad-hoc-
        // signed binary were observed to intermittently fail. One read here,
        // passed through explicitly, avoids hitting that on every email.
        guard let apiKey = KeychainStore.get(service: KeychainKeys.anthropicService, account: KeychainKeys.anthropicAccount) else {
            return nil
        }
        let result = await categorizeAndDraft(account: account, provider: provider, apiKey: apiKey)

        if result.draftSuggestions > 0 {
            NotificationManager.shared.notifyNewSuggestions(count: result.draftSuggestions)
        }
        if result.categorySuggestions > 0 {
            NotificationManager.shared.notifyNewCategorySuggestions(count: result.categorySuggestions)
        }
        if result.actionItems > 0 {
            NotificationManager.shared.notifyNewActionItems(count: result.actionItems)
        }
        return result
    }

    private static func summary(for result: (categorized: Int, draftSuggestions: Int, categorySuggestions: Int, actionItems: Int)) -> String {
        "Categorized \(result.categorized) email\(result.categorized == 1 ? "" : "s") — " +
        "\(result.draftSuggestions) reply suggestion\(result.draftSuggestions == 1 ? "" : "s"), " +
        "\(result.categorySuggestions) new category suggestion\(result.categorySuggestions == 1 ? "" : "s"), " +
        "\(result.actionItems) action item\(result.actionItems == 1 ? "" : "s")."
    }

    // MARK: - Fetch

    private func fetchAndCacheMessages(account: Account, provider: GmailProvider) async throws -> [String] {
        var pageToken: String?
        var fetchedIDs = Set<String>()
        var allNew: [EmailMessage] = []

        repeat {
            let page = try await provider.fetchNewMessages(accountID: account.id, since: account.lastSyncedAt, filter: appState.store.syncSettings, pageToken: pageToken)
            for message in page.messages {
                fetchedIDs.insert(message.id)
                if !appState.store.messages.contains(where: { $0.id == message.id }) {
                    allNew.append(message)
                }
            }
            pageToken = page.nextPageToken
        } while pageToken != nil

        // Best-effort staleness detection: Gmail's `newer_than` query searches all
        // mail (not just inbox), so a previously-cached message whose receivedAt
        // falls inside the current query window but no longer comes back is very
        // likely permanently deleted. Rows are kept (isArchivedOrDeleted = true),
        // never removed, so suggestion history survives.
        let windowStart = account.lastSyncedAt ?? .distantPast
        var staleIDs: [String] = []

        appState.mutateStore { store in
            store.messages.append(contentsOf: allNew)
            for idx in store.messages.indices {
                let message = store.messages[idx]
                guard message.accountID == account.id, !message.isArchivedOrDeleted, message.receivedAt >= windowStart else { continue }
                if !fetchedIDs.contains(message.id) {
                    store.messages[idx].isArchivedOrDeleted = true
                    staleIDs.append(message.id)
                }
            }
        }

        return staleIDs
    }

    // MARK: - Categorize + draft-suggest

    private func categorizeAndDraft(account: Account, provider: GmailProvider, apiKey: String) async -> (categorized: Int, draftSuggestions: Int, categorySuggestions: Int, actionItems: Int) {
        let categories = appState.store.categories
        let toCategorize = appState.store.messages.filter {
            $0.accountID == account.id && $0.categoryID == nil && !$0.isArchivedOrDeleted
        }
        print("[Mailify] sync: \(categories.count) categories, \(toCategorize.count) messages to categorize")

        var categorizedCount = 0
        var newCategorySuggestionCount = 0
        var newActionItemCount = 0
        for message in toCategorize {
            do {
                let result = try await appState.claude.categorize(email: message, categories: categories, apiKey: apiKey)
                print("[Mailify] categorize \(message.id): categoryName=\(result.categoryName) needsReply=\(result.needsReply)")
                guard let matched = categories.first(where: { $0.name == result.categoryName }) else {
                    print("[Mailify] categorize \(message.id): '\(result.categoryName)' didn't match any known category name — skipped")
                    continue
                }
                categorizedCount += 1
                appState.mutateStore { store in
                    guard let idx = store.messages.firstIndex(where: { $0.id == message.id }) else { return }
                    store.messages[idx].categoryID = matched.id
                    store.messages[idx].categoryConfidence = result.confidence
                    store.messages[idx].needsReply = result.needsReply

                    switch CategorySuggestion.decide(
                        classifiedCategoryName: result.categoryName,
                        proposedRawName: result.proposedNewCategoryName,
                        existingCategories: store.categories,
                        existingSuggestions: store.categorySuggestions
                    ) {
                    case .ignore:
                        break
                    case .mergeInto(let suggestionID):
                        if let sIdx = store.categorySuggestions.firstIndex(where: { $0.id == suggestionID }),
                           !store.categorySuggestions[sIdx].sourceMessageIDs.contains(message.id) {
                            store.categorySuggestions[sIdx].sourceMessageIDs.append(message.id)
                        }
                    case .create(let name, let colorHex):
                        store.categorySuggestions.append(CategorySuggestion(
                            proposedName: name,
                            proposedColorHex: colorHex,
                            reasoning: result.proposedNewCategoryReasoning,
                            sourceMessageIDs: [message.id]
                        ))
                        newCategorySuggestionCount += 1
                    }

                    if let summary = result.actionItemSummary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty,
                       !store.actionItems.contains(where: { $0.emailMessageID == message.id }) {
                        store.actionItems.append(ActionItem(emailMessageID: message.id, summary: summary, dueDate: result.actionDueDate))
                        newActionItemCount += 1
                    }
                }
            } catch {
                lastError = error.localizedDescription
                print("[Mailify] categorize \(message.id) FAILED: \(error)")
                // One bad email shouldn't stop the whole sync.
            }
        }

        let needingDraft = appState.store.messages.filter { message in
            message.accountID == account.id && message.needsReply && !message.isArchivedOrDeleted &&
                !appState.store.suggestions.contains { $0.emailMessageID == message.id && $0.status != .dismissed }
        }

        var newSuggestionCount = 0
        for message in needingDraft {
            do {
                let bodyHTML: String
                if let cached = message.bodyHTML {
                    bodyHTML = cached
                } else {
                    bodyHTML = try await provider.fetchMessageBody(messageID: message.id)
                    appState.mutateStore { store in
                        if let idx = store.messages.firstIndex(where: { $0.id == message.id }) {
                            store.messages[idx].bodyHTML = bodyHTML
                        }
                    }
                }

                let draft = try await appState.claude.suggestDraft(email: message, bodyHTML: bodyHTML, apiKey: apiKey)
                let suggestion = DraftSuggestion(
                    emailMessageID: message.id,
                    suggestedSubject: draft.subject,
                    suggestedBody: draft.body,
                    reasoning: draft.reasoning
                )
                appState.mutateStore { store in
                    store.suggestions.append(suggestion)
                }
                newSuggestionCount += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        return (categorizedCount, newSuggestionCount, newCategorySuggestionCount, newActionItemCount)
    }

    private func reindexSpotlight(staleIDs: [String]) {
        let active = appState.store.messages.filter { !$0.isArchivedOrDeleted }
        SpotlightManager.shared.index(messages: active, categories: appState.store.categories)
        SpotlightManager.shared.deleteStaleItems(messageIDs: staleIDs)
    }

    // MARK: - Accept / Dismiss (user-triggered, outside the sync loop)

    func acceptSuggestion(_ suggestion: DraftSuggestion) async {
        guard let account = appState.store.accounts.first(where: { $0.provider == "gmail" }),
              let message = appState.store.messages.first(where: { $0.id == suggestion.emailMessageID }) else { return }

        let provider = GmailProvider(account: account, oauth: appState.oauth)
        do {
            let draftID = try await provider.createDraft(
                inReplyTo: message.threadID,
                to: [message.from],
                subject: suggestion.suggestedSubject,
                body: suggestion.suggestedBody
            )
            appState.mutateStore { store in
                guard let idx = store.suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
                store.suggestions[idx].status = .accepted
                store.suggestions[idx].gmailDraftID = draftID
                store.suggestions[idx].decidedAt = Date()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissSuggestion(_ suggestion: DraftSuggestion) {
        appState.mutateStore { store in
            guard let idx = store.suggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
            store.suggestions[idx].status = .dismissed
            store.suggestions[idx].decidedAt = Date()
        }
    }

    // MARK: - Category suggestion Accept / Dismiss (synchronous — no network
    // call, unlike draft-accept: creating a Category is purely local)

    func acceptCategorySuggestion(_ suggestion: CategorySuggestion) {
        appState.mutateStore { store in
            guard let idx = store.categorySuggestions.firstIndex(where: { $0.id == suggestion.id }),
                  store.categorySuggestions[idx].status == .pending else { return }

            let nextOrder = (store.categories.map(\.sortOrder).max() ?? -1) + 1
            let newCategory = Category(
                name: store.categorySuggestions[idx].proposedName,
                colorHex: store.categorySuggestions[idx].proposedColorHex,
                sortOrder: nextOrder
            )
            store.categories.append(newCategory)

            let sourceIDs = Set(store.categorySuggestions[idx].sourceMessageIDs)
            for messageIdx in store.messages.indices where sourceIDs.contains(store.messages[messageIdx].id) {
                store.messages[messageIdx].categoryID = newCategory.id
            }

            store.categorySuggestions[idx].status = .accepted
            store.categorySuggestions[idx].decidedAt = Date()
        }
    }

    func dismissCategorySuggestion(_ suggestion: CategorySuggestion) {
        appState.mutateStore { store in
            guard let idx = store.categorySuggestions.firstIndex(where: { $0.id == suggestion.id }) else { return }
            store.categorySuggestions[idx].status = .dismissed
            store.categorySuggestions[idx].decidedAt = Date()
        }
    }

    // MARK: - Action item Done / Dismiss (synchronous — local tracking only,
    // no calendar/reminders integration)

    func markActionItemDone(_ item: ActionItem) {
        appState.mutateStore { store in
            guard let idx = store.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
            store.actionItems[idx].status = .done
            store.actionItems[idx].decidedAt = Date()
        }
    }

    func dismissActionItem(_ item: ActionItem) {
        appState.mutateStore { store in
            guard let idx = store.actionItems.firstIndex(where: { $0.id == item.id }) else { return }
            store.actionItems[idx].status = .dismissed
            store.actionItems[idx].decidedAt = Date()
        }
    }
}
