import ClapCore
import Foundation

extension AppModel {
    func openEffects(ids: [Int64]) {
        let selected = ids.compactMap { sampleByID[$0] }
        guard !selected.isEmpty else { return }
        player.stop()
        effects.errorSink = { [weak self] in self?.errorMessage = $0 }
        effects.statusSink = { [weak self] in self?.statusMessage = $0 }
        effects.open(samples: selected, trims: trims, protectedSources: samples.map(\.url))
    }
}
