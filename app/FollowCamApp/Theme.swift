import SwiftUI
import UIKit

// Apple-style iOS: SF Pro, system lists, tab bar and sheets, dark. Black,
// white and orange like the pod; orange is the app tint (actions, the
// selected tab, the locked player). Team colours only mark a team.

extension Color {
    static let pla = Color(red: 0.92, green: 0.39, blue: 0.08)
    static let servo = Color(red: 0.15, green: 0.38, blue: 0.90)
    static let chrome = Color(white: 0.55)
    static let ink = Color.black
    static let surface = Color(white: 0.055)
    static let hairline = Color(white: 0.13)
    static let muted = Color(white: 0.56)

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
    /// Display: SF Pro, heavy, for numbers, names and titles.
    static func wide(_ size: CGFloat, _ weight: CGFloat = 700) -> Font {
        .system(size: size, weight: weight >= 850 ? .heavy : (weight >= 650 ? .bold : .semibold))
    }

    /// Text: SF Pro, for sentences and labels.
    static func text(_ size: CGFloat, _ weight: CGFloat = 400) -> Font {
        let w: Font.Weight = switch weight {
        case ..<450: .regular
        case ..<575: .medium
        case ..<675: .semibold
        default: .bold
        }
        return .system(size: size, weight: w)
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

/// Buttons give way under the thumb instead of just dimming.
struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// Black glass for anything that floats over the picture.
struct Glass: ViewModifier {
    var radius: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial.opacity(0.9))
            .background(Color.black.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08)))
    }
}

extension View {
    func glass(_ radius: CGFloat = 16) -> some View { modifier(Glass(radius: radius)) }
}
