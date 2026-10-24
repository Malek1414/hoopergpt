import PhotosUI
import SwiftUI

// Teams you play with: name, colour, logo and the players with their
// jersey numbers, so the box score can say who #23 is. Kept on the phone
// (Documents/teams.json, logos as Documents/team-<id>.png).

struct RosterPlayer: Codable, Identifiable, Equatable {
    var id = UUID()
    var number: Int
    var name: String
}

struct Team: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var color: String   // "#rrggbb"
    var players: [RosterPlayer] = []

    func player(number: Int?) -> RosterPlayer? {
        number.flatMap { n in players.first { $0.number == n } }
    }
}

enum TeamStore {
    static let palette = ["#2f6fdb", "#c8102e", "#f2c230", "#1f9d55", "#7b3fe4", "#eb6414", "#ffffff", "#111111"]

    private static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var url: URL { docs.appendingPathComponent("teams.json") }

    static func all() -> [Team] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Team].self, from: data)) ?? []
    }

    static func save(_ team: Team) {
        var teams = all()
        if let i = teams.firstIndex(where: { $0.id == team.id }) { teams[i] = team } else { teams.append(team) }
        if let data = try? JSONEncoder().encode(teams) { try? data.write(to: url) }
    }

    static func delete(_ team: Team) {
        let teams = all().filter { $0.id != team.id }
        if let data = try? JSONEncoder().encode(teams) { try? data.write(to: url) }
        removeLogo(team.id)
    }

    // MARK: the two teams of the next game

    static var homeID: UUID? {
        get { UserDefaults.standard.string(forKey: "game.homeID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "game.homeID") }
    }

    static var awayID: UUID? {
        get { UserDefaults.standard.string(forKey: "game.awayID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "game.awayID") }
    }

    static var home: Team { pick(homeID, fallback: Team(name: "Home", color: palette[0])) }
    static var away: Team { pick(awayID, fallback: Team(name: "Away", color: palette[1])) }

    private static func pick(_ id: UUID?, fallback: Team) -> Team {
        all().first { $0.id == id } ?? fallback
    }

    // MARK: logos

    private static func logoURL(_ id: UUID) -> URL { docs.appendingPathComponent("team-\(id.uuidString).png") }

    static func logo(_ id: UUID) -> UIImage? { UIImage(contentsOfFile: logoURL(id).path) }

    /// Stored square and small: a logo is a badge, not a photo.
    @discardableResult
    static func saveLogo(_ image: UIImage, for id: UUID) -> UIImage? {
        let size = CGSize(width: 256, height: 256)
        let square = UIGraphicsImageRenderer(size: size).image { _ in
            let s = min(image.size.width, image.size.height)
            let scale = size.width / s
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2, width: w, height: h))
        }
        guard let data = square.pngData(), (try? data.write(to: logoURL(id))) != nil else { return nil }
        return square
    }

    static func removeLogo(_ id: UUID) { try? FileManager.default.removeItem(at: logoURL(id)) }
}

// MARK: - badge: the logo, or the team's initial on its colour

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

extension TeamBadge {
    init(team: Team, size: CGFloat = 36) {
        self.init(name: team.name, color: Color(hex: team.color) ?? .muted, logo: TeamStore.logo(team.id), size: size)
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

// MARK: - team form: logo, name, colour

struct TeamForm: View {
    @Binding var team: Team
    @State private var item: PhotosPickerItem?
    @State private var logo: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                PhotosPicker(selection: $item, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        TeamBadge(name: team.name.isEmpty ? "?" : team.name,
                                  color: Color(hex: team.color) ?? .muted, logo: logo, size: 72)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color.white))
                            .offset(x: 2, y: 2)
                    }
                }
                .accessibilityLabel("Team logo")
                .contextMenu {
                    if logo != nil {
                        Button("Remove logo", role: .destructive) {
                            TeamStore.removeLogo(team.id)
                            logo = nil
                        }
                    }
                }
                TextField("Team name", text: $team.name)
                    .font(.wide(30, 800))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.3)).frame(height: 1.5) }
            }
            HStack(spacing: 0) {
                ForEach(TeamStore.palette, id: \.self) { hex in
                    Button { team.color = hex } label: {
                        Circle()
                            .fill(Color(hex: hex) ?? .muted)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(Color.white.opacity(0.2)))
                            .overlay(Circle().stroke(Color.pla, lineWidth: team.color == hex ? 3 : 0).padding(-5))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .accessibilityLabel("Colour \(hex)")
                }
            }
        }
        .onAppear { logo = TeamStore.logo(team.id) }
        .onChange(of: item) {
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    logo = TeamStore.saveLogo(picked, for: team.id)
                }
                item = nil
            }
        }
    }
}

