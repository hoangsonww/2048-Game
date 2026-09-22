import Foundation
import AVFoundation

/// Short procedural cues for the iOS client.
///
/// Generated sine bursts through `AVAudioEngine`, so there are no bundled
/// audio files to keep in sync with the other clients. The session is
/// `.ambient`, so the hardware mute switch and other apps' audio both take
/// priority — a 2048 chime should never interrupt a podcast.
///
/// The player *pool* is the important part. `AVAudioPlayerNode` is a queue:
/// buffers scheduled on one node play strictly one after another, so a single
/// node turns a fast run of moves into a backlog that drains long after the
/// moves that caused it. Each cue therefore goes to the next node in a small
/// ring and interrupts whatever that node was doing, which makes cues overlap
/// the way they should and bounds the backlog at the size of the ring.
@MainActor
final class GameSounds: ObservableObject {
    static let shared = GameSounds()

    /// Cues able to sound at once. Past this, the oldest is cut off rather
    /// than the newest being made to wait.
    static let voiceCount = 8
    static let sampleRate = 44_100.0

    private let defaults: UserDefaults
    private let key = "game2048SoundEnabledV1"
    private let engine = AVAudioEngine()
    private let players: [AVAudioPlayerNode]
    private var nextVoice = 0
    private var started = false
    /// Rendered buffers, keyed by the cue that produced them. A player holding
    /// an arrow key would otherwise resynthesise the same few thousand samples
    /// on the main actor several times a second.
    private var cache: [Tone: AVAudioPCMBuffer] = [:]

    @Published private(set) var isEnabled: Bool

    /// The parameters that fully determine a rendered cue.
    struct Tone: Hashable {
        let frequency: Double
        let duration: Double
        let volume: Float
        let slideTo: Double?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: key) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: key)
        }
        players = (0..<Self.voiceCount).map { _ in AVAudioPlayerNode() }
        let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)
        for player in players {
            engine.attach(player)
            if let format {
                engine.connect(player, to: engine.mainMixerNode, format: format)
            }
        }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: key)
        if enabled { ensureRunning() }
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    func move() { blip(frequency: 420, duration: 0.05, volume: 0.18) }
    func merge(points: Int = 4) {
        let base = 520 + min(400, log2(Double(max(4, points))) * 55)
        blip(frequency: base, duration: 0.09, volume: 0.28)
        blip(frequency: base * 1.5, duration: 0.07, volume: 0.14, delay: 0.02)
    }
    func undo() { blip(frequency: 360, duration: 0.07, volume: 0.2, slideTo: 240) }
    func newGame() {
        blip(frequency: 480, duration: 0.06, volume: 0.22)
        blip(frequency: 640, duration: 0.08, volume: 0.18, delay: 0.07)
    }
    func win() {
        [523.0, 659.0, 784.0, 1046.0].enumerated().forEach { index, frequency in
            blip(frequency: frequency, duration: 0.14, volume: 0.26, delay: Double(index) * 0.09)
        }
    }
    func gameOver() {
        blip(frequency: 280, duration: 0.18, volume: 0.22, slideTo: 140)
        blip(frequency: 180, duration: 0.22, volume: 0.16, delay: 0.1, slideTo: 90)
    }
    func invalid() { blip(frequency: 160, duration: 0.04, volume: 0.1) }

    private func ensureRunning() {
        guard !started else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            try engine.start()
            for player in players { player.play() }
            started = true
        } catch {
            started = false
        }
    }

    private func blip(frequency: Double, duration: Double, volume: Float, delay: Double = 0, slideTo: Double? = nil) {
        guard isEnabled else { return }
        let tone = Tone(frequency: frequency, duration: duration, volume: volume, slideTo: slideTo)
        guard delay > 0 else {
            play(tone)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // Mute between the cue and its own second note is still mute.
            guard let self, self.isEnabled else { return }
            self.play(tone)
        }
    }

    private func play(_ tone: Tone) {
        ensureRunning()
        guard started, let buffer = buffer(for: tone) else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        // `.interrupts` is what keeps this a mixer rather than a queue: the
        // node drops whatever it was holding and starts now.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    private func buffer(for tone: Tone) -> AVAudioPCMBuffer? {
        if let cached = cache[tone] { return cached }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else { return nil }
        let samples = Self.render(tone, sampleRate: Self.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for index in samples.indices { channel[index] = samples[index] }
        cache[tone] = buffer
        return buffer
    }

    /// The cue as raw samples.
    ///
    /// Pure and `nonisolated` so the envelope and the frequency slide are
    /// testable without an audio device — the same reason the rules engine
    /// takes an injected tile generator. See ARCHITECTURE.md,
    /// "Determinism seams".
    nonisolated static func render(_ tone: Tone, sampleRate: Double) -> [Float] {
        let frameCount = max(1, Int(tone.duration * sampleRate))
        var samples = [Float](repeating: 0, count: frameCount)
        let twoPi = 2.0 * Double.pi
        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let progress = Double(index) / Double(frameCount)
            let frequency = tone.slideTo.map { tone.frequency + ($0 - tone.frequency) * progress } ?? tone.frequency
            let envelope = Float(sin(min(1, progress * Double.pi)))
            samples[index] = sin(Float(twoPi * frequency * t)) * tone.volume * envelope * 0.35
        }
        return samples
    }
}

// MARK: - Focused maintainer notes (documentation only)
//
// Sound-engine maintenance guide
//
// These notes describe the existing contract. They intentionally add no declarations,
// expressions, fixtures, branches, or runtime behavior.
//
// Review guardrails
//
// 01. A cue is played immediately or dropped; never queue stale gameplay feedback.
//
// 02. Keep the voice pool bounded so rapid moves cannot create unbounded audio work.
//
// 03. Honor mute state before opening or scheduling work on the audio engine.
//
// 04. Maintain short, distinct envelopes for movement, merge, undo, win, and game-over feedback.
//
// 05. Treat audio-session interruption as recoverable and avoid changing game state from sound
//     callbacks.
//
// 06. Keep generated tones deterministic enough for buffer-shape unit tests.
//
// 07. Do not add bundled audio assets unless product direction explicitly changes.
//
// 08. Preserve main-actor ownership for UI-observable sound preference state.
//
// Symbol and scenario index
//
// 01. `final class GameSounds: ObservableObject`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 02. `struct Tone: Hashable`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 03. `init(defaults: UserDefaults = .standard)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 04. `func setEnabled(_ enabled: Bool)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 05. `func toggle()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 06. `func move() { blip(frequency: 420, duration: 0.05, volume: 0.18) }`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 07. `func merge(points: Int = 4)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 08. `func undo() { blip(frequency: 360, duration: 0.07, volume: 0.2, slideTo: 240) }`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 09. `func newGame()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 10. `func win()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 11. `func gameOver()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 12. `func invalid() { blip(frequency: 160, duration: 0.04, volume: 0.1) }`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 13. `private func ensureRunning()`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 14. `private func blip(frequency: Double, duration: Double, volume: Float, delay: Double = 0, slideTo: Double? = nil)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 15. `private func play(_ tone: Tone)`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
// 16. `private func buffer(for tone: Tone) -> AVAudioPCMBuffer?`
//     This entry points to an existing declaration or test scenario above; it is listed
//     here only to make the file's maintenance surface easier to scan during review.
//
