import Combine
import Foundation

final class StepSequencer: ObservableObject {
    @Published var isRunning = false
    @Published var currentStep = 0
    @Published var steps: [Bool] = [true, false, false, true, false, true, false, false, true, false, false, true, false, false, true, false]
    @Published var notes: [Int] = [36, 39, 43, 46, 48, 51, 55, 58]
    @Published var bpm: Double = 124

    private var timer: Timer?

    func toggleStep(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].toggle()
    }

    func start(tick: @escaping (Int, Int) -> Void) {
        guard !isRunning else { return }
        isRunning = true
        currentStep = 0
        schedule(tick: tick)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        currentStep = 0
    }

    private func schedule(tick: @escaping (Int, Int) -> Void) {
        timer?.invalidate()
        let interval = (60.0 / bpm) / 4.0
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.steps[self.currentStep] {
                    let note = self.notes[self.currentStep % self.notes.count]
                    tick(self.currentStep, note)
                }
                self.currentStep = (self.currentStep + 1) % self.steps.count
            }
        }
    }
}
