import AVFoundation
import Combine
import Foundation

final class VoiceSynth: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var hasRecording = false
    @Published var isPlaying = false
    @Published var status = "READY"
    @Published var pitch: Float = 700
    @Published var rate: Float = 0.82

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitchUnit = AVAudioUnitTimePitch()
    private let reverb = AVAudioUnitReverb()
    private var recorder: AVAudioRecorder?

    private var recordingURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("air_synth_voice.m4a")
    }

    override init() {
        super.init()
        configurePlaybackEngine()
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    func playVoiceSynth() {
        guard hasRecording else {
            status = "REC FIRST"
            return
        }

        do {
            if engine.isRunning {
                player.stop()
            } else {
                try engine.start()
            }

            let file = try AVAudioFile(forReading: recordingURL)
            pitchUnit.pitch = pitch
            pitchUnit.rate = rate
            player.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.status = "VOICE READY"
                }
            }
            player.play()
            isPlaying = true
            status = "VOICE SYNTH"
        } catch {
            status = "VOICE ERROR"
        }
    }

    func stopVoiceSynth() {
        player.stop()
        isPlaying = false
        status = hasRecording ? "VOICE READY" : "READY"
    }

    private func startRecording() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if allowed {
                        self.beginRecorder()
                    } else {
                        self.status = "MIC DENIED"
                    }
                }
            }
        } catch {
            status = "MIC ERROR"
        }
    }

    private func beginRecorder() {
        do {
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
            recorder?.delegate = self
            recorder?.record(forDuration: 8)
            isRecording = true
            status = "RECORDING"
        } catch {
            status = "REC ERROR"
        }
    }

    private func stopRecording() {
        recorder?.stop()
        isRecording = false
        hasRecording = FileManager.default.fileExists(atPath: recordingURL.path)
        status = hasRecording ? "VOICE READY" : "READY"
    }

    private func configurePlaybackEngine() {
        guard engine.attachedNodes.contains(player) == false else { return }

        pitchUnit.pitch = pitch
        pitchUnit.rate = rate
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = 42

        engine.attach(player)
        engine.attach(pitchUnit)
        engine.attach(reverb)
        engine.connect(player, to: pitchUnit, format: nil)
        engine.connect(pitchUnit, to: reverb, format: nil)
        engine.connect(reverb, to: engine.mainMixerNode, format: nil)
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isRecording = false
            self.hasRecording = flag
            self.status = flag ? "VOICE READY" : "REC FAILED"
        }
    }
}
