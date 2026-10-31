---
name: designing-macos-interfaces
description: Design and build macOS desktop app interfaces with proven interaction-design patterns. Use when creating, reviewing, or fixing a macOS app in SwiftUI or AppKit — window/sidebar/inspector layout, toolbar and menu bar commands, keyboard shortcuts, lists and tables, settings, forms, onboarding, undo, progress, empty/error states, accessibility, and design systems.
---

# Designing macOS Interfaces

A condensed field guide derived from *Designing Interfaces*, 3rd Edition (Tidwell, Brewer & Valencia-Brooks), translated from its web/mobile pattern catalog into macOS practice.

**Core stance:** a Mac app is not an iPad app in a resizable window. macOS users expect a menu bar, multiple windows, keyboard parity, persistent state, and standard controls. Build with AppKit/SwiftUI system components first; customize only where it earns its cost.

## How to use this skill

Before writing UI code, do this in order:

1. **Name the user's goal** and the one screen where they start.
2. **Pick the app archetype** (document editor, library browser, canvas, dashboard, utility, settings-only).
3. **Choose entry points** — feature, search, and browse, not just one.
4. **Sketch the hierarchy** — window → sidebar → content → inspector; decide what is a sheet, panel, or separate window.
5. **Map every command** to a menu item, a toolbar/context-menu surface, and a keyboard shortcut.
6. **Define the states** — empty, loading, error, offline, permission, partial.
7. **Build with system components**, then run the review checklist at the end.

If a requirement conflicts with a macOS convention, prefer the convention unless there is a measured reason not to.

---

## 1. Design for how people actually work

| Principle | What it means | macOS implementation |
|---|---|---|
| **Safe exploration** | Users try things when mistakes are cheap. | Undo/redo everywhere, non-destructive edits, Duplicate instead of overwrite, Revert To, autosave versions. |
| **Instant gratification** | Show a result immediately. | Respond in <100 ms; optimistic UI; don't gate reversible actions behind confirmations. |
| **Satisficing** | People pick the first reasonable option, not the best. | Good defaults, recents, search, smart prefill. Don't demand exhaustive configuration. |
| **Changes in midstream** | Goals and context change. | Preserve drafts and selection; allow branching/duplicate; never discard input on navigation. |
| **Deferred choices** | Users don't want to decide everything upfront. | Optional fields, "Decide later", incremental setup, sensible defaults. |
| **Incremental construction** | Complex artifacts are built piece by piece. | Live preview, partial saves, add-row/add-section patterns, no all-or-nothing forms. |
| **Habituation** | Repeated use makes people stop seeing the UI. | Keep locations and shortcuts stable; don't move controls between versions. |
| **Microbreaks** | Waiting breaks attention and memory. | Background long tasks; restore context on return; avoid blocking modal work. |
| **Spatial memory** | People remember *where* things are. | Stable window/panel positions, restored frames, movable inspectors, consistent placement. |
| **Prospective memory** | People need reminders of future actions. | Recents, drafts, badges, "Continue where you left off", completion notifications. |
| **Streamlined repetition** | Experts repeat actions constantly. | Shortcuts, batch operations, duplicate, macros, scriptability, keyboard-first flows. |
| **Keyboard only** | Some users never touch the pointer. | Full keyboard access, logical focus order, visible focus rings, every command in a menu. |
| **Social** | Work is shared and observed. | Share/collaborate affordances, presence, export, permissions that are understandable. |

**Agent implications:** don't ask the user to configure what you can infer; don't block on questions with a safe default; never destroy work to simplify state management.

---

## 2. Pick the app archetype

| Archetype | Use when | macOS shape |
|---|---|---|
| **Document editor** | Users create/save/open files. | `DocumentGroup` / `NSDocument`; one window per document; autosave, Versions, Duplicate, Revert; proxy icon in title bar. |
| **Library / browser** | Large collection, detail per item. | Two- or three-column `NavigationSplitView`; source-list sidebar; table/grid content; inspector. |
| **Canvas + tools** | Direct manipulation of a spatial artifact. | Canvas center stage; floating tool palette; non-modal inspector; zoom/pan; rulers and guides. |
| **Dashboard / monitor** | Glanceable status, many small datasets. | Card grid or small multiples; clear refresh cadence; drill-down on click. |
| **Settings-only / utility** | One job, little content. | `Settings` scene or `MenuBarExtra`; compact window; no document model. |
| **Wizard / setup** | Infrequent, linear, consequential setup. | Sheet with Back/Continue; progress; cancellable; never for routine editing. |
| **Media browser** | Visual assets, previews matter. | Thumbnail grid + preview pane; filmstrip; Quick Look; drag out. |
| **Menu bar utility** | Ambient/quick action. | `MenuBarExtra` / `NSStatusItem`; popover; optional Dock icon (`LSUIElement`). |

