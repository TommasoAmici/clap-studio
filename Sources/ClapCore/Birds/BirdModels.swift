#if NON_COMMERCIAL
import CoreML
import Foundation

/// BirdNET V2.4 on Core ML: 3 s of 48 kHz mono audio in, one logit per species out.
/// Export it with `tools/export_birdnet.py` (the model is CC BY-NC-SA 4.0, so it is not shipped with the app).
public final class BirdClassifier: @unchecked Sendable {
    public static let modelName = "BirdNET"
    public static let sampleRate = 48_000.0
    public static let windowSamples = 144_000
    public static let speciesCount = 6_522

    private let model: MLModel
    private let outputName: String
    private let lock = NSLock()

    init(model: MLModel) throws {
        guard let name = model.modelDescription.outputDescriptionsByName.keys.first else {
            throw ModelLoadError.failed("BirdNET has no output")
        }
        self.model = model
        outputName = name
    }

    /// Runs on the CPU: the model is small, and the Neural Engine is slower than the CPU for it.
    public static func load() -> Result<BirdClassifier, ModelLoadError> {
        do {
            return .success(try BirdClassifier(model: try ModelLocator.load(modelName, computeUnits: .cpuOnly)))
        } catch let error as ModelLoadError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    public static var isInstalled: Bool { ModelLocator.exists(modelName) && ModelLocator.resource("birdnet_labels.txt") != nil }

    /// Logits for exactly `windowSamples` samples (shorter input is zero-padded, longer is cut).
    public func logits(_ window: [Float]) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, NSNumber(value: Self.windowSamples)], dataType: .float32)
        let target = input.dataPointer.assumingMemoryBound(to: Float.self)
        let count = min(window.count, Self.windowSamples)
        window.withUnsafeBufferPointer { target.update(from: $0.baseAddress!, count: count) }
        if count < Self.windowSamples { (target + count).update(repeating: 0, count: Self.windowSamples - count) }
        let features = try MLDictionaryFeatureProvider(dictionary: ["inputs": MLFeatureValue(multiArray: input)])
        // One prediction at a time per model instance keeps memory flat; callers use one classifier per worker.
        lock.lock(); defer { lock.unlock() }
        let output = try model.prediction(from: features)
        guard let array = output.featureValue(for: outputName)?.multiArrayValue else {
            throw ModelLoadError.failed("missing BirdNET output")
        }
        return array.floatValues()
    }
}

/// BirdNET's location model: how likely each species is at a place and time of year.
public final class BirdLocationModel: @unchecked Sendable {
    public static let modelName = "BirdNETLocation"
    /// BirdNET's own default: species below this at the recording's place and week are ruled out.
    public static let defaultThreshold: Float = 0.03

    private let model: MLModel

    init(model: MLModel) { self.model = model }

    public static func load() -> Result<BirdLocationModel, ModelLoadError> {
        do {
            return .success(BirdLocationModel(model: try ModelLocator.load(modelName, computeUnits: .cpuOnly)))
        } catch let error as ModelLoadError {
            return .failure(error)
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// Probabilities per species. `week` is 1...48 (four per month), or nil for "any time of year".
    public func probabilities(latitude: Double, longitude: Double, week: Int?) throws -> [Float] {
        let input = try MLMultiArray(shape: [1, 3], dataType: .float32)
        input[0] = NSNumber(value: Float(latitude))
        input[1] = NSNumber(value: Float(longitude))
        input[2] = NSNumber(value: Float(week.map { (1...48).contains($0) ? $0 : -1 } ?? -1))
        let features = try MLDictionaryFeatureProvider(dictionary: ["location": MLFeatureValue(multiArray: input)])
        let output = try model.prediction(from: features)
        guard let array = output.featureValue(for: "probabilities")?.multiArrayValue else {
            throw ModelLoadError.failed("missing BirdNET location output")
        }
        return array.floatValues()
    }

    /// The model's week of the year, 1...48 (each is about a week and a half long).
    public static func week(of date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let days = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        return min(48, max(1, Int((Double(day) / Double(days) * 48).rounded(.up))))
    }
}
#endif
