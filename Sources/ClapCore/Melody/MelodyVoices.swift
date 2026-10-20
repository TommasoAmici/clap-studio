import AVFoundation
import Foundation

/// The audio players the melody sounds through: a few per track, used in turn, so chords and notes that ring into
/// the next one do not cut each other off. A track's volume and mute are set on its players.
final class MelodyVoices: @unchecked Sendable {
    static let voicesPerTrack = 4

    private let nodes: [AVAudioPlayerNode]
    private var next = [Int](repeating: 0, count: MelodyPattern.maxTracks)

    init(engine: AVAudioEngine, format: AVAudioFormat) {
        var made: [AVAudioPlayerNode] = []
        for _ in 0..<(MelodyPattern.maxTracks * Self.voicesPerTrack) {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            made.append(node)
        }
        nodes = made
    }

    func play() { for node in nodes { node.play() } }

    /// Drops anything scheduled but not yet played.
    func stop() { for node in nodes { node.stop() } }

    func setMix(_ melody: MelodyPattern) {
        for t in 0..<MelodyPattern.maxTracks {
            let level: Float = melody.tracks.indices.contains(t) && !melody.tracks[t].muted ? melody.tracks[t].volume : 0
            for v in 0..<Self.voicesPerTrack { nodes[t * Self.voicesPerTrack + v].volume = level }
        }
    }

    /// Starts `buffer` on the track's next free player at `time`.
    func schedule(_ buffer: AVAudioPCMBuffer, track: Int, at time: AVAudioTime) {
        guard track >= 0, track < MelodyPattern.maxTracks else { return }
        let node = nodes[track * Self.voicesPerTrack + next[track]]
        next[track] = (next[track] + 1) % Self.voicesPerTrack
        node.scheduleBuffer(buffer, at: time, options: .interrupts, completionHandler: nil)
    }
}
