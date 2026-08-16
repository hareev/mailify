import SwiftUI

struct AISettingsView: View {
    @State private var apiKeyInput = ""
    @State private var hasStoredKey = false
    @State private var isEditing = false
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSucceeded = false

    var body: some View {
        Form {
            Section {
                if hasStoredKey && !isEditing {
                    HStack {
                        Text("••••••••••••••••").foregroundStyle(.secondary)
                        Spacer()
                        Button("Change") { isEditing = true }
                        Button("Remove", role: .destructive) { removeKey() }
                    }
                } else {
                    SecureField("sk-ant-...", text: $apiKeyInput)
                    HStack {
                        Button("Save") { save() }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Test Key") { Task { await testKey() } }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || isValidating)
                        if isValidating { ProgressView().controlSize(.small) }
                    }
                }
                // Rendered regardless of which branch above is showing —
                // a Remove failure needs to be visible even while the
                // "saved" (hasStoredKey && !isEditing) branch is active.
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(validationSucceeded ? .green : .red)
                }
            } header: {
                Text("Anthropic API Key")
            } footer: {
                Text("Used to categorize mail and draft reply suggestions. Never displayed again after saving. Without a key, mail still syncs but stays uncategorized.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasStoredKey = KeychainStore.get(service: KeychainKeys.anthropicService, account: KeychainKeys.anthropicAccount) != nil
        }
    }

    private func save() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard KeychainStore.set(trimmed, service: KeychainKeys.anthropicService, account: KeychainKeys.anthropicAccount) else {
            // Previously this branch didn't exist — save() always reported
            // success even if the underlying Keychain write failed, so a
            // failure here was invisible: the UI would switch to "saved"
            // while nothing was actually stored, and the key would silently
            // stay missing on every later sync.
            validationSucceeded = false
            validationMessage = "Couldn't save the key to Keychain. Try again, or check for a Keychain Access permission prompt."
            return
        }
        // Confirm the write actually stuck rather than trusting the status
        // code alone — belt-and-suspenders given the above was silently
        // wrong before.
        guard KeychainStore.get(service: KeychainKeys.anthropicService, account: KeychainKeys.anthropicAccount) == trimmed else {
            validationSucceeded = false
            validationMessage = "The key didn't save correctly. Try again."
            return
        }
        hasStoredKey = true
        isEditing = false
        apiKeyInput = ""
        validationMessage = nil
    }

    private func removeKey() {
        guard KeychainStore.delete(service: KeychainKeys.anthropicService, account: KeychainKeys.anthropicAccount) else {
            validationSucceeded = false
            validationMessage = "Couldn't remove the key from Keychain. Try again."
            return
        }
        hasStoredKey = false
        isEditing = false
    }

    private func testKey() async {
        isValidating = true
        validationMessage = nil
        defer { isValidating = false }
        do {
            try await ClaudeAPIClient().validateKey(apiKeyInput.trimmingCharacters(in: .whitespaces))
            validationSucceeded = true
            validationMessage = "Key looks valid."
        } catch {
            validationSucceeded = false
            validationMessage = error.localizedDescription
        }
    }
}
