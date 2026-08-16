import SwiftUI

struct CategorySuggestionQueueView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncCoordinator: SyncCoordinator

    private var pending: [CategorySuggestion] {
        appState.store.categorySuggestions
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView(
                    "No category suggestions",
                    systemImage: "folder.badge.plus",
                    description: Text("When mail doesn't fit any existing category well, proposed new categories will show up here for you to accept or dismiss.")
                )
            } else {
                List(pending) { suggestion in
                    CategorySuggestionRow(
                        suggestion: suggestion,
                        sourceMessages: appState.store.messages.filter { suggestion.sourceMessageIDs.contains($0.id) },
                        onAccept: { syncCoordinator.acceptCategorySuggestion(suggestion) },
                        onDismiss: { syncCoordinator.dismissCategorySuggestion(suggestion) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("New Categories")
    }
}

private struct CategorySuggestionRow: View {
    let suggestion: CategorySuggestion
    let sourceMessages: [EmailMessage]
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: suggestion.proposedColorHex)).frame(width: 10, height: 10)
                Text(suggestion.proposedName).font(.headline)
                Spacer()
                Text("\(suggestion.sourceMessageIDs.count) email\(suggestion.sourceMessageIDs.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let reasoning = suggestion.reasoning {
                Text(reasoning)
                    .font(.caption).italic()
                    .foregroundStyle(.secondary)
            }
            ForEach(sourceMessages.prefix(3)) { message in
                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack {
                Spacer()
                Button("Dismiss", role: .cancel) { onDismiss() }
                Button("Accept → Create Category") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}