### Entry points: offer all three paths

- **Feature** — a prominent, named action for the primary job ("New Project", "Import").
- **Search** — toolbar search field (`⌘F`), scoped and fast, with recent searches.
- **Browse** — sidebar categories, recents, favorites, tags, templates.

A content-rich app with only a browse tree forces users to remember structure. A search-only app hides what is possible.

---

## 3. Navigation and wayfinding

### 3.1 Three maps

- **Global map:** the menu bar. Every command must be discoverable there.
- **Local map:** the sidebar / source list. Shows sections, counts, favorites, tags.
- **You-are-here:** window title, subtitle, breadcrumb or jump bar, selected row.

### 3.2 Depth rules

- Prefer **split view over drill-down**: source list → list → detail, with the hierarchy visible.
- Keep routine tasks within **2–3 levels**. Deeper structures need a path control, jump bar, or search.
- A drill-down is acceptable for homogeneous lists (Mail mailbox → message); always provide Back (`⌘[`) and a visible escape hatch.
- Don't hide primary navigation behind a hamburger icon or a bottom tab bar — both are foreign to macOS.

### 3.3 Modal decision table

| Need | Use | Not |
|---|---|---|
| Collect input scoped to a document | **Sheet** (`.sheet`, `beginSheet`) | App-modal dialog |
| Irreversible/destructive confirmation | **Alert** with explicit verb ("Delete", not "OK") | Sheet with a form |
| Transient options anchored to a control | **Popover** | Separate window |
| Persistent tools/properties | **Inspector / utility panel**, non-modal | Modal dialog |
| App preferences | **Settings window** (`⌘,`) | Modal dialog or sheet |
| Long, optional, or reference content | **Separate window** or tab | Blocking modal |

Rules: sheets must have a clear default and Cancel (`Esc`); alerts only for consequences the user cannot undo; never use a modal to report validation errors.

### 3.4 Progress and waiting

| Duration | Treatment |
|---|---|
| **< 100 ms** | No indicator; instant response. |
| **100 ms – 1 s** | Small spinner or inline activity; keep layout stable. |
| **> 1 s** | Determinate progress if measurable; label the task; allow cancel. |
| **> 2 s** | Prominent progress with cancel and background continuation; never freeze the window. |

- Delay showing a spinner by ~100 ms to avoid flicker on fast operations.
- Never fake progress. If progress is unknown, use indeterminate + status text.
- Put ongoing progress in the toolbar or sidebar so users can keep working.
- On completion, restore focus/context and summarize what changed.

### 3.5 Transitions

- Animate to explain a change, not to decorate: ~200–300 ms, ease-out.
- Respect **Reduce Motion**; provide a cross-fade instead of movement.
- Don't animate every list update; animate insertions/deletions and view-mode changes only.

### 3.6 Escape hatches

Every flow needs: Cancel (`Esc`), Back (`⌘[`), Close (`⌘W`), Undo (`⌘Z`), and a way to return to a known state. If users can get somewhere, they must be able to get back without losing work.

**Deep links:** support URL schemes, Open Recent, and drag-and-drop so a specific document, record, or view can be opened directly — without forcing users to reconstruct navigation by hand.

---

## 4. Layout and hierarchy

### 4.1 Window anatomy

```
┌──────────────────── toolbar / title ────────────────────┐
│ sidebar │            content                 │ inspector │
│ (source │   (table, grid, canvas, form)     │ (details) │
│  list)  │                                   │           │
├──────────────────── status / progress ──────────────────┤
```

- **Visual framework:** consistent chrome and alignment; content sits on a clear grid.
- **Center stage:** the primary content dominates. Give it margins at least **2×** the standard gutter; don't let sidebars and toolbars crowd it.
- **Grid of equals:** peer items get equal weight; don't make one card visually dominant unless it is the primary action.
- **Titled sections / grouped form:** group related controls; use whitespace before borders.
- **Module tabs:** for 2–9 peer views in one region; beyond ~10, use a sidebar or segmented picker.
- **Accordion / collapsible panels:** for secondary detail; remember expanded state.
- **Movable panels:** pro tools may float and dock; persist positions and allow reset.

### 4.2 SwiftUI skeleton

