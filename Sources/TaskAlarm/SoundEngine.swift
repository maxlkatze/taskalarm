import AVFoundation
import AppKit

/// All sounds are synthesized at runtime: no audio files to ship, and every
/// sound shares the same soft, bell-like character.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    enum Sound: CaseIterable {
        case chime      // a task is due: cheerful rising arpeggio
        case nudge      // gentle repeat while waiting for you
        case alarm      // missed / overdue: insistent ding-dong
        case success    // task done
        case allDone    // the last task is done: tiny fanfare
        case snooze     // sleepy descending notes
        case add        // task added: bubbly pop
        case checkIn    // "hey!"
        case headsUp    // soft "coming up" sparkle
        case tick       // haptic-like click
        case tock       // softer, lower click (undo, uncheck)
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let sampleRate = 44_100.0
    private let format: AVAudioFormat
    private var cache: [Sound: AVAudioPCMBuffer] = [:]
    private var idleStop: DispatchWorkItem?

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        for _ in 0..<4 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            // Output device changed (e.g. headphones plugged in): stop now, restart lazily on next sound.
            MainActor.assumeIsolated { self?.engine.stop() }
        }
    }

    func play(_ sound: Sound, volumeScale: Double = 1) {
        let prefs = Prefs.shared
        guard prefs.soundsEnabled else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        let buffer = cache[sound] ?? render(sound)
        cache[sound] = buffer

        let player = players[next]
        next = (next + 1) % players.count
        player.stop()
        player.volume = Float(prefs.volume * volumeScale)
        player.scheduleBuffer(buffer, at: nil, options: [])
        player.play()

        // Let the audio hardware sleep again when we're quiet.
        idleStop?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.engine.stop() }
        }
        idleStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: - Synthesis

    private enum Wave { case bell, soft, pulse, click }

    private struct Note {
        var freq: Double
        var start: Double
        var length: Double
        var amp: Double
        var wave: Wave = .bell
        var glideTo: Double? = nil
    }

    // Note frequencies: kept mostly in the C4–C6 range so nothing gets piercing.
    private static let C4 = 261.63, E4 = 329.63, G4 = 392.0, A4 = 440.0
    private static let C5 = 523.25, D5 = 587.33, E5 = 659.25, G5 = 783.99, A5 = 880.0
    private static let C6 = 1046.5

    private func notes(for sound: Sound) -> (notes: [Note], length: Double) {
        typealias S = SoundEngine
        switch sound {
        case .chime:
            return ([
                Note(freq: S.C5, start: 0.00, length: 1.0, amp: 0.30),
                Note(freq: S.E5, start: 0.11, length: 1.0, amp: 0.27),
                Note(freq: S.G5, start: 0.22, length: 1.0, amp: 0.24),
                Note(freq: S.C6, start: 0.33, length: 1.2, amp: 0.18),
                Note(freq: S.C4, start: 0.33, length: 1.2, amp: 0.14, wave: .soft),
            ], 1.7)
        case .nudge:
            return ([
                Note(freq: S.E5, start: 0.00, length: 0.7, amp: 0.26),
                Note(freq: S.C5, start: 0.18, length: 0.9, amp: 0.26),
            ], 1.2)
        case .alarm:
            // Insistent "ding-dong" pairs: clearly an alert, but round instead of piercing.
            var list: [Note] = []
            for i in 0..<3 {
                let t = Double(i) * 0.5
                list.append(Note(freq: S.E5, start: t, length: 0.45, amp: 0.30, wave: .pulse))
                list.append(Note(freq: S.C5, start: t + 0.2, length: 0.55, amp: 0.30, wave: .pulse))
            }
            return (list, 1.9)
        case .success:
            return ([
                Note(freq: S.G4, start: 0.00, length: 0.6, amp: 0.26),
                Note(freq: S.C5, start: 0.08, length: 0.7, amp: 0.26),
                Note(freq: S.E5, start: 0.16, length: 1.0, amp: 0.24),
                Note(freq: S.C6, start: 0.26, length: 0.8, amp: 0.07, wave: .soft),
            ], 1.4)
        case .allDone:
            return ([
                Note(freq: S.C5, start: 0.00, length: 0.45, amp: 0.24),
                Note(freq: S.E5, start: 0.10, length: 0.45, amp: 0.24),
                Note(freq: S.G5, start: 0.20, length: 0.45, amp: 0.22),
                Note(freq: S.C4, start: 0.38, length: 1.4, amp: 0.18, wave: .soft),
                Note(freq: S.C5, start: 0.38, length: 1.4, amp: 0.18),
                Note(freq: S.E5, start: 0.38, length: 1.4, amp: 0.16),
                Note(freq: S.G5, start: 0.38, length: 1.4, amp: 0.14),
            ], 2.0)
        case .snooze:
            return ([
                Note(freq: S.G4, start: 0.00, length: 0.5, amp: 0.26, wave: .soft),
                Note(freq: S.E4, start: 0.15, length: 0.5, amp: 0.26, wave: .soft),
                Note(freq: S.C4, start: 0.30, length: 0.8, amp: 0.26, wave: .soft),
            ], 1.2)
        case .add:
            return ([
                Note(freq: 330, start: 0, length: 0.12, amp: 0.28, wave: .soft, glideTo: 700),
                Note(freq: S.A5, start: 0.08, length: 0.35, amp: 0.06),
            ], 0.5)
        case .checkIn:
            return ([
                Note(freq: S.D5, start: 0.00, length: 0.5, amp: 0.26),
                Note(freq: S.A5, start: 0.15, length: 0.9, amp: 0.20),
            ], 1.2)
        case .headsUp:
            return ([
                Note(freq: S.G4, start: 0.00, length: 0.6, amp: 0.20, wave: .soft),
                Note(freq: S.D5, start: 0.12, length: 0.8, amp: 0.20),
                Note(freq: S.G5, start: 0.24, length: 0.9, amp: 0.12),
            ], 1.3)
        case .tick:
            return ([Note(freq: 1050, start: 0, length: 0.03, amp: 0.16, wave: .click)], 0.05)
        case .tock:
            return ([Note(freq: 480, start: 0, length: 0.05, amp: 0.20, wave: .click)], 0.07)
        }
    }

    private func render(_ sound: Sound) -> AVAudioPCMBuffer {
        let (list, length) = notes(for: sound)
        let frames = Int(length * sampleRate)
        var mix = [Double](repeating: 0, count: frames)

        for n in list {
            let start = Int(n.start * sampleRate)
            let count = Int(n.length * sampleRate)
            var phase = 0.0
            var detuned = 0.0
            for i in 0..<count {
                let idx = start + i
                guard idx < frames else { break }
                let t = Double(i) / sampleRate
                let progress = t / n.length
                let f = n.glideTo.map { n.freq + ($0 - n.freq) * progress } ?? n.freq
                phase += 2 * .pi * f / sampleRate
                detuned += 2 * .pi * f * 1.0025 / sampleRate

                // Softer attack than a pluck so notes bloom instead of snapping.
                let attackTime = n.wave == .click ? 0.002 : 0.012
                let attack = min(1, t / attackTime)
                let release = min(1, (n.length - t) / 0.06)
                var v: Double
                switch n.wave {
                case .bell:
                    // Warm, vibraphone-like: a gently beating fundamental plus a quick octave shimmer.
                    v = 0.55 * sin(phase) + 0.45 * sin(detuned) + 0.12 * sin(2 * phase) * exp(-t * 12)
                    v *= exp(-t * 3.2)
                case .soft:
                    v = sin(phase) * exp(-t * 3.0)
                case .pulse:
                    v = (0.6 * sin(phase) + 0.4 * sin(detuned) + 0.08 * sin(2 * phase)) * exp(-t * 3.5)
                case .click:
                    v = sin(phase) * exp(-t * 110)
                }
                mix[idx] += v * max(0, attack) * max(0, release) * n.amp
            }
        }

        // Gentle low-pass (~2.8 kHz) to take the edge off any remaining brightness.
        let rc = 1 / (2 * Double.pi * 2800)
        let alpha = (1 / sampleRate) / (rc + 1 / sampleRate)
        var lp = 0.0
        for i in 0..<frames {
            lp += alpha * (mix[i] - lp)
            mix[i] = lp
        }

        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for i in 0..<frames {
            let s = Float(tanh(mix[i])) // gentle limiter
            left[i] = s
            right[i] = s
        }
        return buffer
    }
}

/// Trackpad haptics (on Force Touch trackpads) plus an optional soft click so the
/// feedback is felt *and* heard on every Mac.
@MainActor
enum Haptics {
    static func tap(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic, sound: SoundEngine.Sound? = .tick) {
        let prefs = Prefs.shared
        if prefs.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
        }
        if prefs.clickSounds, let sound {
            SoundEngine.shared.play(sound, volumeScale: 0.8)
        }
    }

    /// A short "buzz" made of several haptic pulses, used for alarms.
    static func buzz() {
        guard Prefs.shared.hapticsEnabled else { return }
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.09) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }
}
