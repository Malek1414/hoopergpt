import AVFoundation
import SwiftUI

// Film tab: the viewfinder, chrome like Apple's Camera app. Plain symbols
// for the pod and the strap at the top, the timecode in red while recording,
// the shutter at the bottom with the last game to its left. Orange marks the
// followed player, red is REC.

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @ObservedObject var pan: PanController
    @Binding var showGuide: Bool
    @StateObject private var heart = HeartRateMonitor()
    @StateObject private var whoop = WhoopAuthCoordinator.shared
    @StateObject private var level = MotionLevel()
    @State private var tracker = SubjectTracker()
    @State private var subjectBox: CGRect?
    @State private var players: [CGRect] = []   // detected people, Vision-normalized
    // Remembered between launches: the laptop does not move between court tests.
    @AppStorage("bridgeHost") private var bridgeHost = "192.168.1.10"
    @State private var recordingStarted: Date?
    @State private var lostFlashUntil: Date?
    @State private var sweptRange: ClosedRange<Double> = 90...90
    // auto-reacquire: retry the last known box for a short window after loss
    @State private var reacquireBox: CGRect?
    @State private var reacquireUntil: Date = .distantPast
    @State private var frameCount = 0
    // session summary counters (active while recording)
    @State private var recFrames = 0
    @State private var recTargetFrames = 0
    @State private var recHRRange: ClosedRange<Int>?
    @State private var recSwept: ClosedRange<Double> = 90...90
    @State private var summary: SessionSummary?
    // Screenshots: launch with `-debugSetup YES` to open the game setup.
    @State private var settingUpGame = UserDefaults.standard.bool(forKey: "debugSetup")
    @AppStorage("didOnboard") private var didOnboard = false
    // Newest saved game, for the button left of the shutter (nil hides it).
    @State private var lastGame: GameRecord?
    @State private var showingLastGame = false

    var body: some View {
        ZStack {
            CameraPreview(layer: camera.previewLayer)
                .ignoresSafeArea()
                .onTapGesture { location in
                    let tapROI = camera.normalizedRect(aroundLayerPoint: location)
                    let tapCenter = CGPoint(x: tapROI.midX, y: tapROI.midY)
                    // snap to the detected player nearest the tap; raw ROI fallback
                    let hit = players.min(by: {
                        hypot($0.midX - tapCenter.x, $0.midY - tapCenter.y) <
                        hypot($1.midX - tapCenter.x, $1.midY - tapCenter.y)
                    })
                    if let hit, hypot(hit.midX - tapCenter.x, hit.midY - tapCenter.y) < 0.25 {
                        tracker.select(roi: hit)
                    } else {
                        tracker.select(roi: tapROI)
                    }
                    lostFlashUntil = nil
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

            FloorRings(players: players, locked: subjectBox).allowsHitTesting(false)

            if let box = subjectBox {
                LockRing(box: box).allowsHitTesting(false)
            }

            VStack(spacing: 12) {
                statusStrip
                if let started = recordingStarted {
                    TimecodeView(since: started)
                        .transition(.opacity)
                }
                // Only while the phone is tilted; the frame stays so nothing jumps.
                Horizon(angle: pan.angle, roll: level.rollDegrees, isLevel: level.isLevel)
                    .frame(width: 150, height: 14)
                    .opacity(level.isLevel ? 0 : 1)
                    .animation(.easeOut(duration: 0.25), value: level.isLevel)
                Spacer()
                if let until = lostFlashUntil, until > Date() {
                    Text("Lost them. Tap a player.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .glass(20)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                bottomBar
            }
            .animation(.easeOut(duration: 0.2), value: lostFlashUntil)
            .animation(.easeOut(duration: 0.2), value: recordingStarted)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $summary) { s in SummaryCard(summary: s, camera: camera) }
        // A sheet that leaves the camera usable behind it: the steps tick off
        // live while the user taps Pod and a player.
        .sheet(isPresented: $showGuide, onDismiss: { didOnboard = true }) {
            SetupGuide(rigLinked: pan.connected,
                       targetSet: tracker.isTracking,
                       recording: camera.isRecording) {
                showGuide = false
            }
        }
        .onAppear {
            camera.onFrame = { pixelBuffer in
                let box = tracker.track(in: pixelBuffer)   // Vision work stays off-main
                let detected = tracker.frameIndex % 3 == 0 ? tracker.humans(in: pixelBuffer) : nil
                DispatchQueue.main.async {
                    if let detected { players = detected }
                    handleFrame(box: box)
                }
            }
            camera.start()
            level.start()
            refreshLastGame()
            if !didOnboard { showGuide = true }
        }
    }

    // MARK: per-frame state (main thread)

    private func handleFrame(box: CGRect?) {
        frameCount += 1
        if recordingStarted != nil {
            recFrames += 1
            if box != nil { recTargetFrames += 1 }
            if let bpm = heart.bpm {
                recHRRange = recHRRange.map { min($0.lowerBound, bpm)...max($0.upperBound, bpm) } ?? bpm...bpm
            }
            let swept = min(recSwept.lowerBound, pan.angle)...max(recSwept.upperBound, pan.angle)
            if swept != recSwept { recSwept = swept }
        }
        guard let box = box else {
            if subjectBox != nil {   // just lost the target
                lostFlashUntil = Date().addingTimeInterval(2.5)
                reacquireBox = subjectBox
                reacquireUntil = Date().addingTimeInterval(3.0)
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
            subjectBox = nil
            // auto-reacquire: prefer the detected player nearest the last known
            // spot; fall back to a widened blind reseed
            if let lost = reacquireBox, Date() < reacquireUntil, frameCount % 10 == 0 {
                let near = players.min(by: {
                    hypot($0.midX - lost.midX, $0.midY - lost.midY) <
                    hypot($1.midX - lost.midX, $1.midY - lost.midY)
                })
                if let near, hypot(near.midX - lost.midX, near.midY - lost.midY) < 0.3 {
                    tracker.select(roi: near)
                } else {
                    tracker.select(roi: lost.insetBy(dx: -lost.width * 0.35, dy: -lost.height * 0.35))
                }
            }
            return
        }
        if subjectBox == nil, reacquireBox != nil {   // reacquired
            reacquireBox = nil
            lostFlashUntil = nil
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
        subjectBox = box
        pan.update(centerX: box.midX)
        // Written only when it grows: a state write per frame re-renders the
        // wedge thirty times a second for a range that has not moved.
        let swept = min(sweptRange.lowerBound, pan.angle)...max(sweptRange.upperBound, pan.angle)
        if swept != sweptRange { sweptRange = swept }
    }

    // MARK: top status strip: pod, heart rate, lock, timecode

    private var statusStrip: some View {
        HStack(spacing: 4) {
            symbolButton(pan.connected ? "antenna.radiowaves.left.and.right"
                                       : "antenna.radiowaves.left.and.right.slash",
                         on: pan.connected,
                         label: pan.connected ? "Pod, connected" : "Pod, not connected") {
                pan.connect(host: bridgeHost)
            }
            // Tap starts the strap search; tap again to stop it.
            symbolButton(heart.bpm != nil ? "heart.fill" : "heart",
                         on: heart.bpm != nil,
                         dimmed: !heart.scanning && heart.bpm == nil,
                         label: heart.bpm.map { "Heart rate, \($0) beats per minute" }
                             ?? (heart.scanning ? "Heart rate, searching" : "Heart rate, off")) {
                if heart.isActive { heart.stop() } else { heart.startScan() }
            }
            // The live pulse is information, so it stays on screen.
            if let bpm = heart.bpm {
                Text("\(bpm)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
            Spacer()
            if tracker.isTracking {
                Button {
                    tracker.clear()
                    subjectBox = nil
                    lostFlashUntil = nil
                    sweptRange = 90...90
                    pan.recenter()
                } label: {
                    Text("Unlock")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.pla)
                        .padding(.horizontal, 16).frame(height: 38)
                        .glass(19)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    /// One white SF Symbol with a 44 pt target, like the Camera app's top row.
    /// State shows only in the symbol itself and a green dot when connected.
    private func symbolButton(_ symbol: String, on: Bool, dimmed: Bool = true,
                              label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(on || !dimmed ? Color.white : Color.white.opacity(0.6))
                .overlay(alignment: .topTrailing) {
                    if on {
                        Circle().fill(Color.green)
                            .frame(width: 7, height: 7)
                            .offset(x: 5, y: -3)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: bottom bar — record + target state

    private var bottomBar: some View {
        HStack(spacing: 0) {
            // Left: the newest game, like the Camera app's last photo.
            // Right stays empty for balance: there is no second function yet.
            Group {
                if let game = lastGame, !camera.isRecording {
                    Button { showingLastGame = true } label: {
                        // Like the Camera app's last-photo thumbnail: the two
                        // teams of the newest game.
                        ZStack {
                            TeamBadge(team: game.away, size: 30).offset(x: 7, y: 7)
                            TeamBadge(team: game.home, size: 30).offset(x: -7, y: -7)
                        }
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Last game, \(game.home.name) vs \(game.away.name)")
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            RecordButton(isRecording: camera.isRecording) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                if camera.isRecording {
                    stopGame()
                } else if showGuide {
                    // One sheet at a time: the guide steps aside for the setup.
                    showGuide = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { settingUpGame = true }
                } else {
                    // Teams first, so the game is named before the first frame.
                    settingUpGame = true
                }
            }
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        .padding(.bottom, 20)
        .animation(.easeOut(duration: 0.2), value: lastGame?.id)
        .animation(.easeOut(duration: 0.2), value: camera.isRecording)
        .sheet(isPresented: $showingLastGame) {
            if let game = lastGame {
                NavigationStack {
                    GameDetailView(game: game)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingLastGame = false }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $settingUpGame) {
            GameSetupView(start: {
                settingUpGame = false
                startGame()
            }, cancel: { settingUpGame = false })
        }
    }

    private func startGame() {
        recFrames = 0
        recTargetFrames = 0
        recHRRange = nil
        recSwept = pan.angle...pan.angle
        heart.beginLog()
        camera.startRecording()
        recordingStarted = Date()
    }

    private func stopGame() {
        camera.stopRecording()
        heart.endLog(stamp: Int(Date().timeIntervalSince1970))
        if let started = recordingStarted {
            let duration = Date().timeIntervalSince(started)
            summary = SessionSummary(
                duration: duration,
                coverageDeg: recSwept.upperBound - recSwept.lowerBound,
                targetHeld: recFrames > 0 ? Double(recTargetFrames) / Double(recFrames) : 0,
                hr: recHRRange)
            // Keep the game with whatever the Mac counted, for Account later.
            let game = GameRecord(date: started, home: TeamStore.home, away: TeamStore.away,
                                  duration: duration)
            Task {
                var done = game
                done.final = await MacEndpoint(host: bridgeHost).currentState()
                GameStore.add(done)
                await MainActor.run { refreshLastGame() }
            }
        }
        recordingStarted = nil
    }

    private func refreshLastGame() {
        lastGame = GameStore.load().max(by: { $0.date < $1.date })
    }

}

// MARK: - session summary after each recording

struct SessionSummary: Identifiable {
    let id = UUID()
    let duration: TimeInterval
    let coverageDeg: Double     // swept range while recording
    let targetHeld: Double      // 0...1 share of frames with a locked target
    let hr: ClosedRange<Int>?
}

struct SummaryCard: View {
    let summary: SessionSummary
    @ObservedObject var camera: CameraManager
    @Environment(\.dismiss) private var dismiss

    /// Tells the truth about the save, which finishes a moment after the
    /// sheet appears: saving, saved, or why not.
    @ViewBuilder private var saveStatus: some View {
        switch camera.saveState {
        case .idle, .saving:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Saving to Photos")
            }
            .foregroundStyle(.secondary)
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .failed(let reason):
            Label("Not saved: \(reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    stat(String(format: "%d:%02d", Int(summary.duration) / 60,
                                Int(summary.duration) % 60), "Filmed")
                    stat("\(Int(summary.coverageDeg))°", "Panned")
                    stat("\(Int(summary.targetHeld * 100))%", "On target")
                }
                if let hr = summary.hr {
                    Label("\(hr.lowerBound) to \(hr.upperBound) bpm", systemImage: "heart.fill")
                        .monospacedDigit()
                }
                saveStatus
                    .font(.subheadline)
                    .animation(.default, value: camera.saveState)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle("Game Recorded")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        // Opaque, so the shutter does not glow through the glass.
        .presentationBackground(Color(.secondarySystemBackground))
    }
}

// MARK: - first-launch setup guide (doubles as the demo script)

/// A short sheet that leaves the viewfinder usable: each step ticks off
/// as it happens.
struct SetupGuide: View {
    let rigLinked: Bool
    let targetSet: Bool
    let recording: Bool
    let dismiss: () -> Void

    private func step(_ n: Int, _ text: String, done: Bool) -> some View {
        Label {
            Text(text)
                .foregroundStyle(done ? .secondary : .primary)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "\(n).circle")
                .font(.title2)
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        NavigationStack {
            List {
                step(1, "Tap Pod to link the rig", done: rigLinked)
                step(2, "Tap the player to follow", done: targetSet)
                step(3, "Hit record", done: recording)
            }
            .listStyle(.insetGrouped)
            .scrollDisabled(true)
            .navigationTitle("Ready in Three")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
        .presentationDetents([.height(300)])
        .presentationBackgroundInteraction(.enabled)
    }
}

// MARK: - horizon: one hairline that tilts with the phone, a dot for the pan

/// Replaces the 40-140 ruler, the bubble level and the coverage wedge.
/// The line rotates with the roll and brightens when the tripod is level;
/// the dot slides with the servo angle. No numbers on the picture.
struct Horizon: View {
    let angle: Double   // servo 40...140
    let roll: Double
    let isLevel: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                Capsule()
                    .fill(Color.white.opacity(isLevel ? 0.75 : 0.3))
                    .frame(width: w, height: 1.5)
                Circle()
                    .fill(Color.white)
                    .frame(width: 9, height: 9)
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .offset(x: CGFloat((angle - 90) / 50) * (w / 2))
            }
            .frame(width: w, height: geo.size.height)
            .rotationEffect(.degrees(-roll))
            .animation(.linear(duration: 0.1), value: roll)
            .animation(.linear(duration: 0.08), value: angle)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - floor rings: a soft ellipse at every player's feet (tap one to lock)

private func feet(_ box: CGRect, in size: CGSize) -> (center: CGPoint, width: CGFloat) {
    // Vision boxes are normalized with the origin bottom-left: minY is the feet.
    let w = box.width * size.width * 1.15
    return (CGPoint(x: box.midX * size.width, y: (1 - box.minY) * size.height), w)
}

struct FloorRings: View {
    let players: [CGRect]
    let locked: CGRect?

    var body: some View {
        GeometryReader { geo in
            ForEach(Array(players.enumerated()), id: \.offset) { _, box in
                if locked.map({ hypot($0.midX - box.midX, $0.midY - box.midY) > 0.06 }) ?? true {
                    let f = feet(box, in: geo.size)
                    Ellipse()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .background(Ellipse().fill(Color.white.opacity(0.08)))
                        .frame(width: f.width, height: f.width * 0.3)
                        .position(f.center)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: players)
    }
}

// MARK: - lock ring: the followed player gets an orange ring and a marker

struct LockRing: View {
    let box: CGRect
    @State private var pulse = false

    var body: some View {
        GeometryReader { geo in
            let f = feet(box, in: geo.size)
            let head = CGPoint(x: box.midX * geo.size.width, y: (1 - box.maxY) * geo.size.height)
            ZStack {
                Ellipse()
                    .stroke(Color.pla.opacity(pulse ? 0 : 0.6), lineWidth: 2)
                    .frame(width: f.width * (pulse ? 1.5 : 1), height: f.width * 0.3 * (pulse ? 1.5 : 1))
                    .position(f.center)
                Ellipse()
                    .stroke(Color.pla, lineWidth: 3)
                    .background(Ellipse().fill(Color.pla.opacity(0.18)))
                    .frame(width: f.width, height: f.width * 0.3)
                    .position(f.center)
                Triangle()
                    .fill(Color.pla)
                    .frame(width: 14, height: 10)
                    .position(x: head.x, y: head.y - 14)
            }
            .animation(.easeOut(duration: 0.12), value: box)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) { pulse = true }
        }
    }
}

struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - shutter like Apple Camera's video mode: red disc becomes a square

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)
                RoundedRectangle(cornerRadius: isRecording ? 7 : 32, style: .continuous)
                    .fill(Color(.systemRed))
                    .frame(width: isRecording ? 30 : 64,
                           height: isRecording ? 30 : 64)
            }
            .contentShape(Circle())
            .animation(.spring(duration: 0.3), value: isRecording)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
    }
}

// MARK: - live timecode while recording, red like Apple Camera

struct TimecodeView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let s = Int(context.date.timeIntervalSince(since))
            Text(String(format: "%02d:%02d:%02d", s / 3600, s / 60 % 60, s % 60))
                .font(.system(size: 17, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

/// UIKit wrapper for the AVCaptureVideoPreviewLayer. The host view re-frames
/// the layer in layoutSubviews — updateUIView does NOT run on layout, which
/// left the preview at zero size (black screen) before.
final class PreviewHostView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let l = previewLayer {
                layer.addSublayer(l)
                setNeedsLayout()
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}

struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer = layer
        return view
    }

    func updateUIView(_ view: PreviewHostView, context: Context) {
        if view.previewLayer !== layer { view.previewLayer = layer }
    }
}
