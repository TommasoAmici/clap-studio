#if DEBUG
import AppKit
import ClapCore
import Foundation

/// Exercises the same selection, preview, editor and card removal actions as the drawer.
@MainActor enum DebugEffectsSnapshot {
    static func exercise(model: AppModel, bundle: URL) async throws {
        func waitFor(_ action: String, _ ready: () -> Bool) async throws {
            for _ in 0..<750 {
                if ready() { return }
                try await Task.sleep(for: .milliseconds(20))
            }
            throw VST3Error.message("The effects snapshot timed out waiting for \(action). Chain: \(model.effects.chain.count); busy: \(model.effects.busy); playback: \(model.playback.sampleID.map(String.init) ?? "none"); error: \(model.errorMessage ?? model.effects.message ?? "none").")
        }
        try await waitFor("initial effect") { !model.effects.busy && !model.effects.chain.isEmpty }
        guard let sample = model.selectedSample else { throw VST3Error.message("No snapshot sample is selected.") }
        model.playSample(sample)
        try await waitFor("sample \(sample.id) playback") { model.playback.sampleID == sample.id }
        guard !model.effects.busy, !model.effects.progress.contains("preview") else {
            throw VST3Error.message("Preview changed the drawer's busy controls or status.")
        }
        let id = model.effects.chain[0].id
        model.effects.edit(id)
        try await Task.sleep(for: .milliseconds(800))
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(150))
        let nativePress = pressRemove()
        if !nativePress { model.effects.removeEffect(id) }
        try await waitFor("editor slot removal") { model.effects.chain.isEmpty }
        model.effects.addBundle(bundle)
        try await waitFor("first duplicate effect") { !model.effects.busy && model.effects.chain.count == 1 }
        model.effects.addBundle(bundle)
        try await waitFor("second duplicate effect") { !model.effects.busy && model.effects.chain.count == 2 }
        model.effects.chain.swapAt(0, 1)
        model.playSample(sample)
        try await waitFor("sample \(sample.id) playback") { model.playback.sampleID == sample.id }
        model.stopAudition()
        let ids = Array(model.visible.prefix(2).map(\.id))
        model.mapSelection = ids; model.viewMode = .map
        model.refreshEffectsSelection()
        guard model.effects.samples.map(\.id).sorted() == ids.sorted() else {
            throw VST3Error.message("The effects bounce selection did not follow the Map dots.")
        }
        if ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_MAP"] != "1" { model.viewMode = .library }
        model.tableSelection = Set(ids); model.refreshEffectsSelection()
        if let path = ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_EFFECTS_REPORT"] {
            try Data("Preview stayed enabled; live editor opened; Remove Effect \(nativePress ? "native accessibility press succeeded" : "workbench action succeeded; native accessibility press unavailable"); duplicate chain reordered and played; Map selection followed; Stop succeeded. Error: \(model.errorMessage ?? "none"); effect message: \(model.effects.message ?? "none").\n".utf8)
                .write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    private static func pressRemove() -> Bool {
        var visited: Set<ObjectIdentifier> = []
        var labels: [String] = []
        func attribute(_ object: NSObject, _ name: String) -> AnyObject? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func search(_ object: Any) -> Bool {
            guard let node = object as? NSObject, visited.insert(ObjectIdentifier(node)).inserted else { return false }
            let legacy = NSSelectorFromString("accessibilityAttributeValue:")
            func legacyValue(_ key: String) -> AnyObject? {
                guard node.responds(to: legacy) else { return nil }
                return node.perform(legacy, with: key)?.takeUnretainedValue()
            }
            let label = (attribute(node, "accessibilityLabel") as? String)
                ?? (attribute(node, "accessibilityTitle") as? String)
                ?? (legacyValue("AXDescription") as? String) ?? (legacyValue("AXTitle") as? String) ?? ""
            if !label.isEmpty { labels.append(label) }
            if label == "Remove effect" {
                let selector = NSSelectorFromString("accessibilityPerformPress")
                guard node.responds(to: selector), let method = node.method(for: selector) else { return false }
                let press = unsafeBitCast(method, to: (@convention(c) (AnyObject, Selector) -> ObjCBool).self)
                return press(node, selector).boolValue
            }
            let children = ((attribute(node, "accessibilityChildren") as? [Any]) ?? [])
                + ((attribute(node, "accessibilityContents") as? [Any]) ?? [])
                + ((legacyValue("AXChildren") as? [Any]) ?? [])
            for child in children { if search(child) { return true } }
            if let view = node as? NSView {
                for child in view.subviews { if search(child) { return true } }
            }
            return false
        }
        let success = NSApp.windows.filter(\.isVisible).contains { window in
            search(window) || window.contentView.map { search($0) } == true
        }
        if !success, let report = ProcessInfo.processInfo.environment["CLAP_SNAPSHOT_EFFECTS_REPORT"] {
            try? Data(labels.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: report + ".labels"), options: .atomic)
        }
        return success
    }
}
#endif
