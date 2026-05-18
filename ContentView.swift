import SwiftUI

struct ContentView: View {
    @StateObject private var synth = SynthEngine()
    @StateObject private var midi = MidiOut()
    @StateObject private var sequencer = StepSequencer()
    @StateObject private var voiceSynth = VoiceSynth()

    @State private var touchPoint = CGPoint(x: 0.42, y: 0.36)
    @State private var pulse = false

    private var voicePitchBinding: Binding<Double> {
        Binding(
            get: { Double(voiceSynth.pitch + 1_200) / 2_400 },
            set: { voiceSynth.pitch = Float(($0 * 2_400) - 1_200) }
        )
    }

    private var voiceRateBinding: Binding<Double> {
        Binding(
            get: { Double((voiceSynth.rate - 0.45) / 1.1) },
            set: { voiceSynth.rate = Float(0.45 + $0 * 1.1) }
        )
    }

    var body: some View {
        ZStack {
            Image("AirSynthVisual")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.38))
                .overlay(
                    LinearGradient(
                        colors: [.black.opacity(0.5), .clear, .black.opacity(0.82)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 12) {
                    header
                    waveformScope
                    performanceField
                    patchPanel
                    controlRack
                    rhythmVoicePanel
                    sequencerPanel
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 34)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AIR SYNTH")
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(
                        LinearGradient(colors: [.white, .cyan, Color(red: 1.0, green: 0.56, blue: 0.2)], startPoint: .leading, endPoint: .trailing)
                    )
                Text("NO-TOUCH WAVE INSTRUMENT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.62))
                    .tracking(1.2)
            }

            Spacer()

            Button {
                synth.isPlaying ? synth.stop() : synth.start()
                if synth.isPlaying {
                    midi.noteOn(synth.noteNumber())
                }
            } label: {
                Image(systemName: synth.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .black))
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(synth.isPlaying ? Color.cyan : Color.orange))
                    .foregroundColor(.black)
                    .shadow(color: (synth.isPlaying ? Color.cyan : Color.orange).opacity(0.75), radius: 18)
            }
        }
    }

    private var waveformScope: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("LIVE WAVEFORM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                    Spacer()
                    Text("\(Int(synth.frequency())) Hz")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.orange)
                }

                WaveformView(pitch: synth.pitch, volume: synth.volume)
                .frame(height: 78)
            }
        }
    }

    private var performanceField: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(.cyan.opacity(0.42), lineWidth: 1.5)
                    )

                GridLines()
                    .stroke(.cyan.opacity(0.16), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 28))

                Circle()
                    .stroke(.orange.opacity(0.52), lineWidth: 2)
                    .frame(width: 168 + synth.filter * 90, height: 168 + synth.filter * 90)
                    .position(x: touchPoint.x * proxy.size.width, y: touchPoint.y * proxy.size.height)
                    .shadow(color: .orange.opacity(0.75), radius: 18)

                Circle()
                    .fill(.cyan)
                    .frame(width: 18, height: 18)
                    .position(x: touchPoint.x * proxy.size.width, y: touchPoint.y * proxy.size.height)
                    .shadow(color: .cyan, radius: 18)

                VStack {
                    HStack {
                        Text("HAND FIELD")
                        Spacer()
                        Text("MIDI \(midi.destinationCount)")
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(.white.opacity(0.65))
                    .padding(16)
                    Spacer()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                        let y = min(max(value.location.y / max(proxy.size.height, 1), 0), 1)
                        touchPoint = CGPoint(x: x, y: y)
                        synth.pitch = x
                        synth.filter = 1.0 - y
                        synth.volume = 0.35 + (1.0 - y) * 0.58
                        if synth.isPlaying {
                            midi.noteOn(synth.noteNumber())
                            midi.controlChange(74, value: UInt8(synth.filter * 127))
                            midi.controlChange(7, value: UInt8(synth.volume * 127))
                        }
                    }
            )
        }
        .frame(height: 218)
    }

    private var controlRack: some View {
        GlassPanel {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(SynthEngine.Waveform.allCases, id: \.self) { wave in
                        Button {
                            synth.waveform = wave
                        } label: {
                            Text(wave.rawValue)
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(synth.waveform == wave ? Color.cyan : Color.white.opacity(0.08)))
                                .foregroundColor(synth.waveform == wave ? .black : .white.opacity(0.82))
                        }
                    }
                }

                HStack(spacing: 12) {
                    MacroSlider(title: "DRIVE", value: $synth.drive, color: .orange)
                    MacroSlider(title: "DELAY", value: $synth.delayMix, color: .cyan)
                    MacroSlider(title: "LFO", value: $synth.lfoRate, color: .mint)
                }
            }
        }
    }

    private var patchPanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AMBIENT PATCH")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                    Spacer()
                    Text(synth.patch.rawValue)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.orange)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(SynthEngine.AmbientPatch.allCases, id: \.self) { patch in
                            Button {
                                synth.applyPatch(patch)
                            } label: {
                                Text(patch.rawValue)
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(synth.patch == patch ? Color.orange : Color.white.opacity(0.08))
                                    )
                                    .foregroundColor(synth.patch == patch ? .black : .white.opacity(0.84))
                            }
                        }
                    }
                }
            }
        }
    }

    private var rhythmVoicePanel: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DRUM / VOICE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white.opacity(0.72))
                    Spacer()
                    Text(voiceSynth.status)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(voiceSynth.isRecording ? .orange : .cyan)
                }

                HStack(spacing: 8) {
                    Button {
                        synth.triggerKick(.kick808)
                    } label: {
                        Label("808", systemImage: "circle.fill")
                    }
                    .buttonStyle(InstrumentButtonStyle(color: .orange))

                    Button {
                        synth.triggerKick(.kick909)
                    } label: {
                        Label("909", systemImage: "circle.circle.fill")
                    }
                    .buttonStyle(InstrumentButtonStyle(color: .cyan))
                }

                HStack(spacing: 8) {
                    Button {
                        voiceSynth.toggleRecording()
                    } label: {
                        Label(voiceSynth.isRecording ? "STOP REC" : "REC VOICE", systemImage: voiceSynth.isRecording ? "stop.fill" : "mic.fill")
                    }
                    .buttonStyle(InstrumentButtonStyle(color: voiceSynth.isRecording ? .orange : .red))

                    Button {
                        voiceSynth.isPlaying ? voiceSynth.stopVoiceSynth() : voiceSynth.playVoiceSynth()
                    } label: {
                        Label(voiceSynth.isPlaying ? "STOP" : "VOICE SYNTH", systemImage: voiceSynth.isPlaying ? "stop.fill" : "waveform")
                    }
                    .buttonStyle(InstrumentButtonStyle(color: .mint))
                    .opacity(voiceSynth.hasRecording ? 1 : 0.58)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(VoiceSynth.VoiceStyle.allCases, id: \.self) { style in
                            Button {
                                voiceSynth.applyStyle(style)
                            } label: {
                                Text(style.rawValue)
                                    .font(.system(size: 11, weight: .black, design: .monospaced))
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 9)
                                    .background(
                                        Capsule()
                                            .fill(voiceSynth.style == style ? Color.mint : Color.white.opacity(0.08))
                                    )
                                    .foregroundColor(voiceSynth.style == style ? .black : .white.opacity(0.84))
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    MacroSlider(title: "VOICE PITCH", value: voicePitchBinding, color: .mint)
                    MacroSlider(title: "VOICE RATE", value: voiceRateBinding, color: .cyan)
                }
            }
        }
    }

    private var sequencerPanel: some View {
        GlassPanel {
            VStack(spacing: 13) {
                HStack {
                    Text("SEQUENCE")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                    Spacer()
                    Stepper("\(Int(sequencer.bpm)) BPM", value: $sequencer.bpm, in: 72...168, step: 1)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .labelsHidden()
                    Button(sequencer.isRunning ? "STOP" : "RUN") {
                        if sequencer.isRunning {
                            sequencer.stop()
                            midi.noteOff(synth.noteNumber())
                        } else {
                            synth.start()
                            sequencer.start { _, note in
                                let normalized = min(max((Double(note) - 36.0) / 24.0, 0), 1)
                                synth.pitch = normalized
                                midi.noteOn(UInt8(note))
                            }
                        }
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(sequencer.isRunning ? Color.orange : Color.cyan))
                    .foregroundColor(.black)
                }
                .foregroundColor(.white)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 8), spacing: 8) {
                    ForEach(0..<sequencer.steps.count, id: \.self) { index in
                        Button {
                            sequencer.toggleStep(index)
                        } label: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(stepColor(index))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(index == sequencer.currentStep ? .white : .clear, lineWidth: 2)
                                )
                                .frame(height: 34)
                        }
                    }
                }

                HStack {
                    Toggle("MIDI OUT", isOn: $midi.isEnabled)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                    Spacer()
                    Text(midi.lastMessage)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }
                .foregroundColor(.white)
            }
        }
    }

    private func stepColor(_ index: Int) -> Color {
        if index == sequencer.currentStep {
            return .white
        }
        return sequencer.steps[index] ? .orange : .white.opacity(0.09)
    }
}

