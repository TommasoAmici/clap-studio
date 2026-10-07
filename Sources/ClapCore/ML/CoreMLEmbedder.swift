import CoreML
import Foundation

public enum ModelLoadError: Error, CustomStringConvertible {
    case notFound
    case failed(String)
    public var description: String {
        switch self {
        case .notFound: return "CNN14Trunk model not found"
        case .failed(let m): return "model failed to load: \(m)"
        }
    }
}

/// PANNs CNN14 trunk running on Core ML. The model maps a (1,1,401,64) log-mel
/// input to a (1,2048,T) feature map; pooling is done here over valid frames only,
/// so short one-shots are not diluted by padding.
public final class CoreMLEmbedder: EmbeddingProvider, @unchecked Sendable {
    public static let modelName = "CNN14Trunk"
    public let version = "panns-cnn14-v1"
    public let dimension = 2048
    private static let timeStride = 32   // five 2x poolings

    private let model: MLModel

    init(model: MLModel) { self.model = model }

    // MARK: loading

    public static func searchLocations() -> [URL] {
        var urls: [URL] = []
        if let env = ProcessInfo.processInfo.environment["CLAP_MODEL_PATH"] { urls.append(URL(fileURLWithPath: env)) }
        if let res = Bundle.main.resourceURL {
            urls.append(res.appendingPathComponent("\(modelName).mlmodelc"))
            urls.append(res.appendingPathComponent("\(modelName).mlpackage"))
        }
        if let dir = try? modelsDirectory() {
            urls.append(dir.appendingPathComponent("\(modelName).mlmodelc"))
            urls.append(dir.appendingPathComponent("\(modelName).mlpackage"))
        }
        return urls
    }

    public static func modelsDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ClapStudio/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func load() -> Result<CoreMLEmbedder, ModelLoadError> {
        guard let source = searchLocations().first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .failure(.notFound)
        }
        do {
            let compiled = try compiledURL(for: source)
            let config = MLModelConfiguration()
            config.computeUnits = .all
            return .success(CoreMLEmbedder(model: try MLModel(contentsOf: compiled, configuration: config)))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
    }

    /// Compiles an .mlpackage once and caches the result next to it in Application Support.
    private static func compiledURL(for source: URL) throws -> URL {
        if source.pathExtension == "mlmodelc" { return source }
        let cached = try modelsDirectory().appendingPathComponent("\(modelName)-compiled.mlmodelc")
        let fm = FileManager.default
        func modified(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        if fm.fileExists(atPath: cached.path), modified(cached) >= modified(source) { return cached }
        let temp = try MLModel.compileModel(at: source)
        try? fm.removeItem(at: cached)
        try fm.moveItem(at: temp, to: cached)
        return cached
    }

    // MARK: inference

    public func embed(_ mel: MelSpectrogram) throws -> [Float] {
        let frames = mel.frames, bands = MelSpectrogram.nMels
        let input = try MLMultiArray(shape: [1, 1, NSNumber(value: frames), NSNumber(value: bands)], dataType: .float32)
        mel.values.withUnsafeBufferPointer { src in
            input.dataPointer.copyMemory(from: src.baseAddress!, byteCount: src.count * MemoryLayout<Float>.size)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)])
        let output = try model.prediction(from: provider)
        guard let features = output.featureValue(for: "features")?.multiArrayValue else {
            throw ModelLoadError.failed("missing 'features' output")
        }
        return pool(features, validFrames: mel.validFrames)
    }

    /// max + mean over the valid time steps, then L2 normalisation (as PANNs does).
    private func pool(_ array: MLMultiArray, validFrames: Int) -> [Float] {
        let channels = array.shape[1].intValue, steps = array.shape[2].intValue
        let cStride = array.strides[1].intValue, tStride = array.strides[2].intValue
        let used = max(1, min(steps, (validFrames - 1) / Self.timeStride + 1))
        var out = [Float](repeating: 0, count: channels)

        func reduce<T>(_ type: T.Type, _ convert: (T) -> Float) {
            let p = array.dataPointer.assumingMemoryBound(to: T.self)
            for c in 0..<channels {
                var mx = -Float.greatestFiniteMagnitude, sum: Float = 0
                for t in 0..<used {
                    let v = convert(p[c * cStride + t * tStride])
                    mx = max(mx, v); sum += v
                }
                out[c] = mx + sum / Float(used)
            }
        }
        switch array.dataType {
        case .float16: reduce(Float16.self) { Float($0) }
        case .double: reduce(Double.self) { Float($0) }
        default: reduce(Float.self) { $0 }
        }
        l2Normalize(&out)
        return out
    }
}
