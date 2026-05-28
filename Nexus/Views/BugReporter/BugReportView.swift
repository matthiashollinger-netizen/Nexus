import SwiftUI

// MARK: - Bug Report Sheet

struct BugReportView: View {
    @Environment(AppViewModel.self) private var vm
    @Environment(\.dismiss) private var dismiss

    @State private var report = BugReport()
    @State private var isSubmitting = false
    @State private var submittedURL: URL? = nil
    @State private var errorMessage: String? = nil
    @State private var systemInfoLoaded = false
    @State private var showSystemInfo = false

    private var canSubmit: Bool {
        !report.title.trimmingCharacters(in: .whitespaces).isEmpty &&
        !report.reproductionSteps.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if let url = submittedURL {
                SuccessView(issueURL: url, onDone: { dismiss() })
            } else {
                formContent
            }
        }
        .frame(width: 560, height: 640)
        .onAppear { loadSystemInfo() }
    }

    // MARK: - Form

    private var formContent: some View {
        VStack(spacing: 0) {
            // Header
            SheetHeader(
                icon: "ladybug.fill",
                iconColor: .red,
                title: "bug.title",
                subtitle: "bug.subtitle"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Section 1 — Was ist passiert?
                    ReporterSection(title: "bug.section.what", required: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("bug.title.placeholder", text: $report.title)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: report.title) { _, new in
                                    if new.count > 100 {
                                        report.title = String(new.prefix(100))
                                    }
                                }
                            HStack {
                                Spacer()
                                Text("\(report.title.count)/100")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("bug.severity.label")
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 4)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(BugSeverity.allCases) { severity in
                                    SeverityCard(
                                        severity: severity,
                                        isSelected: report.severity == severity
                                    ) {
                                        report.severity = severity
                                    }
                                }
                            }
                        }
                    }

                    // Section 2 — Wie reproduzieren?
                    ReporterSection(title: "bug.section.repro", required: true) {
                        ZStack(alignment: .topLeading) {
                            if report.reproductionSteps.isEmpty {
                                Text("bug.repro.placeholder")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 9)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $report.reproductionSteps)
                                .font(.callout)
                                .frame(minHeight: 100, maxHeight: 160)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                        }
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
                    }

                    // Section 3 — Automatisch erfasste Infos
                    ReporterSection(title: "bug.section.auto", required: false) {
                        DisclosureGroup(isExpanded: $showSystemInfo) {
                            VStack(alignment: .leading, spacing: 8) {
                                SystemInfoRow(key: "bug.info.version",   value: "\(report.systemInfo.appVersion) (\(report.systemInfo.buildNumber))")
                                SystemInfoRow(key: "bug.info.macos",     value: report.systemInfo.macOSVersion)
                                SystemInfoRow(key: "bug.info.arch",      value: report.systemInfo.architecture)
                                SystemInfoRow(key: "bug.info.sessions",  value: report.systemInfo.activeSessionsSummary)
                                SystemInfoRow(key: "bug.info.ram",       value: "\(report.systemInfo.freeRAMMB) MB frei")
                                SystemInfoRow(key: "bug.info.timestamp", value: report.systemInfo.timestamp)
                                Divider()
                                Text("bug.info.logs_note")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Toggle("bug.screenshot.include", isOn: $report.includeScreenshot)
                                    .onChange(of: report.includeScreenshot) { _, include in
                                        if include { captureScreenshot() }
                                        else { report.screenshotData = nil }
                                    }
                                if report.screenshotData != nil {
                                    Label("bug.screenshot.captured", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            Label("bug.section.auto.toggle", systemImage: systemInfoLoaded ? "checkmark.seal.fill" : "clock")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }

                    // Section 4 — Kontakt
                    ReporterSection(title: "bug.section.contact", required: false) {
                        TextField("bug.contact.placeholder", text: $report.email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                    }

                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(err)
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Text("bug.privacy_note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("action.cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button {
                    submitReport()
                } label: {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("bug.submitting")
                        }
                    } else {
                        Text("bug.submit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    // MARK: - Actions

    private func loadSystemInfo() {
        Task {
            let info = await BugReporterService.shared.collectSystemInfo(
                activeSessions: vm.activeSessions
            )
            let logs = await BugReporterService.shared.collectLogs()
            await MainActor.run {
                report.systemInfo = info
                report.logs = logs
                systemInfoLoaded = true
            }
        }
    }

    @MainActor
    private func captureScreenshot() {
        report.screenshotData = BugReporterService.shared.captureScreenshot()
    }

    private func submitReport() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let url = try await BugReporterService.shared.submitBugReport(report)
                await MainActor.run { submittedURL = url }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Feature Request Sheet

struct FeatureRequestView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var request = FeatureRequest()
    @State private var isSubmitting = false
    @State private var submittedURL: URL? = nil
    @State private var errorMessage: String? = nil

    private var canSubmit: Bool {
        !request.title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Group {
            if let url = submittedURL {
                SuccessView(issueURL: url, onDone: { dismiss() })
            } else {
                formContent
            }
        }
        .frame(width: 520, height: 540)
    }

    private var formContent: some View {
        VStack(spacing: 0) {
            SheetHeader(
                icon: "lightbulb.fill",
                iconColor: .yellow,
                title: "feature.title",
                subtitle: "feature.subtitle"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    ReporterSection(title: "feature.section.title", required: true) {
                        TextField("feature.title.placeholder", text: $request.title)
                            .textFieldStyle(.roundedBorder)
                    }

                    ReporterSection(title: "feature.section.what", required: false) {
                        PlaceholderEditor(text: $request.description, placeholder: "feature.what.placeholder", minHeight: 80)
                    }

                    ReporterSection(title: "feature.section.why", required: false) {
                        PlaceholderEditor(text: $request.reason, placeholder: "feature.why.placeholder", minHeight: 60)
                    }

                    ReporterSection(title: "feature.section.priority", required: false) {
                        Picker("", selection: $request.priority) {
                            ForEach(FeaturePriority.allCases) { p in
                                Text(p.localizedTitle).tag(p)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    ReporterSection(title: "bug.section.contact", required: false) {
                        TextField("bug.contact.placeholder", text: $request.email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                    }

                    if let err = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            Text(err).foregroundStyle(.red).font(.callout)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(24)
            }

            Divider()

            HStack(spacing: 12) {
                Text("bug.privacy_note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("action.cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                Button {
                    submitRequest()
                } label: {
                    if isSubmitting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("bug.submitting")
                        }
                    } else {
                        Text("feature.submit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
    }

    private func submitRequest() {
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                let url = try await BugReporterService.shared.submitFeatureRequest(request)
                await MainActor.run { submittedURL = url }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

// MARK: - Shared sub-components

private struct SheetHeader: View {
    let icon: String
    let iconColor: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        Divider()
    }
}

private struct ReporterSection<Content: View>: View {
    let title: LocalizedStringKey
    let required: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if required {
                    Text("*").foregroundStyle(.red).font(.subheadline)
                } else {
                    Text("bug.optional").font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
    }
}

private struct SeverityCard: View {
    let severity: BugSeverity
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(severity.emoji).font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(severity.localizedTitle).font(.caption.weight(.semibold))
                    Text(severity.localizedDescription).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SystemInfoRow: View {
    let key: LocalizedStringKey
    let value: String
    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.caption.monospacedDigit())
            Spacer()
        }
    }
}

private struct PlaceholderEditor: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    var minHeight: CGFloat = 80

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(.secondary).font(.callout)
                    .padding(.horizontal, 5).padding(.vertical, 9)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .font(.callout)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
                .padding(4)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
    }
}

// MARK: - Success View

private struct SuccessView: View {
    let issueURL: URL
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            VStack(spacing: 8) {
                Text("bug.success.title").font(.title2.weight(.bold))
                Text("bug.success.subtitle").foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Link("bug.success.open_issue", destination: issueURL)
                .buttonStyle(.borderedProminent)
            Spacer()
            Button("action.close") { onDone() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.bottom, 20)
        }
        .padding()
    }
}
