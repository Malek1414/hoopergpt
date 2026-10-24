import SwiftUI

// Account tab: your teams and games, your pod (with heart rate) and the
// app itself. Settings style: one inset grouped list.
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
    @StateObject private var whoop = WhoopAuthCoordinator.shared
    @State private var games: [GameRecord] = []
    @State private var teams: [Team] = []
    @State private var editingTeam: Team?
    @State private var path: [UUID] = []
    @State private var didDebug = false
    @State private var editingMac = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                teamsSection
                gamesSection
                podSection
                appSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Account")
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: UUID.self) { id in
                if let game = games.first(where: { $0.id == id }) { GameDetailView(game: game) }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $editingMac) {
            MacAddressSheet(host: bridgeHost) { host in
                bridgeHost = host
                pan.connect(host: host)
            }
        }
        .sheet(item: $editingTeam) { team in
            TeamDetailView(team: team) { _ in
                teams = TeamStore.all()
                editingTeam = nil
            }
        }
    }

    // MARK: sections

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
            Button { editingMac = true } label: {
                LabeledContent("Mac") {
                    if pan.connected {
                        Text("Connected")
                    } else {
                        Text(bridgeHost.isEmpty ? "Not Set" : bridgeHost)
                    }
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            // A settings row, not a tinted link: label white, value grey.
            .buttonStyle(.plain)
            Toggle("Reverse Pan", isOn: $pan.invert)
            NavigationLink {
                HeartRateView()
            } label: {
                LabeledContent("Heart Rate", value: whoop.connected ? "WHOOP" : "Off")
            }
            if pan.connected {
                Button("Disconnect", role: .destructive) { pan.disconnect() }
            }
        } header: {
            Text("Pod")
        } footer: {
            Text("Turn on Reverse Pan if the pod turns away from the action.")
        }
    }

    private var appSection: some View {
        Section {
            Button("Show Setup Steps Again", action: replayGuide)
        } header: {
            Text("App")
        } footer: {
            Text(appVersion)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private func gameRow(_ game: GameRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(game.home.name).lineLimit(2)
                Text(game.away.name).lineLimit(2)
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let t = game.final?.teams, t.count == 2 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(t[0].score)")
                    Text("\(t[1].score)")
                }
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
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
}

// Heart Rate: pushed from the Pod section. WHOOP connect and developer keys.
private struct HeartRateView: View {
    @StateObject private var whoop = WhoopAuthCoordinator.shared
    // WHOOP app credentials (reuse the HUSTLR registration: add the redirect
    // URI followcam://whoop-callback to it at developer.whoop.com)
    @State private var whoopClientID = Keychain.get(KeychainKey.whoopClientID)
        ?? "fcdd77dd-47c5-4530-857a-014a480437b0"
    @State private var whoopSecret = ""
    @State private var whoopStatus: String?
    @State private var showWhoopKeys = false

    var body: some View {
        List {
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
            }
            Section {
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
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Heart Rate")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
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

// Edit sheet for the Mac address. Cancel leading, Connect trailing.
private struct MacAddressSheet: View {
    @State var host: String
    let connect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    private var trimmed: String { host.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Mac Address", text: $host)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit(save)
            }
            .navigationTitle("Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect", action: save).disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        connect(trimmed)
        dismiss()
    }
}
