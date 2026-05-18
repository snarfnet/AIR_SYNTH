import Combine
import CoreMIDI
import Foundation

final class MidiOut: ObservableObject {
    @Published var isEnabled = true
    @Published var lastMessage = "READY"
    @Published var destinationCount = 0

    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var activeNote: UInt8?

    init() {
        MIDIClientCreate("AIR SYNTH MIDI" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "AIR SYNTH OUT" as CFString, &outputPort)
        refreshDestinations()
    }

    func refreshDestinations() {
        destinationCount = MIDIGetNumberOfDestinations()
    }

    func noteOn(_ note: UInt8, velocity: UInt8 = 100) {
        guard isEnabled else { return }
        if let activeNote, activeNote != note {
            noteOff(activeNote)
        }
        activeNote = note
        send([0x90, note, velocity])
        lastMessage = "NOTE \(note)"
    }

    func noteOff(_ note: UInt8) {
        guard isEnabled else { return }
        send([0x80, note, 0])
        if activeNote == note {
            activeNote = nil
        }
    }

    func controlChange(_ number: UInt8, value: UInt8) {
        guard isEnabled else { return }
        send([0xB0, number, min(value, 127)])
        lastMessage = "CC \(number) \(value)"
    }

    private func send(_ bytes: [UInt8]) {
        refreshDestinations()
        guard destinationCount > 0 else {
            lastMessage = "NO MIDI DEST"
            return
        }

        var packetList = MIDIPacketList()
        withUnsafeMutablePointer(to: &packetList) { listPointer in
            var packet = MIDIPacketListInit(listPointer)
            bytes.withUnsafeBufferPointer { buffer in
                packet = MIDIPacketListAdd(listPointer, 1024, packet, 0, bytes.count, buffer.baseAddress!)
            }

            for index in 0..<destinationCount {
                let destination = MIDIGetDestination(index)
                MIDISend(outputPort, destination, listPointer)
            }
        }
    }
}
