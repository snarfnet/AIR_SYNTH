import AVFoundation
import Combine
import Foundation

final class SynthEngine: ObservableObject {
    enum KickType {
        case kick808
        case kick909

        var label: String {
            switch self {
            case .kick808:
                return "808"
            case .kick909:
                return "909"
            }
        }
    }

    enum Waveform: String, CaseIterable {
        case saw = "SAW"
        case square = "SQR"
        case sine = "SIN"
        case noise = "NOISE"
    }

    enum AmbientPatch: String, CaseIterable {
        case airPad = "AIR PAD"
        case glassDrone = "GLASS"
        case tapeCloud = "TAPE"
        case shimmer = "SHIMMER"
        case subMist = "MIST"
        case crystalBell = "CRYSTAL"
        case velvetChoir = "VELVET"
        case dawnKeys = "DAWN"
        case analogChorus = "1980 PAD"
        case fmGlass = "FM GLASS"
        case warmPoly = "WARM POLY"
        case wideBrass = "WIDE BRASS"
        case stringMachine = "STRING"
        case tapeKeys = "TAPE KEYS"
    }

    @Published var isPlaying = false
    @Published var pitch: Double = 0.42
    @Published var filter: Double = 0.66
    @Published var volume: Double = 0.62
    @Published var drive: Double = 0.38
    @Published var delayMix: Double = 0.28
    @Published var lfoRate: Double = 0.22
    @Published var waveform: Waveform = .saw
    @Published var patch: AmbientPatch = .airPad
    @Published var scaleName = "MINOR"

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var phase: Double = 0
    private var phase2: Double = 0.12
    private var phase3: Double = 0.36
    private var phase4: Double = 0.72
    private var lfoPhase: Double = 0
    private var slowPhase: Double = 0
    private var filteredSample: Double = 0
    private var hazeSample: Double = 0
    private var delayBuffer = [Float](repeating: 0, count: 132_300)
    private var delayIndex = 0
    private var kickType: KickType = .kick808
    private var kickTime: Double = 1
    private var kickPhase: Double = 0
    private let scale = [0, 2, 3, 5, 7, 10, 12, 14, 15, 17, 19, 22, 24]

    func applyPatch(_ newPatch: AmbientPatch) {
        patch = newPatch
        switch newPatch {
        case .airPad:
            waveform = .saw
            filter = 0.72
            drive = 0.12
            delayMix = 0.56
            lfoRate = 0.11
            volume = 0.52
        case .glassDrone:
            waveform = .sine
            filter = 0.88
            drive = 0.06
            delayMix = 0.62
            lfoRate = 0.06
            volume = 0.5
        case .tapeCloud:
            waveform = .saw
            filter = 0.56
            drive = 0.24
            delayMix = 0.78
            lfoRate = 0.1
            volume = 0.46
        case .shimmer:
            waveform = .sine
            filter = 0.94
            drive = 0.08
            delayMix = 0.72
            lfoRate = 0.24
            volume = 0.44
        case .subMist:
            waveform = .square
            filter = 0.38
            drive = 0.18
            delayMix = 0.44
            lfoRate = 0.08
            volume = 0.58
        case .crystalBell:
            waveform = .sine
            filter = 0.98
            drive = 0.04
            delayMix = 0.68
            lfoRate = 0.18
            volume = 0.42
        case .velvetChoir:
            waveform = .noise
            filter = 0.64
            drive = 0.08
            delayMix = 0.82
            lfoRate = 0.12
            volume = 0.38
        case .dawnKeys:
            waveform = .sine
            filter = 0.82
            drive = 0.1
            delayMix = 0.48
            lfoRate = 0.16
            volume = 0.5
        case .analogChorus:
            waveform = .saw
            filter = 0.68
            drive = 0.13
            delayMix = 0.64
            lfoRate = 0.2
            volume = 0.5
        case .fmGlass:
            waveform = .sine
            filter = 0.96
            drive = 0.05
            delayMix = 0.7
            lfoRate = 0.14
            volume = 0.4
        case .warmPoly:
            waveform = .saw
            filter = 0.58
            drive = 0.2
            delayMix = 0.52
            lfoRate = 0.12
            volume = 0.54
        case .wideBrass:
            waveform = .saw
            filter = 0.48
            drive = 0.28
            delayMix = 0.38
            lfoRate = 0.09
            volume = 0.56
        case .stringMachine:
            waveform = .saw
            filter = 0.74
            drive = 0.08
            delayMix = 0.76
            lfoRate = 0.22
            volume = 0.46
        case .tapeKeys:
            waveform = .sine
            filter = 0.7
            drive = 0.22
            delayMix = 0.58
            lfoRate = 0.18
            volume = 0.48
        }
    }

