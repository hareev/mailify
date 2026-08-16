import Foundation
import AppKit

/// Root ObservableObject: owns the single source-of-truth AppStore, the Gmail
/// OAuth/agent services, and the SyncCoordinator that operates on all of it.
@MainActor
final class AppState: ObservableObject {
    @Published private(set) var store: AppStore
    @Published private(set) var pendingSuggestionCount: Int = 0
    @Published private(set) var pendingCategorySuggestionCount: Int = 0
    @Published private(set) var pendingActionItemCount: Int = 0
    @Published var sidebarSelection: SidebarSelection? = .allMail
    @Published var selectedMessageID: String?

    let oauth = GmailOAuthManager()
    let claude = ClaudeAgentService()
    lazy var syncCoordinator = SyncCoordinator(appState: self)

    init() {
        store = AppStorePersistence.load()
        updateDerivedState()
    }

    /// All store mutations go through here so persistence + derived UI state
    /// (dock badge, pending count) stay consistent automatically.
    func mutateStore(_ mutation: (inout AppStore) -> Void) {
        mutation(&store)
        AppStorePersistence.save(store)
        updateDerivedState()
    }

    var gmailAccount: Account? {
        store.accounts.first { $0.provider == "gmail" }
    }

    /// Used by Spotlight tap-through and the menu bar's "New"/select actions —
    /// ContentView is a value type re-created by SwiftUI, so external triggers
    /// route through this published state on AppState instead.
    func selectMessage(id: String) {
        guard let message = store.messages.first(where: { $0.id == id }) else { return }
        sidebarSelection = message.categoryID.map { SidebarSelection.category($0) } ?? .allMail
        selectedMessageID = id
    }

    func connectGmail() async throws {
        let result = try await oauth.connect()
        KeychainStore.set(result.accessToken, service: KeychainKeys.gmailAccessTokenService(email: result.email), account: KeychainKeys.gmailAccount)
        KeychainStore.set(result.refreshToken, service: KeychainKeys.gmailRefreshTokenService(email: result.email), account: KeychainKeys.gmailAccount)
        KeychainStore.set(String(result.expiresAt.timeIntervalSince1970), service: KeychainKeys.gmailExpiryService(email: result.email), account: KeychainKeys.gmailAccount)

        mutateStore { store in
            if let idx = store.accounts.firstIndex(where: { $0.provider == "gmail" }) {
                store.accounts[idx].emailAddress = result.email
                store.accounts[idx].connectedAt = Date()
            } else {
                store.accounts.append(Account(provider: "gmail", emailAddress: result.email))
            }
            // Heals immediately if this connect just created a fresh account
            // id after an earlier disconnect — see reassignOrphanedMessages's
            // doc comment. Also covers reconnecting mid-session, when
            // AppStorePersistence's load-time migration won't run again.
            store.reassignOrphanedMessages(toAccountMatchingProvider: "gmail")
        }
    }

    func disconnectGmail() {
        guard let account = gmailAccount else { return }
        KeychainStore.delete(service: KeychainKeys.gmailAccessTokenService(email: account.emailAddress), account: KeychainKeys.gmailAccount)
        KeychainStore.delete(service: KeychainKeys.gmailRefreshTokenService(email: account.emailAddress), account: KeychainKeys.gmailAccount)
        KeychainStore.delete(service: KeychainKeys.gmailExpiryService(email: account.emailAddress), account: KeychainKeys.gmailAccount)
        mutateStore { store in
            store.accounts.removeAll { $0.provider == "gmail" }
        }
    }

    private func updateDerivedState() {
        pendingSuggestionCount = store.pendingSuggestionCount
        pendingCategorySuggestionCount = store.pendingCategorySuggestionCount
        pendingActionItemCount = store.pendingActionItemCount
        // The dock badge is a coarse "something needs attention" signal —
        // the sidebar's separate badges preserve which queue has what, so
        // summing avoids a mailbox with only pending category suggestions
        // or action items showing no dock badge at all.
        let totalBadgeCount = pendingSuggestionCount + pendingCategorySuggestionCount + pendingActionItemCount
        NSApp.dockTile.badgeLabel = totalBadgeCount > 0 ? "\(totalBadgeCount)" : nil
    }
}
