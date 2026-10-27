import Foundation
import Testing

/// A small native plug-in exercises the real bridge without installed vendor effects.
enum VST3Fixture {
    static func bundle(in folder: URL, withEditor: Bool = true, realTimeOnly: Bool = false) throws -> URL {
        let bundle = folder.appendingPathComponent("Gain.vst3"), contents = bundle.appendingPathComponent("Contents")
        let executable = contents.appendingPathComponent("MacOS/Gain")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let compiler = Process()
        compiler.executableURL = URL(fileURLWithPath: "/usr/bin/clang++")
        compiler.arguments = ["-dynamiclib", "-std=c++17", "-mmacosx-version-min=14.0", "-I", repository.appendingPathComponent("Sources/CVST3/vendor").path,
                              repository.appendingPathComponent("Tests/Fixtures/VST3Gain.mm").path, "-o", executable.path, "-framework", "AppKit"]
        if !withEditor { compiler.arguments?.append("-DCLAP_NO_EDITOR=1") }
        if realTimeOnly { compiler.arguments?.append("-DCLAP_REALTIME_ONLY=1") }
        compiler.arguments?.append("-DGainControl=ClapTestGainControl_" + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        try compiler.run(); compiler.waitUntilExit()
        #expect(compiler.terminationStatus == 0, "The native stereo gain fixture builds with the installed compiler")
        let plist: [String: Any] = ["CFBundleExecutable": "Gain", "CFBundleIdentifier": "app.clapstudio.TestGain", "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        return bundle
    }
}