    func start() {
        guard !isPlaying else { return }
        configureAudioIfNeeded()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            isPlaying = true
        } catch {
            print("AIR SYNTH audio start failed: \(error)")
            isPlaying = false
        }
    }

    func stop() {
        isPlaying = false
        engine.pause()
    }

    func triggerKick(_ type: KickType) {
        configureAudioIfNeeded()
        kickType = type
        kickTime = 0
        kickPhase = 0

        if !isPlaying {
            start()
        }
    }

    func noteNumber() -> UInt8 {
        let step = min(max(Int(pitch * Double(scale.count - 1)), 0), scale.count - 1)
        return UInt8(36 + scale[step])
    }

    func frequency() -> Double {
        440.0 * pow(2.0, (Double(noteNumber()) - 69.0) / 12.0)
    }

    private func configureAudioIfNeeded() {
        guard sourceNode == nil else { return }

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let sampleRate = self.engine.outputNode.outputFormat(forBus: 0).sampleRate

            for frame in 0..<Int(frameCount) {
                let sample = self.renderSample(sampleRate: sampleRate)
                for buffer in ablPointer {
                    let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                    pointer?[frame] = sample
                }
            }

            return noErr
        }

        engine.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
    }

    private func renderSample(sampleRate: Double) -> Float {
        let baseFrequency = frequency()
        let lfo = sin(lfoPhase * .pi * 2)
        let slow = sin(slowPhase * .pi * 2)
        let modulatedFrequency = baseFrequency * (1.0 + lfo * lfoRate * 0.04 + slow * 0.006)

        phase += modulatedFrequency / sampleRate
        phase2 += (modulatedFrequency * 1.003) / sampleRate
        phase3 += (modulatedFrequency * 1.497) / sampleRate
        phase4 += (modulatedFrequency * 0.502) / sampleRate
        lfoPhase += (0.2 + lfoRate * 8.0) / sampleRate
        slowPhase += (0.025 + lfoRate * 0.12) / sampleRate
        phase.formTruncatingRemainder(dividingBy: 1)
        phase2.formTruncatingRemainder(dividingBy: 1)
        phase3.formTruncatingRemainder(dividingBy: 1)
        phase4.formTruncatingRemainder(dividingBy: 1)
        lfoPhase.formTruncatingRemainder(dividingBy: 1)
        slowPhase.formTruncatingRemainder(dividingBy: 1)

        let raw = renderPatchSample(lfo: lfo, slow: slow)
        let cutoff = 0.006 + filter * filter * 0.34
        filteredSample += (raw - filteredSample) * cutoff
        hazeSample += (filteredSample - hazeSample) * (0.0015 + delayMix * 0.006)

        let airy = filteredSample * 0.78 + hazeSample * 0.42
        let driven = tanh(airy * (1.0 + drive * 8.0))

        let delaySeconds = 0.18 + delayMix * 1.62
        let delayFrames = min(delayBuffer.count - 1, max(1, Int(sampleRate * delaySeconds)))
        let readIndex = (delayIndex - delayFrames + delayBuffer.count) % delayBuffer.count
        let delayed = delayBuffer[readIndex]
        let kick = renderKick(sampleRate: sampleRate)
        let output = Float(driven) * Float(volume) + delayed * Float(delayMix) + kick
        delayBuffer[delayIndex] = output * Float(0.48 + delayMix * 0.34)
        delayIndex = (delayIndex + 1) % delayBuffer.count

        return max(-1, min(1, output))
    }

    private func renderKick(sampleRate: Double) -> Float {
        guard kickTime < 1.2 else { return 0 }

        let sample: Double
        switch kickType {
        case .kick808:
            let bodyDecay = exp(-kickTime * 7.2)
            let pitchDrop = exp(-kickTime * 18.0)
            let frequency = 46.0 + pitchDrop * 92.0
            kickPhase += frequency / sampleRate
            kickPhase.formTruncatingRemainder(dividingBy: 1)
            let body = sin(kickPhase * .pi * 2.0) * bodyDecay
            let click = Double.random(in: -1...1) * exp(-kickTime * 90.0) * 0.08
            sample = tanh((body + click) * 1.8) * 0.72
        case .kick909:
            let bodyDecay = exp(-kickTime * 12.0)
            let pitchDrop = exp(-kickTime * 26.0)
            let frequency = 54.0 + pitchDrop * 118.0
            kickPhase += frequency / sampleRate
            kickPhase.formTruncatingRemainder(dividingBy: 1)
            let body = sin(kickPhase * .pi * 2.0) * bodyDecay
            let snap = Double.random(in: -1...1) * exp(-kickTime * 62.0) * 0.24
            let knock = sin(kickPhase * .pi * 8.0) * exp(-kickTime * 36.0) * 0.16
            sample = tanh((body + snap + knock) * 2.2) * 0.66
        }

        kickTime += 1.0 / sampleRate
        return Float(sample)
    }

    private func renderPatchSample(lfo: Double, slow: Double) -> Double {
        switch patch {
        case .analogChorus:
            return vintageChorusPad(lfo: lfo, slow: slow)
        case .fmGlass:
            return fmGlassTone(lfo: lfo)
        case .warmPoly:
            return warmPolyPad(slow: slow)
        case .wideBrass:
            return wideBrassTone(lfo: lfo)
        case .stringMachine:
            return stringMachineTone(lfo: lfo, slow: slow)
        case .tapeKeys:
            return tapeKeysTone(lfo: lfo, slow: slow)
        default:
            break
        }

        switch waveform {
        case .saw:
            let saw1 = (phase * 2.0) - 1.0
            let saw2 = (phase2 * 2.0) - 1.0
            let sine = sin(phase3 * .pi * 2)
            let softPad = saw1 * 0.28 + saw2 * 0.22 + sine * 0.5
            return beautifulColor(softPad)
        case .square:
            let sub = phase4 < 0.5 ? 1.0 : -1.0
            let soft = sin(phase * .pi * 2) * 0.45
            return beautifulColor(sub * 0.36 + soft)
        case .sine:
            let root = sin(phase * .pi * 2)
            let fifth = sin(phase3 * .pi * 2) * 0.28
            let octave = sin(phase2 * .pi * 4) * 0.18
            let bell = sin(phase3 * .pi * 6) * 0.08 * (0.5 + filter * 0.5)
            return beautifulColor(root * 0.62 + fifth + octave + bell)
        case .noise:
            let noise = Double.random(in: -1...1)
            let choirTone = sin(phase * .pi * 2) * 0.34 + sin(phase3 * .pi * 2) * 0.2
            return beautifulColor(noise * (0.12 + slow * 0.05) + choirTone + lfo * 0.035)
        }
    }

    private func vintageChorusPad(lfo: Double, slow: Double) -> Double {
        let detune = 0.006 + lfoRate * 0.012
        let sawA = softSaw(phase)
        let sawB = softSaw(wrap(phase2 + lfo * detune))
        let sawC = softSaw(wrap(phase3 - slow * detune * 0.7))
        let body = sawA * 0.34 + sawB * 0.28 + sawC * 0.2
        let chorus = sin((phase2 + slow * 0.012) * .pi * 2.0) * 0.12
        return body + chorus
    }

    private func fmGlassTone(lfo: Double) -> Double {
        let mod = sin(phase3 * .pi * 2.0) * (2.4 + filter * 4.2)
        let carrier = sin((phase * .pi * 2.0) + mod)
        let bell = sin((phase2 * .pi * 4.0) + mod * 0.42) * 0.2
        let shine = sin(phase4 * .pi * 14.0) * 0.08 * (0.4 + filter * 0.6)
        return carrier * 0.48 + bell + shine + lfo * 0.018
    }

    private func warmPolyPad(slow: Double) -> Double {
        let sawA = softSaw(phase) * 0.34
        let sawB = softSaw(wrap(phase2 + slow * 0.004)) * 0.28
        let square = (phase4 < 0.52 ? 1.0 : -1.0) * 0.14
        let soft = sin(phase3 * .pi * 2.0) * 0.22
        return tanh((sawA + sawB + square + soft) * 1.25)
    }

    private func wideBrassTone(lfo: Double) -> Double {
        let opening = 0.54 + filter * 0.46
        let saw = softSaw(phase) * 0.38 + softSaw(phase2) * 0.3
        let pulse = (phase3 < (0.44 + lfo * 0.04) ? 1.0 : -1.0) * 0.18
        let bite = sin(phase * .pi * 6.0) * 0.08 * opening
        return tanh((saw + pulse + bite) * (1.1 + drive * 1.8))
    }

    private func stringMachineTone(lfo: Double, slow: Double) -> Double {
        let layerA = softSaw(wrap(phase + lfo * 0.006)) * 0.24
        let layerB = softSaw(wrap(phase2 - lfo * 0.009)) * 0.24
        let layerC = softSaw(wrap(phase3 + slow * 0.014)) * 0.18
        let air = sin(phase4 * .pi * 2.0) * 0.18
        return layerA + layerB + layerC + air
    }

    private func tapeKeysTone(lfo: Double, slow: Double) -> Double {
        let wow = slow * 0.012 + lfo * 0.004
        let root = sin(wrap(phase + wow) * .pi * 2.0) * 0.5
        let octave = sin(wrap(phase2 - wow * 0.6) * .pi * 4.0) * 0.18
        let worn = softSaw(wrap(phase4 + slow * 0.008)) * 0.16
        return tanh((root + octave + worn) * 1.25)
    }

    private func beautifulColor(_ input: Double) -> Double {
        switch patch {
        case .crystalBell:
            let chime = sin(phase3 * .pi * 8.0) * 0.16 + sin(phase2 * .pi * 12.0) * 0.08
            return input * 0.72 + chime
        case .velvetChoir:
            let choir = sin(phase * .pi * 2.0) * 0.34 + sin(phase2 * .pi * 2.0) * 0.32 + sin(phase3 * .pi * 2.0) * 0.18
            return choir + input * 0.18
        case .dawnKeys:
            let keyTone = sin(phase * .pi * 2.0) * 0.52 + sin(phase3 * .pi * 4.0) * 0.16
            return keyTone + input * 0.34
        case .shimmer:
            let shimmerTone = sin(phase2 * .pi * 6.0) * 0.1 + sin(phase3 * .pi * 8.0) * 0.07
            return input * 0.82 + shimmerTone
        default:
            return input
        }
    }

    private func softSaw(_ value: Double) -> Double {
        tanh((((value * 2.0) - 1.0) * 1.6))
    }

    private func wrap(_ value: Double) -> Double {
        var wrapped = value
        wrapped.formTruncatingRemainder(dividingBy: 1)
        if wrapped < 0 {
            wrapped += 1
        }
        return wrapped
    }
}
