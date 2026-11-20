import SwiftUI

// Stream skins: how the score bar looks on the outgoing stream. Classic is
// free, the rest are paid. Purchases are simulated until StoreKit products
// exist in App Store Connect; prices are placeholders.

struct Skin: Identifiable, Equatable {
    let id: String
    let name: String
    let price: String?          // nil = free
    let bar: Color
    let text: Color
    let accent: Color
    let slant: Bool
    let glow: Bool

    static let all: [Skin] = [
        Skin(id: "classic", name: "Classic", price: nil,
             bar: Color(white: 0.06).opacity(0.86), text: .white, accent: .white, slant: false, glow: false),
        Skin(id: "neon", name: "Neon", price: "1,99 €",
             bar: Color(red: 0.02, green: 0.03, blue: 0.07), text: .white,
             accent: Color(red: 0.25, green: 0.92, blue: 1), slant: false, glow: true),
        Skin(id: "gold", name: "Gold", price: "2,99 €",
             bar: Color(red: 0.07, green: 0.06, blue: 0.045), text: Color(red: 0.98, green: 0.93, blue: 0.82),
             accent: Color(red: 0.86, green: 0.68, blue: 0.33), slant: false, glow: false),
        Skin(id: "street", name: "Street", price: "1,99 €",
             bar: .white, text: .black, accent: .pla, slant: true, glow: false),
    ]

    static func find(_ id: String) -> Skin { all.first { $0.id == id } ?? all[0] }
}

// What each skin does with the clock cell and the outline.
private extension Skin {
    var clockFill: AnyShapeStyle {
        switch id {
        case "gold":
            return AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.82, blue: 0.52), accent,
                                                         Color(red: 0.62, green: 0.46, blue: 0.2)],
                                                startPoint: .top, endPoint: .bottom))
        case "street": return AnyShapeStyle(accent)
        case "neon": return AnyShapeStyle(accent.opacity(0.12))
        default: return AnyShapeStyle(Color.white.opacity(0.1))
        }
    }

    var clockText: Color {
        switch id {
        case "gold": return Color(red: 0.12, green: 0.09, blue: 0.04)
        case "street": return .white
        case "neon": return accent
        default: return text
        }
    }

    var outline: AnyShapeStyle {
        switch id {
        case "gold":
            return AnyShapeStyle(LinearGradient(colors: [accent, accent.opacity(0.35), accent],
                                                startPoint: .leading, endPoint: .trailing))
        case "neon": return AnyShapeStyle(accent.opacity(0.9))
        case "street": return AnyShapeStyle(Color.clear)
        default: return AnyShapeStyle(Color.white.opacity(0.14))
        }
    }
}

/// The score bar as it would sit on the stream, in a given skin.
struct ScoreBar: View {
    let skin: Skin
    var home = "HOME", away = "AWAY"
    var homeScore = 24, awayScore = 19
    var homeColor = Color(hex: "#2f6fdb")!, awayColor = Color(hex: "#c8102e")!
    var homeLogo: UIImage?, awayLogo: UIImage?
    var scale: CGFloat = 1

    private var s: CGFloat { scale }

    var body: some View {
        HStack(spacing: 0) {
            team(home, homeScore, homeColor, homeLogo, trailing: false)
            clock
            team(away, awayScore, awayColor, awayLogo, trailing: true)
        }
        .frame(height: 36 * s)
        .background(skin.bar)
        .clipShape(barShape)
        .overlay(barShape.stroke(skin.outline, lineWidth: (skin.glow ? 1.2 : 1) * s))
        .shadow(color: skin.glow ? skin.accent.opacity(0.55) : .black.opacity(0.35),
                radius: (skin.glow ? 7 : 6) * s, y: skin.glow ? 0 : 2 * s)
        .environment(\.layoutDirection, .leftToRight)
        .fixedSize()
    }

    private var barShape: AnyShape {
        skin.slant ? AnyShape(Slant(inset: 9 * s))
                   : AnyShape(RoundedRectangle(cornerRadius: 9 * s, style: .continuous))
    }

    private var clock: some View {
        VStack(spacing: 0) {
            Text("Q2").font(.system(size: 8.5 * s, weight: .semibold)).opacity(0.75)
            Text("6:12").font(.system(size: 11.5 * s, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(skin.clockText)
        .frame(width: 46 * s)
        .frame(maxHeight: .infinity)
        .background(skin.clockFill)
    }

    @ViewBuilder
    private func team(_ name: String, _ score: Int, _ color: Color, _ logo: UIImage?, trailing: Bool) -> some View {
        let strip = Rectangle().fill(color).frame(width: 4 * s)
        let label = Text(Self.code(name))
            .font(.system(size: 12 * s, weight: .bold))
            .tracking(0.4 * s)
            .lineLimit(1)
            .frame(width: 44 * s, alignment: trailing ? .trailing : .leading)
            .padding(.horizontal, 8 * s)
        let points = Text("\(score)")
            .font(.system(size: 18 * s, weight: .heavy))
            .monospacedDigit()
            .frame(minWidth: 26 * s)
        HStack(spacing: 0) {
            if trailing {
                points.padding(.leading, 10 * s)
                label
                mark(logo).padding(.trailing, logo == nil ? 0 : 7 * s)
                strip
            } else {
                strip
                mark(logo).padding(.leading, logo == nil ? 0 : 7 * s)
                label
                points.padding(.trailing, 10 * s)
            }
        }
        .foregroundStyle(skin.text)
        .frame(maxHeight: .infinity)
    }

    /// Broadcast-style team code: a name of up to 4 letters stays, two or
    /// more words give their initials (up to 3), else the first 3 letters.
    static func code(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 4 { return trimmed.uppercased() }
        let words = trimmed.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.count >= 2 {
            return String(words.prefix(3).compactMap(\.first)).uppercased()
        }
        return String(trimmed.prefix(3)).uppercased()
    }

    @ViewBuilder
    private func mark(_ logo: UIImage?) -> some View {
        if let logo {
            Image(uiImage: logo).resizable().scaledToFill()
                .frame(width: 20 * s, height: 20 * s)
                .clipShape(Circle())
        }
    }
}

struct Slant: Shape {
    let inset: CGFloat
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX + inset, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

/// A small chip of a skin for list rows: bar colour, clock cell, outline.
struct SkinSwatch: View {
    let skin: Skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        HStack(spacing: 0) {
            Color.clear
            Rectangle().fill(skin.clockFill).frame(width: 10)
            Color.clear
        }
        .frame(width: 40, height: 22)
        .background(skin.bar)
        .clipShape(shape)
        .overlay(shape.stroke(skin.outline, lineWidth: 1))
        .accessibilityHidden(true)
    }
}
