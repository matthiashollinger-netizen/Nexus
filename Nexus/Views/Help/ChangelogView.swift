import SwiftUI

// MARK: - Changelog window (Help → Versionsverlauf)

struct ChangelogView: View {
    @State private var releases: [ChangelogRelease] = []
    @State private var selectedID: String?

    var body: some View {
        NavigationSplitView {
            List(releases, selection: $selectedID) { release in
                VStack(alignment: .leading, spacing: 3) {
                    Text("v\(release.version)")
                        .font(.headline)
                    Text(release.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(release.id)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            if let id = selectedID,
               let release = releases.first(where: { $0.id == id }) {
                ChangelogDetailView(release: release)
            } else {
                ContentUnavailableView(
                    "changelog.select",
                    systemImage: "clock.arrow.circlepath"
                )
            }
        }
        .frame(minWidth: 680, minHeight: 460)
        .onAppear {
            releases = ChangelogParser.parse()
            if selectedID == nil { selectedID = releases.first?.id }
        }
    }
}

// MARK: - Detail view

private struct ChangelogDetailView: View {
    let release: ChangelogRelease

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                HStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nexus v\(release.version)")
                            .font(.largeTitle.weight(.bold))
                        Text(release.date)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider()

                // Section blocks
                ForEach(release.sections, id: \.heading) { section in
                    ChangelogSectionBlock(section: section)
                }
            }
            .padding(32)
            .frame(maxWidth: 660, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Section block

private struct ChangelogSectionBlock: View {
    let section: ChangelogSection

    private var style: (icon: String, color: Color) {
        let h = section.heading.lowercased()
        if h.contains("neu") || h.contains("new") || h.contains("added") || h.contains("feat") {
            return ("sparkles", .green)
        } else if h.contains("behob") || h.contains("fix") || h.contains("bug") {
            return ("wrench.and.screwdriver.fill", .orange)
        } else if h.contains("geänd") || h.contains("changed") || h.contains("improved") || h.contains("verbess") {
            return ("arrow.triangle.2.circlepath", .blue)
        } else if h.contains("entfernt") || h.contains("removed") || h.contains("deprec") {
            return ("trash.fill", .red)
        } else {
            return ("doc.text.fill", Color.secondary)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(section.heading, systemImage: style.icon)
                .font(.headline)
                .foregroundStyle(style.color)

            ForEach(section.items, id: \.self) { item in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(style.color.opacity(0.65))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(item)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Model

struct ChangelogRelease: Identifiable {
    let id: String        // same as version
    let version: String
    let date: String
    let sections: [ChangelogSection]
}

struct ChangelogSection {
    let heading: String
    let items: [String]
}

// MARK: - Parser

enum ChangelogParser {
    static func parse() -> [ChangelogRelease] {
        guard
            let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }

        var releases: [ChangelogRelease] = []
        var currentVersion: String?
        var currentDate: String?
        var currentSectionHeading: String?
        var currentItems: [String] = []
        var currentSections: [ChangelogSection] = []

        func flushSection() {
            guard let heading = currentSectionHeading, !currentItems.isEmpty else { return }
            currentSections.append(ChangelogSection(heading: heading, items: currentItems))
            currentItems = []
            currentSectionHeading = nil
        }

        func flushRelease() {
            flushSection()
            guard let v = currentVersion, let d = currentDate, !currentSections.isEmpty else { return }
            releases.append(ChangelogRelease(id: v, version: v, date: d, sections: currentSections))
            currentSections = []
            currentVersion = nil
            currentDate = nil
        }

        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## [") {
                flushRelease()
                // format: ## [1.1.0] - 2026-05-28
                let inner = String(line.dropFirst(4))
                if let bracket = inner.firstIndex(of: "]") {
                    currentVersion = String(inner[inner.startIndex..<bracket])
                    let rest = inner[inner.index(after: bracket)...]
                    if let dashRange = rest.range(of: " - ") {
                        currentDate = String(rest[dashRange.upperBound...])
                            .trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if line.hasPrefix("### ") {
                flushSection()
                currentSectionHeading = String(line.dropFirst(4))
            } else if line.hasPrefix("- ") {
                currentItems.append(String(line.dropFirst(2)))
            }
        }
        flushRelease()

        return releases
    }
}
