import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $appState.sidebarSelection)
        } content: {
            switch appState.sidebarSelection {
            case .settings:
                SettingsView()
            case .suggestions:
                SuggestionQueueView()
            case .categorySuggestions:
                CategorySuggestionQueueView()
            case .actionItems:
                ActionItemQueueView()
            case .allMail, .category, .none:
                MessageListView(selection: appState.sidebarSelection ?? .allMail, selectedMessageID: $appState.selectedMessageID)
            }
        } detail: {
            if let selectedMessageID = appState.selectedMessageID,
               let message = appState.store.messages.first(where: { $0.id == selectedMessageID }) {
                MessageDetailView(message: message)
            } else {
                ContentUnavailableView("Select a message", systemImage: "envelope.open")
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
    }
}
