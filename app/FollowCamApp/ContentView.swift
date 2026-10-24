import AVFoundation
import SwiftUI

// Viewfinder chrome: broadcast-camera vocabulary — tally lamps, a graduated
// pan scale with a live needle, monospaced telemetry, AF-corner target box.
// Orange = the printed parts' PLA; blue = servo; red = REC only.

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
    @AppStorage("didOnboard") private var didOnboard = false

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

            VStack(spacing: 14) {
                statusStrip
                Horizon(angle: pan.angle, roll: level.rollDegrees, isLevel: level.isLevel)
                    .frame(width: 150, height: 14)
                Spacer()
                if let until = lostFlashUntil, until > Date() {
                    Text("Lost them. Tap a player.")
                        .font(.text(15, 600))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .glass(22)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                bottomBar
            }
            .animation(.easeOut(duration: 0.2), value: lostFlashUntil)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $summary) { s in SummaryCard(summary: s, camera: camera) }
        .overlay {
            if showGuide {
                SetupGuide(rigLinked: pan.connected,
                           targetSet: tracker.isTracking,
                           recording: camera.isRecording) {
                    showGuide = false
                    didOnboard = true
                }
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
        HStack(spacing: 8) {
            chip("Pod", on: pan.connected) { pan.connect(host: bridgeHost) }
            // Tap starts the strap search; tap again to stop it.
            chip(heart.bpm.map { "\($0) bpm" } ?? (heart.scanning ? "Searching" : "Heart"),
                 on: heart.bpm != nil, pending: heart.scanning) {
                if heart.isActive { heart.stop() } else { heart.startScan() }
            }
            if tracker.isTracking {
                Button {
                    tracker.clear()
                    subjectBox = nil
                    lostFlashUntil = nil
                    sweptRange = 90...90
                    pan.recenter()
                } label: {
                    Text("Unlock")
                        .font(.text(14, 650))
                        .foregroundColor(.pla)
                        .padding(.horizontal, 14).frame(height: 36)
                        .glass(18)
                }
                .buttonStyle(PressScale())
            }
            Spacer()
            if let started = recordingStarted {
                TimecodeView(since: started)
                    .padding(.horizontal, 14).frame(height: 36)
                    .glass(18)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func chip(_ label: String, on: Bool, pending: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(on ? Color.green : (pending ? Color.white : Color(white: 0.35)))
                    .frame(width: 7, height: 7)
                    .opacity(pending ? 0.6 : 1)
                Text(label).font(.text(14, 650)).foregroundColor(on ? .white : .muted)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .glass(18)
        }
        .buttonStyle(PressScale())
    }

    // MARK: bottom bar — record + target state

    private var bottomBar: some View {
        ZStack {
            RecordButton(isRecording: camera.isRecording) {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                if camera.isRecording {
                    camera.stopRecording()
                    heart.endLog(stamp: Int(Date().timeIntervalSince1970))
                    if let started = recordingStarted {
                        summary = SessionSummary(
                            duration: Date().timeIntervalSince(started),
                            coverageDeg: recSwept.upperBound - recSwept.lowerBound,
                            targetHeld: recFrames > 0 ? Double(recTargetFrames) / Double(recFrames) : 0,
                            hr: recHRRange)
                    }
                    recordingStarted = nil
                } else {
                    recFrames = 0
                    recTargetFrames = 0
                    recHRRange = nil
                    recSwept = pan.angle...pan.angle
                    heart.beginLog()
                    camera.startRecording()
                    recordingStarted = Date()
                }
            }
        }
        .padding(.bottom, 30)
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

    /// The headline tells the truth about the save, which finishes a moment
    /// after the sheet appears: saving, saved, or why not.
    private var headline: (String, Color) {
        switch camera.saveState {
        case .idle, .saving: return ("Saving to Photos", .muted)
        case .saved: return ("Saved to Photos", .white)
        case .failed(let reason): return ("Not saved: \(reason)", .red)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.wide(30, 850)).foregroundColor(.white).monospacedDigit()
            Text(label).font(.text(14, 500)).foregroundColor(.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(headline.0)
                .font(.text(17, 650))
                .foregroundColor(headline.1)
                .animation(.default, value: camera.saveState)
            HStack(alignment: .top) {
                stat(String(format: "%d:%02d", Int(summary.duration) / 60,
                            Int(summary.duration) % 60), "filmed")
                stat("\(Int(summary.coverageDeg))°", "panned")
                stat("\(Int(summary.targetHeld * 100))%", "on target")
            }
            if let hr = summary.hr {
                Text("\(hr.lowerBound) to \(hr.upperBound) bpm")
                    .font(.text(16, 600))
                    .foregroundColor(.red)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surface)
        .presentationDetents([.height(250)])
    }
}

// MARK: - first-launch setup guide (doubles as the demo script)

struct SetupGuide: View {
    let rigLinked: Bool
    let targetSet: Bool
    let recording: Bool
    let dismiss: () -> Void

    private func step(_ n: Int, _ text: String, done: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(done ? "✓" : "\(n)")
                .font(.wide(18, 850))
                .foregroundColor(done ? .green : .muted)
                .frame(width: 22, alignment: .leading)
            Text(text)
                .font(.text(17, 550))
                .foregroundColor(done ? .white : Color(white: 0.8))
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Ready in three")
                .font(.wide(24, 850))
                .foregroundColor(.white)
            step(1, "Tap Pod to link the rig", done: rigLinked)
            step(2, "Tap the player to follow", done: targetSet)
            step(3, "Hit record", done: recording)
            PrimaryButton(title: rigLinked && targetSet && recording ? "Rolling" : "Got it", action: dismiss)
                .padding(.top, 6)
        }
        .padding(24)
        .glass(28)
        .padding(20)
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
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
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

// MARK: - camera-idiom record button: red core morphs to a square

struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .stroke(.white, lineWidth: 3.5)
                    .frame(width: 66, height: 66)
                RoundedRectangle(cornerRadius: isRecording ? 6 : 27)
                    .fill(.red)
                    .frame(width: isRecording ? 30 : 54,
                           height: isRecording ? 30 : 54)
            }
            .animation(.spring(duration: 0.25), value: isRecording)
        }
    }
}

// MARK: - live timecode while recording

struct TimecodeView: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let s = Int(context.date.timeIntervalSince(since))
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                    .opacity(s % 2 == 0 ? 1 : 0.35)
                Text(String(format: "%02d:%02d", s / 60, s % 60))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
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