// MARK: - roster: one line per player, pencil opens the edit window

struct RosterList: View {
    @Binding var players: [RosterPlayer]
    @State private var editing: RosterPlayer?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(players.sorted { $0.number < $1.number }) { p in
                HStack(spacing: 16) {
                    Text("\(p.number)")
                        .font(.wide(26, 900))
                        .foregroundColor(.white)
                        .frame(width: 48, alignment: .leading)
                    Text(p.name.isEmpty ? "No name" : p.name)
                        .font(.text(18, 500))
                        .foregroundColor(p.name.isEmpty ? .muted : .white)
                    Spacer()
                    Button { editing = p } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Edit \(p.name)")
                }
                .frame(minHeight: 60)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
            }
            Button { adding = true } label: {
                HStack(spacing: 16) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 48, alignment: .leading)
                    Text("Add player").font(.text(18, 600))
                    Spacer()
                }
                .foregroundColor(.pla)
                .frame(minHeight: 60)
            }
        }
        .sheet(item: $editing) { p in
            PlayerEditor(player: p, taken: Set(players.filter { $0.id != p.id }.map(\.number))) { result in
                if let i = players.firstIndex(where: { $0.id == p.id }) {
                    if let result { players[i] = result } else { players.remove(at: i) }
                }
                editing = nil
            }
        }
        .sheet(isPresented: $adding) {
            PlayerEditor(player: nil, taken: Set(players.map(\.number))) { result in
                if let result { players.append(result) }
                adding = false
            }
        }
    }
}

/// Edit window for one player. Close left, Save right; Delete only when editing.
private struct PlayerEditor: View {
    let player: RosterPlayer?
    let taken: Set<Int>
    let done: (RosterPlayer?) -> Void
    @State private var number = ""
    @State private var name = ""
    @FocusState private var field: Int?

    private var parsed: Int? { Int(number).flatMap { (0...99).contains($0) ? $0 : nil } }
    private var clash: Bool { parsed.map(taken.contains) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Button("Close") { done(player) }
                    .font(.text(17, 500)).foregroundColor(.muted)
                Spacer()
                Button("Save") {
                    guard let n = parsed else { return }
                    var p = player ?? RosterPlayer(number: n, name: "")
                    p.number = n
                    p.name = name.trimmingCharacters(in: .whitespaces)
                    done(p)
                }
                .font(.text(17, 700))
                .foregroundColor(parsed != nil && !clash ? .pla : .muted)
                .disabled(parsed == nil || clash)
            }
            .frame(minHeight: 44)
            HStack(alignment: .firstTextBaseline, spacing: 18) {
                TextField("00", text: $number)
                    .font(.wide(64, 900))
                    .keyboardType(.numberPad)
                    .focused($field, equals: 0)
                    .frame(width: 110)
                    .onChange(of: number) { number = String(number.filter(\.isNumber).prefix(2)) }
                TextField("Name", text: $name)
                    .font(.text(24, 600))
                    .textInputAutocapitalization(.words)
                    .focused($field, equals: 1)
            }
            .foregroundColor(.white)
            if clash {
                Text("Number \(number) is taken.").font(.text(15)).foregroundColor(.pla)
            }
            Spacer()
            if player != nil {
                Button("Delete player", role: .destructive) { done(nil) }
                    .font(.text(17, 500))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(24)
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.medium])
        .onAppear {
            number = player.map { "\($0.number)" } ?? ""
            name = player?.name ?? ""
            field = 0
        }
    }
}

// MARK: - one team, full: used from Account and the game setup

struct TeamDetailView: View {
    @State var team: Team
    let done: (Team?) -> Void
    var canDelete = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Close") { done(nil) }
                    .font(.text(17, 500)).foregroundColor(.muted)
                Spacer()
                Button("Save") {
                    TeamStore.save(team)
                    done(team)
                }
                .font(.text(17, 700))
                .foregroundColor(team.name.trimmingCharacters(in: .whitespaces).isEmpty ? .muted : .pla)
                .disabled(team.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    TeamForm(team: $team)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Players").font(.wide(24, 800)).foregroundColor(.white)
                        RosterList(players: $team.players)
                    }
                    if canDelete, TeamStore.all().contains(where: { $0.id == team.id }) {
                        Button("Delete team", role: .destructive) {
                            TeamStore.delete(team)
                            done(nil)
                        }
                        .font(.text(17, 500))
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