```swift
@main
struct AppMain: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            SidebarCommands()
            ToolbarCommands()
        }

        Settings { SettingsView() }
    }
}

struct RootView: View {
    @State private var selection: Item.ID?
    @State private var search = ""
    @State private var showInspector = true

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) { /* sections + rows */ }
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            DetailView(selection: selection)
                .inspector(isPresented: $showInspector) { InspectorView() }
        }
        .searchable(text: $search, placement: .toolbar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button("New", systemImage: "plus") {} }
            ToolbarItem { Button("Inspector", systemImage: "sidebar.right") { showInspector.toggle() } }
        }
    }
}
```

AppKit equivalents: `NSSplitViewController`, `NSOutlineView` (source list), `NSTableView`, `NSToolbar`, `NSPanel` (inspector), `NSVisualEffectView` (sidebar material).

### 4.3 Spacing and sizing

| Element | Guidance |
|---|---|
| Base grid | 4 pt; use 8 pt increments for layout spacing. |
| Window content margins | 16–20 pt; 20–24 pt for text-heavy views. |
| Sidebar width | 200–320 pt; resizable; remember width. |
| Inspector width | 260–360 pt; collapsible; remember width. |
| Control height | ~22 pt regular; 28–32 pt for prominent buttons. |
| Click target | ≥ 24×24 pt; 28×28 comfortable. 44 pt only for touch/iPad apps. |
| Table row | 24–28 pt compact; 32–40 pt comfortable. |
| Reading text | 45–75 characters, ~10–12 words per line; constrain measure. |
| Toolbar | 28–52 pt tall; ≤ 7 primary items before overflow. |

### 4.4 Window behavior checklist

- [ ] Sensible default size and a real minimum size; content doesn't clip at minimum.
- [ ] Window frame autosaved (`setFrameAutosaveName`, `@SceneStorage`).
- [ ] Zoom button maximizes usefully; full screen (`⌃⌘F`) works.
- [ ] Multiple windows supported for document/multi-project work; Window menu lists them.
- [ ] `⌘W` closes a window; `⌘Q` quits; closing the last window does not quit by default.
- [ ] Restores selection, scroll position, sidebar width, inspector visibility, and expanded sections.
- [ ] State restoration works after relaunch, not just after window close.

---

## 5. Visual style

### 5.1 Color

- Use **semantic/system colors** (`labelColor`, `secondaryLabelColor`, `controlAccentColor`, `Color.primary`, `.tint`), never hard-coded hex for text or chrome.
- Support **Dark Mode**, **Increase Contrast**, and **Differentiate Without Color** automatically.
- Use one accent color for interactive emphasis; reserve red for destructive/error, yellow for warning, green for success — and always pair with text or an icon.
- **10% of men and 1% of women are colorblind.** Never encode meaning by hue alone; add shape, label, position, or pattern.
- Check contrast: 4.5:1 for body text, 3:1 for large text and essential graphics.
- Sidebar and toolbar materials should use system vibrancy; don't paint opaque custom colors over them.

### 5.2 Typography

- Use the **system font** (SF Pro) and semantic text styles: `.largeTitle`, `.title`, `.headline`, `.body`, `.callout`, `.caption`.
- macOS body is ~13 pt; **never below 11 pt** for essential text. Secondary text may be 11 pt.
- Use weight and color for hierarchy before size; avoid more than 3 sizes in one view.
- Support bold text and larger accessibility sizes; don't lock line heights that clip.
- Use tabular/monospaced digits for tables, timers, and aligned numbers.

### 5.3 Density and materials

- macOS is denser than iOS: avoid 44 pt rows and oversized padding in desktop tables.
- Use materials (`.regularMaterial`, sidebar vibrancy) for chrome, not for content cards everywhere.
- Prefer subtle separators and whitespace over heavy borders and shadows.
- Skeuomorphism is optional; clarity and consistency are not. Avoid decorative textures that fight content.

### 5.4 Icons

- Use **SF Symbols** with consistent weight and scale; symbol + label for primary actions.
- Menu bar extras need template images that adapt to light/dark and tint.
- Icon-only toolbar buttons require tooltips (`.help`) and accessibility labels.
- Don't invent icons for standard actions (Add, Delete, Share, Search, Info, Settings).

### 5.5 Motion

- 200–300 ms for view transitions; spring only for direct manipulation.
- Respect Reduce Motion and Reduce Transparency.
- No looping decorative animation in the content area; it steals attention from data.

---

## 6. Lists, tables, and collections

### 6.1 Choose the presentation

