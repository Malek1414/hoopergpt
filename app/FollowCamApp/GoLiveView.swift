import SwiftUI

// Live tab: where the stream goes, who plays, how the score bar looks.
// Sending is backend work and not built yet, so there is no send button;
// the stream key lives in the Keychain only.

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
                    StreamPreview(skin: skin, home: home, away: away)
                        .animation(.spring(duration: 0.35), value: selectedSkin)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                destination
                Section {
                    teamsRow
                    NavigationLink {
                        SkinPicker(home: home, away: away, selected: $selectedSkin,
                                   owns: owns, buy: { buying = $0 })
                    } label: {
                        LabeledContent("Score Bar", value: skin.name)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Live")
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
            .contentShape(Rectangle())
        }
        // A list row, not a tinted link: the label stays white.
        .buttonStyle(.plain)
    }

    private func reloadTeams() {
        home = TeamStore.home
        away = TeamStore.away
    }

    // MARK: skins

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
            .pickerStyle(.navigationLink)
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

    var body: some View {
        CourtLines()
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .top) {
                ScoreBar(skin: skin, home: home.name, away: away.name,
                         homeColor: Color(hex: home.color) ?? .white, awayColor: Color(hex: away.color) ?? .muted,
                         homeLogo: TeamStore.logo(home.id), awayLogo: TeamStore.logo(away.id),
                         scale: 0.92)
                    .padding(.top, 11)
                    .id(skin.id)
                    .transition(.opacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The skin list: one preview of the chosen skin, then plain rows.
private struct SkinPicker: View {
    let home: Team
    let away: Team
    @Binding var selected: String
    let owns: (Skin) -> Bool
    let buy: (Skin) -> Void

    var body: some View {
        List {
            Section {
                StreamPreview(skin: Skin.find(selected), home: home, away: away)
                    .animation(.spring(duration: 0.35), value: selected)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(Skin.all) { s in
                    Button {
                        if owns(s) { selected = s.id } else { buy(s) }
                    } label: {
                        HStack(spacing: 12) {
                            SkinSwatch(skin: s)
                            Text(s.name).foregroundStyle(.primary)
                            Spacer()
                            if s.id == selected {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            } else if !owns(s), let price = s.price {
                                Text(price).foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(s.id == selected ? .isSelected : [])
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .navigationTitle("Score Bar")
        .navigationBarTitleDisplayMode(.inline)
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
                StreamPreview(skin: skin, home: home, away: away)
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
