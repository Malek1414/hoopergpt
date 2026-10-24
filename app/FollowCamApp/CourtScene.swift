import SwiftUI

// Drawn court, used where there is no real picture yet: the onboarding
// hero and the skin previews. The hero loops what the app does in three
// beats of four seconds: tracking, going live, counting the shot.

private let home = Color(hex: "#2f6fdb")!
private let away = Color(hex: "#c8102e")!

/// 0 before a, 1 after b, smooth in between.
private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double {
    let x = min(max((t - a) / (b - a), 0), 1)
    return x * x * (3 - 2 * x)
}

// MARK: - the court

struct CourtLines: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.05, green: 0.055, blue: 0.07)))
            let line = GraphicsContext.Shading.color(.white.opacity(0.16))
            let w = size.width, h = size.height
            var p = Path()
            // baseline, key, free-throw circle, three-point arc, half-court circle
            p.move(to: CGPoint(x: 0, y: h * 0.08)); p.addLine(to: CGPoint(x: w, y: h * 0.08))
            p.addRect(CGRect(x: w * 0.34, y: h * 0.08, width: w * 0.32, height: h * 0.34))
            p.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.42 - w * 0.12, width: w * 0.24, height: w * 0.24))
            p.move(to: CGPoint(x: w * 0.07, y: h * 0.08))
            p.addLine(to: CGPoint(x: w * 0.07, y: h * 0.26))
            p.addQuadCurve(to: CGPoint(x: w * 0.93, y: h * 0.26), control: CGPoint(x: w * 0.5, y: h * 0.86))
            p.addLine(to: CGPoint(x: w * 0.93, y: h * 0.08))
            p.addEllipse(in: CGRect(x: w * 0.36, y: h * 0.96, width: w * 0.28, height: w * 0.28))
            ctx.stroke(p, with: line, lineWidth: 1.5)
            // rim
            ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.5 - 9, y: h * 0.12 - 4, width: 18, height: 8)),
                       with: .color(.pla.opacity(0.9)), lineWidth: 2)
        }
    }
}

// MARK: - onboarding hero