| Pattern | Use when | macOS |
|---|---|---|
| **Two-panel selector / split view** | Many items, detail per item, comparison. | `NavigationSplitView`; `NSTableView` + detail. |
| **One-window drilldown** | Homogeneous hierarchy, small screens. | `NavigationStack`; breadcrumb/back. |
| **List inlay** | Detail expands in place, context must stay visible. | `DisclosureGroup`; outline rows. |
| **Cards** | Heterogeneous items with image + metadata. | `LazyVGrid`; `NSCollectionView`. |
| **Thumbnail grid** | Visual assets; recognition beats text. | `LazyVGrid`; adjustable thumbnail size. |
| **Carousel / filmstrip** | Sequential browsing, small set. | Horizontal `ScrollView`; filmstrip in media apps. |
| **Pagination** | Large ordered result sets, page-oriented tasks. | Prefer infinite/virtualized scroll; paginate only when page identity matters. |
| **Jump to item** | Huge alphabetic/numeric list. | Section index, jump bar, `⌘F`; type-select. |
| **Alpha/numeric scroller** | Contacts, fonts, long sorted lists. | Section index alongside list. |
| **New-item row** | Frequent creation inside a list. | Trailing "Add…" row; `⌘N`. |

Elide pagination beyond ~20 pages; offer "Go to page" instead.

### 6.2 Table/list behavior checklist

- [ ] Column headers sort; show sort direction; persist sort.
- [ ] Multi-select with `⌘`-click and `⇧`-click; `⌘A` selects all.
- [ ] Arrow keys move selection; type-select jumps to matching rows.
- [ ] Context menu on rows with the same commands as the menu bar.
- [ ] Drag to reorder or move where meaningful; show drop targets.
- [ ] Inline rename (`Return`) with validation and `Esc` to cancel.
- [ ] Quick Look (`Space`) for previewable items.
- [ ] Empty state, loading state, and "no results" state.
- [ ] Selection and scroll preserved across refresh and window restore.
- [ ] Column widths, visibility, and order persist.
- [ ] Batch actions appear only with a selection and state the count ("Delete 3 Items…").

### 6.3 Large data

- Virtualize rows (`List`, `LazyVStack`, `NSTableView`); never render 10k views.
- Load incrementally; show a footer spinner, not a blocking screen.
- Search should be scoped, debounced, and cancellable; show "Searching…" for slow queries.
- Provide an overview (counts, sections) before detail; don't make users scroll to discover scope.

---

## 7. Commands, menus, and keyboard

### 7.1 The menu bar is the contract

Every command must exist in the menu bar, even if it also appears in a toolbar or context menu.

| Menu | Must contain | Notes |
|---|---|---|
| **App** | About, Settings… (`⌘,`), Services, Hide (`⌘H`), Hide Others (`⌥⌘H`), Show All, Quit (`⌘Q`) | Use "Settings…" (macOS 13+), not "Preferences". |
| **File** | New (`⌘N`), Open (`⌘O`), Open Recent, Close (`⌘W`), Save (`⌘S`), Duplicate (`⇧⌘S`), Rename, Move To, Export, Print (`⌘P`) | Omit irrelevant items; don't disable-and-hide inconsistently. |
| **Edit** | Undo (`⌘Z`), Redo (`⇧⌘Z`), Cut/Copy/Paste, Delete, Select All, Find (`⌘F`), Spelling | Use standard selectors so system features work. |
| **View** | Show/Hide Sidebar, Show/Hide Inspector, view modes, Zoom, Enter Full Screen (`⌃⌘F`) | Alternate views belong here. |
| **Window** | Minimize (`⌘M`), Zoom, Show Previous/Next Tab, Bring All to Front | System adds the window list; don't duplicate it. |
| **Help** | Search field, app help, keyboard shortcuts, release notes, feedback | Never omit Help. |

Rules:
- Use standard names and shortcuts; don't invent alternatives for Cut, Copy, Paste, Save, Undo.
- Menu items must enable/disable correctly with context; never leave a dead item enabled.
- Dynamic labels are allowed ("Undo Typing", "Show 3 Hidden Items") but must remain predictable.
- Destructive items use an ellipsis only when they open a dialog.

### 7.2 Toolbar

- Primary actions only: New, Add, Delete, Share, Search, view switcher, inspector toggle.
- Icon + label for ambiguous actions; tooltips for all icon-only buttons.
- Support toolbar customization and overflow; don't hide every command in overflow.
- Keep toolbar state stable across launches.
- Don't duplicate the entire menu bar in the toolbar.

### 7.3 Context menus

