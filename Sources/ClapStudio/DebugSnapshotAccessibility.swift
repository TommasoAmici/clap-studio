#if DEBUG
import SwiftUI

/// Exercises custom panel fallbacks without changing the Mac's accessibility settings.
struct DebugSnapshotAccessibility: ViewModifier {
    private static let env = ProcessInfo.processInfo.environment

    func body(content: Content) -> some View {
        content.transaction {
            if Self.env["CLAP_SNAPSHOT"] != nil, Self.env["CLAP_SNAPSHOT_REDUCE_MOTION"] == "1" {
                $0.animation = nil
                $0.disablesAnimations = true
            }
        }
    }

    static func reduceTransparency(systemValue: Bool) -> Bool {
        override("CLAP_SNAPSHOT_REDUCE_TRANSPARENCY", systemValue: systemValue)
    }

    static func opaquePanels(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        self.reduceTransparency(systemValue: reduceTransparency)
            || override("CLAP_SNAPSHOT_INCREASE_CONTRAST", systemValue: increasedContrast)
    }

    private static func override(_ key: String, systemValue: Bool) -> Bool {
        guard env["CLAP_SNAPSHOT"] != nil, let value = env[key] else { return systemValue }
        return value == "1"
    }
}
#endif
