import SwiftUI

struct SuggestionQueueView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var syncCoordinator: SyncCoordinator
    @State private var decidingIDs: Set<UUID> = []

    private var pending: [DraftSuggestion] {
        appState.store.suggestions
            .filter { $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if pending.isEmpty {
                ContentUnavailableView("No suggestions", systemImage: "sparkles", description: Text("Drafted replies will show up here for you to accept or dismiss. Nothing is ever sent automatically."))
            } else {
                List(pending) { suggestion in
                    SuggestionRow(
                        suggestion: suggestion,
                        message: appState.store.messages.first { $0.id == suggestion.emailMessageID },
                        isDeciding: decidingIDs.contains(suggestion.id),
                        onAccept: { await accept(suggestion) },
                        onDismiss: { dismiss(suggestion) }
                    )
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Suggestions")
    }

    private func accept(_ suggestion: DraftSuggestion) async {
        decidingIDs.insert(suggestion.id)
        defer { decidingIDs.remove(suggestion.id) }
        await syncCoordinator.acceptSuggestion(suggestion)
    }

    private func dismiss(_ suggestion: DraftSuggestion) {
        syncCoordinator.dismissSuggestion(suggestion)
    }
}

private struct SuggestionRow: View {
    let suggestion: DraftSuggestion
    let message: EmailMessage?
    let isDeciding: Bool
    let onAccept: () async -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let message {
                Text("Re: \(message.subject.isEmpty ? "(no subject)" : message.subject)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(suggestion.suggestedSubject)
                .font(.headline)
            Text(suggestion.suggestedBody)
                .font(.body)
                .lineLimit(6)
            if let reasoning = suggestion.reasoning {
                Text(reasoning)
                    .font(.caption).italic()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Dismiss", role: .cancel) { onDismiss() }
                    .disabled(isDeciding)
                Button {
                    Task { await onAccept() }
                } label: {
                    if isDeciding {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Accept → Create Draft")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isDeciding)
            }
        }
        .padding(.vertical, 6)
    }
}