- Use for secondary, repeated, or row-specific actions: Open With, Rename, Duplicate, Reveal in Finder, Copy Link.
- Never make a context menu the *only* home for a critical command.
- Mirror menu bar commands and shortcuts; include separators and destructive items last.

### 7.4 Buttons and dialogs

- One **default** button per view, bound to `Return`; one **Cancel**, bound to `Esc`.
- Label buttons with verbs: "Save", "Delete", "Move", not "OK"/"Yes".
- Destructive buttons are red and never the default; require an explicit choice for irreversible actions.
- Prefer **undo over confirmation** for reversible actions. Confirm only when data is truly lost.
- Disable a button only when the reason is obvious; otherwise explain inline why it's unavailable.
- For long-lived workspaces, use a persistent **action panel** (bottom bar or inspector footer) for the few primary actions; keep it stable as selection changes.

### 7.5 Undo and redo

- Every reversible change registers with `UndoManager` / `NSUndoManager`.
- Support at least **10–12 levels**; group typing into sensible units.
- Name actions ("Undo Move", "Undo Rename") and update the Edit menu.
- Preserve undo across saves; clear it only when the document closes or the model is replaced.
- Undo must restore selection and scroll context, not just data.
- Provide Redo (`⇧⌘Z`) and don't clear the redo stack on unrelated UI events.

### 7.6 Long-running work

- Never block the main thread; use async tasks and show progress.
- Make operations cancellable; `Esc` or a Cancel button stops them cleanly.
- On failure, preserve input and offer Retry; don't discard partial results silently.
- If work continues in the background, show it in the toolbar/sidebar and notify on completion.

### 7.7 Keyboard checklist

- [ ] Every menu command has a shortcut where a convention exists.
- [ ] `Tab`/`Shift-Tab` move focus logically; focus ring is always visible.
- [ ] Full Keyboard Access reaches toolbars, sidebars, tables, and inspectors.
- [ ] `Return` commits, `Esc` cancels, `Space` previews, `Delete` deletes.
- [ ] Arrow keys navigate lists/grids; `⌘↑/↓` jumps to ends where appropriate.
- [ ] No keyboard traps; users can always leave a control or view.
- [ ] Single-key shortcuts only in canvas contexts (tools, nudging), never globally.
- [ ] Shortcuts are discoverable in menus and a Help > Keyboard Shortcuts window.

### 7.8 Automation and macros

- Expose core actions to Shortcuts, AppleScript, and URL schemes where valuable.
- Support batch operations on multi-selection rather than forcing repetition.
- Recordable/repeatable actions should be deterministic and undoable.
- Provide a **command history** for repeated expert workflows (recent commands, replay last action); make replay visible and cancellable.
- Document automation in Help; don't make it the only way to do something.

---

## 8. Complex data

| Technique | Use when | Rules |
|---|---|---|
| **Datatips / tooltips** | Exact values are needed on hover. | Follow the pointer, never cover the data point, dismiss on leave. |
| **Data spotlight** | One subset must stand out. | Dim the rest; keep context visible; allow toggle. |
| **Dynamic queries** | Users explore by filtering continuously. | Update live, debounce heavy work, show active filters as removable chips. |
| **Data brushing** | Linked views should highlight together. | Selection in one view highlights the same records everywhere; clear on click-away. |
| **Multi-Y graph** | Comparing series with different units. | Label axes and units; don't imply correlation; allow series toggle. |
| **Small multiples** | Compare many slices without overlap. | Shared scales, aligned axes, consistent color mapping. |
| **Focus + context** | Detail without losing the whole. | Overview + zoom/pan; show where the detail sits; provide "reset zoom". |

**Preattentive encoding:** position and length are most accurate; color and size are faster but less precise. Use **one or two** encodings per attribute, not five. Never use color alone; pair with shape/label/pattern.

For tables and charts:
- Right-align numbers, use tabular digits, consistent decimals and units.
- Show units in headers, not repeated in every cell.
- Sort nulls and missing values deliberately; label them.
- Provide a table view or accessible summary for chart-only data.
- Don't truncate labels without a tooltip or expansion path.

---

## 9. Forms and settings

### 9.1 Pattern selection

