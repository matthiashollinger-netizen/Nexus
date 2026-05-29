import SwiftUI
import AppKit

// MARK: - Text Editor Window Scene Entry Point

struct NexusTextEditorView: View {
    @StateObject private var document = TextEditorDocument()
    @State private var fileURL: URL? = nil
    @State private var fontSize: Double = 13.0
    @State private var errorMessage: String? = nil
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                Button(action: openFile) {
                    Label("action.import", systemImage: "folder")
                }
                .buttonStyle(.borderless)

                Button(action: { Task { await saveFile() } }) {
                    Label("action.save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("s", modifiers: .command)
                .disabled(document.filePath.isEmpty)

                Divider().frame(height: 20)

                // Encoding picker
                Picker("", selection: $document.encoding) {
                    Text("UTF-8").tag(String.Encoding.utf8)
                    Text("Latin-1").tag(String.Encoding.isoLatin1)
                    Text("Windows-1252").tag(String.Encoding.windowsCP1252)
                    Text("macOS Roman").tag(String.Encoding.macOSRoman)
                }
                .frame(width: 120)
                .labelsHidden()

                Spacer()

                // Font size controls
                Button {
                    fontSize = max(8, fontSize - 1)
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("-", modifiers: .command)

                Text("\(Int(fontSize)) pt")
                    .font(.caption)
                    .frame(width: 40)

                Button {
                    fontSize = min(36, fontSize + 1)
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("=", modifiers: .command)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Editor area
            NexusCodeEditorView(
                text: Binding(
                    get: { document.content },
                    set: { document.content = $0; document.markModified() }
                ),
                fontSize: fontSize,
                filePath: document.filePath
            )

            Divider()

            // Status bar
            HStack {
                if !document.filePath.isEmpty {
                    Text(document.filePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("editor.no_file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(encodingLabel)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.bar)
        }
        .frame(minWidth: 600, minHeight: 400)
        .alert("editor.error", isPresented: $showError) {
            Button("action.close", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var encodingLabel: String {
        switch document.encoding {
        case .utf8: return "UTF-8"
        case .isoLatin1: return "Latin-1"
        case .windowsCP1252: return "Win-1252"
        case .macOSRoman: return "macOS Roman"
        default: return "Unknown"
        }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try document.open(url: url)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func saveFile() async {
        do {
            try await document.save()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - NSTextView-based Code Editor with Syntax Highlighting + Line Numbers

struct NexusCodeEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: Double
    var filePath: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.isEditable = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1)
        textView.insertionPointColor = NSColor.white
        textView.selectedTextAttributes[.backgroundColor] = NSColor.selectedTextBackgroundColor

        // Use NSTextFinder for ⌘F / ⌘H
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        applyFont(to: textView, size: fontSize)
        addLineNumberRuler(to: scrollView, textView: textView, coordinator: context.coordinator)

        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Update font size
        applyFont(to: textView, size: fontSize)

        // Only update text if it differs (avoids cursor jump)
        if textView.string != text {
            let sel = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = sel.filter { $0.rangeValue.upperBound <= text.utf16.count }
            applySyntaxHighlighting(to: textView, path: filePath)
        }
    }

    private func applyFont(to textView: NSTextView, size: Double) {
        let font = NSFont(name: "Menlo", size: CGFloat(size)) ??
                   NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
        textView.font = font
        textView.textColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        ]
    }

    private func addLineNumberRuler(to scrollView: NSScrollView, textView: NSTextView, coordinator: Coordinator) {
        let ruler = NexusLineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        coordinator.lineNumberRuler = ruler
        NotificationCenter.default.addObserver(ruler,
            selector: #selector(NexusLineNumberRuler.textDidChange(_:)),
            name: NSText.didChangeNotification,
            object: textView)
    }

    private func applySyntaxHighlighting(to textView: NSTextView, path: String) {
        let ext = (path as NSString).pathExtension.lowercased()
        let highlighter = SyntaxHighlighter(extension: ext)
        highlighter.highlight(textView)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NexusCodeEditorView
        weak var textView: NSTextView?
        weak var lineNumberRuler: NexusLineNumberRuler?

        init(_ parent: NexusCodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            lineNumberRuler?.needsDisplay = true

            // Apply syntax highlighting on each change (throttled via DispatchQueue)
            let path = parent.filePath
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak tv] in
                guard let tv else { return }
                let ext = (path as NSString).pathExtension.lowercased()
                let highlighter = SyntaxHighlighter(extension: ext)
                highlighter.highlight(tv)
            }
        }
    }
}

// MARK: - Line Number Ruler

final class NexusLineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.ruleThickness = 40
    }

    required init(coder: NSCoder) { fatalError() }

    @objc func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        NSColor(white: 0.15, alpha: 1).setFill()
        rect.fill()

        let visibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        let text = textView.string as NSString
        var lineNumber = 1

        // Count newlines before visible range
        let preceding = text.substring(to: charRange.location)
        lineNumber = preceding.components(separatedBy: "\n").count

        var index = charRange.location

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(white: 0.4, alpha: 1)
        ]

        while index <= NSMaxRange(charRange) {
            var lineRange = NSRange(location: 0, length: 0)
            var lineRect = layoutManager.lineFragmentRect(forGlyphAt: layoutManager.glyphIndexForCharacter(at: index), effectiveRange: &lineRange)

            let yOffset = lineRect.minY - visibleRect.minY + convert(textView.bounds.origin, from: textView).y
            let label = "\(lineNumber)" as NSString
            let size = label.size(withAttributes: attributes)
            let drawRect = NSRect(x: ruleThickness - size.width - 4,
                                  y: yOffset + (lineRect.height - size.height) / 2,
                                  width: size.width, height: size.height)
            label.draw(in: drawRect, withAttributes: attributes)

            lineNumber += 1
            if NSMaxRange(lineRange) >= NSMaxRange(charRange) { break }
            index = NSMaxRange(lineRange)
        }
    }
}

// MARK: - Syntax Highlighter

final class SyntaxHighlighter {
    private let fileExtension: String

    init(extension ext: String) {
        self.fileExtension = ext
    }

    func highlight(_ textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(text.startIndex..., in: text)

        // Reset to base color
        let baseColor = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        storage.beginEditing()
        storage.setAttributes([.foregroundColor: baseColor, .font: font], range: fullRange)

        let rules = rulesForExtension(fileExtension)
        for rule in rules {
            applyRule(rule, to: storage, text: text)
        }
        storage.endEditing()
    }

    private struct HighlightRule {
        let pattern: String
        let color: NSColor
        let options: NSRegularExpression.Options
    }

    private func applyRule(_ rule: HighlightRule, to storage: NSTextStorage, text: String) {
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: rule.options) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            storage.addAttribute(.foregroundColor, value: rule.color, range: match.range)
        }
    }

    private func rulesForExtension(_ ext: String) -> [HighlightRule] {
        let keyword    = NSColor(red: 0.55, green: 0.65, blue: 1.0, alpha: 1)  // blue
        let string     = NSColor(red: 0.85, green: 0.55, blue: 0.45, alpha: 1) // orange-red
        let comment    = NSColor(red: 0.45, green: 0.55, blue: 0.45, alpha: 1) // muted green
        let number     = NSColor(red: 0.75, green: 0.55, blue: 0.85, alpha: 1) // purple
        let typeColor  = NSColor(red: 0.4,  green: 0.8,  blue: 0.75, alpha: 1) // cyan
        let funcColor  = NSColor(red: 0.9,  green: 0.8,  blue: 0.4,  alpha: 1) // yellow

        switch ext {
        case "swift":
            return [
                HighlightRule(pattern: "//.*$", color: comment, options: .anchorsMatchLines),
                HighlightRule(pattern: "/\\*[\\s\\S]*?\\*/", color: comment, options: []),
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: string, options: []),
                HighlightRule(pattern: "\\b(func|class|struct|enum|protocol|extension|var|let|if|else|guard|return|import|for|while|switch|case|break|continue|throw|throws|try|catch|async|await|actor|nonisolated|@MainActor|@Observable|@State|@Binding|@Environment|override|final|private|public|internal|static|init|self|super|true|false|nil)\\b", color: keyword, options: []),
                HighlightRule(pattern: "\\b[A-Z][A-Za-z0-9_]+\\b", color: typeColor, options: []),
                HighlightRule(pattern: "\\bfunc\\s+([A-Za-z_][A-Za-z0-9_]*)\\b", color: funcColor, options: []),
                HighlightRule(pattern: "\\b\\d+\\.?\\d*\\b", color: number, options: []),
            ]
        case "py", "python":
            return [
                HighlightRule(pattern: "#.*$", color: comment, options: .anchorsMatchLines),
                HighlightRule(pattern: "\"\"\"[\\s\\S]*?\"\"\"", color: comment, options: []),
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'", color: string, options: []),
                HighlightRule(pattern: "\\b(def|class|import|from|return|if|elif|else|for|while|try|except|finally|with|as|pass|break|continue|raise|yield|lambda|and|or|not|in|is|True|False|None|print)\\b", color: keyword, options: []),
                HighlightRule(pattern: "\\b\\d+\\.?\\d*\\b", color: number, options: []),
            ]
        case "sh", "bash", "zsh":
            return [
                HighlightRule(pattern: "#.*$", color: comment, options: .anchorsMatchLines),
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'", color: string, options: []),
                HighlightRule(pattern: "\\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|function|return|export|local|echo|exit|source|\\.|set|unset|readonly|declare|trap|shift|getopts|break|continue)\\b", color: keyword, options: []),
                HighlightRule(pattern: "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?", color: typeColor, options: []),
                HighlightRule(pattern: "\\b\\d+\\b", color: number, options: []),
            ]
        case "json":
            return [
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"\\s*:", color: keyword, options: []),
                HighlightRule(pattern: ":\\s*\"(?:[^\"\\\\]|\\\\.)*\"", color: string, options: []),
                HighlightRule(pattern: "\\b(true|false|null)\\b", color: typeColor, options: []),
                HighlightRule(pattern: "\\b-?\\d+\\.?\\d*(?:[eE][+-]?\\d+)?\\b", color: number, options: []),
            ]
        case "yaml", "yml":
            return [
                HighlightRule(pattern: "#.*$", color: comment, options: .anchorsMatchLines),
                HighlightRule(pattern: "^\\s*[A-Za-z_][A-Za-z0-9_-]*\\s*:", color: keyword, options: .anchorsMatchLines),
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"|'[^']*'", color: string, options: []),
                HighlightRule(pattern: "\\b(true|false|null|yes|no)\\b", color: typeColor, options: .caseInsensitive),
                HighlightRule(pattern: "\\b\\d+\\.?\\d*\\b", color: number, options: []),
            ]
        case "xml", "html":
            return [
                HighlightRule(pattern: "<!--[\\s\\S]*?-->", color: comment, options: []),
                HighlightRule(pattern: "</?[A-Za-z][A-Za-z0-9_:-]*", color: keyword, options: []),
                HighlightRule(pattern: "[A-Za-z][A-Za-z0-9_:-]*\\s*=", color: typeColor, options: []),
                HighlightRule(pattern: "\"[^\"]*\"|'[^']*'", color: string, options: []),
            ]
        default:
            // Generic: strings and numbers
            return [
                HighlightRule(pattern: "\"(?:[^\"\\\\]|\\\\.)*\"", color: string, options: []),
                HighlightRule(pattern: "\\b\\d+\\.?\\d*\\b", color: number, options: []),
                HighlightRule(pattern: "#.*$", color: comment, options: .anchorsMatchLines),
            ]
        }
    }
}
