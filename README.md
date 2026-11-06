# Swide

Keyboard-driven project switcher for Cursor or VS Code on macOS. `⌥ Space` opens a glass panel above everything, on the screen under the mouse pointer:

- top: recent projects of the IDE, even before it has started; fuzzy search covers all of `~/dev`;
- bottom: every open IDE window, across all screens and desktops, most recently used first, with the Claude status of each.

The project opens on the screen where the panel was opened, whatever screen it was on before.

At most 3 IDE windows: opening a 4th project closes the least recently used one, unless it is pinned or Claude is working in it. The window about to close is greyed out ("Sera fermé") before you confirm.

The UI is in French.

## Installation

Requirements: macOS 26, Command Line Tools (Swift 6.2+), Cursor or VS Code.

```sh
scripts/create-signing-cert.sh   # once: keeps macOS permissions across rebuilds
scripts/build.sh install         # builds, copies to ~/Applications and launches
```

On first launch, Swide turns on launch at login. Turn it off from the menu (Lancer à la connexion) and it stays off.

Then, from the Swide menu (menu bar icon, or ⚙︎ in the panel: the icon can hide behind the notch):

- **IDE**: Cursor (default) or VS Code, also switchable from the panel's search bar. Only the chosen IDE's windows and recent projects are shown.

Configuration section:

1. **Accessibility**: required to move and maximize IDE windows.
2. **swide-bridge extension**: installed in the chosen IDE (once per IDE); reports each window to Swide (folder, focus) and lets Swide close it.
3. **Claude Code hooks**: adds the hooks that report Claude's status to `~/.claude/settings.json` (backup in `settings.json.swide-backup`).
4. **Window previews** (optional): requests the Screen Recording permission.

## Keyboard

| Key | Action |
|---|---|
| `⌥ Space` | Open / close Swide |
| letters | Filter projects |
| `↑ ↓ ← →` | Navigate; the selection opens by itself after `autoOpenDelay` (a bar fills up meanwhile) |
| `space` | Same as `→` |
| `↵` | Open right away |
| `⌘ ↵` | Open without closing any window |
| `⌘ 1`–`⌘ 9` | Switch to window n |
| `⌘ ⌫` | Close the selected window |
| `⌘ P` | Pin / unpin the selected window |
| `esc` | Clear the search, then dismiss |

Mouse: hovering selects, releasing the button opens. Press, slide to another tile and release to open that one; release outside the tiles to cancel. `⌘`-click opens without closing any window.

## Configuration

`~/.config/swide/config.json`, created on first launch. It is re-read every time the panel opens, except `hotkey`, which needs a relaunch:

```json
{
  "hotkey": "option+space",
  "ide": "cursor",
  "autoOpenDelay": 0.8,
  "maxWindows": 3,
  "searchRoot": "~/dev",
  "protect": { "pinned": true, "claudeWorking": true }
}
```

- `ide`: `cursor` or `vscode`; also set from the menu.
- `autoOpenDelay`: seconds before a keyboard selection opens by itself; `0` waits for `↵`.

## How it works

| Need | Source |
|---|---|
| Recent projects | The IDE's `state.vscdb` (`history.recentlyOpenedPathsList`), opened `immutable` when the IDE is closed; else Swide's own history |
| Projects in `~/dev` | Scan: direct children of group folders, top-level folders that are git repos or have no subfolders, git repos up to 4 levels deep |
| Open windows | `bridge/` extension: one JSON file per window in `~/Library/Application Support/Swide/windows`, a Unix socket for `close` |
| Claude status | `Swide --claude-hook`, called by Claude Code hooks, writes `~/Library/Application Support/Swide/claude/<session>.json` |
| Placement | `NSWorkspace.open` on the folder (the IDE focuses the existing window), then the Accessibility API maximizes it on the panel's screen, re-applied if the Space switch undoes it |

## Development

```sh
scripts/test.sh                       # SwideCore tests (Swift Testing)
swift build && .build/debug/Swide --snapshot /tmp/panel.png   # render the panel without permissions
```

- `Sources/SwideCore`: pure logic (search, project index, window rule, Claude status).
- `Sources/Swide`: AppKit/SwiftUI app (hotkey, panel, window placement, integrations).
- `bridge/`: Cursor / VS Code extension, dependency-free JavaScript, packaged by `scripts/package-bridge.sh`.
