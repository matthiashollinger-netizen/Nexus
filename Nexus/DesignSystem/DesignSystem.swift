import SwiftUI

// MARK: - Nexus Design System  (v3.0)
//
// The single source of truth for spacing, radius, typography and semantic color.
// Before this file every view hardcoded its own values — the audit found 8
// different corner radii, ~149 ad-hoc `.font()` calls, scattered paddings and
// literal `.green`/`.red`/`.black`. Everything visual now reaches for a `DS`
// token so the whole app reads as one cohesive, native-macOS instrument.
//
// Identity: a calm, dense, status-first tool built from system materials. Color
// is rationed almost entirely to connection state; depth comes from materials +
// hairline borders, not heavy shadows. The terminal `NexusTheme` (ANSI colors +
// per-session font) is intentionally EXEMPT and untouched.
//
// All tokens are immutable statics of Sendable types, safe to read from any
// context (views, AppKit terminal code, services).

enum DS {

    // MARK: Spacing — one 4pt-anchored grid
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12   // row horizontal inset
        static let xl: CGFloat = 16   // card inner padding
        static let xxl: CGFloat = 24  // section gap
        static let xxxl: CGFloat = 32 // page outer margin
    }

    // MARK: Corner radius — one ladder, continuous curves everywhere
    enum Radius {
        static let sm: CGFloat = 5    // pills, tags, key-hint chips, small buttons
        static let md: CGFloat = 8    // rows, tab items, text fields
        static let lg: CGFloat = 12   // cards, palette, popovers, dashboard panels
        static let xl: CGFloat = 16   // sheets / large modals
        static let pill: CGFloat = 999
    }

    // MARK: Typography — explicit pt for tabular density (maps to system SF)
    // Inside this enum, `SwiftUI.Font` is spelled out so it isn't shadowed by the
    // enum name.
    enum Font {
        /// 20 semibold — dashboard hero / greeting.
        static let display: SwiftUI.Font = .system(size: 20, weight: .semibold)
        /// 15 semibold — sheet / panel / palette field titles.
        static let title: SwiftUI.Font = .system(size: 15, weight: .semibold)
        /// 13 semibold — section headers, selected/active rows.
        static let headline: SwiftUI.Font = .system(size: 13, weight: .semibold)
        /// 13 — primary row text, default control baseline.
        static let body: SwiftUI.Font = .system(size: 13)
        /// 12 — secondary row text.
        static let callout: SwiftUI.Font = .system(size: 12)
        /// 11 medium — tags, badges, metadata.
        static let caption: SwiftUI.Font = .system(size: 11, weight: .medium)
        /// 11 medium monospaced + tabular digits — IP / port / latency / baud.
        static let mono: SwiftUI.Font = .system(size: 11, weight: .medium, design: .monospaced).monospacedDigit()
        /// 10 semibold, used UPPERCASED with tracking for section eyebrows.
        static let eyebrow: SwiftUI.Font = .system(size: 10, weight: .semibold)
    }

    // MARK: Semantic colors — NSColor/material-backed so light/dark + accent +
    // increase-contrast resolve for free. `SwiftUI.Color` is spelled out so it
    // isn't shadowed by the enum name.
    enum Color {
        // Surfaces
        static let surface = SwiftUI.Color(nsColor: .windowBackgroundColor)
        static let surfaceRaised = SwiftUI.Color(nsColor: .controlBackgroundColor)
        // Content
        static let textPrimary = SwiftUI.Color(nsColor: .labelColor)
        static let textSecondary = SwiftUI.Color(nsColor: .secondaryLabelColor)
        static let textTertiary = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        // Lines & accents
        static let hairline = SwiftUI.Color(nsColor: .separatorColor)
        static let accent = SwiftUI.Color.accentColor
        // Interaction washes
        static let rowHover = SwiftUI.Color.primary.opacity(0.06)
        static let rowSelected = SwiftUI.Color.accentColor.opacity(0.14)

        // Connection-state palette — the ONLY saturated color in the app. System
        // colors already resolve to the blueprint's light/dark hex (emerald,
        // amber, rose) and adapt to appearance + increase-contrast automatically.
        static let stateConnected = SwiftUI.Color(nsColor: .systemGreen)
        static let stateConnecting = SwiftUI.Color(nsColor: .systemOrange)
        static let stateFailed = SwiftUI.Color(nsColor: .systemRed)
        static let stateIdle = SwiftUI.Color(nsColor: .tertiaryLabelColor)
        static let stateDisconnected = SwiftUI.Color(nsColor: .secondaryLabelColor)
        // Generic callout hues (info cards, warnings)
        static let info = SwiftUI.Color(nsColor: .systemBlue)
        static let warning = SwiftUI.Color(nsColor: .systemYellow)
    }

    // MARK: Icon sizes — SF Symbols on a fixed grid
    enum Icon {
        static let statusDot: CGFloat = 8
        static let row: CGFloat = 16        // protocol glyph (always .frame(width:16))
        static let tab: CGFloat = 13
        static let toolbar: CGFloat = 15
        static let card: CGFloat = 22
        static let emptyState: CGFloat = 44
    }

    // MARK: Motion
    enum Motion {
        /// Snappy spring — selection, hover, palette entrance, insertion lines.
        static let snappy: Animation = .spring(response: 0.28, dampingFraction: 0.86)
        /// Gentle spring — content/layout transitions, card hover-lift.
        static let gentle: Animation = .spring(response: 0.3, dampingFraction: 0.8)
        /// Quick ease — opacity / hover reveals.
        static let quick: Animation = .easeOut(duration: 0.14)
    }
}

// MARK: - dsPadding convenience

extension View {
    /// Apply a design-token padding so no raw spacing numbers appear at call sites.
    func dsPadding(_ edges: Edge.Set = .all, _ token: CGFloat = DS.Space.xl) -> some View {
        padding(edges, token)
    }
}

// MARK: - ConnectionState → presentation
//
// The SINGLE source of truth mapping a live connection state to its color, SF
// Symbol and localized label. Because `ConnectionState` carries an associated
// value (`.failed(String)`) and is not Equatable, this is a computed switch —
// the `.failed` case ignores its message. Every status indicator (sidebar dot,
// tab item, dashboard, server panel) reads from here, so "connected" looks
// identical everywhere and no view hardcodes `.green`/`.red` again.

extension ConnectionState {
    var tint: Color {
        switch self {
        case .connected: return DS.Color.stateConnected
        case .connecting: return DS.Color.stateConnecting
        case .failed: return DS.Color.stateFailed
        case .disconnected: return DS.Color.stateDisconnected
        case .idle: return DS.Color.stateIdle
        }
    }

    /// A distinct glyph per state — this is what keeps the palette colorblind-safe.
    var symbol: String {
        switch self {
        case .connected: return "circle.fill"
        case .connecting: return "circle.dotted"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "pause.circle.fill"
        case .idle: return "circle"
        }
    }

    var label: LocalizedStringKey {
        switch self {
        case .connected: return "status.connected"
        case .connecting: return "status.connecting"
        case .failed: return "status.failed"
        case .disconnected: return "status.disconnected"
        case .idle: return "status.idle"
        }
    }

    /// Only `connecting` breathes; steady states stay calm.
    var pulses: Bool {
        if case .connecting = self { return true }
        return false
    }
}
