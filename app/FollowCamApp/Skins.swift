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
             bar: .black.opacity(0.75), text: .white, accent: .white, slant: false, glow: false),
        Skin(id: "neon", name: "Neon", price: "1,99 €",
             bar: Color(red: 0.03, green: 0.02, blue: 0.08), text: .white,
             accent: Color(red: 0.2, green: 0.95, blue: 1), slant: false, glow: true),
        Skin(id: "gold", name: "Gold", price: "2,99 €",
             bar: Color(red: 0.07, green: 0.06, blue: 0.04), text: Color(red: 0.98, green: 0.92, blue: 0.78),
             accent: Color(red: 0.84, green: 0.65, blue: 0.29), slant: false, glow: false),
        Skin(id: "street", name: "Street", price: "1,99 €",
             bar: .white, text: .black, accent: .pla, slant: true, glow: false),
    ]

    static func find(_ id: String) -> Skin { all.first { $0.id == id } ?? all[0] }
}

/// The score bar as it would sit on the stream, in a given skin.
struct ScoreBar: View {
    let skin: Skin
    var home = "HOME", away = "AWAY"
    var homeScore = 24, awayScore = 19
    var homeColor = Color(hex: "#2f6fdb")!, awayColor = Color(hex: "#c8102e")!
    var homeLogo: UIImage?, awayLogo: UIImage?
    var scale: CGFloat = 1

    var body: some View {
        HStack(spacing: 10 * scale) {
            side(home, homeScore, homeColor, homeLogo)
            Text("Q2 6:12")
                .font(.wide(10 * scale, 700))
                .foregroundColor(skin.text.opacity(0.7))
            side(away, awayScore, awayColor, awayLogo, trailing: true)
        }
        .padding(.horizontal, 12 * scale)
        .frame(height: 34 * scale)
        .background(skin.bar)
        .clipShape(barShape)
        .overlay(barShape.stroke(skin.accent.opacity(skin.glow ? 0.9 : 0), lineWidth: 1.5 * scale))
        .shadow(color: skin.glow ? skin.accent.opacity(0.7) : .clear, radius: 8 * scale)
        .overlay(alignment: .bottom) {
            if !skin.glow && skin.id != "classic" {
                Rectangle().fill(skin.accent).frame(height: 2 * scale).padding(.horizontal, 10 * scale)
            }
        }
    }

    private var barShape: AnyShape {
        skin.slant ? AnyShape(Slant(inset: 10 * scale)) : AnyShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
    }

    private func side(_ name: String, _ score: Int, _ color: Color, _ logo: UIImage?, trailing: Bool = false) -> some View {
        HStack(spacing: 6 * scale) {
            if trailing { Text("\(score)").font(.wide(17 * scale, 900)).foregroundColor(skin.text) }
            badge(name, color, logo)
            if !trailing { Text("\(score)").font(.wide(17 * scale, 900)).foregroundColor(skin.text) }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    @ViewBuilder
    private func badge(_ name: String, _ color: Color, _ logo: UIImage?) -> some View {
        if let logo {
            Image(uiImage: logo).resizable().scaledToFill()
                .frame(width: 20 * scale, height: 20 * scale)
                .clipShape(Circle())
        } else {
            HStack(spacing: 4 * scale) {
                Rectangle().fill(color).frame(width: 3 * scale, height: 14 * scale)
                Text(name).font(.wide(10 * scale, 800)).foregroundColor(skin.text)
            }
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
