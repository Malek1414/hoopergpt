import SwiftUI

// Watch tab: the Mac's stream, landscape as filmed. Upright: picture on top,
// the teams with their logos and the numbers underneath. Sideways: the
// picture fills the screen; the numbers sit in a drawer you pull in from the
// right edge. Team names, colours and logos come from the game setup on the
// phone; scores and players from the Mac's state.json.

struct WatchView: View {
    @StateObject private var feed = LiveFeed()
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"
    @Environment(\.scenePhase) private var scenePhase
    // Screenshots: launch with `-debugDrawer YES` to start with the drawer open.
    @State private var drawerOpen = UserDefaults.standard.bool(forKey: "debugDrawer")
    @State private var controlsShown = true
    @State private var drag: CGFloat = 0

    private var teams: TeamsView { TeamsView(state: feed.state) }

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height {
                sideways(width: min(310, geo.size.width * 0.38))
            } else {
                VStack(spacing: 0) {
                    StreamPicture(frame: feed.frame, link: feed.link, host: bridgeHost) {
                        feed.start(host: bridgeHost)
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) { LiveDot(link: feed.link).padding(12) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            teams
                            if let state = feed.state, state.teams.count == 2 {
                                StatsBlock(state: state, homeName: teams.home.name, awayName: teams.away.name,
                                           colors: teams.colors)
                            } else {
                                waiting
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                }
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .onAppear {
            feed.start(host: bridgeHost)
            AppDelegate.allow(.allButUpsideDown)
        }
        .onDisappear { feed.stop() }
        .onChange(of: scenePhase) {
            if scenePhase == .active { feed.start(host: bridgeHost) } else { feed.stop() }
        }
    }

    private var waiting: some View {
        Text("Score and players show up once the Mac sends a game.")
            .font(.text(16)).foregroundColor(.muted)
    }

    // MARK: sideways: full picture, pull-in drawer

    private func sideways(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            StreamPicture(frame: feed.frame, link: feed.link, host: bridgeHost, bleed: true) {
                feed.start(host: bridgeHost)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    if drawerOpen { drawerOpen = false } else { controlsShown.toggle() }
                }
            }
            .overlay(alignment: .topLeading) {
                LiveDot(link: feed.link).padding(14).opacity(controlsShown ? 1 : 0)
            }

            if drawerOpen {
                drawer
                    .frame(width: width)
                    .offset(x: max(drag, 0))
                    .transition(.move(edge: .trailing))
            } else if controlsShown {
                handle.transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { v in if drawerOpen { drag = v.translation.width } }
                .onEnded { v in
                    withAnimation(.spring(duration: 0.35)) {
                        if drawerOpen, v.translation.width > 60 { drawerOpen = false }
                        if !drawerOpen, v.translation.width < -40 { drawerOpen = true; controlsShown = true }
                        drag = 0
                    }
                }
        )
        .animation(.spring(duration: 0.35), value: drawerOpen)
    }

    /// Closed drawer: a slim tab on the right edge with the score on it.
    private var handle: some View {
        Button {
            withAnimation(.spring(duration: 0.35)) { drawerOpen = true }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                if let state = feed.state, state.teams.count == 2 {
                    VStack(spacing: 4) {
                        Text("\(state.teams[0].score)").font(.wide(17, 900))
                        Rectangle().fill(Color.white.opacity(0.3)).frame(width: 14, height: 1)
                        Text("\(state.teams[1].score)").font(.wide(17, 900))
                    }
                    .monospacedDigit()
                }
            }
            .foregroundColor(.white)
            .frame(width: 44)
            .padding(.vertical, 16)
            .glass(16)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Show stats")
    }

    private var drawer: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.35)) { drawerOpen = false }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 32, height: 64)
            }
            .accessibilityLabel("Hide stats")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    teams.compact()
                    if let state = feed.state, state.teams.count == 2 {
                        StatsBlock(state: state, homeName: teams.home.name, awayName: teams.away.name,
                                   colors: teams.colors)
                    } else {
                        waiting
                    }
                }
                .padding(.vertical, 16)
                .padding(.trailing, 16)
            }
        }
        .glass(22)
        .padding(.vertical, 8)
    }
}

