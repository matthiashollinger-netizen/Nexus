import Foundation
import OSLog
import AppKit

// MARK: - Models

enum BugSeverity: String, CaseIterable, Identifiable {
    case crash       = "crash"
    case severe      = "severe"
    case medium      = "medium"
    case cosmetic    = "cosmetic"

    var id: String { rawValue }

    nonisolated var emoji: String {
        switch self {
        case .crash:    return "🔴"
        case .severe:   return "🟠"
        case .medium:   return "🟡"
        case .cosmetic: return "🟢"
        }
    }

    nonisolated var localizedTitle: String {
        switch self {
        case .crash:    return String(localized: "bug.severity.crash")
        case .severe:   return String(localized: "bug.severity.severe")
        case .medium:   return String(localized: "bug.severity.medium")
        case .cosmetic: return String(localized: "bug.severity.cosmetic")
        }
    }

    nonisolated var localizedDescription: String {
        switch self {
        case .crash:    return String(localized: "bug.severity.crash.desc")
        case .severe:   return String(localized: "bug.severity.severe.desc")
        case .medium:   return String(localized: "bug.severity.medium.desc")
        case .cosmetic: return String(localized: "bug.severity.cosmetic.desc")
        }
    }
}

enum FeaturePriority: String, CaseIterable, Identifiable {
    case niceToHave = "niceToHave"
    case important  = "important"
    case critical   = "critical"

    var id: String { rawValue }

    nonisolated var localizedTitle: String {
        switch self {
        case .niceToHave: return String(localized: "feature.priority.nice")
        case .important:  return String(localized: "feature.priority.important")
        case .critical:   return String(localized: "feature.priority.critical")
        }
    }
}

struct BugReport {
    var title: String = ""
    var severity: BugSeverity = .medium
    var reproductionSteps: String = ""
    var email: String = ""
    var systemInfo: SystemInfo = SystemInfo()
    var logs: String = ""
    var includeScreenshot: Bool = false
    var screenshotData: Data? = nil
}

struct FeatureRequest {
    var title: String = ""
    var description: String = ""
    var reason: String = ""
    var priority: FeaturePriority = .important
    var email: String = ""
}

struct SystemInfo: Sendable {
    var appVersion: String
    var buildNumber: String
    var macOSVersion: String
    var architecture: String
    var freeRAMMB: Int
    var activeSessionsSummary: String
    var timestamp: String

    nonisolated init() {
        appVersion   = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        buildNumber  = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        var sysInfo = utsname()
        uname(&sysInfo)
        architecture = withUnsafePointer(to: &sysInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }

        var stats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = Int(vm_page_size)
            freeRAMMB = (Int(stats.free_count) + Int(stats.inactive_count)) * pageSize / 1_048_576
        } else {
            freeRAMMB = 0
        }

        activeSessionsSummary = ""
        timestamp = ISO8601DateFormatter().string(from: Date())
    }
}

enum BugReporterError: LocalizedError {
    case noToken
    case networkError(String)
    case apiError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noToken:
            return String(localized: "bug.error.no_token")
        case .networkError(let msg):
            return String(localized: "bug.error.network") + ": \(msg)"
        case .apiError(let code, let msg):
            return "GitHub API \(code): \(msg)"
        }
    }
}

// MARK: - Service

