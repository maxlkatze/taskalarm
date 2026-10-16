import AppKit
import SwiftUI

/// One accent color (a friendly violet) plus three semantic status colors
/// that are only ever used to signal state.
enum Theme {
    static let accentNS = NSColor(srgbRed: 0.486, green: 0.361, blue: 1.000, alpha: 1) // #7C5CFF
    static let goodNS   = NSColor(srgbRed: 0.204, green: 0.780, blue: 0.482, alpha: 1) // #34C77B
    static let warnNS   = NSColor(srgbRed: 1.000, green: 0.690, blue: 0.125, alpha: 1) // #FFB020
    static let badNS    = NSColor(srgbRed: 1.000, green: 0.302, blue: 0.369, alpha: 1) // #FF4D5E

    static let accent = Color(nsColor: accentNS)
    static let good = Color(nsColor: goodNS)
    static let warn = Color(nsColor: warnNS)
    static let bad = Color(nsColor: badNS)

    /// Dark ink used for the smiley's eyes and mouth.
    static let ink = Color(red: 0.11, green: 0.08, blue: 0.19)
    static let blush = Color(red: 1.0, green: 0.55, blue: 0.70)

    static let corner: CGFloat = 12
}

/// Overall state shown in the menu bar.
enum StatusLevel: Equatable {
    case clear, soon, alert, overdue

    var nsColor: NSColor {
        switch self {
        case .clear: return Theme.goodNS
        case .soon, .alert: return Theme.warnNS
        case .overdue: return Theme.badNS
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

// MARK: - Reusable button styles

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(tint.gradient))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08)))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IconButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hovering ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hovering = $0 }
            .contentShape(Circle())
    }
}

extension View {
    /// Runs haptics and a soft tick when the view is clicked.
    func hapticTap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) -> some View {
        simultaneousGesture(TapGesture().onEnded { Haptics.tap(pattern) })
    }
}
