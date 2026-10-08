import CoreML
import Foundation

public enum ModelLoadError: Error, CustomStringConvertible {
    case notFound(String)
    case failed(String)
    public var description: String {
        switch self {
        case .notFound(let name): return "\(name) model not found"
        case .failed(let m): return "model failed to load: \(m)"
        }
    }
}

/// Finds, compiles (once) and loads Core ML models exported by `tools/`.
/// Compiling happens at runtime with `MLModel.compileModel`, so no Xcode is needed.
public enum ModelLocator {
    public static func modelsDirectory() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CLAP_MODELS_DIR"] {
            let dir = URL(fileURLWithPath: override, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("ClapStudio/Models", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Candidate locations for a model, in priority order. `CLAP_MODEL_PATH` overrides the CNN14 model only.
    public static func searchLocations(_ name: String) -> [URL] {
        var urls: [URL] = []
        if name == "CNN14Trunk", let env = ProcessInfo.processInfo.environment["CLAP_MODEL_PATH"] {
            urls.append(URL(fileURLWithPath: env))
        }
        if let res = Bundle.main.resourceURL {
            urls.append(res.appendingPathComponent("\(name).mlmodelc"))
            urls.append(res.appendingPathComponent("\(name).mlpackage"))
        }
        if let dir = try? modelsDirectory() {
            urls.append(dir.appendingPathComponent("\(name).mlmodelc"))
            urls.append(dir.appendingPathComponent("\(name).mlpackage"))
        }
        return urls
    }

    public static func exists(_ name: String) -> Bool {
        searchLocations(name).contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    public static func load(_ name: String, computeUnits: MLComputeUnits = .all) throws -> MLModel {
        guard let source = searchLocations(name).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw ModelLoadError.notFound(name)
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = computeUnits
            return try MLModel(contentsOf: try compiledURL(name: name, source: source), configuration: config)
        } catch let error as ModelLoadError {
            throw error
        } catch {
            throw ModelLoadError.failed(error.localizedDescription)
        }
    }

    /// Path of a plain data file (tokenizer vocabulary etc.) next to the models.
    public static func resource(_ file: String) -> URL? {
        var candidates: [URL] = []
        if let res = Bundle.main.resourceURL { candidates.append(res.appendingPathComponent(file)) }
        if let dir = try? modelsDirectory() { candidates.append(dir.appendingPathComponent(file)) }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Compiling and caching must not interleave: two loads of the same model would race on the cached copy.
    private static let compileLock = NSLock()

    private static func compiledURL(name: String, source: URL) throws -> URL {
        if source.pathExtension == "mlmodelc" { return source }
        compileLock.lock(); defer { compileLock.unlock() }
        let cached = try modelsDirectory().appendingPathComponent("\(name)-compiled.mlmodelc")
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
}

extension MLMultiArray {
    /// Contiguous float copy regardless of the underlying storage type.
    func floatValues() -> [Float] {
        let n = count
        var out = [Float](repeating: 0, count: n)
        switch dataType {
        case .float16:
            let p = dataPointer.assumingMemoryBound(to: Float16.self)
            for i in 0..<n { out[i] = Float(p[i]) }
        case .double:
            let p = dataPointer.assumingMemoryBound(to: Double.self)
            for i in 0..<n { out[i] = Float(p[i]) }
        default:
            let p = dataPointer.assumingMemoryBound(to: Float.self)
            for i in 0..<n { out[i] = p[i] }
        }
        return out
    }
}
