import SwiftUI

struct AddFolderView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    var existingFolder: Folder?
    var parentFolderId: UUID?

    @State private var name: String = ""
    @State private var selectedParentId: UUID?
    @State private var selectedCredentialId: UUID?

    private var isEditing: Bool { existingFolder != nil }

    init(folder: Folder? = nil, parentFolderId: UUID? = nil) {
        self.existingFolder = folder
        self.parentFolderId = parentFolderId
        if let f = folder {
            _name = State(initialValue: f.name)
            _selectedParentId = State(initialValue: f.parentId)
            _selectedCredentialId = State(initialValue: f.credentialId)
        } else {
            _selectedParentId = State(initialValue: parentFolderId)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("folder.general") {
                    LabeledContent("folder.name") {
                        TextField("folder.name.placeholder", text: $name)
                    }
                    LabeledContent("folder.parent") {
                        Picker("", selection: $selectedParentId) {
                            Text("folder.parent.none").tag(Optional<UUID>.none)
                            ForEach(vm.folders.filter { $0.id != existingFolder?.id }) { folder in
                                Text(folder.name).tag(Optional(folder.id))
                            }
                        }
                    }
                }
                Section("folder.credential") {
                    PasswordGroupPicker(selectedId: $selectedCredentialId)
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? String(localized: "folder.edit") : String(localized: "folder.new"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.save") { save() }
                        .disabled(name.isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 280)
    }

    private func save() {
        if isEditing, var folder = existingFolder {
            folder.name = name
            folder.parentId = selectedParentId
            folder.credentialId = selectedCredentialId
            vm.updateFolder(folder)
        } else {
            vm.addFolder(name: name, parentId: selectedParentId)
        }
        dismiss()
    }
}
