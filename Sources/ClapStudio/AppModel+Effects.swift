import ClapCore
import Foundation

extension AppModel {
    var showEffects: Bool {
        get { effects.isOpen }
        set {
            guard effects.isOpen != newValue else { return }
            effects.isOpen = newValue
            if newValue {
                showDrums = false; showMelody = false
                configureEffects()
                effects.open(samples: effectsActionTargets.compactMap { sampleByID[$0] }, trims: trims,
                             protectedSources: samples.map(\.url))
            } else { effects.closeDrawer() }
        }
    }

    var effectsActionTargets: [Int64] {
        viewMode == .map && !mapSelection.isEmpty ? mapSelection.sorted() : actionTargets
    }

    func openEffects(ids: [Int64]) {
        showEffects = true
        effects.refresh(samples: ids.compactMap { sampleByID[$0] }, trims: trims)
    }

    func configureEffects() {
        effects.errorSink = { [weak self] in self?.errorMessage = $0 }
        effects.statusSink = { [weak self] in self?.statusMessage = $0 }
        effects.playbackSink = { [weak self] in self?.playback = $0 }
        effects.previewSink = { [weak self] sample in self?.playSample(sample) }
        refreshEffectsSelection()
    }

    func refreshEffectsSelection(forBounce: Bool = false) {
        effects.refresh(samples: effectsActionTargets.compactMap { sampleByID[$0] }, trims: trims,
                        protectedSources: forBounce ? samples.map(\.url) : nil)
    }

    var usesEffects: Bool { showEffects && effects.enabled && !effects.chain.isEmpty }

    func auditionEffects(_ sample: SampleRecord, trim: SampleTrim?) {
        guard FileManager.default.isReadableFile(atPath: sample.url.path) else {
            errorMessage = "\(sample.name) is not available (is the volume mounted?)"
            return
        }
        player.stop()
        let fit = adjustment(for: sample)
        effects.audition(sample, trim: trim, rate: fit.rate, pitchCents: Float(fit.semitones * 100),
                         gainDB: previewGain(for: sample), volume: volume)
    }

    func stopAudition() { player.stop(); effects.stopPreview() }
}
