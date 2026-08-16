import SwiftUI

/// Connector card UI, conceptually adapted from a React "integrations" admin
/// panel pattern: icon/name/connected-state badge/connect-disconnect action.
struct AccountsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var isConnecting = false
    @State private var connectError: String?

    var body: some View {
        Form {
            Section("Mail Providers") {
                gmailCard
                iCloudCard
            }
        }
        .formStyle(.grouped)
    }

    private var gmailCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.title2)
                .foregroundStyle(.red)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Gmail").fontWeight(.semibold)
                if let account = appState.gmailAccount {
                    Text("Connected as \(account.emailAddress)")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Read mail and create draft replies. Never sends.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let connectError {
                    Text(connectError).font(.caption).foregroundStyle(.red)
                }
                if !appState.oauth.isConfigured {
                    Text("Not configured — add your Google OAuth client ID/secret. See SETUP-GMAIL.md.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Spacer()

            if appState.gmailAccount != nil {
                Button("Disconnect", role: .destructive) { appState.disconnectGmail() }
            } else {
                Button {
                    Task { await connectGmail() }
                } label: {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isConnecting || !appState.oauth.isConfigured)
            }
        }
        .padding(.vertical, 4)
    }

    private var iCloudCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.fill")
                .font(.title2)
                .foregroundStyle(.gray)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("iCloud Mail").fontWeight(.semibold)
                Text("Not yet available — coming in a future update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") {}.disabled(true)
        }
        .padding(.vertical, 4)
        .opacity(0.6)
    }

    private func connectGmail() async {
        isConnecting = true
        connectError = nil
        defer { isConnecting = false }
        do {
            try await appState.connectGmail()
        } catch {
            connectError = error.localizedDescription
        }
    }
}
