import Foundation
import UIKit

// Client side of the contract in docs/BROADCAST.md: MJPEG on :8501/stream and
// a once-a-second poll of :8501/state.json. Only schema 1 exists today;
// anything else is refused rather than half-read.

struct MacEndpoint {
    let host: String

    private var base: URL? { URL(string: "http://\(host.trimmingCharacters(in: .whitespaces)):8501") }
    var streamURL: URL? { base?.appendingPathComponent("stream") }
    var stateURL: URL? { base?.appendingPathComponent("state.json") }

    func isReachable() async -> Bool {
        guard let url = stateURL else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }
}

// MARK: - state.json, schema 1

struct GameState: Decodable, Equatable {
    let schema: Int
    let t: Double
    let period: Int
    let clock: String
    let teams: [Team]
    let players: [Player]
    let lastEvent: GameEvent?
    let panDeg: Int?
    let camera: String

    struct Team: Decodable, Equatable, Identifiable {
        let id: Int
        let name: String
        let color: String
        let score: Int
        let fga: Int
        let fgm: Int
        let fgPct: Double?
    }

    struct Player: Decodable, Equatable, Identifiable {
        let key: String
        let number: Int?
        let team: Int          // -1 = not assigned yet
        let pts: Int
        let fga: Int
        let fgm: Int
        var id: String { key }
        /// Tracker noise: no team and no shot yet. Kept out of the box score.
        var isWorthShowing: Bool { team != -1 || fga > 0 }
    }

    struct GameEvent: Decodable, Equatable {
        let t: Double
        let type: String       // "made" | "miss" | "manual"
        let team: Int
        let playerKey: String?
        let points: Int
    }
}

@MainActor
final class LiveFeed: ObservableObject {
    enum Link: Equatable { case off, connecting, live, lost, badSchema }

    @Published private(set) var link: Link = .off
    @Published private(set) var state: GameState?
    @Published private(set) var frame: UIImage?

    private var pollTask: Task<Void, Never>?
    private let mjpeg = MJPEGReader()
    private var lastT: Double?
    private var lastTChange = Date()

    func start(host: String) {
        stop()
        let endpoint = MacEndpoint(host: host)
        link = .connecting
        if let url = endpoint.streamURL {
            mjpeg.onFrame = { [weak self] image in
                let video = Self.videoPart(of: image)
                Task { @MainActor in self?.frame = video }
            }
            mjpeg.start(url: url)
        }
        guard let stateURL = endpoint.stateURL else { link = .lost; return }
        pollTask = Task { [weak self] in
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            while !Task.isCancelled {
                await self?.poll(stateURL, decoder: decoder)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The Mac sends the 16:9 video with the minimap beside it (1920x720).
    /// The app wants the picture only; anything much wider than 16:9 is
    /// cut back to its left 16:9. Goes away once the Mac offers a video-only
    /// stream.
    nonisolated static func videoPart(of image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        guard w / h > 2.2, let cut = cg.cropping(to: CGRect(x: 0, y: 0, width: h * 16 / 9, height: h)) else {
            return image
        }
        return UIImage(cgImage: cut)
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        mjpeg.stop()
        link = .off
        frame = nil
    }

    private func poll(_ url: URL, decoder: JSONDecoder) async {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            if link != .connecting { link = .lost }
            return
        }
        // Read the schema first so a newer server never gets misparsed.
        struct Probe: Decodable { let schema: Int }
        guard let probe = try? decoder.decode(Probe.self, from: data), probe.schema == 1 else {
            link = .badSchema
            return
        }
        guard let next = try? decoder.decode(GameState.self, from: data) else { return }
        if next.t != lastT {
            lastT = next.t
            lastTChange = Date()
        }
        // The contract: t frozen for more than 5 s means the signal is gone.
        link = Date().timeIntervalSince(lastTChange) > 5 ? .lost : .live
        if next != state { state = next }
    }
}

// MARK: - MJPEG (multipart/x-mixed-replace) reader

/// Splits the byte stream on JPEG start/end markers instead of parsing the
/// multipart headers: boundaries differ between servers, the markers do not.
final class MJPEGReader: NSObject, URLSessionDataDelegate {
    var onFrame: ((UIImage) -> Void)?
    private var session: URLSession?
    private var buffer = Data()
    private static let soi = Data([0xFF, 0xD8])
    private static let eoi = Data([0xFF, 0xD9])

    func start(url: URL) {
        stop()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        session.dataTask(with: url).resume()
    }

    func stop() {
        session?.invalidateAndCancel()
        session = nil
        buffer.removeAll()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        while let start = buffer.range(of: Self.soi),
              let end = buffer.range(of: Self.eoi, in: start.upperBound..<buffer.endIndex) {
            let jpeg = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            if let image = UIImage(data: jpeg) { onFrame?(image) }
        }
        // A broken stream without an end marker must not grow forever.
        if buffer.count > 4_000_000 { buffer.removeAll() }
    }
}