| Pattern | Use when | macOS |
|---|---|---|
| **Forgiving format** | Users type dates, phones, currency in varied ways. | Parse and normalize on commit; show the interpreted value. |
| **Structured format** | Input has known shape (serial, date, range). | Segmented fields, steppers, formatted text fields. |
| **Fill-in-the-blanks** | A natural sentence describes the task. | Inline fields inside a sentence; good for filters and rules. |
| **Input hints** | Users need guidance on expected format. | Persistent helper text below the field; not placeholder-only. |
| **Input prompt** | Example value clarifies the field. | Placeholder as a supplement, never the only label. |
| **Password strength meter** | Creating/changing credentials. | Show strength + requirements; allow show/hide; never block paste. |
| **Autocompletion** | Large known value set. | Debounce, keyboard-navigable, don't steal `Return`, allow free text when valid. |
| **Drop-down chooser** | Complex choice in a small space. | `NSPopUpButton` or popover with list/grid/calendar; clear down-arrow affordance. |
| **List builder** | Select a subset from a large source. | Source + destination columns, Add/Remove, drag, multi-select, search both sides. |
| **Good defaults / smart prefills** | Most users choose the same value or context is known. | Prefill from account, location, recents, clipboard, current selection. |
| **Error messages** | Input is invalid or missing. | Inline, next to the field, plus a top summary for long forms. |

### 9.2 Form layout rules

- **One column** for reading flow; group related fields with titled sections.
- Labels: leading-aligned for scanning, or trailing-aligned for compact settings; be consistent.
- Mark required fields explicitly, or mark optional ones — never leave the convention ambiguous.
- Put units and constraints next to the field ("Max 20 characters", "USD").
- Keep help text visible; don't rely on placeholders that vanish on typing.
- Preserve entered values after validation errors; focus the first invalid field.
- Don't validate mid-keystroke in a way that shows errors before the user finishes; validate on blur or submit, and clear errors as soon as the value becomes valid.
- Long forms: show a summary at the top with links/anchors to each invalid field.

### 9.3 Error message formula

1. **What went wrong** — specific field and problem.
2. **Why** — only if non-obvious.
3. **How to fix it** — concrete action.

Examples: "Zip code must be 5 digits." not "Numeric validation error." "Passwords don't match. Re-enter the confirmation." not "Invalid input."

Never use a modal alert as the only place an error appears; users dismiss it and lose the message.

### 9.4 Settings

- Use the `Settings` scene / `⌘,`; never a modal preferences dialog.
- Organize with toolbar-style tabs for 3–7 groups; use a sidebar for more.
- Apply changes immediately when cheap and reversible; provide Undo or "Reset to Defaults".
- Use OK/Cancel only when applying is expensive or requires a restart; say so before the user commits.
- Label scope: "for this window" vs "for all documents".
- Searchable settings for large apps; deep-link to a specific pane when needed.
- Never hide essential settings behind a defaults command or a config file.

---

## 10. Required states

Design every screen for these, not just the happy path:

| State | Show | Rules |
|---|---|---|
| **First-run empty** | What this view is for + primary action + template/sample. | Never a bare "No items". |
| **Filtered empty** | "No results for ‘X’" + Clear filter / adjust query. | Preserve the query for editing. |
| **Loading** | Stable layout + spinner/skeleton after ~100 ms. | Don't flash spinners for fast loads. |
| **Partial** | What loaded + "Load more"/retry for the rest. | Don't hide successful data behind a global error. |
| **Error** | Inline message + Retry + preserved input. | No data loss; no modal-only errors. |
| **Offline** | Banner/status + queued changes + retry. | Distinguish "saved locally" from "synced". |
| **Permission denied** | Why + button to open the relevant System Settings pane. | Don't loop the user through the same failure. |
| **Destructive** | Explicit verb + consequence + undo where possible. | Never default to destructive. |

---

## 11. Onboarding and help

- Don't gate the app behind a mandatory tour. Let users start; teach in context.
- First-run: offer a sample document/template and one clear primary action.
- Use coach marks once, anchored to the real control, dismissible, and never blocking.
- Empty states are the best onboarding surface: explain + offer the action.
- Provide a Help menu with search, keyboard shortcuts, and troubleshooting.
- "What's New" after updates, dismissible, with a link to details.
- Tooltips for unfamiliar icons; inline hints for non-obvious fields.
- Don't rely on documentation for basic navigation; the UI should teach itself.

---

## 12. Accessibility

- [ ] Every control has an accessibility label, role, and value; icon-only buttons included.
- [ ] VoiceOver order matches visual order; groups have meaningful labels.
- [ ] Full keyboard access; visible focus; no traps.
- [ ] Contrast ≥ 4.5:1 for text, ≥ 3:1 for large text and essential graphics.
- [ ] Meaning never conveyed by color alone.
- [ ] Supports Increase Contrast, Reduce Motion, Reduce Transparency, Differentiate Without Color.
- [ ] Text scales without clipping; no fixed heights that truncate.
- [ ] Charts/tables expose data in accessible form (labels, summaries, table alternative).
- [ ] Custom controls implement `NSAccessibility` / SwiftUI accessibility modifiers, not just visuals.
- [ ] Test with VoiceOver and keyboard only before shipping.

