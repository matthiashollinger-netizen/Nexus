import SwiftUI
import UniformTypeIdentifiers

struct ImportCSVView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss
    @State private var csvText = ""
    @State private var showFilePicker = false
    @State private var importError: String? = nil
    @State private var importedCount: Int? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("import.choose_file", systemImage: "doc.badge.plus")
                    }
                } header: {
                    Text("import.csv.header")
                } footer: {
                    Text("import.csv.format_hint")
                        .font(.caption)
                }

                Section("import.csv.preview") {
                    TextEditor(text: $csvText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 200)
                }

                if let error = importError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                if let count = importedCount {
                    Section {
                        Label(String(format: String(localized: "import.success"), count), systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("import.csv.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("action.close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("action.import") { doImport() }
                        .disabled(csvText.isEmpty)
                }
            }
        }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            guard let url = try? result.get() else { return }
            _ = url.startAccessingSecurityScopedResource()
            defer { url.stopAccessingSecurityScopedResource() }
            csvText = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    private func doImport() {
        let before = vm.sessions.count
        vm.importCSV(csvText)
        importedCount = vm.sessions.count - before
        importError = nil
    }
}
