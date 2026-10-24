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
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundColor(color.isLight ? .black : .white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.15)))
        .accessibilityHidden(true)
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

// MARK: - logo picker: the badge with a camera mark, tap to choose a photo

private struct LogoPicker: View {
    let team: Team
    var size: CGFloat = 64
    @State private var item: PhotosPickerItem?
    @State private var logo: UIImage?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            TeamBadge(name: team.name.isEmpty ? "?" : team.name,
                      color: Color(hex: team.color) ?? .muted, logo: logo, size: size)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .white)
                        .font(.system(size: size * 0.36))
                        .offset(x: 3, y: 3)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Team logo")
        .contextMenu {
            if logo != nil {
                Button("Remove Logo", systemImage: "trash", role: .destructive) {
                    TeamStore.removeLogo(team.id)
                    logo = nil
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

/// The team colours in one row; the chosen one gets a ring.
private struct ColorSwatches: View {
    @Binding var color: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TeamStore.palette, id: \.self) { hex in
                Button { color = hex } label: {
                    Circle()
                        .fill(Color(hex: hex) ?? .muted)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.2)))
                        .padding(4)
                        .overlay(Circle().strokeBorder(color == hex ? Color.primary : .clear, lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Colour \(hex)")
                .accessibilityAddTraits(color == hex ? .isSelected : [])
            }
        }
    }
}

/// One roster line: number, name. Same in a Form and in the onboarding card.
private struct PlayerRow: View {
    let player: RosterPlayer

    var body: some View {
        HStack(spacing: 14) {
            Text("\(player.number)")
                .font(.system(.body, design: .monospaced).weight(.bold))
                .frame(minWidth: 30, alignment: .leading)
            Text(player.name.isEmpty ? "No Name" : player.name)
                .foregroundStyle(player.name.isEmpty ? .secondary : .primary)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

// MARK: - team form: logo, name, colour (onboarding, outside a Form)

struct TeamForm: View {
    @Binding var team: Team

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                LogoPicker(team: team, size: 64)
                TextField("Team Name", text: $team.name)
                    .font(.title3)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            ColorSwatches(color: $team.color)
                .padding(.horizontal, 8)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

// MARK: - roster (onboarding, outside a Form): grouped card, row tap edits

struct RosterList: View {
    @Binding var players: [RosterPlayer]
    @State private var editing: RosterPlayer?
    @State private var adding = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(players.sorted { $0.number < $1.number }) { p in
                Button { editing = p } label: {
                    HStack {
                        PlayerRow(player: p)
                        Image(systemName: "pencil").foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Edit")
                Divider().padding(.leading, 16)
            }
            Button { adding = true } label: {
                Label("Add Player", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .playerEditors(players: $players, editing: $editing, adding: $adding)
    }
}

private extension View {
    /// The edit and add sheets of a roster, shared by RosterList and TeamDetailView.
    func playerEditors(players: Binding<[RosterPlayer]>, editing: Binding<RosterPlayer?>,
                       adding: Binding<Bool>) -> some View {
        self
            .sheet(item: editing) { p in
                PlayerEditor(player: p,
                             taken: Set(players.wrappedValue.filter { $0.id != p.id }.map(\.number))) { result in
                    if let i = players.wrappedValue.firstIndex(where: { $0.id == p.id }) {
                        switch result {
                        case .save(let new): players.wrappedValue[i] = new
                        case .delete: players.wrappedValue.remove(at: i)
                        case .cancel: break
                        }
                    }
                    editing.wrappedValue = nil
                }
            }
            .sheet(isPresented: adding) {
                PlayerEditor(player: nil, taken: Set(players.wrappedValue.map(\.number))) { result in
                    if case .save(let new) = result { players.wrappedValue.append(new) }
                    adding.wrappedValue = false
                }
            }
    }
}

/// Edit sheet for one player. Cancel left, Save right; Delete only when editing.
private struct PlayerEditor: View {
    enum Result { case save(RosterPlayer), delete, cancel }

    let player: RosterPlayer?
    let taken: Set<Int>
    let done: (Result) -> Void
    @State private var number = ""
    @State private var name = ""
    @FocusState private var field: Int?

    private var parsed: Int? { Int(number).flatMap { (0...99).contains($0) ? $0 : nil } }
    private var clash: Bool { parsed.map(taken.contains) ?? false }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Number") {
                        TextField("0 to 99", text: $number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($field, equals: 0)
                            .onChange(of: number) { number = String(number.filter(\.isNumber).prefix(2)) }
                    }
                    LabeledContent("Name") {
                        TextField("Optional", text: $name)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .focused($field, equals: 1)
                    }
                } footer: {
                    if clash {
                        Label("Number \(number) is already taken.", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                if player != nil {
                    Section {
                        Button("Delete Player", role: .destructive) { done(.delete) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(player == nil ? "New Player" : "Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { done(.cancel) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let n = parsed else { return }
                        var p = player ?? RosterPlayer(number: n, name: "")
                        p.number = n
                        p.name = name.trimmingCharacters(in: .whitespaces)
                        done(.save(p))
                    }
                    .fontWeight(.semibold)
                    .disabled(parsed == nil || clash)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            number = player.map { "\($0.number)" } ?? ""
            name = player?.name ?? ""
            // A dedicated edit sheet: the keyboard may come up right away.
            field = 0
        }
    }
}

// MARK: - one team, full: used from Account and the game setup

struct TeamDetailView: View {
    @State var team: Team
    let done: (Team?) -> Void
    var canDelete = true

    @State private var editing: RosterPlayer?
    @State private var adding = false
    @State private var confirmDelete = false
    @State private var stored = false

    private var nameIsEmpty: Bool { team.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var sorted: [RosterPlayer] { team.players.sorted { $0.number < $1.number } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        LogoPicker(team: team, size: 60)
                        TextField("Team Name", text: $team.name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                    }
                    .padding(.vertical, 6)
                }
                Section("Color") {
                    ColorSwatches(color: $team.color)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                Section {
                    ForEach(sorted) { p in
                        Button { editing = p } label: {
                            HStack {
                                PlayerRow(player: p)
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityHint("Edit")
                    }
                    .onDelete { offsets in
                        let ids = Set(offsets.map { sorted[$0].id })
                        team.players.removeAll { ids.contains($0.id) }
                    }
                    Button { adding = true } label: {
                        Label("Add Player", systemImage: "plus")
                    }
                } header: {
                    Text("Players")
                } footer: {
                    if !team.players.isEmpty {
                        Text(team.players.count == 1 ? "1 player" : "\(team.players.count) players")
                    }
                }
                if canDelete, stored {
                    Section {
                        Button("Delete Team", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(stored ? "Edit Team" : "New Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { done(nil) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        team.name = team.name.trimmingCharacters(in: .whitespaces)
                        TeamStore.save(team)
                        done(team)
                    }
                    .fontWeight(.semibold)
                    .disabled(nameIsEmpty)
                }
            }
            .confirmationDialog("Delete \(team.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Team", role: .destructive) {
                    TeamStore.delete(team)
                    done(nil)
                }
            } message: {
                Text("Past games keep their score.")
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .playerEditors(players: $team.players, editing: $editing, adding: $adding)
        .presentationDetents([.large])
        .onAppear {
            stored = TeamStore.all().contains { $0.id == team.id }
            #if DEBUG
            // Screenshots: `-debugPlayer YES` opens the first player's edit sheet.
            if UserDefaults.standard.bool(forKey: "debugPlayer"), editing == nil { editing = sorted.first }
            #endif
        }
    }
}
