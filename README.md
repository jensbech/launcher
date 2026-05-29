# Sift

A minimal Spotlight-style macOS app launcher for apps only. ⌘Space opens a frosted search
panel that fuzzy-searches your apps. Every installed app is searchable by
default; disable the ones you don't want in Settings. Runs as a menu bar agent.

![Sift search panel showing fuzzy matches with highlighted letters](docs/screenshot.png)

This app is fully vibe coded.

## Requirements

- macOS 14+
- Swift toolchain (Command Line Tools is enough — no full Xcode needed)

## Build

```bash
just build
open build/Sift.app
# or: just run
```

All tasks run through [`just`](https://github.com/casey/just); see `just`
for the full list. The recipes wrap the scripts in `scripts/`, which are
also safe to invoke directly from any working directory.

## First-run setup

macOS uses ⌘Space for Spotlight by default. To let Sift own ⌘Space, open
**System Settings → Keyboard → Keyboard Shortcuts → Spotlight** and turn off
"Show Spotlight search" (or change its shortcut). Sift shows a reminder on
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
just icon   # rebuilds Resources/Sift.icns from the SVG
```

`just build` regenerates it automatically if missing.

## Configuration

Preferences (the set of *disabled* apps + launch-at-login) are stored at
`~/Library/Application Support/Sift/config.json`. An empty/missing file
means every app is searchable.

## Development

```bash
just test       # run SiftCore unit tests
just dev        # run unbundled (launch-at-login needs the bundled .app)
```
