import ClapCore
import Foundation

/// Synthetic ambience with demonstration places: these are not recordings made at the named sites.
enum MediaFieldSounds {
    static let sites: [(String, Double, Double)] = [
        ("Reykjavik Shore", 64.15, -21.94), ("Amsterdam Rain", 52.37, 4.90),
        ("Lisbon Harbour", 38.72, -9.14), ("Marrakesh Courtyard", 31.63, -7.99),
        ("Nairobi Grassland", -1.29, 36.82), ("Cape Town Surf", -33.92, 18.42),
        ("Tokyo Crossing", 35.68, 139.69), ("Chiang Mai Stream", 18.79, 98.99),
        ("Sydney Coast", -33.87, 151.21), ("Vancouver Forest", 49.28, -123.12),
        ("Mexico City Square", 19.43, -99.13), ("Rio Evening", -22.91, -43.17)
    ]

    static func seed(in root: URL) throws -> [String: SoundDescriptors] {
        let folder = root.appendingPathComponent("Field Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let analyzer = DescriptorAnalyzer()
        var descriptors: [String: SoundDescriptors] = [:]
        for (site, item) in sites.enumerated() {
            for variation in 0..<3 {
                let name = String(format: "%@ %02d", item.0, variation + 1)
                var state = UInt64(site * 100 + variation + 1)
                var filtered = 0.0
                let audio = (0..<Int(MediaLibrary.rate * 8)).map { frame -> Float in
                    let t = Double(frame) / MediaLibrary.rate
                    state = state &* 6_364_136_223_846_793_005 &+ 1
                    let noise = Double(state >> 32) / Double(UInt32.max) * 2 - 1
                    filtered = filtered * 0.97 + noise * 0.03
                    let swell = 0.6 + 0.4 * sin(t * (0.7 + Double(site) * 0.04))
                    let hum = sin(t * 2 * .pi * Double(70 + site * 11)) * 0.025
                    let fade = min(1, t / 0.05) * min(1, (8 - t) / 0.1)
                    return Float((filtered * swell + hum) * fade)
                }
                try MediaLibrary.write(audio, to: folder.appendingPathComponent(name + ".wav"))
                let measured = analyzer.analyze(samples: audio, sampleRate: MediaLibrary.rate, fileDuration: 8)
                descriptors[name] = FieldRecording.aggregate([(descriptors: measured, seconds: 8)])
            }
        }
        return descriptors
    }
}
