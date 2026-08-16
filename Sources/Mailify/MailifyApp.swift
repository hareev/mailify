import SwiftUI
import CoreSpotlight

@main
struct MailifyApp: App {
    @StateObject private var appState = AppState()

    init() {
        NotificationManager.shared.requestAuthorizationIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.syncCoordinator)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    if let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        appState.selectMessage(id: id)
                    }
                }
        }

        MenuBarExtra(appState.pendingSuggestionCount > 0 ? "\(appState.pendingSuggestionCount) new suggestions" : "Mailify",
                     systemImage: appState.pendingSuggestionCount > 0 ? "envelope.badge" : "envelope") {
            if appState.pendingSuggestionCount > 0 {
                Text("\(appState.pendingSuggestionCount) new draft suggestion\(appState.pendingSuggestionCount == 1 ? "" : "s")")
                Divider()
            }

            Button("Sync Now") { Task { await appState.syncCoordinator.syncNow() } }
                .keyboardShortcut("r")

            Button("Open Mailify") { NSApp.activate(ignoringOtherApps: true) }
                .keyboardShortcut("o")

            Divider()

            Button("Quit Mailify") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