actor BugReporterService {
    static let shared = BugReporterService()

    private let repo = "matthiashollinger-netizen/Nexus"

    // Try keychain → fall back to known file path on dev machine
    nonisolated private func resolveToken() -> String? {
        // 1. Keychain
        if let fromKeychain = KeychainService.load(key: "NexusGitHubReporterToken"),
           !fromKeychain.isEmpty { return fromKeychain }

        // 2. Dev machine fallback
        let paths = [
            "~/XCode Projects/Nexus/github_token.txt",
            "~/.nexus_github_token"
        ]
        for rawPath in paths {
            let path = NSString(string: rawPath).expandingTildeInPath
            if let token = try? String(contentsOfFile: path, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !token.isEmpty {
                // Cache in keychain for next time
                KeychainService.save(key: "NexusGitHubReporterToken", value: token)
                return token
            }
        }
        return nil
    }

    var isConfigured: Bool { resolveToken() != nil }

    // MARK: - System Info

    func collectSystemInfo(activeSessions: [ConnectionSession]) -> SystemInfo {
        var info = SystemInfo()
        let sessionList = activeSessions.map { s in
            "\(s.session.connectionType.rawValue)://\(s.session.host)"
        }.joined(separator: ", ")
        info.activeSessionsSummary = activeSessions.isEmpty
            ? "Keine aktiven Sessions"
            : "\(activeSessions.count) (\(sessionList))"
        return info
    }

    // MARK: - Log capture

    func collectLogs() -> String {
        guard #available(macOS 12.0, *) else { return "OSLogStore nicht verfügbar." }
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let since = store.position(date: Date().addingTimeInterval(-300)) // last 5 min
            let entries = try store.getEntries(
                at: since,
                matching: nil
            )
            var lines: [String] = []
            for entry in entries {
                if lines.count >= 200 { break }
                lines.append(entry.composedMessage)
            }
            return lines.isEmpty
                ? "Keine strukturierten Logs für diese Session gefunden."
                : lines.joined(separator: "\n")
        } catch {
            return "Log-Erfassung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    // MARK: - Screenshot (no screen-recording permission required — renders view directly)

    @MainActor
    func captureScreenshot() -> Data? {
        guard let window = NSApplication.shared.mainWindow,
              let contentView = window.contentView else { return nil }

        let bounds = contentView.bounds
        guard let bitmapRep = contentView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        contentView.cacheDisplay(in: bounds, to: bitmapRep)

        let image = NSImage(size: bounds.size)
        image.addRepresentation(bitmapRep)
        guard let tiff = image.tiffRepresentation,
              let bmp = NSBitmapImageRep(data: tiff) else { return nil }
        return bmp.representation(using: .png, properties: [:])
    }

    // MARK: - Submit Bug Report

    func submitBugReport(_ report: BugReport) async throws -> URL {
        guard let token = resolveToken() else { throw BugReporterError.noToken }

        let body = buildBugMarkdown(report)
        let issueTitle = "[BUG] \(report.title)"

        let issueURL = try await createGitHubIssue(
            title: issueTitle,
            body: body,
            labels: ["bug-open"],
            token: token
        )

        // Note screenshot in a follow-up comment if one was captured
        if report.screenshotData != nil,
           let issueNumber = issueURL.pathComponents.last {
            let commentBody = "📸 Screenshot wurde erfasst. Bitte manuell auf GitHub anhängen falls relevant."
            try? await postGitHubComment(issueNumber: issueNumber, body: commentBody, token: token)
        }

        return issueURL
    }

    // MARK: - Submit Feature Request

    func submitFeatureRequest(_ request: FeatureRequest) async throws -> URL {
        guard let token = resolveToken() else { throw BugReporterError.noToken }

        let body = buildFeatureMarkdown(request)
        let issueTitle = "[FEATURE] \(request.title)"

        return try await createGitHubIssue(
            title: issueTitle,
            body: body,
            labels: ["feature-request"],
            token: token
        )
    }

    // MARK: - GitHub API

    private func createGitHubIssue(title: String, body: String, labels: [String], token: String) async throws -> URL {
        let url = URL(string: "https://api.github.com/repos/\(repo)/issues")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "title": title,
            "body": body,
            "labels": labels
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BugReporterError.networkError("Keine HTTP-Antwort")
        }
        guard http.statusCode == 201 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unbekannter Fehler"
            throw BugReporterError.apiError(http.statusCode, msg)
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let htmlURL = json["html_url"] as? String,
           let issueURL = URL(string: htmlURL) {
            return issueURL
        }
        return URL(string: "https://github.com/\(repo)/issues")!
    }

    private func postGitHubComment(issueNumber: String, body: String, token: String) async throws {
        let url = URL(string: "https://api.github.com/repos/\(repo)/issues/\(issueNumber)/comments")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["body": body])
        _ = try? await URLSession.shared.data(for: request)
    }

    // MARK: - Markdown formatting

    private func buildBugMarkdown(_ report: BugReport) -> String {
        let info = report.systemInfo
        let screenshotNote = report.screenshotData != nil
            ? "📸 Screenshot wurde erfasst (bitte nach Öffnen des Issues manuell anhängen)"
            : "Kein Screenshot"

        return """
        ## 🐛 Bug Report — Nexus v\(info.appVersion)

        ### Beschreibung
        \(report.title)

        ### Schritte zum Reproduzieren
        \(report.reproductionSteps.isEmpty ? "_Keine Schritte angegeben_" : report.reproductionSteps)

        ### Schweregrad
        \(report.severity.emoji) **\(report.severity.localizedTitle)** — \(report.severity.localizedDescription)

        ### Umgebung
        | Key | Value |
        |-----|-------|
        | App Version | v\(info.appVersion) (Build \(info.buildNumber)) |
        | macOS | \(info.macOSVersion) |
        | Architektur | \(info.architecture) |
        | Aktive Sessions | \(info.activeSessionsSummary) |
        | Freier RAM | \(info.freeRAMMB) MB |
        | Zeitstempel | \(info.timestamp) |

        ### App Logs (letzte 5 Minuten)
        <details>
        <summary>Logs aufklappen</summary>

        ```
        \(report.logs.isEmpty ? "Keine Logs verfügbar" : report.logs)
        ```

        </details>

        ### Screenshot
        \(screenshotNote)

        ---
        _Gemeldet via Nexus In-App Bug Reporter_
        _Kontakt: \(report.email.isEmpty ? "Anonym" : report.email)_
        """
    }

    private func buildFeatureMarkdown(_ request: FeatureRequest) -> String {
        """
        ## 💡 Feature Request — Nexus

        ### Was soll die Funktion machen?
        \(request.description.isEmpty ? "_Keine Beschreibung_" : request.description)

        ### Welches Problem löst das?
        \(request.reason.isEmpty ? "_Nicht angegeben_" : request.reason)

        ### Priorität
        \(request.priority.localizedTitle)

        ---
        _Eingereicht via Nexus In-App Feature Request_
        _Kontakt: \(request.email.isEmpty ? "Anonym" : request.email)_
        """
    }
}
