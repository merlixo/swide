# Swide

Keyboard-driven project switcher for Cursor on macOS. `⌥ Space` opens a glass panel above everything, on the screen under the mouse pointer:

- top: recent Cursor projects; fuzzy search covers all of `~/dev`;
- bottom: every open Cursor window, across all screens and desktops, most recently used first, with the Claude status of each.

At most 3 Cursor windows: opening a 4th project closes the least recently used one, unless it is pinned or Claude is working in it. The window about to close is greyed out ("Sera fermé") before you confirm.

The UI is in French.

## Installation

Requirements: macOS 26, Command Line Tools (Swift 6.2+), Cursor in `/Applications`.

```sh
scripts/create-signing-cert.sh   # once: keeps macOS permissions across rebuilds
scripts/build.sh install         # builds, copies to ~/Applications and launches
```

Then, from the Swide menu bar icon (Configuration section):

1. **Accessibility**: required to move and maximize Cursor windows.
2. **Cursor extension swide-bridge**: reports each window to Swide (folder, focus) and lets Swide close it.
3. **Claude Code hooks**: adds the hooks that report Claude's status to `~/.claude/settings.json` (backup in `settings.json.swide-backup`).
4. **Window previews** (optional): requests the Screen Recording permission.

## Keyboard

| Key | Action |
|---|---|
| `⌥ Space` | Open / close Swide |
| letters | Filter projects |
| `↑ ↓ ← →` | Navigate |
| `↵` | Open the project or switch to the window |
| `⌘ ↵` | Open without closing any window |
| `⌘ 1`–`⌘ 9` | Switch to window n |
| `⌘ ⌫` | Close the selected window |
| `⌘ P` | Pin / unpin the selected window |
| `esc` | Clear the search, then dismiss |

## Configuration

`~/.config/swide/config.json`, created on first launch. It is re-read every time the panel opens, except `hotkey`, which needs a relaunch:

```json
{
  "hotkey": "option+space",
  "maxWindows": 3,
  "searchRoot": "~/dev",
  "protect": { "pinned": true, "claudeWorking": true }
}
```

## How it works

| Need | Source |
|---|---|
| Recent projects | Cursor's `state.vscdb` (`history.recentlyOpenedPathsList`) |
| Projects in `~/dev` | Scan: direct children of group folders, top-level folders that are git repos or have no subfolders, git repos up to 4 levels deep |
| Open windows | `bridge/` extension: one JSON file per window in `~/Library/Application Support/Swide/windows`, a Unix socket for `close` |
| Claude status | `Swide --claude-hook`, called by Claude Code hooks, writes `~/Library/Application Support/Swide/claude/<session>.json` |
| Placement | `NSWorkspace.open` on the folder (Cursor focuses the existing window), then the Accessibility API maximizes it on the active screen |

## Development

```sh
scripts/test.sh                       # SwideCore tests (Swift Testing)
swift build && .build/debug/Swide --snapshot /tmp/panel.png   # render the panel without permissions
```

- `Sources/SwideCore`: pure logic (search, project index, window rule, Claude status).
- `Sources/Swide`: AppKit/SwiftUI app (hotkey, panel, window placement, integrations).
- `bridge/`: Cursor extension, dependency-free JavaScript, packaged by `scripts/package-bridge.sh`.