---

## 13. Design system and consistency

Build a system, not one-off screens. Use the atomic hierarchy:

| Level | Definition | macOS/SwiftUI |
|---|---|---|
| **Atoms** | Smallest functional units. | Colors, type styles, spacing tokens, `ButtonStyle`, `LabelStyle`, icons. |
| **Molecules** | 2+ atoms forming a functional unit. | Labeled field, search field + scope, toolbar group, list row. |
| **Organisms** | Molecules combined into a major region. | Sidebar, toolbar, inspector, table with headers, empty-state view. |
| **Templates** | Layout recipes for recurring screen types. | Browser template, document template, settings template, detail template. |
| **Pages** | Templates with real content. | Actual screens; only content varies. |

Rules:
- One component, reused everywhere; variants via style/parameters, not forks.
- Semantic tokens (`Color.accent`, `Spacing.m`, `Typography.body`), not raw values scattered in views.
- Changing a token must propagate everywhere; avoid per-screen overrides.
- Document components in a preview gallery or catalog target.
- Consistency is not rigidity: allow intentional variants, but name and document them.
- A framework is a floor, not a ceiling — customize where it improves the task, not to look different.

---

## 14. Anti-patterns (and what to do instead)

| Anti-pattern | Do instead |
|---|---|
| Bottom tab bar or hamburger menu on macOS | Sidebar + menu bar + toolbar. |
| Critical commands only in a context menu | Menu bar item + shortcut + context menu. |
| Confirmation dialog for every reversible action | Undo + non-destructive default. |
| Modal settings dialog | `Settings` scene with `⌘,`. |
| Alert-based form validation | Inline field errors + top summary. |
| Disabled primary button with no explanation | Inline reason or enable with validation on submit. |
| Hard-coded colors/fonts | Semantic system colors and text styles. |
| Fixed window size or no state restoration | Default/min size, autosaved frame, restored selection. |
| Blocking the main thread | Async work + progress + cancel. |
| Discarding a draft on navigation | Autosave/preserve input; confirm only if truly lost. |
| Resetting scroll/selection on refresh | Preserve identity and position. |
| iOS-sized rows and giant padding | Desktop density (24–32 pt rows). |
| Fake or jumping progress bars | Determinate real progress or indeterminate status. |
| Destructive button as default | Safe default; explicit destructive choice. |
| Icon-only toolbar with no tooltips/labels | Symbol + label, `.help`, accessibility label. |
| Bare "No items" empty state | Explain + primary action + sample. |
| Prefix-only search | Tokenized, fuzzy, scoped search with recents. |
| Restart required but undisclosed | State it before commit, or avoid it. |
| "Are you sure?" on quit with no save path | Autosave, or a save/discard/cancel sheet. |

---

## 15. Review checklist

**Architecture**
- [ ] Archetype and entry points are explicit (feature/search/browse).
- [ ] Document vs library vs utility model is consistent.
- [ ] Multi-window and restoration behavior are defined.

**Navigation**
- [ ] Menu bar exposes every command.
- [ ] Hierarchy is ≤ 3 levels for routine tasks; path/back always available.
- [ ] Modals are used only where appropriate (sheet/alert/popover/panel).
- [ ] Progress, cancel, and escape hatches exist for every long flow.

**Layout**
- [ ] Center stage dominates; margins ≥ 2× gutter.
- [ ] Sidebar/inspector are resizable, collapsible, and remembered.
- [ ] Minimum window size works; no clipping.
- [ ] Spacing follows a 4/8 pt grid; alignment is consistent.

**Visual**
- [ ] Semantic colors; dark mode and high contrast verified.
- [ ] Type scale limited; body ≥ 13 pt; nothing essential below 11 pt.
- [ ] Icons are SF Symbols or consistent custom set; tooltips present.
- [ ] Motion is purposeful and respects Reduce Motion.

**Lists and data**
- [ ] Sorting, multi-select, keyboard navigation, context menus, drag/drop.
- [ ] Selection/scroll preserved; large lists virtualized.
- [ ] Empty/loading/error states designed.
- [ ] Data encodings use ≤ 2 preattentive variables; color never alone.

