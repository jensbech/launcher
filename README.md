# Launcher

A minimal Spotlight-style macOS app launcher for apps only. ⌘Space opens a frosted search
panel that fuzzy-searches your apps. Every installed app is searchable by
default; disable the ones you don't want in Settings. Runs as a menu bar agent.

![Launcher search panel showing fuzzy matches with highlighted letters](docs/screenshot.png)

This app is fully vibe coded.

## Requirements

- macOS 14+
- Swift toolchain (Command Line Tools is enough — no full Xcode needed)

## Build

```bash
./scripts/build-app.sh
open build/Launcher.app
```

## First-run setup

macOS uses ⌘Space for Spotlight by default. To let Launcher own ⌘Space, open
**System Settings → Keyboard → Keyboard Shortcuts → Spotlight** and turn off
"Show Spotlight search" (or change its shortcut). Launcher shows a reminder on
first launch.

## Usage

- **⌘Space** — open / close the launcher
- Type to fuzzy-search your apps
- **↑ / ↓** — move selection, **Enter** — launch, **Esc** — dismiss
- Menu bar icon → **Settings…** — all apps are enabled by default; turn off any
  you don't want searchable, and toggle launch at login

## App icon

The icon is generated from `Resources/AppIcon.svg`:

```bash
./scripts/make-icon.sh   # rebuilds Resources/Launcher.icns from the SVG
```

`build-app.sh` regenerates it automatically if missing.

## Configuration

Preferences (the set of *disabled* apps + launch-at-login) are stored at
`~/Library/Application Support/Launcher/config.json`. An empty/missing file
means every app is searchable.

## Development

```bash
./scripts/test.sh   # run LauncherCore unit tests
swift run Launcher  # run unbundled (launch-at-login needs the bundled .app)
```
