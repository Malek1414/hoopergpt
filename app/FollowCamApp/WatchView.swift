import SwiftUI

// Watch tab, landscape: the Mac's stream on the left with the score on the
// glass over it, the numbers on the right next to it. Teams and players come
// from state.json only; nothing is guessed here.

struct WatchView: View {
    @StateObject private var feed = LiveFeed()
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                StreamWindow(frame: feed.frame, link: feed.link, host: bridgeHost, state: feed.state) {
                    feed.start(host: bridgeHost)
                }
                .frame(width: geo.size.width * 0.6)
                StatsColumn(state: feed.state)
                    .frame(maxWidth: .infinity)
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .onAppear { feed.start(host: bridgeHost) }
        .onDisappear { feed.stop() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { feed.start(host: bridgeHost) } else { feed.stop() }
        }
    }
}

// MARK: - stream window

struct StreamWindow: View {
    let frame: UIImage?
    let link: LiveFeed.Link
    let host: String
    let state: GameState?
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color.ink
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .overlay(alignment: .topLeading) { badges }
                    .overlay(alignment: .bottom) { caption }
            } else {
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .topLeading) { badges }
            }
        }
        .animation(.spring(duration: 0.4), value: state?.lastEvent)
        .clipped()
    }

    private var badges: some View {
            HStack(spacing: 8) {
                LinkBadge(link: link)
                if let state, state.teams.count == 2 {
                    MiniScore(state: state)
                }
            }
            .padding(12)
    }

    @ViewBuilder
    private var caption: some View {
            if let state, let event = state.lastEvent {
                Text(EventText.sentence(event, players: state.players))
                    .font(.text(15, 600))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.black.opacity(0.8))
                    .padding(.bottom, 14)
                    .id(event.t)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            if link == .connecting {
                ProgressView().tint(.white)
                Text("Looking for \(host)").font(.text(15)).foregroundColor(.muted)
            } else {
                Text(link == .badSchema ? "The Mac runs a newer version" : "No picture from the Mac")
                    .font(.wide(18, 800))
                    .foregroundColor(.white)
                Button("Try again", action: retry)
                    .font(.text(16, 650))
                    .foregroundColor(.pla)
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct LinkBadge: View {
    let link: LiveFeed.Link

    var body: some View {
        let (label, color): (String, Color) = switch link {
        case .live: ("LIVE", .red)
        case .connecting: ("…", .muted)
        case .lost: ("Signal lost", .muted)
        case .badSchema: ("Update", .muted)
        case .off: ("Off", .muted)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.wide(11, 900)).foregroundColor(.white)
        }
        .padding(.horizontal, 10).frame(height: 28)
        .glass(14)
    }
}

private struct MiniScore: View {
    let state: GameState

    var body: some View {
        HStack(spacing: 10) {
            ForEach(state.teams) { team in
                HStack(spacing: 6) {
                    Rectangle().fill(Color(hex: team.color) ?? .muted).frame(width: 3, height: 14)
                    Text("\(team.score)")
                        .font(.wide(16, 900))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            Text(state.clock).font(.text(12, 600)).foregroundColor(.white.opacity(0.7))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12).frame(height: 28)
        .glass(14)
        .animation(.spring(duration: 0.5), value: state.teams.map(\.score))
    }
}

enum EventText {
    static func sentence(_ event: GameState.GameEvent, players: [GameState.Player]) -> String {
        let number = players.first { $0.key == event.playerKey }?.number
        let who = number.map { "#\($0)" } ?? "Someone"
        switch event.type {
        case "made": return "\(who) scores \(event.points)."
        case "miss": return "\(who) misses."
        default: return "\(event.points) points, entered by hand."
        }
    }
}

// MARK: - stats next to the picture

private struct StatsColumn: View {
    let state: GameState?

    var body: some View {
        if let state, state.teams.count == 2 {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header(state)
                    VStack(spacing: 14) {
                        Versus(label: "Points", a: state.teams[0].score, b: state.teams[1].score,
                               colors: colors(state))
                        Versus(label: "Shots made", a: state.teams[0].fgm, b: state.teams[1].fgm,
                               colors: colors(state))
                        Versus(label: "Shots taken", a: state.teams[0].fga, b: state.teams[1].fga,
                               colors: colors(state))
                    }
                    PlayerList(players: state.players.filter(\.isWorthShowing), teams: state.teams)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
        } else {
            Text("Score and players show up once the Mac sends a game.")
                .font(.text(15))
                .foregroundColor(.muted)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func colors(_ state: GameState) -> (Color, Color) {
        (Color(hex: state.teams[0].color) ?? .white, Color(hex: state.teams[1].color) ?? .muted)
    }

    private func header(_ state: GameState) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.teams[0].name).font(.wide(15, 800)).foregroundColor(.white).lineLimit(1)
            Spacer()
            Text("Q\(state.period)  \(state.clock)").font(.text(13, 600)).foregroundColor(.muted).monospacedDigit()
            Spacer()
            Text(state.teams[1].name).font(.wide(15, 800)).foregroundColor(.white).lineLimit(1)
        }
    }
}

/// Two numbers and a split bar between them: who is ahead, at a glance.
private struct Versus: View {
    let label: String
    let a: Int
    let b: Int
    let colors: (Color, Color)

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(a)").font(.wide(20, 900)).contentTransition(.numericText())
                Spacer()
                Text(label).font(.text(13, 550)).foregroundColor(.muted)
                Spacer()
                Text("\(b)").font(.wide(20, 900)).contentTransition(.numericText())
            }
            .foregroundColor(.white)
            .monospacedDigit()
            GeometryReader { geo in
                // 0:0 is a draw, not a lead: both halves grey and equal.
                let share = a + b == 0 ? 0.5 : CGFloat(a) / CGFloat(a + b)
                HStack(spacing: 3) {
                    Capsule().fill(a + b == 0 ? Color.hairline : colors.0)
                        .frame(width: max((geo.size.width - 3) * share, 4))
                    Capsule().fill(a + b == 0 ? Color.hairline : colors.1)
                }
            }
            .frame(height: 6)
            .animation(.spring(duration: 0.6), value: a)
            .animation(.spring(duration: 0.6), value: b)
        }
    }
}

private struct PlayerList: View {
    let players: [GameState.Player]
    let teams: [GameState.Team]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(players) { player in
                row(player)
            }
        }
    }

    private func row(_ player: GameState.Player) -> some View {
        let team = teams.first { $0.id == player.team }
        let color = team.flatMap { Color(hex: $0.color) } ?? Color(white: 0.3)
        let share = player.fga > 0 ? CGFloat(player.fgm) / CGFloat(player.fga) : 0
        return HStack(spacing: 12) {
            // No confident number yet: show it greyed instead of inventing one.
            Text(player.number.map { "\($0)" } ?? "?")
                .font(.wide(22, 900))
                .foregroundColor(player.number == nil ? .muted : .white)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(player.fgm) of \(player.fga)")
                    .font(.text(13, 550))
                    .foregroundColor(.muted)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.hairline)
                        Capsule().fill(color).frame(width: max(geo.size.width * share, 3))
                    }
                }
                .frame(height: 4)
            }
            Text("\(player.pts)")
                .font(.wide(22, 900))
                .foregroundColor(.white)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}
