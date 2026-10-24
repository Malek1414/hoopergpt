import PhotosUI
import SwiftUI

// A game: the two teams you name before filming, and what the Mac counted
// by the time you stopped. Kept on the phone (Documents/games.json) so the
// Account tab can show every game afterwards.

struct TeamSetup: Codable, Equatable {
    var name: String
    var color: String   // "#rrggbb"
}

struct GameRecord: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let home: TeamSetup
    let away: TeamSetup
    var duration: TimeInterval = 0
    var final: GameState?       // the Mac's last state.json, nil if it was not reachable
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

/// The teams for the next game, remembered between games.
enum CurrentTeams {
    static let palette = ["#2f6fdb", "#c8102e", "#f2c230", "#1f9d55", "#7b3fe4", "#f97316", "#ffffff", "#111111"]

    static var home: TeamSetup {
        get { read("game.home") ?? TeamSetup(name: "Home", color: palette[0]) }
        set { write(newValue, "game.home") }
    }

    static var away: TeamSetup {
        get { read("game.away") ?? TeamSetup(name: "Away", color: palette[1]) }
        set { write(newValue, "game.away") }
    }

    private static func read(_ key: String) -> TeamSetup? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(TeamSetup.self, from: $0) }
    }

    private static func write(_ team: TeamSetup, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(team), forKey: key)
    }
}

// MARK: - team badge: the logo, or the team's initial on its colour

struct TeamBadge: View {
    let name: String
    let color: Color
    var logo: UIImage?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let logo {
                Image(uiImage: logo).resizable().scaledToFill()
            } else {
                color
                Text(String(name.prefix(1)).uppercased())
                    .font(.wide(size * 0.42, 900))
                    .foregroundColor(color.isLight ? .black : .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white.opacity(0.15)))
    }
}

extension Color {
    /// Rough luminance check so a white or yellow badge gets dark text.
    var isLight: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}

// MARK: - game setup, shown before the first frame is filmed

struct GameSetupView: View {
    var actionTitle = "Start filming"
    let start: () -> Void
    let cancel: () -> Void
    @State private var home = CurrentTeams.home
    @State private var away = CurrentTeams.away
    @State private var logos: [UIImage?] = [TeamLogo.load(0), TeamLogo.load(1)]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack {
                Button("Cancel", action: cancel)
                    .font(.text(16, 600))
                    .foregroundColor(.muted)
                    .frame(minHeight: 44)
                Spacer()
            }
            Text("Who's playing?").font(.wide(30, 900)).foregroundColor(.white)
            TeamEditor(team: $home, logo: $logos[0], side: 0, placeholder: "Home")
            TeamEditor(team: $away, logo: $logos[1], side: 1, placeholder: "Away")
            Spacer(minLength: 0)
            PrimaryButton(title: actionTitle,
                          enabled: !home.name.trimmingCharacters(in: .whitespaces).isEmpty
                              && !away.name.trimmingCharacters(in: .whitespaces).isEmpty) {
                CurrentTeams.home = home
                CurrentTeams.away = away
                start()
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct TeamEditor: View {
    @Binding var team: TeamSetup
    @Binding var logo: UIImage?
    let side: Int
    let placeholder: String
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $item, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        TeamBadge(name: team.name.isEmpty ? placeholder : team.name,
                                  color: Color(hex: team.color) ?? .muted, logo: logo, size: 56)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white))
                            .offset(x: 2, y: 2)
                    }
                }
                .accessibilityLabel("\(placeholder) logo")
                .contextMenu {
                    if logo != nil {
                        Button("Remove logo", role: .destructive) {
                            TeamLogo.remove(side)
                            logo = nil
                        }
                    }
                }
                TextField(placeholder, text: $team.name)
                    .font(.wide(22, 800))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.vertical, 10)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1.5) }
            }
            HStack(spacing: 10) {
                ForEach(CurrentTeams.palette, id: \.self) { hex in
                    Button {
                        team.color = hex
                    } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .muted)
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(Color.white, lineWidth: team.color == hex ? 2.5 : 0).padding(-4))
                            .overlay(Circle().stroke(Color.white.opacity(0.2)))
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Colour \(hex)")
                }
            }
        }
        .onChange(of: item) {
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    logo = TeamLogo.save(picked, side: side)
                }
                item = nil
            }
        }
    }
}

// MARK: - one finished game, from the Account tab

struct GameDetailView: View {
    let game: GameRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.text(15, 550)).foregroundColor(.muted)
                HStack(alignment: .center) {
                    side(game.home, score: game.final?.teams.first?.score)
                    Spacer()
                    Text("vs").font(.text(15, 600)).foregroundColor(.muted)
                    Spacer()
                    side(game.away, score: game.final?.teams.dropFirst().first?.score, trailing: true)
                }
                if let state = game.final, state.teams.count == 2 {
                    StatsBlock(state: state, homeName: game.home.name, awayName: game.away.name,
                               colors: (Color(hex: game.home.color) ?? .white, Color(hex: game.away.color) ?? .muted))
                } else {
                    Text("No stats from the Mac for this game.")
                        .font(.text(16)).foregroundColor(.muted)
                }
                Text("Filmed \(Int(game.duration) / 60) min \(Int(game.duration) % 60) s")
                    .font(.text(15, 550)).foregroundColor(.muted)
            }
            .padding(24)
        }
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }

    private func side(_ team: TeamSetup, score: Int?, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 8) {
            TeamBadge(name: team.name, color: Color(hex: team.color) ?? .muted,
                      logo: nil, size: 44)
            Text(team.name).font(.wide(17, 800)).foregroundColor(.white).lineLimit(1)
            Text(score.map(String.init) ?? "–").font(.wide(40, 900)).foregroundColor(.white)
        }
    }
}
