import PhotosUI
import SwiftUI

// Live tab: dress the stream (team logos, a skin for the score bar), then
// send it to YouTube, Twitch or any RTMP server. Sending is backend work,
// so the button stays off; the stream key lives in the Keychain only.

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
    @State private var logos: [UIImage?] = [TeamLogo.load(0), TeamLogo.load(1)]
    @State private var buying: Skin?

    private var skin: Skin { Skin.find(selectedSkin) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                preview
                logoPicker
                skinShelf
                destination
                PrimaryButton(title: "Go live", enabled: false) {}
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.ink.ignoresSafeArea())
        .sheet(item: $buying) { skin in
            BuySheet(skin: skin) {
                own(skin)
                buying = nil
            }
        }
    }

    // MARK: preview: what viewers will see

    private var preview: some View {
        CourtLines()
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(alignment: .top) {
                ScoreBar(skin: skin, homeLogo: logos[0], awayLogo: logos[1])
                    .padding(.top, 12)
                    .id(skin.id)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .animation(.spring(duration: 0.35), value: selectedSkin)
    }

    // MARK: team logos

    private var logoPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Team logos").font(.wide(20, 850)).foregroundColor(.white)
            HStack(spacing: 14) {
                LogoSlot(label: "Home", image: logos[0]) { set($0, side: 0) }
                LogoSlot(label: "Away", image: logos[1]) { set($0, side: 1) }
            }
        }
    }

    private func set(_ image: UIImage?, side: Int) {
        if let image {
            logos[side] = TeamLogo.save(image, side: side)
        } else {
            TeamLogo.remove(side)
            logos[side] = nil
        }
    }

    // MARK: skins

    private var skinShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Skins").font(.wide(20, 850)).foregroundColor(.white)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Skin.all) { s in
                        SkinCard(skin: s, owned: owns(s), selected: s.id == selectedSkin) {
                            if owns(s) { selectedSkin = s.id } else { buying = s }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Stream to").font(.wide(20, 850)).foregroundColor(.white)
            HStack(spacing: 8) {
                ForEach(Platform.allCases) { p in
                    Button {
                        platform = p
                        server = p.defaultServer
                    } label: {
                        Text(p.rawValue)
                            .font(.text(15, platform == p ? 700 : 550))
                            .foregroundColor(platform == p ? .black : .white)
                            .padding(.horizontal, 16).frame(height: 40)
                            .background(platform == p ? Color.white : Color.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PressScale())
                }
            }
            VStack(spacing: 0) {
                TextField("rtmp://", text: $server)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(platform != .custom)
                    .foregroundColor(platform == .custom ? .white : .muted)
                    .field()
                HStack {
                    SecureField(keySaved ? "Stream key saved" : "Stream key from \(platform.rawValue)", text: $key)
                    if !key.isEmpty {
                        Button("Save") {
                            Keychain.set(key, for: KeychainKey.rtmpStreamKey)
                            key = ""
                            keySaved = true
                        }
                        .font(.text(15, 700))
                        .foregroundColor(.pla)
                    }
                }
                .field()
            }
        }
    }
}

private extension View {
    func field() -> some View {
        self
            .font(.text(16, 550))
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}

// MARK: - pieces

private struct LogoSlot: View {
    let label: String
    let image: UIImage?
    let set: (UIImage?) -> Void
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.surface)
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.white.opacity(0.12)))
                Text(label).font(.text(16, 650)).foregroundColor(.white)
                Spacer(minLength: 0)
            }
        }
        .contextMenu {
            if image != nil { Button("Remove logo", role: .destructive) { set(nil) } }
        }
        .onChange(of: item) {
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    set(picked)
                }
                item = nil
            }
        }
    }
}

private struct SkinCard: View {
    let skin: Skin
    let owned: Bool
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            VStack(alignment: .leading, spacing: 10) {
                CourtLines()
                    .frame(width: 170, height: 96)
                    .overlay { ScoreBar(skin: skin, scale: 0.62) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selected ? Color.white : Color.clear, lineWidth: 2))
                HStack {
                    Text(skin.name).font(.text(15, 650)).foregroundColor(.white)
                    Spacer()
                    Text(owned ? (selected ? "On" : "Owned") : skin.price ?? "")
                        .font(.text(14, 650))
                        .foregroundColor(owned ? .muted : .pla)
                }
                .frame(width: 170)
            }
        }
        .buttonStyle(PressScale())
    }
}

/// Purchase step. Simulated: unlocks on the phone until StoreKit is wired.
private struct BuySheet: View {
    let skin: Skin
    let buy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CourtLines()
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .top) { ScoreBar(skin: skin).padding(.top, 12) }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(skin.name).font(.wide(30, 900)).foregroundColor(.white)
            PrimaryButton(title: "Buy for \(skin.price ?? "")", action: buy)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Color.surface)
    }
}
