---
name: macos-development
description: Design, implement, review, and maintain macOS desktop application code. Use whenever working on a macOS desktop app, including SwiftUI, AppKit, Mac Catalyst, and cross-platform desktop apps targeting macOS. Follow Apple's Human Interface Guidelines and the current stable macOS design, with graceful degradation for older supported versions.
---

# macOS development

Use this skill whenever working on macOS desktop application code. For logic-only changes, preserve the app's platform conventions and consult the Apple guidance relevant to that change; apply the UI guidance below whenever the task affects presentation or interaction.

## Consult current Apple guidance

Before making UI decisions, consult the live [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines), starting with [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos) and the pages for the affected components and interactions.

Identify the current **stable, publicly released macOS** using Apple's current release information. Consult its design guidance and relevant SwiftUI or AppKit API documentation. Treat that release as the visual target; a beta becomes the target only when the user requests it. Recheck rather than pinning this skill to a release number or design trend.

Use these primary sources:

- [Apple Design](https://developer.apple.com/design/) for current guidance, design resources, and design sessions.
- [macOS development](https://developer.apple.com/macos/) for current platform information.
- [SwiftUI documentation](https://developer.apple.com/documentation/swiftui) and [AppKit documentation](https://developer.apple.com/documentation/appkit) for actual APIs and their macOS availability.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) when the current design uses it.

Read the pages that bear on the task, rather than just citing the HIG landing page. If live documentation is unavailable, state the limitation and use verified existing platform conventions; flag uncertain API details for verification.

## Implement idiomatic macOS UI

Design and implement the most idiomatic macOS experience that meets the user's intent. Match the current release's layout, hierarchy, spacing, typography, materials, controls, and interaction conventions as closely as the app's scope and supported APIs permit.

Prefer native system components and their default styling: windows, toolbars, sidebars, split views, tables, lists, inspectors, menus, sheets, alerts, settings, and file panels. These let the running OS supply its appearance and behavior. Preserve the project's UI framework; use SwiftUI and AppKit together where one supplies native behavior the other cannot express.

Use system typography, semantic colors, SF Symbols, native control sizes, and system materials. Keep custom rendering for product-specific content, such as waveforms or canvases. Adopt current materials in the roles Apple specifies; for Liquid Glass, follow its guidance for controls and navigation while keeping content readable. Prefer supported system styling to manually reproducing blur, translucency, shadows, or corner geometry.

Respect desktop interaction conventions:

- Support resizable windows and sensible minimum sizes, with stable layout and readable content.
- Put app commands in the menu bar, with conventional keyboard shortcuts, correct enabled states, and context menus where relevant.
- Preserve keyboard navigation, focus, selection, pointer behavior, scrolling, and drag and drop for the affected workflow.
- Use native presentation and dismissal for dialogs and settings; preserve standard window controls and fullscreen behavior.
- Provide accessibility labels and state, VoiceOver access, sufficient contrast, and support for Reduce Motion and Reduce Transparency. Check light and dark appearances and avoid conveying state by color alone.

Keep changes within the requested feature. When a design departs from Apple conventions, explain the concrete product need and keep the departure localized.

## Gracefully support older macOS versions

Inspect the project's deployment target, build SDK, and existing compatibility patterns before choosing APIs. Preserve the minimum supported macOS version unless the user authorizes changing it.

Verify each new API's **macOS** availability in Apple documentation. Use `if #available(macOS …, *)` for runtime branches and `@available` on helpers or types that require newer APIs. Keep newer types and modifiers inside correctly annotated boundaries so older deployment targets still compile.

Distinguish runtime availability from SDK availability: `if #available` does not make an API visible to an older SDK. If older SDKs must remain supported, use a supported implementation or an explicit, tested build configuration that excludes newer declarations.

Prefer one native implementation when the system already adapts its appearance across releases. Where explicit branches are necessary, isolate them in a small view or modifier. Give older releases a native fallback that preserves the workflow, semantics, accessibility, and state; visual effects can simplify to supported materials or standard controls. Add a functional alternative when a new API provides more than decoration.

Choose availability versions from documentation, rather than copying a version from an unrelated example. Avoid scattered OS checks and hard-coded imitations of the latest appearance.

## Verify the result

Use the repository's build and test commands. Build against its deployment target and check that newer APIs are correctly gated.

For UI changes, run or render the affected screen and inspect it on the current stable macOS. Exercise the changed workflow, window resizing, keyboard interaction, light and dark appearances, and relevant accessibility settings.

Exercise explicit fallback paths on the oldest supported macOS when an environment is available. When it is unavailable, inspect the fallback and availability boundaries, and report that older-OS runtime behavior remains unverified. Distinguish a successful compile from runtime verification.

When reporting UI work, identify the Apple guidance that informed material decisions, any intentional departures, and which macOS versions were actually tested.