private struct InstrumentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .black, design: .monospaced))
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(configuration.isPressed ? 0.9 : 0.72))
            )
            .foregroundColor(.black)
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.black.opacity(0.54))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12), lineWidth: 1))
            )
    }
}

private struct MacroSlider: View {
    let title: String
    @Binding var value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(.white.opacity(0.78))
            Slider(value: $value, in: 0...1)
                .tint(color)
        }
    }
}

private struct GridLines: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 1..<6 {
            let x = rect.minX + rect.width * CGFloat(index) / 6.0
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        for index in 1..<5 {
            let y = rect.minY + rect.height * CGFloat(index) / 5.0
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct WaveformView: View {
    let pitch: Double
    let volume: Double

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { graphics, size in
                let path = makePath(size: size, time: context.date.timeIntervalSinceReferenceDate)
                graphics.stroke(path, with: .color(.orange.opacity(0.42)), lineWidth: 8)
                graphics.stroke(path, with: .color(.cyan.opacity(0.96)), lineWidth: 3)
            }
        }
    }

    private func makePath(size: CGSize, time: TimeInterval) -> Path {
        var path = Path()
        let mid = size.height * 0.5
        let amp = size.height * (0.16 + volume * 0.24)

        for x in stride(from: 0.0, through: size.width, by: 3.0) {
            let p = x / max(size.width, 1)
            let primaryPhase = (p * 6.0 + time * 1.7 + pitch * 2.0) * Double.pi * 2.0
            let secondaryPhase = (p * 17.0 + time * 0.72) * Double.pi * 2.0
            let primary = sin(primaryPhase) * amp
            let secondary = sin(secondaryPhase) * amp * 0.28
            let y = mid + primary + secondary

            if x == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }
}
