import AVFoundation
import Photos
import PhotosUI
import SwiftUI

// First launch in three steps, pushed in a NavigationStack like Apple's own
// setup flows: welcome, your team (the home team), get ready (access and the
// Mac). Permissions are asked here on purpose, so the camera prompt never
// fires on top of a black viewfinder.

struct OnboardingView: View {
    let finish: () -> Void

    private enum Step: Hashable { case team, ready }

    // Screenshots: launch with `-debugPage N` (0 welcome, 1 team, 2 get ready).
    #if DEBUG
    @State private var path: [Step] = {
        switch UserDefaults.standard.integer(forKey: "debugPage") {
        case 1: return [.team]
        case 2...: return [.team, .ready]
        default: return []
        }
    }()
    #else
    @State private var path: [Step] = []
    #endif
    @State private var team = TeamStore.all().first ?? Team(name: "", color: TeamStore.palette[0])

    var body: some View {
        NavigationStack(path: $path) {
            WelcomePage { path.append(.team) }
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .team:
                        TeamPage(team: $team) {
                            TeamStore.save(team)
                            TeamStore.homeID = team.id
                            path.append(.ready)
                        }
                    case .ready:
                        ReadyPage(finish: finish)
                    }
                }
        }
        .preferredColorScheme(.dark)
        .tint(.pla)
    }
}

// MARK: - shared

/// The one primary action of a step, on the bottom safe area so the content
/// above uses the whole height and the button rides above the keyboard.
private struct BottomButton: View {
    let title: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!enabled)
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 1 welcome

/// Apple's "What's New" sheet: large title, three features, Continue.
private struct WelcomePage: View {
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                Text("Welcome to HooperGPT")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 56)
                VStack(alignment: .leading, spacing: 28) {
                    Feature(symbol: "video.fill", title: "Follows the Ball",
                            text: "The pod turns with the ball while you film.")
                    Feature(symbol: "play.tv.fill", title: "Live with the Score",
                            text: "Watch the game live with the score on screen.")
                    Feature(symbol: "person.3.fill", title: "Stats per Player",
                            text: "Shots and points for every player.")
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Color(.systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomButton(title: "Continue", action: next)
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
                .font(.title)
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

// MARK: - 2 your team

private struct TeamPage: View {
    @Binding var team: Team
    let next: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var logo: UIImage?
    @State private var adding = false

    private var hasName: Bool { !team.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        Form {
            Section {
                PhotosPicker(selection: $item, matching: .images) {
                    HStack(spacing: 14) {
                        TeamBadge(name: hasName ? team.name : "?",
                                  color: Color(hex: team.color) ?? .secondary, logo: logo, size: 44)
                        Text("Choose Logo")
                    }
                }
                TextField("Team Name", text: $team.name)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }

            Section("Color") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(TeamStore.palette, id: \.self) { hex in
                            Swatch(hex: hex, selected: team.color == hex) { team.color = hex }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
            }

            Section("Players") {
                ForEach(team.players.sorted { $0.number < $1.number }) { player in
                    HStack(spacing: 14) {
                        Text("\(player.number)")
                            .font(.system(.body, design: .monospaced).weight(.bold))
                            .frame(minWidth: 30, alignment: .leading)
                        Text(player.name.isEmpty ? "No Name" : player.name)
                            .foregroundStyle(player.name.isEmpty ? .secondary : .primary)
                    }
                }
                .onDelete { offsets in
                    // Offsets point into the sorted list, not the stored one.
                    let shown = team.players.sorted { $0.number < $1.number }
                    let ids = Set(offsets.map { shown[$0].id })
                    team.players.removeAll { ids.contains($0.id) }
                }
                Button {
                    adding = true
                } label: {
                    Label("Add Player", systemImage: "plus")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Your Team")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomButton(title: "Continue", enabled: hasName, action: next)
        }
        .sheet(isPresented: $adding) {
            AddPlayerSheet(taken: Set(team.players.map(\.number))) { player in
                team.players.append(player)
                team.players.sort { $0.number < $1.number }
            }
        }
        .onAppear { logo = TeamStore.logo(team.id) }
        .onChange(of: item) {
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let picked = UIImage(data: data) {
                    logo = TeamStore.saveLogo(picked, for: team.id)
                }
                self.item = nil
            }
        }
    }
}

private struct Swatch: View {
    let hex: String
    let selected: Bool
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            Circle()
                .fill(Color(hex: hex) ?? .secondary)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2)))
                .frame(width: 28, height: 28)
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? Color.primary : .clear, lineWidth: 2))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(hex)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Number and name, nothing else. Cancel left, Save right.
private struct AddPlayerSheet: View {
    let taken: Set<Int>
    let add: (RosterPlayer) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var name = ""
    @FocusState private var numberFocused: Bool

