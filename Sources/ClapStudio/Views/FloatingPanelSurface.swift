import SwiftUI

extension View {
    /// Keeps floating map actions distinct from the sounds beneath them.
    func floatingControls<S: Shape>(in shape: S) -> some View {
        modifier(FloatingPanelSurface(shape: shape, controls: true))
    }

    /// Gives map captions a readable background without making them look like controls.
    func floatingInformation<S: Shape>(in shape: S) -> some View {
        modifier(FloatingPanelSurface(shape: shape, controls: false))
    }
}

private struct FloatingPanelSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let controls: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if opaqueBackground {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
                .overlay { shape.stroke(.secondary, lineWidth: 1).allowsHitTesting(false) }
        } else if #available(macOS 26.0, *), controls {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }

    private var opaqueBackground: Bool {
        #if DEBUG
        DebugSnapshotAccessibility.opaquePanels(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
        #else
        reduceTransparency || contrast == .increased
        #endif
    }
}

/// Shares rendering work between the map's floating control panels.
struct FloatingControlsContainer: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { content }
        } else {
            content
        }
    }
}

/// Lets a canvas's colours continue beneath the native sidebar and inspector.
struct ExtendCanvasBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.backgroundExtensionEffect(isEnabled: extendsBackground)
        } else {
            content
        }
    }

    private var extendsBackground: Bool {
        #if DEBUG
        !DebugSnapshotAccessibility.reduceTransparency(systemValue: reduceTransparency)
        #else
        !reduceTransparency
        #endif
    }
}
