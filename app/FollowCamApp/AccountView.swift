import SwiftUI

// Account tab: who you are, your teams and games, your pod, your strap,
// what you bought. Settings style: one inset grouped list.
//
// Screenshot flags (DEBUG only):
//   -debugTeam YES     opens the first team's detail sheet
//   -debugTeam NEW     opens the new-team sheet
//   -debugGame YES     pushes the first game
//   -debugPlayer YES   (with -debugTeam) also opens the first player's editor

struct AccountView: View {
    @ObservedObject var pan: PanController
    let replayGuide: () -> Void

    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"
    @AppStorage("skins.owned") private var ownedSkins = "classic"
    @AppStorage("skins.selected") private var selectedSkin = "classic"
    @StateObject private var whoop = WhoopAuthCoordinator.shared
    // WHOOP app credentials (reuse the HUSTLR registration: add the redirect
    // URI followcam://whoop-callback to it at developer.whoop.com)
    @State private var whoopClientID = Keychain.get(KeychainKey.whoopClientID)
        ?? "fcdd77dd-47c5-4530-857a-014a480437b0"
    @State private var whoopSecret = ""
    @State private var whoopStatus: String?
    @State private var showWhoopKeys = false
    @State private var games: [GameRecord] = []
    @State private var teams: [Team] = []
    @State private var editingTeam: Team?
    @State private var path: [UUID] = []
    @State private var didDebug = false

    private var owned: [Skin] {
        Skin.all.filter { ownedSkins.split(separator: ",").contains(Substring($0.id)) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                profile
                teamsSection
                gamesSection
                podSection
                heartRateSection
                skinsSection
                Section("Help") {
                    Button("Show Setup Steps Again", action: replayGuide)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: UUID.self) { id in
                if let game = games.first(where: { $0.id == id }) { GameDetailView(game: game) }
            }
        }
        .onAppear(perform: reload)
        .sheet(item: $editingTeam) { team in
            TeamDetailView(team: team) { _ in
                teams = TeamStore.all()
                editingTeam = nil
            }
        }
    }

    // MARK: sections

    private var profile: some View {
        Section {
            HStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Guest").font(.title2.weight(.semibold))
            }
            .padding(.vertical, 6)
            Button("Sign In") {}
        }
    }

    private var teamsSection: some View {
        Section("Teams") {
            ForEach(teams) { team in
                Button { editingTeam = team } label: {
                    HStack(spacing: 14) {
                        TeamBadge(team: team, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(team.name).foregroundStyle(.primary)
                            Text(team.players.count == 1 ? "1 player" : "\(team.players.count) players")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button {
                editingTeam = Team(name: "", color: TeamStore.palette[teams.count % TeamStore.palette.count])
            } label: {
                Label("New Team", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var gamesSection: some View {
        Section {
            ForEach(games) { game in
                NavigationLink(value: game.id) { gameRow(game) }
            }
        } header: {
            Text("Games")
        } footer: {
            if games.isEmpty { Text("Games you film show up here.") }
        }
    }

    private var podSection: some View {
        Section {
            HStack {
                TextField("Mac Address", text: $bridgeHost)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .onSubmit { pan.connect(host: bridgeHost) }
                if pan.connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else {
                    Button("Connect") { pan.connect(host: bridgeHost) }
                        .buttonStyle(.borderless)
                        .disabled(bridgeHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Toggle("Reverse Pan", isOn: $pan.invert)
            if pan.connected {
                Button("Disconnect", role: .destructive) { pan.disconnect() }
            }
        } header: {
            Text("Pod")
        } footer: {
            Text("Turn on Reverse Pan if the pod turns away from the action.")
        }
    }

    private var heartRateSection: some View {
        Section {
            Button {
                Task { await syncWhoop() }
            } label: {
                LabeledContent(whoop.connected ? "WHOOP Connected" : "Connect WHOOP") {
                    if whoop.connected { Text("Sync") }
                }
            }
            .foregroundStyle(whoop.connected ? .primary : Color.accentColor)
            if let whoopStatus {
                Text(whoopStatus).font(.subheadline).foregroundStyle(.secondary)
            }
            DisclosureGroup("Developer Keys", isExpanded: $showWhoopKeys) {
                TextField("Client ID", text: $whoopClientID)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                SecureField("Client Secret", text: $whoopSecret)
                Button("Save Keys") {
                    WhoopClient.configure(clientID: whoopClientID, secret: whoopSecret)
                    whoopSecret = ""
                    whoopStatus = "Keys saved"
                }
                .disabled(whoopClientID.isEmpty || whoopSecret.isEmpty)
            }
        } header: {
            Text("Heart Rate")
        }
    }

    private var skinsSection: some View {
        Section {
            ForEach(owned) { skin in
                Button { selectedSkin = skin.id } label: {
                    HStack {
                        Text(skin.name).foregroundStyle(.primary)
                        Spacer()
                        if skin.id == selectedSkin {
                            Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(skin.id == selectedSkin ? .isSelected : [])
            }
        } header: {
            Text("Skins")
        } footer: {
            Text("The score bar on your stream.")
        }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(game.home.name) vs \(game.away.name)").lineLimit(1)
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let t = game.final?.teams, t.count == 2 {
                Text("\(t[0].score) : \(t[1].score)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    // MARK: data

    private func reload() {
        games = GameStore.load()
        teams = TeamStore.all()
        #if DEBUG
        guard !didDebug else { return }
        didDebug = true
        switch UserDefaults.standard.string(forKey: "debugTeam") {
        case "YES": editingTeam = teams.first
        case "NEW": editingTeam = Team(name: "", color: TeamStore.palette[teams.count % TeamStore.palette.count])
        default: break
        }
        if UserDefaults.standard.bool(forKey: "debugGame"), let first = games.first { path = [first.id] }
        #endif
    }

    private func syncWhoop() async {
        do {
            if !whoop.connected { try await whoop.connect() }
            let w = try await WhoopClient.shared.exportLatestWorkout()
            whoopStatus = w.map {
                "Strain \($0.score?.strain.map { String(format: "%.1f", $0) } ?? "–"), max \($0.score?.maxHeartRate.map { String(Int($0)) } ?? "–") bpm"
            } ?? "No workout in the last 24 hours"
        } catch {
            whoopStatus = error.localizedDescription
        }
    }
}
