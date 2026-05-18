import Combine
import Foundation

final class KickClock: ObservableObject {
    @Published var isRunning = false
    @Published var bpm: Double = 124 {
        didSet {
            if isRunning {
                schedule()
            }
        }
    }
    @Published var selectedKick: SynthEngine.KickType = .kick808
    @Published var beat = 0

    var trigger: ((SynthEngine.KickType) -> Void)?

    private var timer: Timer?

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        beat = 0
        trigger?(selectedKick)
        schedule()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        beat = 0
    }

    private func schedule() {
        timer?.invalidate()
        let interval = 60.0 / min(max(bpm, 40), 240)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.beat = (self.beat + 1) % 4
            self.trigger?(self.selectedKick)
        }
    }
}
