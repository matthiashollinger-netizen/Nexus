import Foundation
import AppKit
import Combine

// MARK: - Text Editor Document

@MainActor
final class TextEditorDocument: ObservableObject {
    @Published var content: String = ""
    @Published var filePath: String = ""
    @Published var encoding: String.Encoding = .utf8
    @Published var isModified: Bool = false

    var sftpUploadCallback: ((URL) async throws -> Void)?

    private var savedContent: String = ""

    // MARK: - Open

    func open(url: URL) throws {
        let data = try Data(contentsOf: url)

        // Detect encoding
        var detected: String.Encoding = .utf8
        var text: String?

        let encodings: [String.Encoding] = [.utf8, .isoLatin1, .windowsCP1252, .macOSRoman]
        for enc in encodings {
            if let decoded = String(data: data, encoding: enc) {
                text = decoded
                detected = enc
                break
            }
        }

        guard let resolved = text else {
            throw TextEditorError.unsupportedEncoding
        }

        self.content = resolved
        self.savedContent = resolved
        self.filePath = url.path
        self.encoding = detected
        self.isModified = false
    }

    // MARK: - Save

    func save() async throws {
        guard !filePath.isEmpty else { throw TextEditorError.noFilePath }
        let url = URL(fileURLWithPath: filePath)
        guard let data = content.data(using: encoding) else {
            throw TextEditorError.encodingFailed
        }
        try data.write(to: url, options: .atomicWrite)
        savedContent = content
        isModified = false

        // Re-upload to SFTP if opened via SFTP
        if let callback = sftpUploadCallback {
            try await callback(url)
        }
    }

    func markModified() {
        isModified = (content != savedContent)
    }
}

// MARK: - Text Editor Errors

enum TextEditorError: LocalizedError {
    case unsupportedEncoding
    case noFilePath
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedEncoding: return "Could not detect file encoding"
        case .noFilePath: return "No file path set"
        case .encodingFailed: return "Could not encode content with selected encoding"
        }
    }
}
