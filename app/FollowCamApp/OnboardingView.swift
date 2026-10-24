import AVFoundation
import Photos
import SwiftUI

// First launch: four short pages, then the tabs. Permissions are asked here
// on purpose, so the camera prompt never fires on top of a black viewfinder.

struct OnboardingView: View {
    let finish: () -> Void
    // Screenshots: launch with `-debugPage 2` to open a page directly.
    #if DEBUG
    @State private var page = UserDefaults.standard.integer(forKey: "debugPage")
    #else
    @State private var page = 0
    #endif
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                WelcomePage { page = 1 }.tag(0)
                KitPage { page = 2 }.tag(1)
                PermissionsPage { page = 3 }.tag(2)
                ConnectPage(host: $bridgeHost, finish: finish).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(duration: 0.4), value: page)

            if page > 0 {
                HStack(spacing: 6) {
                    ForEach(1..<4) { i in
                        Capsule()
                            .fill(i <= page ? Color.white : Color.white.opacity(0.18))
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
            Wordmark(size: 60)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 24)
                .padding(.top, 16)
            OnboardingHero()
                .frame(maxHeight: .infinity)
                .padding(.vertical, 18)
            VStack(alignment: .leading, spacing: 22) {
                HeroCaption()
                PrimaryButton(title: "Get started", action: next)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

private struct KitPage: View {
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "What you need", buttonTitle: "I have it", action: next) {
            VStack(spacing: 0) {
                Line(icon: "camera.metering.center.weighted", title: "The pod",
                     detail: "Your iPhone in it, tripod at the sideline.")
                Line(icon: "laptopcomputer", title: "A Mac with HooperGPT",
                     detail: "It steers the pod and does the stats.")
                Line(icon: "wifi", title: "One network",
                     detail: "Phone and Mac on the same Wi-Fi.")
            }
        }
    }
}

private struct PermissionsPage: View {
    let next: () -> Void
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        OnboardingPage(title: "Allow access", buttonTitle: "Continue", action: next) {
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
        OnboardingPage(title: "Find your Mac",
                       buttonTitle: check == .ok ? "Start filming" : "Skip for now",
                       action: finish) {
            VStack(alignment: .leading, spacing: 18) {
                Text("The address the Mac shows when HooperGPT starts.")
                    .font(.text(17))
                    .foregroundColor(.muted)
                HStack {
                    TextField("192.168.1.10", text: $host)
                        .font(.wide(24, 750))
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
                            case .failed: Text("Not found").foregroundColor(.red)
                            }
                        }
                        .font(.text(16, 650))
                        .foregroundColor(.white)
                        .frame(minWidth: 60, minHeight: 44)
                    }
                    .disabled(check == .checking || host.isEmpty)
                }
                .padding(.vertical, 8)
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

private struct OnboardingPage<Content: View>: View {
    let title: String
    let buttonTitle: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(title)
                .font(.wide(38, 900))
                .foregroundColor(.white)
                .padding(.top, 56)
            content
            Spacer()
            PrimaryButton(title: buttonTitle, action: action)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
    }
}

/// One line of a list: plain icon, title, one sentence, optional control.
private struct Line<Trailing: View>: View {
    let icon: String
    let title: String
    var detail: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.text(18, 650)).foregroundColor(.white)
                if let detail {
                    Text(detail).font(.text(15)).foregroundColor(.muted)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.vertical, 18)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }
}

private extension Line where Trailing == EmptyView {
    init(icon: String, title: String, detail: String) {
        self.init(icon: icon, title: title, detail: detail) { EmptyView() }
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
            Text("On").font(.text(16, 650)).foregroundColor(.green)
        case .notAsked:
            Button("Allow", action: request)
                .font(.text(16, 700))
                .foregroundColor(.white)
                .frame(minWidth: 60, minHeight: 44)
        case .denied:
            // iOS only asks once; after a no, the switch lives in Settings.
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.text(16, 650))
            .foregroundColor(.muted)
            .frame(minWidth: 60, minHeight: 44)
        }
    }
}
