import Foundation
import AVFoundation
import CoreAudio
import NotchBuddyCore

/// In-memory synthesized audio player for avatar state changes and settings previews.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isEngineStarted = false
    private var gate = SoundGate()
    private var needsYouGate = SoundGate(interval: 10) // someone is waiting on you: don't make them wait a minute for the next chirp
    private var cache: [CacheKey: AVAudioPCMBuffer] = [:]

    private struct CacheKey: Hashable {
        let name: SoundName
        let pack: String
    }

    private init() {}

    /// Previews a sound directly. Always plays, ignores master toggle and gate.
    func preview(_ name: SoundName) {
        guard name != .off else { return }
        let pack = UserDefaults.standard.string(forKey: Prefs.soundPack) ?? "robot"
        let key = CacheKey(name: name, pack: pack)
        let buffer: AVAudioPCMBuffer
        if let cached = cache[key] {
            buffer = cached
        } else if let generated = synthesize(name: name, pack: pack) {
            cache[key] = generated
            buffer = generated
        } else {
            return
        }
        playBuffer(buffer)
    }

    /// Plays notification sound for an agent state if sounds are enabled, not muted, and allowed by SoundGate.
    func play(for state: AgentState) {
        guard UserDefaults.standard.bool(forKey: Prefs.soundsOn) else { return }
        let soundKey = Prefs.sound(for: state)
        let soundRaw = UserDefaults.standard.string(forKey: soundKey) ?? SoundName.default(for: state).rawValue
        guard let soundName = SoundName(rawValue: soundRaw), soundName != .off else { return }

        let muteWhenBusy = UserDefaults.standard.object(forKey: Prefs.muteWhenBusy) != nil
            ? UserDefaults.standard.bool(forKey: Prefs.muteWhenBusy)
            : true
        if muteWhenBusy && isInputDeviceInUse() {
            return
        }

        guard state == .needsYou ? needsYouGate.allow() : gate.allow() else { return }
        preview(soundName)
    }

    private func ensureEngineStarted() {
        guard !isEngineStarted else { return }
        engine.attach(playerNode)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100.0, channels: 1) else { return }
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            isEngineStarted = true
        } catch {
            NSLog("SoundPlayer: Failed to start AVAudioEngine: \(error)")
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        ensureEngineStarted()
        guard isEngineStarted else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        guard engine.isRunning else { return }

        let volDouble = UserDefaults.standard.object(forKey: Prefs.volume) != nil
            ? UserDefaults.standard.double(forKey: Prefs.volume)
            : 0.6
        playerNode.volume = max(0.0, min(1.0, Float(volDouble)))

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, completionHandler: nil)
        playerNode.play()
    }

    private func isInputDeviceInUse() -> Bool {
        var defaultInputDeviceID = AudioDeviceID(0)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultInputDeviceID
        )
        guard err == noErr, defaultInputDeviceID != 0 else {
            return false
        }

        var isRunning: UInt32 = 0
        var isRunningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunningSize = UInt32(MemoryLayout<UInt32>.size)
        let runningErr = AudioObjectGetPropertyData(
            defaultInputDeviceID,
            &isRunningAddress,
            0,
            nil,
            &isRunningSize,
            &isRunning
        )
        return runningErr == noErr && isRunning != 0
    }

    private func synthesize(name: SoundName, pack: String) -> AVAudioPCMBuffer? {
        let sampleRate: Double = 44100.0
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return nil
        }

        if pack == "robot" { return robotBuffer(name, format: format) }
        let isRetro = (pack == "retro")
        let isChirpy = (pack == "chirpy")
        let pitchMultiplier: Double = isChirpy ? 1.5 : 1.0

        func wave(phase: Double) -> Float {
            if isRetro {
                let s = sin(phase)
                return (s >= 0 ? 1.0 : -1.0) * 0.35
            } else {
                return Float(sin(phase))
            }
        }

        switch name {
        case .off:
            return nil

        case .softTick:
            let duration: Double = 0.025
            let frameCount = Int(duration * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            guard let channelData = buffer.floatChannelData else { return nil }
            let ptr = channelData[0]

            let baseFreq = 2000.0 * pitchMultiplier
            let glideDuration = isChirpy ? 0.008 : 0.0
            var phase: Double = 0

            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let freqMultiplier: Double
                if isChirpy && t < glideDuration {
                    freqMultiplier = 0.7 + 0.3 * (t / glideDuration)
                } else {
                    freqMultiplier = 1.0
                }
                phase += 2.0 * .pi * (baseFreq * freqMultiplier) / sampleRate

                let attackTime = 0.002
                let env: Float
                if t < attackTime {
                    env = Float(t / attackTime)
                } else {
                    let decayTime = t - attackTime
                    env = exp(-Float(decayTime / 0.0045))
                }
                let remaining = duration - t
                let tail: Float = remaining < 0.001 ? Float(remaining / 0.001) : 1.0
                ptr[i] = wave(phase: phase) * env * tail
            }
            return buffer

        case .beepBeep:
            let beepDur: Double = 0.110
            let gapDur: Double = 0.090
            let totalDur = beepDur + gapDur + beepDur
            let frameCount = Int(totalDur * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            guard let channelData = buffer.floatChannelData else { return nil }
            let ptr = channelData[0]

            let baseFreq = 880.0 * pitchMultiplier
            let glideDuration = isChirpy ? 0.025 : 0.0
            var phase: Double = 0

            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let sampleVal: Float

                if t < beepDur {
                    let localT = t
                    let freqMultiplier: Double = (isChirpy && localT < glideDuration)
                        ? 0.7 + 0.3 * (localT / glideDuration)
                        : 1.0
                    phase += 2.0 * .pi * (baseFreq * freqMultiplier) / sampleRate

                    let attackTime = 0.004
                    let env: Float
                    if localT < attackTime {
                        env = Float(localT / attackTime)
                    } else {
                        let decayTime = localT - attackTime
                        env = exp(-Float(decayTime / 0.035))
                    }
                    let remaining = beepDur - localT
                    let tail: Float = remaining < 0.002 ? Float(remaining / 0.002) : 1.0
                    sampleVal = wave(phase: phase) * env * tail
                } else if t < beepDur + gapDur {
                    phase = 0
                    sampleVal = 0.0
                } else {
                    let localT = t - (beepDur + gapDur)
                    let freqMultiplier: Double = (isChirpy && localT < glideDuration)
                        ? 0.7 + 0.3 * (localT / glideDuration)
                        : 1.0
                    phase += 2.0 * .pi * (baseFreq * freqMultiplier) / sampleRate

                    let attackTime = 0.004
                    let env: Float
                    if localT < attackTime {
                        env = Float(localT / attackTime)
                    } else {
                        let decayTime = localT - attackTime
                        env = exp(-Float(decayTime / 0.035))
                    }
                    let remaining = beepDur - localT
                    let tail: Float = remaining < 0.002 ? Float(remaining / 0.002) : 1.0
                    sampleVal = wave(phase: phase) * env * tail
                }
                ptr[i] = sampleVal
            }
            return buffer

        case .ding:
            let duration: Double = 0.600
            let frameCount = Int(duration * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            guard let channelData = buffer.floatChannelData else { return nil }
            let ptr = channelData[0]

            let baseFreq1 = 1320.0 * pitchMultiplier
            let baseFreq2 = 2640.0 * pitchMultiplier
            let glideDuration = isChirpy ? 0.030 : 0.0
            var phase1: Double = 0
            var phase2: Double = 0

            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let freqMultiplier: Double
                if isChirpy && t < glideDuration {
                    freqMultiplier = 0.7 + 0.3 * (t / glideDuration)
                } else {
                    freqMultiplier = 1.0
                }
                phase1 += 2.0 * .pi * (baseFreq1 * freqMultiplier) / sampleRate
                phase2 += 2.0 * .pi * (baseFreq2 * freqMultiplier) / sampleRate

                let w1 = wave(phase: phase1)
                let w2 = wave(phase: phase2)
                let rawSample = (w1 + 0.3 * w2) / 1.3

                let attackTime = 0.003
                let env: Float
                if t < attackTime {
                    env = Float(t / attackTime)
                } else {
                    let decayTime = t - attackTime
                    env = exp(-Float(decayTime / 0.11))
                }
                let remaining = duration - t
                let tail: Float = remaining < 0.003 ? Float(remaining / 0.003) : 1.0

                ptr[i] = rawSample * env * tail
            }
            return buffer

        case .bwomp:
            let duration: Double = 0.450
            let frameCount = Int(duration * sampleRate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
                return nil
            }
            buffer.frameLength = AVAudioFrameCount(frameCount)
            guard let channelData = buffer.floatChannelData else { return nil }
            let ptr = channelData[0]

            let startFreq = 320.0 * pitchMultiplier
            let endFreq = 110.0 * pitchMultiplier
            let glideDuration = isChirpy ? 0.030 : 0.0
            var phase: Double = 0

            for i in 0..<frameCount {
                let t = Double(i) / sampleRate
                let baseSweep = startFreq + (endFreq - startFreq) * (t / duration)
                let freqMultiplier: Double
                if isChirpy && t < glideDuration {
                    freqMultiplier = 0.7 + 0.3 * (t / glideDuration)
                } else {
                    freqMultiplier = 1.0
                }
                phase += 2.0 * .pi * (baseSweep * freqMultiplier) / sampleRate

                let attackTime = 0.005
                let env: Float
                if t < attackTime {
                    env = Float(t / attackTime)
                } else {
                    let decayTime = t - attackTime
                    env = exp(-Float(decayTime / 0.12))
                }
                let remaining = duration - t
                let tail: Float = remaining < 0.004 ? Float(remaining / 0.004) : 1.0

                ptr[i] = wave(phase: phase) * env * tail
            }
            return buffer
        }
    }

    /// "Robot" pack: wordless babble made of gliding blips, like a droid reacting. Each sound has a mood.
    private func robotBuffer(_ name: SoundName, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        // (start Hz, end Hz, seconds, gap after, warble depth in Hz)
        typealias Blip = (f0: Double, f1: Double, dur: Double, gap: Double, warble: Double)
        let blips: [Blip]
        switch name {
        case .off: return nil
        case .softTick: blips = [(900, 1300, 0.05, 0, 0)]                                   // tiny "bip"
        case .beepBeep: blips = [(600, 760, 0.07, 0.04, 0), (780, 520, 0.08, 0.04, 0), (520, 1500, 0.20, 0, 25)] // "bu-dwe-weee?" a question
        case .ding: blips = [(800, 1000, 0.06, 0.02, 0), (1000, 1250, 0.06, 0.02, 0), (1250, 1700, 0.07, 0.03, 0), (1500, 2100, 0.22, 0, 40)] // happy trill
        case .bwomp: blips = [(700, 420, 0.16, 0.05, 0), (480, 220, 0.30, 0, 18)]           // sad "wuh-woooh"
        }
        let sr = format.sampleRate
        let total = blips.reduce(0) { $0 + $1.dur + $1.gap }
        let frames = Int(total * sr)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)
        var i = 0, phase = 0.0
        for b in blips {
            let n = Int(b.dur * sr)
            for k in 0..<n where i + k < frames {
                let t = Double(k) / sr, x = Double(k) / Double(n)
                let f = b.f0 + (b.f1 - b.f0) * x + b.warble * sin(2 * .pi * 28 * t)
                phase += 2 * .pi * f / sr
                let env = Float(min(1, t / 0.006) * min(1, (b.dur - t) / 0.02)) // soft edges, no clicks
                out[i + k] = Float(sin(phase) + 0.25 * sin(2 * phase)) / 1.25 * env * 0.7
            }
            i += n + Int(b.gap * sr)
        }
        return buffer
    }
}
