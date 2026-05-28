# Sift — Design Spec

**Date:** 2026-05-27
**Status:** Approved

## Summary

A minimal, pretty macOS app launcher in the style of Spotlight. It runs as a
background agent (no Dock icon), pops up a frosted search overlay on **⌘Space**,
fuzzy-searches a **hand-curated set of apps**, and launches the selected app.
Curation and preferences live in a Settings window reached from a menu bar icon.

The defining constraint vs. Spotlight: it searches **only apps the user has
explicitly enabled** — nothing else (no files, web, calculator, etc.).

## Goals

- ⌘Space global hotkey toggles the launcher (replacing Apple Spotlight, which
  the user disables once in System Settings).
- Fuzzy-finder search over a curated app list; live results, keyboard-driven.
- Classic Spotlight visual style: dark frosted ~560pt panel, icon + name rows,
  blue accent on the selected row.
- Settings window: list all installed apps with per-app enable toggles + filter.
- Launch-at-login toggle.
- Menu bar icon for Settings / Quit.

## Non-Goals (YAGNI)

- File / web / calculator / contacts search or any non-app result types.
- Plugins or extensibility.
- Theming/customization beyond the chosen Classic look.
- Multi-monitor positioning logic beyond "main screen."

## Technical Approach

Environment: Swift 6.2.3, macOS 26.5, **Command Line Tools only (no full Xcode)**.

- **Build with Swift Package Manager** (executable target), packaged into a
  `.app` bundle by a build script. Avoids needing full Xcode.
- **AppKit shell + SwiftUI views.** AppKit owns the borderless floating panel,
  global hotkey, menu bar agent, and app lifecycle. SwiftUI (via `NSHostingView`)
  renders the search UI and Settings.
- **Global hotkey via Carbon `RegisterEventHotKey`** — fires for ⌘Space with **no
  Accessibility permission prompt** (unlike `CGEventTap`). User disables Apple's
  Spotlight ⌘Space binding so ours takes effect.
- **Launch at login via `SMAppService.mainApp`** (macOS 13+).
- **Ad-hoc code signing** (`codesign --sign -`) — runs on the user's own machine,
  no notarization needed.

## Components

1. **App agent** — `LSUIElement = true` (no Dock icon). `NSStatusItem` menu bar
   icon with *Settings…* and *Quit* menu items.
2. **HotkeyManager** — registers ⌘Space via `RegisterEventHotKey`; toggles the
   launcher panel show/hide.
3. **SiftPanel** — borderless, non-activating `NSPanel`
   (`.nonactivatingPanel`, `level = .floating`), centered horizontally in the
   upper third of the main screen. `NSVisualEffectView` frosted dark background,
   rounded corners, soft shadow. Hosts the SwiftUI search view. Dismisses on
   **Esc** or on resignKey (focus loss).
4. **AppIndex** — scans `/Applications`, `/System/Applications`,
   `/System/Applications/Utilities`, `/Applications/Utilities`, and
   `~/Applications`. For each `.app`: display name, path, bundle ID, and real
   icon (`NSWorkspace.shared.icon(forFile:)`). Exposes the **enabled** subset to
   search; exposes the full set to Settings. Refreshes on each panel open.
5. **FuzzyMatcher** — subsequence fuzzy scoring. Higher scores for contiguous
   runs, prefix matches, and word-boundary hits; tie-break alphabetical. Returns
   ranked enabled apps for a query.
6. **SettingsView** (SwiftUI) — scrollable list of all installed apps with a
   filter box and a toggle per app. Includes a **Launch at login** toggle.
   Changes persist immediately.
7. **Store** — persists enabled app set (by bundle ID) + prefs as JSON in
   `~/Library/Application Support/Sift/config.json`. Human-inspectable.
8. **Build script** — assembles the `.app`: writes `Info.plist` (with
   `LSUIElement`), copies the SwiftPM binary into `Contents/MacOS`, sets up
   `Contents/Resources`, ad-hoc signs the bundle.

## Data Flow

```
⌘Space
  → HotkeyManager toggles SiftPanel
  → panel appears with empty field, focused
  → user types
  → FuzzyMatcher filters enabled AppIndex
  → SwiftUI results list updates live (first row highlighted)
  → ↑/↓ moves selection; Enter or click launches
  → NSWorkspace.shared.open(appURL)
  → panel hides
```

Settings flow:

```
menu bar icon → Settings… → SettingsView window
  → toggles update Store (enabled bundle IDs, launchAtLogin)
  → Store writes config.json; SMAppService register/unregister on login toggle
```

## UI Details (Classic Spotlight)

- ~560pt wide dark frosted panel, rounded corners, soft drop shadow.
- Top row: magnifier glyph + large light-weight text field, generous padding.
- Hairline divider, then results list: each row = real app icon (~32pt) + name.
  Selected row highlighted with a blue accent fill. No secondary labels.
- Empty query → no results shown (clean field), per Spotlight behavior.

## Error / Edge Handling

- No matches → empty list, no error chrome.
- App moved/deleted since indexing → on launch failure, refresh index and hide
  panel rather than showing an error.
- AppIndex refresh on each open keeps newly installed apps current at low cost.
- Hotkey registration failure → log via menu bar (e.g., tooltip / disabled state)
  rather than crashing.

## Persistence Schema (config.json)

```json
{
  "enabledBundleIDs": ["com.apple.Safari", "com.figma.Desktop"],
  "launchAtLogin": false
}
```

## Open Onboarding Note

First run: app cannot auto-disable Apple's Spotlight shortcut. Surface a short
one-time hint (menu bar or first Settings open) telling the user to remap/disable
System Settings → Keyboard → Keyboard Shortcuts → Spotlight → ⌘Space so the
launcher's ⌘Space wins.
