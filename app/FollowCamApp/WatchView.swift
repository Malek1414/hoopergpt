import SwiftUI

// Watch tab: the Mac's annotated stream with score and box score under it.
// Teams and players come from state.json only; nothing is guessed here.

struct WatchView: View {
    @StateObject private var feed = LiveFeed()
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StreamWindow(frame: feed.frame, link: feed.link, host: bridgeHost) {
                    feed.start(host: bridgeHost)
                }
                if let state = feed.state {
                    Scoreboard(state: state)
                    if let event = state.lastEvent {
                        EventLine(event: event, teams: state.teams, players: state.players)
                    }
                    BoxScore(players: state.players.filter(\.isWorthShowing), teams: state.teams)
                } else {
                    EmptyGame()
                }
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
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
    let retry: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.panel)
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                placeholder
            }
            LinkBadge(link: link).padding(10)
        }
        // The Mac decides the layout (video plus minimap is wider than 16:9),
        // so the window takes the shape of whatever frame arrives.
        .aspectRatio(frame.map { $0.size.width / max($0.size.height, 1) } ?? 16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            if link == .connecting {
                ProgressView().tint(.white)
                Text("Connecting to \(host)").font(.mono(13)).foregroundColor(.chrome)
            } else {
                Image(systemName: "play.rectangle")
                    .font(.system(size: 34))
                    .foregroundColor(.chrome)
                Text(link == .badSchema ? "Mac runs a newer version" : "No picture from the Mac")
                    .font(.mono(13)).foregroundColor(.chrome)
                Button("TRY AGAIN", action: retry)
                    .font(.mono(13, .bold))
                    .foregroundColor(.pla)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LinkBadge: View {
    let link: LiveFeed.Link

    var body: some View {
        let (label, color): (String, Color) = switch link {
        case .live: ("LIVE", .red)
        case .connecting: ("CONNECTING", .chrome)
        case .lost: ("SIGNAL LOST", .chrome)
        case .badSchema: ("UPDATE NEEDED", .chrome)
        case .off: ("OFF", .chrome)
        }
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.mono(11, .bold)).foregroundColor(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.6))
        .clipShape(Capsule())
    }
}

// MARK: - score

private struct Scoreboard: View {
    let state: GameState

    var body: some View {
        HStack(spacing: 0) {
            if state.teams.count == 2 {
                side(state.teams[0], alignment: .leading)
                VStack(spacing: 2) {
                    Text("Q\(state.period)").font(.mono(12, .bold)).foregroundColor(.chrome)
                    Text(state.clock).font(.mono(15, .bold)).foregroundColor(.white)
                }
                .frame(width: 80)
                side(state.teams[1], alignment: .trailing)
            }
        }
        .padding(16)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func side(_ team: GameState.Team, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: team.color) ?? .chrome).frame(width: 10, height: 10)
                Text(team.name).font(.headline).foregroundColor(.white).lineLimit(1)
            }
            Text("\(team.score)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            Text("FG \(team.fgm)/\(team.fga)\(team.fgPct.map { "  \(Int($0 * 100))%" } ?? "")")
                .font(.mono(11)).foregroundColor(.chrome)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

private struct EventLine: View {
    let event: GameState.GameEvent
    let teams: [GameState.Team]
    let players: [GameState.Player]

    var body: some View {
        let team = teams.first { $0.id == event.team }
        HStack(spacing: 10) {
            Circle().fill(team.flatMap { Color(hex: $0.color) } ?? .chrome).frame(width: 8, height: 8)
            Text(text).font(.mono(13)).foregroundColor(.white)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var text: String {
        let number = players.first { $0.key == event.playerKey }?.number
        let who = number.map { "#\($0)" } ?? "Unknown player"
        switch event.type {
        case "made": return "\(who) scores \(event.points)"
        case "miss": return "\(who) misses"
        default: return "\(who) \(event.points) pts, entered by hand"
        }
    }
}

// MARK: - box score

private struct BoxScore: View {
    let players: [GameState.Player]
    let teams: [GameState.Team]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("PTS").frame(width: 44)
                Text("FG").frame(width: 56)
            }
            .font(.mono(11, .bold)).foregroundColor(.chrome)
            .padding(.horizontal, 16).padding(.vertical, 10)
            ForEach(players) { player in
                row(player)
                if player.id != players.last?.id {
                    Divider().background(Color(white: 0.18)).padding(.leading, 16)
                }
            }
        }
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ player: GameState.Player) -> some View {
        let team = teams.first { $0.id == player.team }
        return HStack {
            HStack(spacing: 10) {
                Circle()
                    .fill(team.flatMap { Color(hex: $0.color) } ?? Color(white: 0.3))
                    .frame(width: 8, height: 8)
                // No confident number yet: show it greyed instead of inventing one.
                Text(player.number.map { "#\($0)" } ?? "#?")
                    .font(.mono(15, .bold))
                    .foregroundColor(player.number == nil ? .chrome : .white)
                if team == nil {
                    Text("no team").font(.mono(11)).foregroundColor(.chrome)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(player.pts)").font(.mono(15, .bold)).foregroundColor(.white).frame(width: 44)
            Text("\(player.fgm)/\(player.fga)").font(.mono(13)).foregroundColor(.chrome).frame(width: 56)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct EmptyGame: View {
    var body: some View {
        Text("Score and players show up here once the Mac sends a game.")
            .font(.subheadline)
            .foregroundColor(.chrome)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color.panel)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
