import Foundation
import Testing
@testable import ClapCore

@Suite struct LocationTests {
    @Test func coordinatesInTheWaysFilesWriteThem() {
        #expect(GeoParse.degrees("51.5") == 51.5 && GeoParse.degrees("-0.12") == -0.12)
        #expect(GeoParse.degrees("51.5N") == 51.5 && GeoParse.degrees("33.25S") == -33.25 && GeoParse.degrees("0.5W") == -0.5)
        #expect(GeoParse.degrees("51,30.0N") == 51.5, "degrees and decimal minutes, as XMP has them")
        #expect(abs(GeoParse.degrees("51°30'36\"N")! - 51.51) < 1e-9 && abs(GeoParse.degrees("12 30 0 W")! + 12.5) < 1e-9)
        #expect(GeoParse.degrees("") == nil && GeoParse.degrees("north") == nil && GeoParse.degrees("12 apples") == nil)
        #expect(GeoParse.degrees("51,75") == nil, "minutes cannot reach 60")
    }

    @Test func pairsAndISO6709() {
        #expect(GeoParse.iso6709("+51.5000-000.1000/") == GeoPoint(latitude: 51.5, longitude: -0.1))
        #expect(GeoParse.iso6709("+48.8584+002.2945+035.000CRSWGS_84/") == GeoPoint(latitude: 48.8584, longitude: 2.2945), "altitude ignored")
        #expect(GeoParse.iso6709("hello") == nil && GeoParse.iso6709("+95.0+010.0/") == nil, "out of range")
        #expect(GeoParse.pair("51.5, -0.1") == GeoPoint(latitude: 51.5, longitude: -0.1))
        #expect(GeoParse.pair("51.5N; 0.1W") == GeoPoint(latitude: 51.5, longitude: -0.1))
        #expect(GeoParse.pair("one, two") == nil)
    }

    @Test func iXMLAndXMPCarryAPlace() {
        let ixml = "<BWFXML><USER><GPS_LATITUDE>51.5</GPS_LATITUDE><GPS_LONGITUDE>-0.12</GPS_LONGITUDE></USER><LONG_NAME>A tape</LONG_NAME></BWFXML>"
        #expect(LocationReader.point(inMarkup: ixml) == GeoPoint(latitude: 51.5, longitude: -0.12), "a LONG_NAME is not a longitude")
        let xmp = #"<rdf:Description exif:GPSLatitude="64,8.5N" exif:GPSLongitude="21,56.0W" exif:GPSAltitude="12"/>"#
        let found = LocationReader.point(inMarkup: xmp)
        #expect(found != nil && abs(found!.latitude - 64.141667) < 1e-5 && abs(found!.longitude + 21.933333) < 1e-5)
        let refs = "<GPSLatitude>33.9</GPSLatitude><GPSLatitudeRef>S</GPSLatitudeRef><GPSLongitude>18.4</GPSLongitude><GPSLongitudeRef>E</GPSLongitudeRef>"
        #expect(LocationReader.point(inMarkup: refs) == GeoPoint(latitude: -33.9, longitude: 18.4))
        #expect(LocationReader.point(inMarkup: "<LOCATION>+10.5+020.25/</LOCATION>") == GeoPoint(latitude: 10.5, longitude: 20.25))
        #expect(LocationReader.point(inMarkup: "<NOTE>no place here</NOTE><LATENCY>3</LATENCY>") == nil)
    }

    /// A tiny WAV with extra chunks after the audio.
    private func wav(chunks: [(String, String)]) -> Data {
        func le32(_ v: Int) -> Data { var d = Data(); for i in 0..<4 { d.append(UInt8((v >> (8 * i)) & 0xFF)) }; return d }
        var body = Data("WAVE".utf8)
        var fmt = Data(); fmt.append(contentsOf: [1, 0, 1, 0]); fmt.append(le32(8000)); fmt.append(le32(16000)); fmt.append(contentsOf: [2, 0, 16, 0])
        body.append(Data("fmt ".utf8)); body.append(le32(fmt.count)); body.append(fmt)
        body.append(Data("data".utf8)); body.append(le32(4)); body.append(contentsOf: [0, 0, 0, 0])
        for (id, text) in chunks {
            let payload = Data(text.utf8)
            body.append(Data(id.utf8)); body.append(le32(payload.count)); body.append(payload)
            if payload.count & 1 == 1 { body.append(0) }
        }
        var file = Data("RIFF".utf8); file.append(le32(body.count)); file.append(body)
        return file
    }

