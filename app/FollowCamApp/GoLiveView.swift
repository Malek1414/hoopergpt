import SwiftUI

// Live tab: dress the stream (teams, a skin for the score bar), then send
// it to YouTube, Twitch or any RTMP server. Sending is backend work, so
// the button stays off; the stream key lives in the Keychain only.

struct GoLiveView: View {
    enum Platform: String, CaseIterable, Identifiable {
        case youtube = "YouTube", twitch = "Twitch", custom = "Custom"
        var id: String { rawValue }

        var defaultServer: String {
            switch self {
            case .youtube: return "rtmp://a.rtmp.youtube.com/live2"
            case .twitch: return "rtmp://live.twitch.tv/app"
            case .custom: return ""
            }
        }
    }

    @AppStorage("live.platform") private var platform: Platform = .youtube
    @AppStorage("live.server") private var server = Platform.youtube.defaultServer
    @AppStorage("skins.selected") private var selectedSkin = "classic"
    @AppStorage("skins.owned") private var ownedSkins = "classic"
    @State private var key = ""
    @State private var keySaved = Keychain.get(KeychainKey.rtmpStreamKey) != nil
    @State private var home = TeamStore.home
    @State private var away = TeamStore.away
    @State private var editingTeams = false
    // Screenshots: launch with `-debugBuy neon` to open the buy sheet.
    #if DEBUG
    @State private var buying: Skin? = UserDefaults.standard.string(forKey: "debugBuy").map(Skin.find)
    #else
    @State private var buying: Skin?
    #endif

    private var skin: Skin { Skin.find(selectedSkin) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StreamPreview(skin: skin, home: home, away: away, radius: 14)
                        .animation(.spring(duration: 0.35), value: selectedSkin)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Teams") { teamsRow }
                Section("Overlay") { skinRow }
                destination
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Go Live")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "Go Live", enabled: false) {}
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(.bar)
            }
        }
        .tint(.pla)
        .sheet(item: $buying) { skin in
            BuySheet(skin: skin, home: home, away: away) {
                own(skin)
                buying = nil
            } close: {
                buying = nil
            }
        }
        .sheet(isPresented: $editingTeams, onDismiss: reloadTeams) {
            GameSetupView(actionTitle: "Save", start: { editingTeams = false }, cancel: { editingTeams = false })
        }
    }

    // MARK: teams: named in the game setup, edited there too

    private var teamsRow: some View {
        Button { editingTeams = true } label: {
            HStack(spacing: 12) {
                HStack(spacing: -8) {
                    TeamBadge(team: home, size: 30)
                    TeamBadge(team: away, size: 30)
                }
                Text("\(home.name) vs \(away.name)")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func reloadTeams() {
        home = TeamStore.home
        away = TeamStore.away
    }

    // MARK: skins

    private var skinRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(Skin.all) { s in
                    SkinCard(skin: s, home: home, away: away, owned: owns(s), selected: s.id == selectedSkin) {
                        if owns(s) { selectedSkin = s.id } else { buying = s }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .listRowInsets(EdgeInsets())
    }

    private func owns(_ s: Skin) -> Bool {
        s.price == nil || ownedSkins.split(separator: ",").contains(Substring(s.id))
    }

    private func own(_ s: Skin) {
        if !owns(s) { ownedSkins += ",\(s.id)" }
        selectedSkin = s.id
    }

    // MARK: where it goes

    private var destination: some View {
        Section {
            Picker("Platform", selection: $platform) {
                ForEach(Platform.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .onChange(of: platform) { server = platform.defaultServer }

            LabeledContent("Server") {
                if platform == .custom {
                    TextField("rtmp://", text: $server)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .multilineTextAlignment(.trailing)
                } else {
                    // Fixed for YouTube and Twitch: shown, not editable.
                    Text(server.replacingOccurrences(of: "rtmp://", with: ""))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            LabeledContent("Stream Key") {
                HStack(spacing: 12) {
                    SecureField(keySaved ? "Saved" : "Required", text: $key)
                        .multilineTextAlignment(.trailing)
                        .onSubmit(saveKey)
                    if !key.isEmpty {
                        Button("Save", action: saveKey)
                            .fontWeight(.semibold)
                            .buttonStyle(.borderless)
                    }
                }
            }
        } header: {
            Text("Destination")
        } footer: {
            Text("Streaming arrives with the next update.")
        }
    }

    private func saveKey() {
        guard !key.isEmpty else { return }
        Keychain.set(key, for: KeychainKey.rtmpStreamKey)
        key = ""
        keySaved = true
    }
}

// MARK: - pieces

/// What viewers will see: the court with the score bar on top.
private struct StreamPreview: View {
    let skin: Skin
    let home: Team
    let away: Team
    var radius: CGFloat = 12
    var scale: CGFloat = 0.92

    var body: some View {
        CourtLines()
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .top) {
                ScoreBar(skin: skin, home: home.name.uppercased(), away: away.name.uppercased(),
                         homeColor: Color(hex: home.color) ?? .white, awayColor: Color(hex: away.color) ?? .muted,
                         homeLogo: TeamStore.logo(home.id), awayLogo: TeamStore.logo(away.id),
                         scale: scale)
                    .padding(.top, 12 * scale)
                    .id(skin.id)
                    .transition(.opacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.white.opacity(0.08)))
    }
}

private struct SkinCard: View {
    let skin: Skin
    let home: Team
    let away: Team
    let owned: Bool
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 8) {
                StreamPreview(skin: skin, home: home, away: away, radius: 10, scale: 0.44)
                    .frame(width: 156)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(selected ? Color.pla : Color.clear, lineWidth: 2.5))
                HStack(spacing: 4) {
                    Text(skin.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                    } else {
                        Text(owned ? "Owned" : skin.price ?? "")
                            .font(.subheadline)
                            .foregroundStyle(owned ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    }
                }
                .frame(width: 156)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Purchase step. Simulated: unlocks on the phone until StoreKit is wired.
private struct BuySheet: View {
    let skin: Skin
    let home: Team
    let away: Team
    let buy: () -> Void
    let close: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                StreamPreview(skin: skin, home: home, away: away, radius: 14)
                VStack(alignment: .leading, spacing: 4) {
                    Text(skin.name).font(.title.bold())
                    Text("Score bar for your stream. One-time purchase.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                PrimaryButton(title: "Buy for \(skin.price ?? "")", action: buy)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 16)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: close)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(.pla)
        .presentationDetents([.height(460)])
        .presentationDragIndicator(.hidden)
    }
}
