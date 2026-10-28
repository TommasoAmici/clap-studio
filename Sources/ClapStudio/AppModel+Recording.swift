import ClapCore
import Foundation

/// Searching with a sound made on the spot: record from the microphone, then rank the library by similarity to it.
extension AppModel {
    func toggleRecording() {
        if isRecording { finishRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard !isRecording, !recordingStarting else { return }
        recordingStarting = true
        errorMessage = nil
        recorder.onProgress = { [weak self] level, seconds in
            MainActor.assumeIsolated { self?.recordingLevel = level; self?.recordingSeconds = seconds }
        }
        recorder.onAutoStop = { [weak self] result in
            MainActor.assumeIsolated { self?.recordingFinished(result) }
        }
        Task {
            defer { recordingStarting = false }
            do {
                try await AudioRecorder.requestAccess()
                stopAudition()                    // a preview would be heard by the microphone
                drumMachine.stop()
                try recorder.start()
                recordingLevel = 0; recordingSeconds = 0
                isRecording = true
            } catch {
                errorMessage = "\(error)"
            }
        }
    }

    func finishRecording() {
        guard isRecording else { return }
        recordingFinished(Result { try recorder.stop() })
    }

    /// Drops a recording that is not wanted (Escape), without searching.
    func cancelRecording() {
        guard isRecording else { return }
        _ = try? recorder.stop()
        isRecording = false
    }

    private func recordingFinished(_ result: Result<URL, Error>) {
        isRecording = false
        switch result {
        case .success(let url): findSimilar(toFileAt: url, name: "your recording", cleanUp: true)
        case .failure(let error): errorMessage = "\(error)"
        }
    }
}
