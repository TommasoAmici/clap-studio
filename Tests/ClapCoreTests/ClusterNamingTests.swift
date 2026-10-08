import Foundation
import Testing
@testable import ClapCore

@Suite struct ClusterNamingTests {
    private func sample(_ id: Int64, category: String?, moods: [String] = [], loop: Bool = false,
                        centroid: Double = 3000, duration: Double = 0.5) -> SampleRecord {
        var s = SampleRecord(id: id, rootID: 1, rootPath: "/", relPath: "s\(id).wav", name: "s\(id)", ext: "wav",
                             duration: duration, sampleRate: 44100, channels: 1, size: 1, mtime: 0, status: .ok,
                             useCount: 0, lastUsed: nil, cueCount: 0)
        s.category = category; s.moods = moods; s.isLoop = loop; s.centroidHz = centroid
        return s
    }

    @Test func aDominantCategoryNamesTheCluster() {
        let samples = (0..<10).map { sample(Int64($0), category: $0 < 8 ? "Snare" : "Tom") }
        let names = ClusterNamer.names(clusters: [Int32](repeating: 0, count: 10), samples: samples)
        #expect(names[0]?.label == "Snare")
        #expect(names[0]?.detail == "10 sounds: 80% Snare, 20% Tom")
    }

    @Test func aMixedClusterIsNamedAfterItsTwoLargestCategories() {
        let samples = (0..<10).map { sample(Int64($0), category: $0 < 4 ? "Kick" : ($0 < 8 ? "Tom" : "Clap")) }
        let names = ClusterNamer.names(clusters: [Int32](repeating: 0, count: 10), samples: samples)
        #expect(names[0]?.label == "Kick & Tom")
    }

    @Test func clustersWithTheSameNameAreToldApart() {
        // Cluster 0: dark snares, cluster 1: bright snares, cluster 2: snares with one mood, all the same otherwise.
        var samples: [SampleRecord] = [], clusters: [Int32] = []
        for i in 0..<12 {
            let cluster = Int32(i / 4)
            samples.append(sample(Int64(i), category: "Snare", moods: cluster == 2 ? ["Dark"] : [],
                                  centroid: cluster == 0 ? 500 : (cluster == 1 ? 9000 : 3000)))
            clusters.append(cluster)
        }
        let names = ClusterNamer.names(clusters: clusters, samples: samples)
        let labels = Set(names.values.map(\.label))
        #expect(labels.count == 3, "every cluster has its own name: \(labels)")
        #expect(labels.allSatisfy { $0.hasPrefix("Snare") })
    }

    @Test func unnamedWhenNothingIsCategorisedAndLoopsAreSpotted() {
        let none = (0..<4).map { sample(Int64($0), category: nil) }
        #expect(ClusterNamer.names(clusters: [0, 0, 0, 0], samples: none).isEmpty)

        // Two Bass clusters, one made of loops: the loop cluster is labelled so.
        var samples: [SampleRecord] = [], clusters: [Int32] = []
        for i in 0..<8 {
            samples.append(sample(Int64(i), category: "Bass", loop: i >= 4)); clusters.append(Int32(i / 4))
        }
        let names = ClusterNamer.names(clusters: clusters, samples: samples)
        #expect(Set(names.values.map(\.label)) == ["Bass · Loops", "Bass · One-shots"])
    }

    @Test func userCategoriesCountAndUnknownSamplesAreSkipped() {
        var overridden = sample(1, category: "Kick"); overridden.categoryManual = "Snare"
        let names = ClusterNamer.names(clusters: [0, 0, 0], samples: [overridden, nil, sample(2, category: "Snare")])
        #expect(names[0]?.label == "Snare")
        #expect(names[0]?.detail.hasPrefix("2 sounds") == true)
    }
}
