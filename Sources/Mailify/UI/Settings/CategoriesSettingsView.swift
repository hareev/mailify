import SwiftUI

struct CategoriesSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var newCategoryName = ""
    @State private var newCategoryColor: Color = Color(hex: Category.suggestionPalette[0])

    var body: some View {
        Form {
            Section {
                ForEach(appState.store.categories.sorted { $0.sortOrder < $1.sortOrder }) { category in
                    HStack {
                        ColorPicker("", selection: colorBinding(for: category), supportsOpacity: false)
                            .labelsHidden()
                            .frame(width: 20)
                        TextField("Name", text: binding(for: category))
                        Spacer()
                        if category.name != Category.otherName {
                            Button(role: .destructive) {
                                delete(category)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    ColorPicker("", selection: $newCategoryColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 20)
                    TextField("New category", text: $newCategoryName)
                    Button("Add") { addCategory() }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Categories")
            } footer: {
                Text("Categories are used by the AI agent to sort incoming mail. \"\(Category.otherName)\" is the required fallback and can't be removed. Click a color swatch to change it.")
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for category: Category) -> Binding<String> {
        Binding(
            get: { category.name },
            set: { newValue in
                appState.mutateStore { store in
                    if let idx = store.categories.firstIndex(where: { $0.id == category.id }) {
                        store.categories[idx].name = newValue
                    }
                }
            }
        )
    }

    private func colorBinding(for category: Category) -> Binding<Color> {
        Binding(
            get: { Color(hex: category.colorHex) },
            set: { newValue in
                appState.mutateStore { store in
                    if let idx = store.categories.firstIndex(where: { $0.id == category.id }) {
                        store.categories[idx].colorHex = newValue.toHex()
                    }
                }
            }
        )
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        appState.mutateStore { store in
            let nextOrder = (store.categories.map(\.sortOrder).max() ?? 0) + 1
            store.categories.append(Category(name: name, colorHex: newCategoryColor.toHex(), sortOrder: nextOrder))
        }
        newCategoryName = ""
        let usedHexes = appState.store.categories.map(\.colorHex)
        newCategoryColor = Color(hex: Category.nextSuggestionColor(avoiding: usedHexes))
    }

    private func delete(_ category: Category) {
        appState.mutateStore { store in
            store.categories.removeAll { $0.id == category.id }
            for idx in store.messages.indices where store.messages[idx].categoryID == category.id {
                store.messages[idx].categoryID = nil
            }
        }
    }
}
