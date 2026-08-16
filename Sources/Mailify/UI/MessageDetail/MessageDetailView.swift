import SwiftUI
import AppKit

struct MessageDetailView: View {
    @EnvironmentObject var appState: AppState
    let message: EmailMessage

    @State private var bodyHTML: String?
    @State private var isLoadingBody = false
    @State private var loadError: String?

    private var category: Category? {
        appState.store.categories.first { $0.id == message.categoryID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            Group {
                if let bodyHTML {
                    HTMLBodyWebView(html: bodyHTML)
                } else if isLoadingBody {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadError {
                    Text(loadError).foregroundStyle(.secondary).padding()
                } else {
                    Color.clear
                }
            }
        }
        .task(id: message.id) { await loadBody() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                    .font(.title3).fontWeight(.semibold)
                Spacer()
                if let category {
                    CategoryBadge(category: category)
                }
            }
            HStack(spacing: 6) {
                Text(message.fromName ?? message.from)
                    .fontWeight(.medium)
                Text("<\(message.from)>")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(message.receivedAt.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
        .padding()
    }

    private func loadBody() async {
        if let cached = message.bodyHTML {
            bodyHTML = cached
            return
        }
        guard let account = appState.gmailAccount else { return }
        isLoadingBody = true
        loadError = nil
        defer { isLoadingBody = false }

        do {
            let provider = GmailProvider(account: account, oauth: appState.oauth)
            let html = try await provider.fetchMessageBody(messageID: message.id)
            bodyHTML = html
            appState.mutateStore { store in
                if let idx = store.messages.firstIndex(where: { $0.id == message.id }) {
                    store.messages[idx].bodyHTML = html
                }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct CategoryBadge: View {
    let category: Category

    var body: some View {
        Text(category.name)
            .font(.caption).fontWeight(.medium)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(hex: category.colorHex).opacity(0.18))
            .foregroundStyle(Color(hex: category.colorHex))
            .clipShape(Capsule())
    }
}

extension Color {
    init(hex: String) {
        var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexString = hexString.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Round-trips a picked Color back to the "#RRGGBB" form the store
    /// persists — the deviceRGB conversion keeps this stable across
    /// wide-gamut/display-P3 color wells (ColorPicker can hand back either).
    func toHex() -> String {
        let converted = NSColor(self).usingColorSpace(.deviceRGB) ?? NSColor(self)
        let r = Int((converted.redComponent * 255).rounded())
        let g = Int((converted.greenComponent * 255).rounded())
        let b = Int((converted.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
