import AVFoundation
import Photos
import SwiftUI

// First launch: what it is, your team, your players, access, your Mac.
// Permissions are asked here on purpose, so the camera prompt never fires
// on top of a black viewfinder. The team made here is the home team.

struct OnboardingView: View {
    let finish: () -> Void
    // Screenshots: launch with `-debugPage 2` to open a page directly.
    #if DEBUG
    @State private var page = UserDefaults.standard.integer(forKey: "debugPage")
    #else
    @State private var page = 0
    #endif
    @State private var team = TeamStore.all().first ?? Team(name: "", color: TeamStore.palette[0])
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                WelcomePage { page = 1 }.tag(0)
                Step(title: "YOUR\nTEAM", button: "Continue",
                     enabled: !team.name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    TeamStore.save(team)
                    page = 2
                } content: {
                    TeamForm(team: $team)
                }
                .tag(1)
                Step(title: "YOUR\nPLAYERS", button: team.players.isEmpty ? "Later" : "Continue", fill: true) {
                    TeamStore.save(team)
                    TeamStore.homeID = team.id
                    page = 3
                } content: {
                    ScrollView { RosterList(players: $team.players) }
                }
                .tag(2)
                PermissionsPage { page = 4 }.tag(3)
                ConnectPage(host: $bridgeHost, finish: finish).tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(duration: 0.4), value: page)

            if page > 0 {
                HStack(spacing: 6) {
                    ForEach(1..<5) { i in
                        Capsule()
                            .fill(i <= page ? Color.pla : Color.white.opacity(0.18))
                            .frame(height: 3)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
        .background(Color.ink.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - pages

private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark(size: 118)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(.top, 20)
            Spacer()
            VStack(alignment: .leading, spacing: 18) {
                claim("01", "Films the game")
                claim("02", "Follows the ball")
                claim("03", "Counts every shot")
            }
            Spacer()
            PrimaryButton(title: "Get started", action: next)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func claim(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(n).font(.wide(22, 800)).foregroundColor(.pla)
            Text(text.uppercased()).font(.wide(40, 900)).foregroundColor(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

/// One onboarding step: big title on top, the content in the middle of the
/// screen (or filling it), the action at the bottom where the thumb is.
private struct Step<Content: View>: View {
    let title: String
    let button: String
    var enabled = true
    var fill = false
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.wide(64, 900))
                .lineSpacing(-18)
                .foregroundColor(.white)
                .padding(.top, 40)
            if fill {
                content.padding(.top, 20)
            } else {
                Spacer()
                content
                Spacer()
            }
            PrimaryButton(title: button, enabled: enabled, action: action)
                .padding(.top, 16)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
        .scrollDismissesKeyboard(.interactively)
    }
}

private struct PermissionsPage: View {
    let next: () -> Void
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        Step(title: "ALLOW\nACCESS", button: "Continue", action: next) {
            VStack(spacing: 0) {
                Line(icon: "video", title: "Camera") {
                    PermissionButton(state: .init(camera)) {
                        AVCaptureDevice.requestAccess(for: .video) { _ in
                            DispatchQueue.main.async { camera = AVCaptureDevice.authorizationStatus(for: .video) }
                        }
                    }
                }
                Line(icon: "mic", title: "Microphone") {
                    PermissionButton(state: .init(mic)) {
                        AVCaptureDevice.requestAccess(for: .audio) { _ in
                            DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                        }
                    }
                }
                Line(icon: "photo.on.rectangle", title: "Photos") {
                    PermissionButton(state: .init(photos)) {
                        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                            DispatchQueue.main.async { photos = status }
                        }
                    }
                }
            }
        }
    }
}

private struct ConnectPage: View {
    @Binding var host: String
    let finish: () -> Void
    @State private var check: MacCheck = .idle
    @FocusState private var focused: Bool

    enum MacCheck: Equatable { case idle, checking, ok, failed }

    var body: some View {
        Step(title: "FIND\nYOUR MAC", button: check == .ok ? "Start" : "Later", action: finish) {
            VStack(alignment: .leading, spacing: 14) {
                Text("The address the Mac shows when HooperGPT starts.")
                    .font(.text(17))
                    .foregroundColor(.muted)
                HStack {
                    TextField("192.168.1.10", text: $host)
                        .font(.wide(36, 800))
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($focused)
                        .onChange(of: host) { check = .idle }
                    Button {
                        focused = false
                        Task { await test() }
                    } label: {
                        Group {
                            switch check {
                            case .idle: Text("Test")
                            case .checking: ProgressView().tint(.white)
                            case .ok: Text("Found").foregroundColor(.green)
                            case .failed: Text("Not found").foregroundColor(.pla)
                            }
                        }
                        .font(.text(17, 650))
                        .foregroundColor(.white)
                        .frame(minWidth: 60, minHeight: 44)
                    }
                    .disabled(check == .checking || host.isEmpty)
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(check == .ok ? Color.green : Color.white.opacity(0.3)).frame(height: 2)
                }
            }
        }
    }

    private func test() async {
        check = .checking
        check = await MacEndpoint(host: host).isReachable() ? .ok : .failed
    }
}

// MARK: - building blocks

/// One line of a list: plain icon, title, optional control.
private struct Line<Trailing: View>: View {
    let icon: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 34)
            Text(title.uppercased()).font(.wide(28, 800)).foregroundColor(.white)
            Spacer(minLength: 0)
            trailing
        }
        .frame(minHeight: 76)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}

private enum PermissionState {
    case notAsked, granted, denied

    init(_ status: AVAuthorizationStatus) {
        switch status {
        case .authorized: self = .granted
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }

    init(_ status: PHAuthorizationStatus) {
        switch status {
        case .authorized, .limited: self = .granted
        case .notDetermined: self = .notAsked
        default: self = .denied
        }
    }
}

private struct PermissionButton: View {
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundColor(.pla)
                .accessibilityLabel("Allowed")
        case .notAsked:
            Button("Allow", action: request)
                .font(.text(17, 700))
                .foregroundColor(.pla)
                .frame(minWidth: 60, minHeight: 44)
        case .denied:
            // iOS only asks once; after a no, the switch lives in Settings.
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.text(17, 600))
            .foregroundColor(.muted)
            .frame(minWidth: 60, minHeight: 44)
        }
    }
}