**Commands**
- [ ] Default/Cancel/destructive button hierarchy is correct.
- [ ] Undo covers every reversible change; ≥ 10 levels; named actions.
- [ ] Shortcuts follow conventions and are discoverable.
- [ ] Long operations are cancellable and non-blocking.

**Forms and settings**
- [ ] Labels persistent; required/optional explicit; units shown.
- [ ] Defaults are helpful and safe (no pre-checked marketing or sensitive fields).
- [ ] Validation is inline, specific, and preserves input.
- [ ] Settings apply immediately or explain why not; reset available.

**Quality**
- [ ] VoiceOver and keyboard-only pass.
- [ ] No anti-patterns from §14 remain.
- [ ] Components come from the design system; no one-off styles.
- [ ] Every screen has first-run, empty, loading, error, and offline behavior.
- [ ] Performance: interactions < 100 ms; no main-thread stalls.

---

## 16. Pattern → macOS API quick reference

| Pattern | SwiftUI | AppKit |
|---|---|---|
| Source list / two-pane | `NavigationSplitView` + `List(selection:)` | `NSOutlineView`, `NSSplitViewController` |
| Three-pane browser | Three-column `NavigationSplitView` | `NSSplitViewController` |
| Inspector | `.inspector(isPresented:)` | `NSPanel`, split view item |
| Toolbar | `.toolbar`, `ToolbarItem` | `NSToolbar`, `NSToolbarItem` |
| Menu commands | `.commands`, `CommandGroup`, `CommandMenu` | `NSMenu`, `NSMenuItem` |
| Settings | `Settings` scene, `SettingsLink` | Settings window controller |
| Sheet | `.sheet` | `beginSheet(_:completionHandler:)` |
| Alert | `.alert` | `NSAlert` |
| Popover | `.popover` | `NSPopover` |
| Table | `Table`, `TableColumn` | `NSTableView` |
| Grid / gallery | `LazyVGrid`, `LazyHGrid` | `NSCollectionView` |
| Outline / disclosure | `OutlineGroup`, `DisclosureGroup` | `NSOutlineView` |
| Search | `.searchable` | `NSSearchField` |
| Token field | custom | `NSTokenField` |
| Path / jump bar | custom | `NSPathControl` |
| Quick Look | `.quickLookPreview` | `QLPreviewPanel` |
| Undo | `UndoManager` environment | `NSUndoManager` |
| Progress | `ProgressView` | `NSProgressIndicator` |
| Charts | Swift Charts | custom / Core Plot |
| Drag and drop | `.draggable`, `.dropDestination` | `NSDraggingSource/Destination` |
| Keyboard shortcut | `.keyboardShortcut` | `keyEquivalent` |
| Focus | `@FocusState` | `NSResponder`, key view loop |
| Accessibility | `.accessibilityLabel`, `.accessibilityValue` | `NSAccessibility` |
| Window restore | `@SceneStorage`, `.defaultSize` | `setFrameAutosaveName` |
| Menu bar extra | `MenuBarExtra` | `NSStatusItem` |
| Document app | `DocumentGroup` | `NSDocument` |
| Tabs | `TabView`, window tabbing | `NSWindow` tabbing |
| Materials | `.background(.regularMaterial)` | `NSVisualEffectView` |
| Symbols | `Image(systemName:)` | `NSImage(systemSymbolName:)` |

---

## Appendix: numbers worth remembering

| Metric | Value |
|---|---|
| Instant feedback | < 100 ms |
| Flow interrupted | > 1 s |
| Attention wanders | > 2 s |
| Spinner threshold | > 1 s (delay ~100 ms to avoid flicker) |
| Determinate progress + cancel | > 2 s |
| Transition duration | 200–300 ms |
| Undo depth | 10–12+ actions |
| Body text | ~13 pt macOS; ≥ 11 pt minimum |
| Line length | 45–75 characters / 10–12 words |
| Spacing grid | 4 pt base, 8 pt layout increments |
| Click target | ≥ 24×24 pt (44 pt only for touch) |
| Table row | 24–28 pt compact / 32–40 pt comfortable |
| Tabs before switching to sidebar | ~10 |
| Pagination elision | ~20 pages |
| Colorblind prevalence | 10% of men, 1% of women |
| Center-stage margin | ≥ 2× standard gutter |
| Text contrast | 4.5:1 body, 3:1 large text |

---

*Source: condensed from Designing Interfaces, 3rd Edition, by Jenifer Tidwell, Charles Brewer, and Aynne Valencia-Brooks (O'Reilly). macOS translations and checklists are adaptations for SwiftUI/AppKit practice.*
