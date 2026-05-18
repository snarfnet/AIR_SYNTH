import AVFoundation
import Combine
import Foundation

final class SynthEngine: ObservableObject {
    enum Waveform: String, CaseIterable {
        case saw = "SAW"
        case square = "SQR"
        case sine = "SIN"
        case noise = "NOISE"
    }

    @Published var isPlaying = false
    @Published var pitch: Double = 0.42
    @Published var filter: Double = 0.66
    @Published var volume: Double = 0.62
    @Published var drive: Double = 0.38
    @Published var delayMix: Double = 0.28
    @Published var lfoRate: Double = 0.22
    @Published var waveform: Waveform = .saw
    @Published var scaleName = "MINOR"

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var phase: Double = 0
    private var lfoPhase: Double = 0
    private var filteredSample: Double = 0
    private var delayBuffer = [Float](repeating: 0, count: 44_100)
    private var delayIndex = 0
    private let scale = [0, 2, 3, 5, 7, 10, 12, 14, 15, 17, 19, 22, 24]

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
        let modulatedFrequency = baseFrequency * (1.0 + lfo * lfoRate * 0.04)

        phase += modulatedFrequency / sampleRate
        lfoPhase += (0.2 + lfoRate * 8.0) / sampleRate
        phase.formTruncatingRemainder(dividingBy: 1)
        lfoPhase.formTruncatingRemainder(dividingBy: 1)

        let raw: Double
        switch waveform {
        case .saw:
            raw = (phase * 2.0) - 1.0
        case .square:
            raw = phase < 0.5 ? 1.0 : -1.0
        case .sine:
            raw = sin(phase * .pi * 2)
        case .noise:
            raw = Double.random(in: -1...1)
        }

        let cutoff = 0.015 + filter * filter * 0.45
        filteredSample += (raw - filteredSample) * cutoff
        let driven = tanh(filteredSample * (1.0 + drive * 8.0))

        let delayFrames = max(1, Int(sampleRate * (0.08 + delayMix * 0.42)))
        let readIndex = (delayIndex - delayFrames + delayBuffer.count) % delayBuffer.count
        let delayed = delayBuffer[readIndex]
        let output = Float(driven) * Float(volume) + delayed * Float(delayMix)
        delayBuffer[delayIndex] = output * 0.55
        delayIndex = (delayIndex + 1) % delayBuffer.count

        return max(-1, min(1, output))
    }
}
