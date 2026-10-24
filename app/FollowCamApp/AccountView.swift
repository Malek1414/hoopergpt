import SwiftUI

// Account tab: who you are, your pod, your strap, what you bought.
// The old settings sheet from the camera screen lives here now.

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
    @State private var openGame: GameRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                profile
                section("Games") {
                    if games.isEmpty {
                        Text("Your games show up here after you film one.")
                            .font(.text(16)).foregroundColor(.muted).row()
                    }
                    ForEach(games) { game in
                        Button { openGame = game } label: { gameRow(game) }
                            .row()
                    }
                }
                section("Pod") {
                    HStack {
                        TextField("Mac address", text: $bridgeHost)
                            .font(.text(17, 550))
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button(pan.connected ? "Connected" : "Connect") { pan.connect(host: bridgeHost) }
                            .font(.text(15, 650))
                            .foregroundColor(pan.connected ? .green : .white)
                    }
                    .row()
                    Toggle("Turn the other way", isOn: $pan.invert)
                        .font(.text(17, 550))
                        .tint(.pla)
                        .row()
                    if pan.connected {
                        Button("Disconnect", role: .destructive) { pan.disconnect() }
                            .font(.text(17, 550))
                            .row()
                    }
                }
                section("Heart rate") {
                    Button {
                        Task { await syncWhoop() }
                    } label: {
                        HStack {
                            Text(whoop.connected ? "WHOOP connected" : "Connect WHOOP")
                            Spacer()
                            Text(whoop.connected ? "Sync" : "")
                                .foregroundColor(.muted)
                        }
                        .font(.text(17, 550))
                        .foregroundColor(.white)
                    }
                    .row()
                    if let whoopStatus {
                        Text(whoopStatus).font(.text(14)).foregroundColor(.muted).row()
                    }
                    DisclosureGroup("Developer keys", isExpanded: $showWhoopKeys) {
                        VStack(spacing: 12) {
                            TextField("Client ID", text: $whoopClientID)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            SecureField("Client secret", text: $whoopSecret)
                            Button("Save keys") {
                                WhoopClient.configure(clientID: whoopClientID, secret: whoopSecret)
                                whoopSecret = ""
                                whoopStatus = "Keys saved"
                            }
                            .disabled(whoopClientID.isEmpty || whoopSecret.isEmpty)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.text(15))
                        .padding(.top, 12)
                    }
                    .font(.text(17, 550))
                    .tint(.muted)
                    .row()
                }
                section("Skins") {
                    ForEach(Skin.all.filter { ownedSkins.split(separator: ",").contains(Substring($0.id)) }) { skin in
                        Button { selectedSkin = skin.id } label: {
                            HStack {
                                Text(skin.name).font(.text(17, 550)).foregroundColor(.white)
                                Spacer()
                                if skin.id == selectedSkin {
                                    Text("On").font(.text(15, 650)).foregroundColor(.green)
                                }
                            }
                        }
                        .row()
                    }
                }
                section("Help") {
                    Button("Show the setup steps again", action: replayGuide)
                        .font(.text(17, 550))
                        .foregroundColor(.white)
                        .row()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ink.ignoresSafeArea())
        .onAppear { games = GameStore.load() }
        .sheet(item: $openGame) { GameDetailView(game: $0) }
    }

    private func gameRow(_ game: GameRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(game.home.name) vs \(game.away.name)")
                    .font(.text(17, 600)).foregroundColor(.white).lineLimit(1)
                Text(game.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.text(14)).foregroundColor(.muted)
            }
            Spacer()
            if let t = game.final?.teams, t.count == 2 {
                Text("\(t[0].score) : \(t[1].score)").font(.wide(18, 900)).foregroundColor(.white)
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.muted)
        }
        .padding(.vertical, 8)
    }

    private var profile: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.surface)
                .overlay(Image(systemName: "person.fill").font(.system(size: 24)).foregroundColor(.muted))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("Guest").font(.wide(26, 850)).foregroundColor(.white)
                Button("Sign in") {}
                    .font(.text(15, 650))
                    .foregroundColor(.pla)
            }
            Spacer()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.wide(20, 850)).foregroundColor(.white).padding(.bottom, 6)
            content()
        }
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

private extension View {
    /// A settings row: full width, a hairline under it, no box around it.
    func row() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}
