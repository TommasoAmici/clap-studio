import ClapCore
import Foundation

/// Sending samples to Squid as joined files.
extension AppModel {
    /// The sheet's samples in order, with their trims and sound edits, ready to join. Samples that left the library are left out.
    func squidJoinSources() -> [JoinSource] {
        squidItems.compactMap { sampleByID[$0] }.map {
            JoinSource(url: $0.url, trim: activeTrim(for: $0), name: $0.name, sampleID: $0.id)
        }
    }

    /// How many joined files the sheet's samples will probably make.
    func squidJoinEstimate() -> Int {
        let seconds = squidItems.compactMap { sampleByID[$0] }.map { sample in
            JoinSource(url: sample.url, trim: activeTrim(for: sample)).estimatedSeconds(fileDuration: sample.duration)
        }
        return JoinPlanner.estimatedFileCount(seconds: seconds, settings: .almSalmple)
    }

    /// Joins the sheet's samples and writes the joined files to the stick. Returns an error message, or nil on success.
    func sendJoinedToSquid(set: String?, firstBank: Int, channel: Int, bankName: String, name: String, driveID: String) async -> String? {
        guard let drive = drive(id: driveID) else { return "The drive is no longer connected." }
        let sources = squidJoinSources()
        guard !sources.isEmpty else { return "Add at least one sample." }
        let categories = Set(squidItems.compactMap { sampleByID[$0]?.effectiveCategory })
        let category = categories.count == 1 ? categories.first : nil
        let volume = drive.url
        let outcome: Result<Void, Error> = await Task.detached(priority: .userInitiated) {
            do {
                try SquidJoinedSender.send(sources, name: name, channel: channel, set: set, firstBank: firstBank, bankName: bankName,
                                           category: category, toVolume: volume)
                return .success(())
            } catch { return .failure(error) }
        }.value
        if case .failure(let error) = outcome {
            return "Could not join and send the samples: \(error.localizedDescription) Your library files were only read, never changed."
        }
        return finishSquidWrite(outcome, volume: volume)
    }
}
