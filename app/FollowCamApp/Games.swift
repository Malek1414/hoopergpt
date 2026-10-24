import SwiftUI

// A game: the two teams picked before filming, and what the Mac counted by
// the time you stopped. Kept on the phone (Documents/games.json) so the
// Account tab can show every game afterwards.

struct GameRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let home: Team          // snapshot, so later roster edits keep old games right
    let away: Team
    var duration: TimeInterval = 0
    var final: GameState?   // the Mac's last state.json, nil if it was not reachable
}

enum GameStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("games.json")
    }

    static func load() -> [GameRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([GameRecord].self, from: data)) ?? []
    }

    static func add(_ game: GameRecord) {
        let all = [game] + load()
        if let data = try? JSONEncoder().encode(all) { try? data.write(to: url) }
    }
}

// MARK: - game setup, shown before the first frame is filmed

struct GameSetupView: View {
    var actionTitle = "Start filming"
    let start: () -> Void
    let cancel: () -> Void
    @State private var home = TeamStore.home
    @State private var away = TeamStore.away
    @State private var picking: Side?

    enum Side: Identifiable { case home, away; var id: Self { self } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Close", action: cancel)
                    .font(.text(17, 500)).foregroundColor(.muted)
                    .frame(minHeight: 44)
                Spacer()
            }
            Text("WHO'S\nPLAYING?")
                .font(.wide(52, 900))
                .lineSpacing(-14)
                .foregroundColor(.white)
                .padding(.top, 12)
            Spacer(minLength: 24)
            teamRow(home, label: "Home") { picking = .home }
            Text("VS")
                .font(.wide(22, 800))
                .foregroundColor(.pla)
                .padding(.vertical, 14)
            teamRow(away, label: "Away") { picking = .away }
            Spacer(minLength: 24)
            PrimaryButton(title: actionTitle) {
                TeamStore.homeID = home.id
                TeamStore.awayID = away.id
                start()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .sheet(item: $picking) { side in
            TeamPicker(selected: side == .home ? home.id : away.id) { team in
                if let team { if side == .home { home = team } else { away = team } }
                picking = nil
            }
        }
    }

    private func teamRow(_ team: Team, label: String, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 18) {
                TeamBadge(team: team, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(team.name.uppercased())
                        .font(.wide(32, 900))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(team.players.isEmpty ? label : "\(label), \(team.players.count) players")
                        .font(.text(16, 500))
                        .foregroundColor(.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.muted)
            }
            .padding(.vertical, 14)
        }
    }
}

/// Choose one of your teams, edit one with the pencil, or make a new one.
private struct TeamPicker: View {
    let selected: UUID
    let done: (Team?) -> Void
    @State private var teams = TeamStore.all()
    @State private var editing: Team?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Close") { done(nil) }
                    .font(.text(17, 500)).foregroundColor(.muted)
                Spacer()
            }
            .frame(minHeight: 44)
            Text("TEAMS").font(.wide(40, 900)).foregroundColor(.white).padding(.vertical, 12)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(teams) { team in
                        HStack(spacing: 16) {
                            Button { done(team) } label: {
                                HStack(spacing: 16) {
                                    TeamBadge(team: team, size: 44)
                                    Text(team.name).font(.text(19, 600)).foregroundColor(.white)
                                    Spacer()
                                    if team.id == selected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 17, weight: .bold)).foregroundColor(.pla)
                                    }
                                }
                            }
                            Button { editing = team } label: {
                                Image(systemName: "pencil")
                                    .font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Edit \(team.name)")
                        }
                        .frame(minHeight: 68)
                        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
                    }
                    Button {
                        editing = Team(name: "", color: TeamStore.palette[teams.count % TeamStore.palette.count])
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).frame(width: 44)
                            Text("New team").font(.text(19, 600))
                            Spacer()
                        }
                        .foregroundColor(.pla)
                        .frame(minHeight: 68)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .background(Color.surface.ignoresSafeArea())
        .sheet(item: $editing) { team in
            TeamDetailView(team: team) { _ in
                teams = TeamStore.all()
                editing = nil
            }
        }
    }
}

// MARK: - one finished game, from the Account tab

struct GameDetailView: View {
    let game: GameRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.text(16, 500)).foregroundColor(.muted)
                HStack(alignment: .center) {
                    side(game.home, score: game.final?.teams.first?.score)
                    Spacer()
                    Text("VS").font(.wide(20, 800)).foregroundColor(.pla)
                    Spacer()
                    side(game.away, score: game.final?.teams.dropFirst().first?.score, trailing: true)
                }
                if let state = game.final, state.teams.count == 2 {
                    StatsBlock(state: state, home: game.home, away: game.away)
                } else {
                    Text("No stats from the Mac for this game.")
                        .font(.text(17)).foregroundColor(.muted)
                }
                Text("Filmed \(Int(game.duration) / 60) min \(Int(game.duration) % 60) s")
                    .font(.text(16, 500)).foregroundColor(.muted)
            }
            .padding(24)
        }
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func side(_ team: Team, score: Int?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 8) {
            TeamBadge(team: team, size: 48)
            Text(team.name.uppercased()).font(.wide(22, 900)).foregroundColor(.white).lineLimit(1)
            Text(score.map(String.init) ?? "0").font(.wide(56, 900)).foregroundColor(.white)
        }
    }
}
