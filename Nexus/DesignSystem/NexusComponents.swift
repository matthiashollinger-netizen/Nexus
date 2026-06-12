import SwiftUI

// MARK: - Nexus Design System — Reusable Components  (v3.0)
//
// Built once on the `DS` tokens, consumed by the sidebar, tab bar, dashboard and
// command palette. These replace the dozens of one-off VStacks, ad-hoc empty
// states, hardcoded status dots and inconsistent cards the audit found scattered
// across the app. Every component honors light/dark and Reduce Motion.

// MARK: StatusDot — colorblind-safe, breathing live-status indicator

/// Hue carries the state but is reinforced by a glyph + label elsewhere, and
/// `.connecting` breathes a soft halo so an in-progress login is visibly alive.
struct StatusDot: View {
    let state: ConnectionState
    var size: CGFloat = DS.Icon.statusDot
    var animated: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var shouldPulse: Bool { state.pulses && animated && !reduceMotion }

    var body: some View {
        Circle()
            .fill(state.tint)
            .frame(width: size, height: size)
            .overlay {
                if shouldPulse {
                    Circle()
                        .stroke(state.tint, lineWidth: 1.5)
                        .scaleEffect(pulse ? 1.9 : 1.0)
                        .opacity(pulse ? 0 : 0.6)
                }
            }
            .onAppear {
                guard shouldPulse else { return }
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .onChange(of: shouldPulse) { _, now in
                pulse = false
                guard now else { return }
                withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
            .help(state.label)
    }
}

// MARK: StateBadge — a labelled status pill

struct StateBadge: View {
    let state: ConnectionState
    var showLabel: Bool = true

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            StatusDot(state: state, size: 7)
            if showLabel {
                Text(state.label)
                    .font(DS.Font.caption)
            }
        }
        .foregroundStyle(state.tint)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, 3)
        .background(state.tint.opacity(0.12), in: Capsule())
    }
}

// MARK: MonoText — tabular IP/port/latency so columns align for fast diffing

struct MonoText: View {
    let string: String
    var tint: Color = DS.Color.textSecondary
    init(_ string: String, tint: Color = DS.Color.textSecondary) {
        self.string = string; self.tint = tint
    }
    var body: some View {
        Text(string)
            .font(DS.Font.mono)
            .foregroundStyle(tint)
            .lineLimit(1)
    }
}

// MARK: KeyHint — inline keyboard-shortcut teaching chips

struct KeyHint: View {
    let keys: [String]
    init(_ keys: [String]) { self.keys = keys }

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, 1)
                    .frame(minWidth: 16)
                    .background(DS.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .strokeBorder(DS.Color.hairline, lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: IconBadge — a glyph inside a soft tinted rounded square

struct IconBadge: View {
    let systemImage: String
    var tint: Color = DS.Color.accent
    var pointSize: CGFloat = DS.Icon.card

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: pointSize, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: pointSize + 18, height: pointSize + 18)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }
}

// MARK: SectionHeader — eyebrow + optional count + optional trailing action

struct SectionHeader: View {
    let titleKey: LocalizedStringKey
    var count: Int? = nil
    var actionLabel: LocalizedStringKey? = nil
    var action: (() -> Void)? = nil

    init(_ titleKey: LocalizedStringKey, count: Int? = nil,
         actionLabel: LocalizedStringKey? = nil, action: (() -> Void)? = nil) {
        self.titleKey = titleKey; self.count = count
        self.actionLabel = actionLabel; self.action = action
    }

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(titleKey)
                .font(DS.Font.eyebrow)
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(DS.Color.textSecondary)
            if let count {
                Text("\(count)")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
            if let actionLabel, let action {
                Button(action: action) {
                    Text(actionLabel).font(DS.Font.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DS.Color.accent)
            }
        }
    }
}

// MARK: NexusCard — the standard panel / tile container (hover-lifts)

struct NexusCard<Content: View>: View {
    var padding: CGFloat = DS.Space.xl
    var radius: CGFloat = DS.Radius.lg
    var hoverLift: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var lifted: Bool { hoverLift && hovering && !reduceMotion }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.surfaceRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(DS.Color.hairline, lineWidth: 1)
            )
            .scaleEffect(lifted ? 1.012 : 1)
            .shadow(color: .black.opacity(lifted ? 0.16 : 0), radius: lifted ? 14 : 8, y: lifted ? 4 : 2)
            .animation(DS.Motion.gentle, value: lifted)
            .onHover { h in hovering = h }
    }
}

// MARK: QuickActionTile — dashboard quick-actions grid item

struct QuickActionTile: View {
    let symbol: String
    let title: LocalizedStringKey
    var tint: Color = DS.Color.accent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: DS.Space.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Text(title)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, DS.Space.md)
            .background(hovering ? DS.Color.rowHover : DS.Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(DS.Color.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(DS.Motion.quick) { hovering = h } }
    }
}

// MARK: EmptyStateView — one component for every "nothing here yet" surface

struct EmptyStateView: View {
    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var tint: Color = DS.Color.accent
    var primary: (LocalizedStringKey, () -> Void)? = nil
    var secondary: (LocalizedStringKey, () -> Void)? = nil

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Image(systemName: symbol)
                .font(.system(size: DS.Icon.emptyState, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 84, height: 84)
                .background(tint.opacity(0.10), in: Circle())
            VStack(spacing: DS.Space.sm) {
                Text(title)
                    .font(DS.Font.title)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message)
                        .font(DS.Font.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            if primary != nil || secondary != nil {
                HStack(spacing: DS.Space.md) {
                    if let secondary {
                        Button(action: secondary.1) { Text(secondary.0) }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                    }
                    if let primary {
                        Button(action: primary.1) { Text(primary.0) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
        }
        .padding(DS.Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: InfoCard — info / warning / danger / success callout

struct InfoCard: View {
    enum Style {
        case info, warning, danger, success
        var tint: Color {
            switch self {
            case .info: return DS.Color.info
            case .warning: return DS.Color.warning
            case .danger: return DS.Color.stateFailed
            case .success: return DS.Color.stateConnected
            }
        }
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .danger: return "xmark.octagon.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }

    var style: Style = .info
    var icon: String? = nil
    var title: LocalizedStringKey? = nil
    let message: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            Image(systemName: icon ?? style.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(style.tint)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                if let title {
                    Text(title).font(DS.Font.callout.weight(.semibold))
                }
                Text(message)
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.lg)
        .background(style.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}
