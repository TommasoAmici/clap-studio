import AppKit

/// Shows the light or the dark artwork of the app icon in the Dock to match the system appearance.
/// The icon is also set explicitly so a stale LaunchServices icon cache cannot hide it.
@MainActor enum AppIconSwitcher {
    private static var observation: NSKeyValueObservation?

    static func start() {
        update()
        observation = NSApplication.shared.observe(\.effectiveAppearance) { _, _ in
            Task { @MainActor in update() }
        }
    }

    private static func update() {
        let dark = NSApplication.shared.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // A build made without Icon Composer has only the light icon.
        let names = dark ? ["AppIconDark", "AppIcon"] : ["AppIcon"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = icon
                return
            }
        }
    }
}
