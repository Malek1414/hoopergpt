import SwiftUI

// Go Live tab: send the game to YouTube, Twitch or any RTMP server.
// Only the setup exists so far. The sending itself is backend work and the
// button says so instead of pretending. The stream key lives in the Keychain.

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
    @State private var key = ""
    @State private var keySaved = Keychain.get(KeychainKey.rtmpStreamKey) != nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Go live")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Picker("Platform", selection: $platform) {
                    ForEach(Platform.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: platform) { server = platform.defaultServer }

                field("SERVER") {
                    TextField("rtmp://", text: $server)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(platform != .custom)
                        .foregroundColor(platform == .custom ? .white : .chrome)
                }
                field("STREAM KEY") {
                    HStack {
                        SecureField(keySaved ? "Saved on this phone" : "Paste from \(platform.rawValue)",
                                    text: $key)
                        if !key.isEmpty {
                            Button("SAVE") {
                                Keychain.set(key, for: KeychainKey.rtmpStreamKey)
                                key = ""
                                keySaved = true
                            }
                            .font(.mono(13, .bold))
                            .foregroundColor(.pla)
                        }
                    }
                }

                PrimaryButton(title: "GO LIVE", enabled: false) {}
                Text("Sending is not switched on yet. Your setup is kept for when it is.")
                    .font(.footnote)
                    .foregroundColor(.chrome)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.mono(11, .bold)).foregroundColor(.chrome)
            content()
                .font(.mono(15, .medium))
                .padding(14)
                .background(Color.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
