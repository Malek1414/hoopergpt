import SwiftUI

// Orange = the printed parts' PLA; blue = servo; red = REC only.
// Shared by every screen so the onboarding, the viewer and the camera chrome
// speak the same colour language.
extension Color {
    static let pla = Color(red: 0.92, green: 0.39, blue: 0.08)
    static let servo = Color(red: 0.15, green: 0.38, blue: 0.90)
    static let chrome = Color(white: 0.55)
    static let panel = Color(white: 0.09)

    /// "#rrggbb" from state.json; nil for anything else.
    init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255,
                  green: Double((v >> 8) & 0xff) / 255,
                  blue: Double(v & 0xff) / 255)
    }
}

extension Font {
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// Placeholder wordmark until the logo is decided. One place to swap it.
struct Wordmark: View {
    var size: CGFloat = 34

    var body: some View {
        HStack(spacing: 0) {
            Text("Hooper").foregroundColor(.white)
            Text("GPT").foregroundColor(.pla)
        }
        .font(.system(size: size, weight: .heavy, design: .rounded))
        .accessibilityLabel("HooperGPT")
    }
}

/// Full-width primary action used across onboarding and the viewer.
struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.mono(15, .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(enabled ? Color.pla : Color(white: 0.2))
                .foregroundColor(enabled ? .black : .chrome)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!enabled)
    }
}