    @Test func aWavFileGivesUpItsPlace() throws {
        let dir = TestSupport.tempDir()
        let withPlace = dir.appendingPathComponent("a.wav")
        try wav(chunks: [("iXML", "<BWFXML><LATITUDE>40.7</LATITUDE><LONGITUDE>-74.0</LONGITUDE></BWFXML>")]).write(to: withPlace)
        let without = dir.appendingPathComponent("b.wav")
        try wav(chunks: [("iXML", "<BWFXML><NOTE>quiet</NOTE></BWFXML>")]).write(to: without)
        #expect(LocationReader.readWav(url: withPlace) == GeoPoint(latitude: 40.7, longitude: -74.0))
        #expect(LocationReader.readWav(url: without) == nil)
        #expect(LocationReader.readWav(url: dir.appendingPathComponent("missing.wav")) == nil)
    }

    @Test func placesAreStoredWithoutOverridingTheUser() throws {
        let (store, dir) = try TestSupport.makeStore()
        let root = try store.addRoot(path: dir.path)
        let files = ["a.wav", "b.wav", "c.wav"].map { ScannedFile(relPath: $0, size: 10, mtime: 1) }
        _ = try store.sync(rootID: root.id, scanned: files) { _ in nil }
        let jobs = store.pendingJobs(limit: 10)
        try store.save(results: jobs.map {
            .success(id: $0.id, duration: 2, sampleRate: 48000, channels: 1, embedding: [1, 0], fingerprint: nil, modelVersion: "m1")
        })
        let ids = store.loadSamples().map(\.id).sorted()
        #expect(ids.count == 3)
        #expect(store.locationBacklog() == 3)
        try store.setLocation(GeoPoint(latitude: 1, longitude: 2), sampleIDs: [ids[0]])
        let placed = try store.saveFileLocations([(ids[0], GeoPoint(latitude: 50, longitude: 50)),
                                                  (ids[1], GeoPoint(latitude: 10, longitude: 20)), (ids[2], nil)])
        #expect(placed == [ids[1]], "the user's place stays")
        #expect(store.location(sampleID: ids[0]) == GeoPoint(latitude: 1, longitude: 2))
        #expect(store.location(sampleID: ids[1]) == GeoPoint(latitude: 10, longitude: 20) && store.location(sampleID: ids[2]) == nil)
        #expect(store.locations().count == 2)
        #expect(store.locationJobs(limit: 10).isEmpty, "everything looked at is marked")
        // A place the user clears is not looked for again: the file is not offered once it has been looked at.
        try store.setLocation(nil, sampleIDs: [ids[1]])
        #expect(store.location(sampleID: ids[1]) == nil && store.locationJobs(limit: 10).isEmpty)
    }
}

@Suite struct PlaceGroupingTests {
    private func point(_ lat: Double, _ lon: Double) -> GeoPoint { GeoPoint(latitude: lat, longitude: lon)! }

    @Test func nearbyRecordingsShareAPin() {
        let pins = PlaceGrouping.group([(1, point(51.5001, -0.1001)), (2, point(51.5004, -0.1003)), (3, point(48.85, 2.35))])
        #expect(pins.count == 2)
        #expect(pins[0].ids == [1, 2] && pins[0].count == 2, "the bigger group first")
        #expect(abs(pins[0].center.latitude - 51.50025) < 1e-6)
        #expect(pins[1].ids == [3])
        #expect(PlaceGrouping.group([]).isEmpty)
    }

    @Test func aPinDoesNotSplitAtAGridEdge() {
        // Straddling a multiple of the cell size (0.01 degrees).
        let pins = PlaceGrouping.group([(1, point(51.4999, -0.1001)), (2, point(51.5002, -0.0999))])
        #expect(pins.count == 1 && pins[0].ids == [1, 2])
        #expect(PlaceGrouping.group([(1, point(51.5, 0)), (2, point(51.6, 0))]).count == 2, "11 km apart is another place")
    }

    @Test func manyPlacesMergeUntilTheyFit() {
        var located: [(id: Int64, point: GeoPoint)] = []
        for i in 0..<60 { for j in 0..<30 { located.append((Int64(i * 100 + j), point(40 + Double(i) * 0.05, 10 + Double(j) * 0.05))) } }
        let pins = PlaceGrouping.group(located, maxPins: 100)
        #expect(pins.count <= 100 && pins.count > 1)
        #expect(pins.flatMap(\.ids).count == located.count, "nothing is lost")
        #expect(Set(pins.flatMap(\.ids)).count == located.count)
    }
}
