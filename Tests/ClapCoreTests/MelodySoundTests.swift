import AVFoundation
import Foundation
import Testing
@testable import ClapCore

@Suite struct MelodyVoiceTests {
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!

    private func constant(_ value: Float, seconds: Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(seconds * 44100)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = value } }
        return buffer
    }

    @Test func notesAreTunedFromTheSamplesOwnPitchWithinTwoOctaves() {
        #expect(MelodyVoice.semitones(note: 60, root: 60) == 0, "the root note plays the sample as it is")
        #expect(MelodyVoice.semitones(note: 72, root: 60) == 12)
        #expect(MelodyVoice.semitones(note: 55, root: 60) == -5)
        #expect(MelodyVoice.semitones(note: 127, root: 60) == 24 && MelodyVoice.semitones(note: 0, root: 60) == -24,
                "the tape-style tuning reaches two octaves each way")
    }

    @Test func aHigherNoteIsTunedUpAndPlaysFaster() {
        let sound = constant(0.5, seconds: 1)
        #expect(MelodyVoice.pitched(sound, semitones: 0) === sound, "no tuning, no work")
        let octave = MelodyVoice.pitched(sound, semitones: 12)
        #expect(abs(Int(octave.frameLength) - 22050) <= 2, "an octave up is half as long, like a tape")
        let down = MelodyVoice.pitched(sound, semitones: -12)
        #expect(abs(Int(down.frameLength) - 88200) <= 2, "an octave down is twice as long")
    }

    @Test func aNoteCutsTheSoundAtItsLengthWithoutAClick() throws {
        let note = try #require(MelodyVoice.shaped(constant(1, seconds: 1), duration: 0.25, velocity: 1))
        #expect(note.frameLength == 11025, "a quarter of a second of a one second sound")
        let data = try #require(note.floatChannelData)
        #expect(abs(data[0][5000] - 1) < 1e-6, "the body is untouched")
        #expect(data[0][0] < 0.05 && data[0][Int(note.frameLength) - 1] < 0.01, "it fades in and out instead of clicking")
    }

    @Test func aShortSoundPlaysToItsEndAndVelocityScalesIt() throws {
        let note = try #require(MelodyVoice.shaped(constant(1, seconds: 0.1), duration: 1, velocity: 0.5))
        #expect(note.frameLength == 4410, "a note longer than the sound does not stretch it")
        let data = try #require(note.floatChannelData)
        #expect(abs(data[1][2000] - 0.5) < 1e-6 && abs(data[0][4409] - 0.5) < 1e-6, "half velocity is half the level, to the last sample")
    }

    @Test func nothingIsMadeFromNothing() {
        let empty = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        #expect(MelodyVoice.shaped(empty, duration: 1, velocity: 1) == nil)
    }
}

@Suite struct MelodySoundsTests {
    private func waitForBuffer(_ sounds: MelodySounds, sample: Int64, semitones: Int) async -> AVAudioPCMBuffer? {
        for _ in 0..<150 {
            if let buffer = sounds.buffer(sampleID: sample, semitones: semitones) { return buffer }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    @Test func eachNeededTuningIsPreparedInTheBackground() async throws {
        let url = TestSupport.tempDir().appendingPathComponent("pad.wav")
        try writeTestWav(url, seconds: 0.5) { Float(sin(2 * .pi * 220 * $0)) * 0.5 }
        var melody = MelodyPattern()
        melody.addTrack(sampleID: 1, label: "Pad", rootNote: 57)
        melody.addNote(track: 0, pitch: 57, start: 0)              // the root: as recorded
        melody.addNote(track: 0, pitch: 69, start: 4)              // an octave up

        let sounds = MelodySounds(cache: AudioBufferCache(sampleRate: 44100))
        sounds.update(melody: melody, sources: [1: DrumSource(url: url)])
        let plain = await waitForBuffer(sounds, sample: 1, semitones: 0)
        let octave = await waitForBuffer(sounds, sample: 1, semitones: 12)
        #expect(plain != nil && abs(Int(plain!.frameLength) - 22050) <= 2)
        #expect(octave != nil && abs(Int(octave!.frameLength) - 11025) <= 2, "the octave is half as long")
        #expect(sounds.buffer(sampleID: 1, semitones: 7) == nil, "tunings no note uses are not made")
    }

    @Test func aSoundThatIsNoLongerUsedIsLetGo() async throws {
        let url = TestSupport.tempDir().appendingPathComponent("pad.wav")
        try writeTestWav(url, seconds: 0.2) { _ in 0.3 }
        var melody = MelodyPattern()
        melody.addTrack(sampleID: 1, label: "Pad")
        melody.addNote(track: 0, pitch: 60, start: 0)
        let sounds = MelodySounds(cache: AudioBufferCache(sampleRate: 44100))
        sounds.update(melody: melody, sources: [1: DrumSource(url: url)])
        let ready = await waitForBuffer(sounds, sample: 1, semitones: 0)
        #expect(ready != nil)
        melody.removeNote(track: 0, id: melody.tracks[0].notes[0].id)
        sounds.update(melody: melody, sources: [1: DrumSource(url: url)])
        #expect(sounds.buffer(sampleID: 1, semitones: 0) == nil, "memory is not held for notes that are gone")
    }

    @Test func aTrackWithoutASoundIsSimplySilent() {
        var melody = MelodyPattern()
        melody.addTrack(sampleID: nil, label: "Track 1")
        melody.addNote(track: 0, pitch: 60, start: 0)
        let sounds = MelodySounds(cache: AudioBufferCache(sampleRate: 44100))
        sounds.update(melody: melody, sources: [:])
        #expect(sounds.buffer(sampleID: 1, semitones: 0) == nil)
    }
}
