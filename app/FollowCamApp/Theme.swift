import SwiftUI
import UIKit

// Apple-style iOS: SF Pro, system lists, tab bar and sheets, dark. Black,
// white and orange like the pod; orange is the app tint (actions, the
// selected tab, the locked player). Team colours only mark a team.

extension Color {
    static let pla = Color(red: 0.92, green: 0.39, blue: 0.08)
    // System colours, so the app follows iOS (contrast settings included).
    static let ink = Color(.systemBackground)
    static let surface = Color(.secondarySystemBackground)
    static let hairline = Color(.separator)
    static let muted = Color(.secondaryLabel)

    /// "#rrggbb" from state.json; nil for anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

// MARK: - type: SF Pro, like the rest of iOS

extension Font {
    /// The iOS text style closest to a point size, so text grows with the
    /// user's Dynamic Type setting instead of staying fixed.
    private static func style(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 34...: return .largeTitle
        case 28..<34: return .title
        case 22..<28: return .title2
        case 20..<22: return .title3
        case 17..<20: return .body
        case 16..<17: return .callout
        case 15..<16: return .subheadline
        case 13..<15: return .footnote
        case 12..<13: return .caption
        default: return .caption2
        }
    }

    private static func weight(_ w: CGFloat) -> Font.Weight {
        switch w {
        case ..<450: return .regular
        case ..<575: return .medium
        case ..<675: return .semibold
        case ..<850: return .bold
        default: return .heavy
        }
    }

    /// Display: bold SF Pro for numbers, names and titles; scales with Dynamic Type.
    static func wide(_ size: CGFloat, _ weight: CGFloat = 700) -> Font {
        .system(style(for: size), weight: Self.weight(max(weight, 600)))
    }

    /// Text: SF Pro for sentences and labels; scales with Dynamic Type.
    static func text(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        .system(style(for: size), weight: Self.weight(weight))
    }
}

/// Placeholder wordmark until the logo is decided. One place to swap it.
struct Wordmark: View {
    var size: CGFloat = 34

    var body: some View {
        (Text("Hooper").foregroundColor(.white) + Text("GPT").foregroundColor(.pla))
            .font(.system(size: size, weight: .heavy))
            .accessibilityLabel("HooperGPT")
    }
}

/// The one primary action per screen: Apple's large prominent button.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.pla)
        .disabled(!enabled)
    }
}


/// Glass for anything that floats over the picture: Liquid Glass on iOS 26,
/// a dark material before that.
struct Glass: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(Color.black.opacity(0.3), in: shape)
        }
    }
}

extension View {
    func glass(_ radius: CGFloat = 16) -> some View { modifier(Glass(radius: radius)) }
}
