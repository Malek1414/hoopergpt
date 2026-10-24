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
        VStack(spacing: 0) {
            HStack {
                ForEach(0..<4) { i in
                    Capsule()
                        .fill(i <= page ? Color.pla : Color(white: 0.2))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)

            TabView(selection: $page) {
                WelcomePage { page = 1 }.tag(0)
                KitPage { page = 2 }.tag(1)
                PermissionsPage { page = 3 }.tag(2)
                ConnectPage(host: $bridgeHost, finish: finish).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.25), value: page)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

// MARK: - pages

private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        OnboardingPage(buttonTitle: "GET STARTED", action: next) {
            Spacer()
            Wordmark(size: 44)
                .frame(maxWidth: .infinity)
            Text("Films your game, follows the ball and counts every shot.")
                .font(.system(size: 19, weight: .medium))
                .foregroundColor(.chrome)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            Spacer()
        }
    }
}

private struct KitPage: View {
    let next: () -> Void

    var body: some View {
        OnboardingPage(title: "What you need", buttonTitle: "I HAVE IT", action: next) {
            VStack(spacing: 14) {
                KitRow(icon: "camera.metering.center.weighted", title: "The pod",
                       detail: "Your iPhone sits in it on a tripod at the sideline.")
                KitRow(icon: "laptopcomputer", title: "A Mac with HooperGPT",
                       detail: "It steers the pod and works out the stats.")
                KitRow(icon: "wifi", title: "One network",
                       detail: "Phone and Mac on the same Wi-Fi or hotspot.")
            }
            Spacer()
        }
    }
}

private struct PermissionsPage: View {
    let next: () -> Void
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)

    var body: some View {
        OnboardingPage(title: "Allow access", buttonTitle: "CONTINUE", action: next) {
            VStack(spacing: 14) {
                PermissionRow(icon: "video", title: "Camera", detail: "To film the game.",
                              state: .init(camera)) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { camera = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
                PermissionRow(icon: "mic", title: "Microphone", detail: "Court sound in the clip.",
                              state: .init(mic)) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                }
                PermissionRow(icon: "photo.on.rectangle", title: "Photos", detail: "Saves each recording.",
                              state: .init(photos)) {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        DispatchQueue.main.async { photos = status }
                    }
                }
            }
            Text("You can change this later in Settings.")
                .font(.footnote)
                .foregroundColor(.chrome)
                .padding(.top, 6)
            Spacer()
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
                       buttonTitle: check == .ok ? "START FILMING" : "SKIP FOR NOW",
                       action: finish) {
            Text("Enter the address shown on the Mac when HooperGPT starts.")
                .foregroundColor(.chrome)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("192.168.1.10", text: $host)
                .font(.mono(20, .medium))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused)
                .padding(16)
                .background(Color.panel)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onChange(of: host) { check = .idle }
            Button {
                focused = false
                Task { await test() }
            } label: {
                HStack(spacing: 10) {
                    switch check {
                    case .idle: Image(systemName: "antenna.radiowaves.left.and.right")
                    case .checking: ProgressView().tint(.white)
                    case .ok: Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    case .failed: Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                    }
                    Text(checkLabel).font(.mono(14, .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(white: 0.3)))
                .foregroundColor(.white)
            }
            .disabled(check == .checking || host.isEmpty)
            Spacer()
        }
    }

    private var checkLabel: String {
        switch check {
        case .idle: return "TEST CONNECTION"
        case .checking: return "LOOKING"
        case .ok: return "MAC FOUND"
        case .failed: return "NOT FOUND, CHECK WI-FI"
        }
    }

    private func test() async {
        check = .checking
        check = await MacEndpoint(host: host).isReachable() ? .ok : .failed
    }
}

// MARK: - building blocks

private struct OnboardingPage<Content: View>: View {
    var title: String?
    let buttonTitle: String
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let title {
                Text(title)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.top, 28)
            }
            content
            PrimaryButton(title: buttonTitle, action: action)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: 520)
    }
}

private struct KitRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(.pla)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundColor(.white)
                Text(detail).font(.subheadline).foregroundColor(.chrome)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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

private struct PermissionRow: View {
    let icon: String
    let title: String
    let detail: String
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.pla)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundColor(.white)
                Text(detail).font(.subheadline).foregroundColor(.chrome)
            }
            Spacer(minLength: 0)
            switch state {
            case .granted:
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundColor(.green)
            case .notAsked:
                Button("ALLOW", action: request)
                    .font(.mono(13, .bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.pla)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            case .denied:
                // iOS only asks once; after a no, the switch lives in Settings.
                Button("SETTINGS") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.mono(13, .bold))
                .foregroundColor(.chrome)
            }
        }
        .padding(16)
        .background(Color.panel)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
