import AVFoundation
import Photos
import SwiftUI

// First launch, in the shape of Apple's own setup screens: welcome, your team,
// your players, access, your Mac. Permissions are asked here on purpose, so
// the camera prompt never fires on top of a black viewfinder. The team made
// here is the home team. No swiping between pages: each step has its gate.

struct OnboardingView: View {
    let finish: () -> Void
    // Screenshots: launch with `-debugPage 2` to open a page directly.
    #if DEBUG
    @State private var page = min(max(UserDefaults.standard.integer(forKey: "debugPage"), 0), 4)
    #else
    @State private var page = 0
    #endif
    @State private var forward = true
    @State private var team = TeamStore.all().first ?? Team(name: "", color: TeamStore.palette[0])
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"

    private static let pages = 5

    var body: some View {
        VStack(spacing: 0) {
            TopBar(page: page, count: Self.pages) { go(page - 1) }
            ZStack {
                current
                    .id(page)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(.pla)
    }

    @ViewBuilder private var current: some View {
        switch page {
        case 0:
            WelcomePage { go(1) }
        case 1:
            Page(button: "Continue",
                 enabled: !team.name.trimmingCharacters(in: .whitespaces).isEmpty,
                 action: { TeamStore.save(team); go(2) }) {
                Header(symbol: "person.3.fill", title: "Your Team")
                TeamForm(team: $team)
                    .padding(.top, 28)
                Spacer(minLength: 0)
            }
        case 2:
            Page(button: team.players.isEmpty ? "Later" : "Continue",
                 action: {
                     TeamStore.save(team)
                     TeamStore.homeID = team.id
                     go(3)
                 }) {
                Header(symbol: "tshirt.fill", title: "Your Players")
                RosterList(players: $team.players)
                    .padding(.top, 20)
                Spacer(minLength: 0)
            }
        case 3:
            PermissionsPage { go(4) }
        default:
            ConnectPage(host: $bridgeHost, finish: finish)
        }
    }

    private func go(_ target: Int) {
        guard (0..<Self.pages).contains(target) else { return }
        forward = target > page
        withAnimation(.spring(duration: 0.4)) { page = target }
    }
}

// MARK: - frame

/// Back on the left, page dots in the middle, like Apple's setup assistant.
private struct TopBar: View {
    let page: Int
    let count: Int
    let back: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(page + 1) of \(count)")
            .animation(.easeInOut(duration: 0.2), value: page)

            HStack {
                if page > 0 {
                    Button(action: back) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            Text("Back")
                        }
                        .frame(minHeight: 44)
                    }
                    .transition(.opacity)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }
}

/// One step: content scrolls and fills the height, the primary button sits at
/// the bottom on the safe area, so it rides above the keyboard on any phone.
private struct Page<Content: View>: View {
    let button: String
    var enabled = true
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) { content }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .frame(maxWidth: 520)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: button, enabled: enabled, action: action)
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 12)
                .background(Color(.systemBackground))
        }
    }
}

/// Plain SF Symbol over a large centered title, as in Apple's setup screens.
private struct Header: View {
    let symbol: String
    let title: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 50, weight: .regular))
                .foregroundStyle(Color.pla)
                .frame(height: 60)
                .accessibilityHidden(true)
            Text(title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

// MARK: - pages

/// Apple's "Welcome to" / "What's New" sheet: title, three features, Continue.
private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        Page(button: "Continue", action: next) {
            Spacer(minLength: 16)
            VStack(spacing: 2) {
                Text("Welcome to")
                    .font(.system(size: 34, weight: .bold))
                Wordmark(size: 44)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 28) {
                Feature(symbol: "video.fill", title: "Films the Game",
                        text: "The camera turns with the ball, so you can coach instead of filming.")
                Feature(symbol: "dot.radiowaves.left.and.right", title: "Live with the Score",
                        text: "Watch the game live with the score on screen.")
                Feature(symbol: "person.text.rectangle", title: "Stats per Player",
                        text: "Shots and points for every number on your roster.")
            }
            Spacer(minLength: 24)
            Spacer(minLength: 0)
        }
    }
}

private struct Feature: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(Color.pla)
                .frame(width: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionsPage: View {
    let next: () -> Void
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        Page(button: "Continue", action: next) {
            Header(symbol: "hand.raised.fill", title: "Allow Access")
            VStack(spacing: 0) {
                PermissionRow(symbol: "video.fill", title: "Camera", text: "Films the game.",
                              state: .init(camera)) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { camera = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
                Divider().padding(.leading, 56)
                PermissionRow(symbol: "mic.fill", title: "Microphone", text: "Records the sound of the gym.",
                              state: .init(mic)) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                }
                Divider().padding(.leading, 56)
                PermissionRow(symbol: "photo.on.rectangle", title: "Photos", text: "Saves your recordings.",
                              state: .init(photos)) {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        DispatchQueue.main.async { photos = status }
                    }
                }
            }
            .padding(.horizontal, 16)
            .background(Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 32)
            Spacer(minLength: 0)
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
        Page(button: check == .ok ? "Start" : "Later", action: finish) {
            Header(symbol: "macbook", title: "Find Your Mac")
            Text("Type the address your Mac shows when HooperGPT starts.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    TextField("192.168.1.10", text: $host)
                        .font(.body.monospacedDigit())
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { Task { await test() } }
                        .onChange(of: host) { check = .idle }
                    Button {
                        focused = false
                        Task { await test() }
                    } label: {
                        Group {
                            if check == .checking { ProgressView() } else { Text("Test") }
                        }
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .disabled(check == .checking || host.isEmpty)
                }
                .padding(.leading, 16)
                .padding(.trailing, 8)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                status
                    .font(.footnote)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 18, alignment: .leading)
            }
            .padding(.top, 28)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var status: some View {
        switch check {
        case .idle, .checking:
            Text(" ")
        case .ok:
            Label("Mac found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Label("No Mac at this address. Same Wi-Fi?", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Color.pla)
        }
    }

    private func test() async {
        focused = false
        check = .checking
        check = await MacEndpoint(host: host).isReachable() ? .ok : .failed
    }
}

// MARK: - permissions

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let text: String
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(Color.pla)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body)
                Text(text).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PermissionButton(state: state, request: request)
        }
        .frame(minHeight: 64)
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
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Allowed")
        case .notAsked:
            Button("Allow", action: request)
                .font(.body.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        case .denied:
            // iOS only asks once; after a no, the switch lives in Settings.
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
    }
}