struct OnboardingHero: View {
    @State private var start = Date()
    static let beat: Double = 4
    static let loop: Double = 12

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: Self.loop)
            GeometryReader { geo in
                frame(t: t, size: geo.size)
            }
        }
        .accessibilityLabel("The app follows the players, streams the game and counts the shots")
    }

    /// Where each player stands at time t, in unit coordinates.
    private func players(_ t: Double) -> [(CGPoint, Color)] {
        let base: [(Double, Double, Color, Double)] = [
            (0.50, 0.55, home, 0.0),   // ball carrier
            (0.28, 0.38, home, 1.7),
            (0.72, 0.34, away, 3.1),
            (0.40, 0.66, away, 4.4),
            (0.66, 0.62, home, 5.2),
        ]
        return base.map { (x: Double, y: Double, c: Color, phase: Double) -> (CGPoint, Color) in
            let dx: Double = 0.07 * sin(t * 0.9 + phase)
            let dy: Double = 0.05 * cos(t * 0.7 + phase)
            return (CGPoint(x: x + dx, y: y + dy), c)
        }
    }

    @ViewBuilder
    private func frame(t: Double, size: CGSize) -> some View {
        let live = ramp(t, 4.0, 4.8) * (1 - ramp(t, 11.4, 12))
        let stats = ramp(t, 9.3, 10.2) * (1 - ramp(t, 11.4, 12))
        let shrink = 1 - 0.14 * live
        let carrier = players(t)[0].0
        let rim = CGPoint(x: 0.5, y: 0.12)
        // the shot: the ball leaves the carrier at 8 s and drops in at 9.2 s
        let flight = ramp(t, 8.0, 9.2)
        let ball = CGPoint(x: carrier.x + 0.03 + (rim.x - carrier.x - 0.03) * flight,
                           y: carrier.y - 0.02 + (rim.y - carrier.y + 0.02) * flight - 0.28 * sin(.pi * flight))
        let scored = t >= 9.2 && t < 11.6

        ZStack {
            ZStack {
                CourtLines()
                Canvas { ctx, s in
                    let ringIn = ramp(t, 0.3, 1.1) * (1 - ramp(t, 11.4, 12))
                    // the camera's line of sight, first beat only
                    let sight = ringIn * (1 - ramp(t, 3.4, 4.2))
                    if sight > 0 {
                        var los = Path()
                        los.move(to: CGPoint(x: s.width * 0.5, y: s.height * 1.02))
                        los.addLine(to: CGPoint(x: carrier.x * s.width, y: carrier.y * s.height))
                        ctx.stroke(los, with: .color(.white.opacity(0.35 * sight)),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
                    }
                    for (i, (pt, color)) in players(t).enumerated() {
                        let c = CGPoint(x: pt.x * s.width, y: pt.y * s.height)
                        let rw: CGFloat = i == 0 ? 46 : 38
                        let ring = Path(ellipseIn: CGRect(x: c.x - rw / 2, y: c.y + 4 - rw * 0.15, width: rw, height: rw * 0.3))
                        if i == 0 {
                            ctx.fill(ring, with: .color(.pla.opacity(0.2 * ringIn)))
                            ctx.stroke(ring, with: .color(.pla.opacity(ringIn)), lineWidth: 2.5)
                        } else {
                            ctx.stroke(ring, with: .color(.white.opacity(0.65 * ringIn)), lineWidth: 1.3)
                        }
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)), with: .color(color))
                        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 8, y: c.y - 8, width: 16, height: 16)),
                                   with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                    }
                    let b = CGPoint(x: ball.x * s.width, y: ball.y * s.height)
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 5, y: b.y - 5, width: 10, height: 10)), with: .color(.pla))
                }
                if scored {
                    Text("+2")
                        .font(.wide(28, 900))
                        .foregroundColor(.white)
                        .position(x: size.width * 0.5, y: size.height * (0.2 - 0.05 * ramp(t, 9.2, 10)))
                        .opacity(1 - ramp(t, 10.4, 11))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 28 * live, style: .continuous))
            .overlay(alignment: .top) {
                ScoreBar(skin: Skin.find("classic"), homeScore: scored || t >= 11.6 ? 24 : 22, scale: 1.05)
                    .padding(.top, 14)
                    .opacity(live)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("LIVE").font(.wide(11, 900))
                    Text("\(Int(120 + 900 * ramp(t, 4.5, 11)))").font(.text(11, 600)).foregroundColor(.white.opacity(0.75))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10).frame(height: 24)
                .glass(12)
                .padding(.leading, 14).padding(.top, 58)
                .opacity(live)
            }
            .scaleEffect(shrink)

            statsPanel(fill: stats)
                .padding(.horizontal, 28)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 26)
                .opacity(stats)
                .offset(y: 30 * (1 - stats))
        }
    }

    private func statsPanel(fill: Double) -> some View {
        VStack(spacing: 12) {
            statRow("Points", 24, 19, max: 30, fill: fill)
            statRow("Field goals", 48, 41, max: 70, fill: fill, suffix: "%")
        }
        .padding(16)
        .glass(20)
    }

    private func statRow(_ label: String, _ a: Int, _ b: Int, max: Double, fill: Double, suffix: String = "") -> some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(a)\(suffix)").font(.wide(16, 850))
                Spacer()
                Text(label).font(.text(13, 550)).foregroundColor(.white.opacity(0.7))
                Spacer()
                Text("\(b)\(suffix)").font(.wide(16, 850)).foregroundColor(.white.opacity(0.75))
            }
            GeometryReader { geo in
                let half = geo.size.width / 2 - 3
                HStack(spacing: 6) {
                    HStack { Spacer(minLength: 0); Capsule().fill(home).frame(width: half * CGFloat(Double(a) / max * fill)) }
                    HStack { Capsule().fill(away).frame(width: half * CGFloat(Double(b) / max * fill)); Spacer(minLength: 0) }
                }
            }
            .frame(height: 5)
        }
        .foregroundColor(.white)
    }
}

/// Which beat is playing, for the caption under the hero.
struct HeroCaption: View {
    @State private var start = Date()
    private let lines = ["Follows every player.", "Streams it live.", "Counts every shot."]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let t = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: OnboardingHero.loop)
            let i = min(Int(t / OnboardingHero.beat), 2)
            Text(lines[i])
                .font(.wide(26, 850))
                .foregroundColor(.white)
                .id(i)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .opacity))
                .animation(.spring(duration: 0.45), value: i)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
