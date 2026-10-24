import CoreText
import SwiftUI
import UIKit

// Floodlight: the picture is the hero, everything else is black glass over
// it. One typeface (Archivo, variable width + weight), white type, team
// colours as the only colour. Orange stays for the locked target and REC.

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

// MARK: - Archivo

enum Archivo {
    /// Registers the bundled variable font once, at launch.
    static let base: UIFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "Archivo", withExtension: "ttf") else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
        return descriptors?.first.map { $0 as UIFontDescriptor }
    }()

    /// weight 100...900, width 62...125 (100 = normal, 125 = expanded).
    static func uiFont(_ size: CGFloat, weight: CGFloat, width: CGFloat) -> UIFont {
        guard let base else { return .systemFont(ofSize: size, weight: .bold) }
        let axes: [NSNumber: CGFloat] = [
            NSNumber(value: 0x7767_6874): weight,   // 'wght'
            NSNumber(value: 0x7764_7468): width,    // 'wdth'
        ]
        let descriptor = base.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

extension Font {
    /// Display: wide and heavy, for numbers and titles.
    static func wide(_ size: CGFloat, _ weight: CGFloat = 850) -> Font {
        Font(Archivo.uiFont(size, weight: weight, width: 125))
    }

    /// Text: normal width, for sentences and labels.
    static func text(_ size: CGFloat, _ weight: CGFloat = 500) -> Font {
        Font(Archivo.uiFont(size, weight: weight, width: 100))
    }

    /// Old name kept for the camera chrome while it is being restyled.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Placeholder wordmark until the logo is decided. One place to swap it.
struct Wordmark: View {
    var size: CGFloat = 34

    var body: some View {
        Text("HOOPER\nGPT")
            .font(.wide(size, 900))
            .lineSpacing(-size * 0.2)
            .foregroundColor(.white)
            .accessibilityLabel("HooperGPT")
    }
}

/// White capsule, black label. The one primary action per screen.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.wide(17, 800))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(enabled ? Color.white : Color(white: 0.16))
                .foregroundColor(enabled ? .black : .muted)
                .clipShape(Capsule())
        }
        .disabled(!enabled)
        .buttonStyle(PressScale())
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