// MARK: - the picture

struct StreamPicture: View {
    let frame: UIImage?
    let link: LiveFeed.Link
    let host: String
    /// Sideways: the picture runs under the notch and corners.
    var bleed = false
    let retry: () -> Void

    var body: some View {
        // The container stays inside the safe area; only the picture behind
        // it may run to the screen edges.
        ZStack {
            if frame == nil { placeholder }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Color.ink
                if let frame {
                    Image(uiImage: frame).resizable().scaledToFill()
                }
            }
            .clipped()
            .ignoresSafeArea(edges: bleed ? .all : [])
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

/// Signal state as one dot: red and breathing when live, grey otherwise.
private struct LiveDot: View {
    let link: LiveFeed.Link
    @State private var breathe = false

    var body: some View {
        Circle()
            .fill(link == .live ? Color.red : Color(white: 0.6))
            .frame(width: 10, height: 10)
            .opacity(link == .live && breathe ? 0.45 : 1)
            .padding(6)
            .background(Circle().fill(Color.black.opacity(0.35)))
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever()) { breathe = true }
            }
            .accessibilityLabel(link == .live ? "Live" : "No signal")
    }
}

// MARK: - teams header: logos, names, score

struct TeamsView: View {
    let state: GameState?
    var isCompact = false

    var home: TeamSetup { CurrentTeams.home }
    var away: TeamSetup { CurrentTeams.away }
    var colors: (Color, Color) { (Color(hex: home.color) ?? .white, Color(hex: away.color) ?? .muted) }

    func compact() -> TeamsView { TeamsView(state: state, isCompact: true) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            side(home, colors.0, logo: TeamLogo.load(0), score: state?.teams.first?.score)
            VStack(spacing: 2) {
                if let state {
                    Text("Q\(state.period)").font(.text(13, 600)).foregroundColor(.muted)
                    Text(state.clock).font(.text(15, 650)).foregroundColor(.white).monospacedDigit()
                }
            }
            .frame(width: isCompact ? 52 : 70)
            side(away, colors.1, logo: TeamLogo.load(1), score: state?.teams.dropFirst().first?.score, trailing: true)
        }
    }

    private func side(_ team: TeamSetup, _ color: Color, logo: UIImage?, score: Int?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 8) {
            TeamBadge(name: team.name, color: color, logo: logo, size: isCompact ? 34 : 44)
            Text(team.name)
                .font(.wide(isCompact ? 13 : 16, 800))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(score.map(String.init) ?? "–")
                .font(.wide(isCompact ? 30 : 40, 900))
                .foregroundColor(.white)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .animation(.spring(duration: 0.5), value: score)
    }
}

// MARK: - numbers: team comparison and player list

struct StatsBlock: View {
    let state: GameState
    let homeName: String
    let awayName: String
    let colors: (Color, Color)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(spacing: 14) {
                Versus(label: "Shots made", a: state.teams[0].fgm, b: state.teams[1].fgm, colors: colors)
                Versus(label: "Shots taken", a: state.teams[0].fga, b: state.teams[1].fga, colors: colors)
            }
            PlayerList(players: state.players.filter(\.isWorthShowing), colors: colors)
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
                Text(label).font(.text(14, 550)).foregroundColor(.muted)
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
    let colors: (Color, Color)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(players) { player in
                row(player)
            }
        }
    }

    private func row(_ player: GameState.Player) -> some View {
        let color = player.team == 0 ? colors.0 : (player.team == 1 ? colors.1 : Color(white: 0.3))
        let share = player.fga > 0 ? CGFloat(player.fgm) / CGFloat(player.fga) : 0
        return HStack(spacing: 12) {
            // No confident number yet: show it quietly instead of inventing one.
            Text(player.number.map { "\($0)" } ?? "#?")
                .font(player.number == nil ? .text(16, 600) : .wide(22, 900))
                .foregroundColor(player.number == nil ? .muted : .white)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(player.fgm) of \(player.fga)")
                    .font(.text(14, 550))
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