    private var parsed: Int? {
        guard let n = Int(number.trimmingCharacters(in: .whitespaces)), (0...99).contains(n) else { return nil }
        return n
    }
    private var duplicate: Bool { parsed.map(taken.contains) ?? false }
    private var valid: Bool { parsed != nil && !duplicate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Number", text: $number)
                        .keyboardType(.numberPad)
                        .focused($numberFocused)
                        .onChange(of: number) {
                            let digits = String(number.filter(\.isNumber).prefix(2))
                            if digits != number { number = digits }
                        }
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if duplicate { Text("Number \(number) is already on the team.") }
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let n = parsed, !duplicate else { return }
                        add(RosterPlayer(number: n, name: name.trimmingCharacters(in: .whitespaces)))
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
            .onAppear { numberFocused = true }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 3 get ready

private struct ReadyPage: View {
    let finish: () -> Void
    @AppStorage("bridgeHost") private var host = "192.168.1.10"
    @Environment(\.scenePhase) private var scenePhase
    @State private var camera = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    @State private var check: MacCheck = .idle
    @FocusState private var hostFocused: Bool

    enum MacCheck: Equatable { case idle, checking, ok, failed }

    var body: some View {
        Form {
            Section("Access") {
                PermissionRow(symbol: "video", title: "Camera", state: .init(camera)) {
                    AVCaptureDevice.requestAccess(for: .video) { _ in
                        DispatchQueue.main.async { camera = AVCaptureDevice.authorizationStatus(for: .video) }
                    }
                }
                PermissionRow(symbol: "mic", title: "Microphone", state: .init(mic)) {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in
                        DispatchQueue.main.async { mic = AVCaptureDevice.authorizationStatus(for: .audio) }
                    }
                }
                PermissionRow(symbol: "photo.on.rectangle", title: "Photos", state: .init(photos)) {
                    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                        DispatchQueue.main.async { photos = status }
                    }
                }
            }

            Section {
                HStack(spacing: 12) {
                    TextField("192.168.1.10", text: $host)
                        .font(.body.monospacedDigit())
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.go)
                        .focused($hostFocused)
                        .onSubmit { Task { await test() } }
                        .onChange(of: host) { check = .idle }
                    Button {
                        Task { await test() }
                    } label: {
                        if check == .checking { ProgressView() } else { Text("Test") }
                    }
                    .buttonStyle(.borderless)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(check == .checking || host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Mac")
            } footer: {
                status
            }
        }
        .formStyle(.grouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Get Ready")
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomButton(title: "Start", action: finish)
        }
        .onChange(of: scenePhase) {
            // Back from Settings: show what was switched there.
            guard scenePhase == .active else { return }
            camera = AVCaptureDevice.authorizationStatus(for: .video)
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
            photos = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        }
    }

    @ViewBuilder private var status: some View {
        switch check {
        case .idle, .checking:
            EmptyView()
        case .ok:
            Label("Mac found", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Color.pla)
        case .failed:
            Label("No Mac at this address. Same Wi-Fi?", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(Color.pla)
        }
    }

    private func test() async {
        hostFocused = false
        check = .checking
        check = await MacEndpoint(host: host).isReachable() ? .ok : .failed
    }
}

// MARK: - permissions

private struct PermissionRow: View {
    let symbol: String
    let title: String
    let state: PermissionState
    let request: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer(minLength: 8)
            PermissionButton(state: state, request: request)
        }
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
            Image(systemName: "checkmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Allowed")
        case .notAsked:
            Button("Allow", action: request)
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
        case .denied:
            // iOS only asks once; after a no, the switch lives in Settings.
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
    }
}
