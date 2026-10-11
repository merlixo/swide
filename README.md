# Swide

Sélecteur de projets Cursor pour macOS, piloté au clavier. `⌥ Space` ouvre un panneau en verre au-dessus de tout, sur l'écran où se trouve la souris :

- en haut, les projets récents de Cursor ; la recherche floue couvre tout `~/dev` ;
- en bas, toutes les fenêtres Cursor ouvertes, tous écrans et bureaux confondus, de la plus récente à la plus ancienne, avec l'état de Claude dans chacune.

Au plus 3 fenêtres Cursor : ouvrir un 4ᵉ projet ferme celle utilisée il y a le plus longtemps, sauf si elle est épinglée ou si Claude y travaille. La fenêtre visée est grisée (« Sera fermé ») avant validation.

## Installation

Prérequis : macOS 26, Command Line Tools (Swift 6.2+), Cursor dans `/Applications`.

```sh
scripts/create-signing-cert.sh   # une fois : garde les permissions macOS d'un build à l'autre
scripts/build.sh install         # construit, copie dans ~/Applications et lance
```

Puis, depuis l'icône Swide de la barre de menus (section Configuration) :

1. **Accessibilité** : obligatoire pour déplacer et agrandir les fenêtres Cursor.
2. **Extension Cursor swide-bridge** : signale chaque fenêtre à Swide (dossier, focus) et permet de la fermer.
3. **Hooks Claude Code** : ajoute à `~/.claude/settings.json` les hooks qui remontent l'état de Claude (sauvegarde dans `settings.json.swide-backup`).
4. **Aperçus des fenêtres** (facultatif) : demande la permission Enregistrement de l'écran.

## Clavier

| Touche | Action |
|---|---|
| `⌥ Space` | Ouvrir / fermer Swide |
| lettres | Filtrer les projets |
| `↑ ↓ ← →` | Naviguer |
| `↵` | Ouvrir le projet ou basculer sur la fenêtre |
| `⌘ ↵` | Ouvrir sans fermer de fenêtre |
| `⌘ 1`–`⌘ 9` | Basculer sur la fenêtre n |
| `⌘ ⌫` | Fermer la fenêtre sélectionnée |
| `⌘ P` | Épingler / désépingler la fenêtre sélectionnée |
| `esc` | Effacer la recherche, puis quitter |

## Configuration

`~/.config/swide/config.json`, créé au premier lancement (relu à chaque ouverture du panneau, sauf `hotkey` qui demande un relancement) :

```json
{
  "hotkey": "option+space",
  "maxWindows": 3,
  "searchRoot": "~/dev",
  "protect": { "pinned": true, "claudeWorking": true }
}
```

## Fonctionnement

| Besoin | Source |
|---|---|
| Projets récents | `state.vscdb` de Cursor (`history.recentlyOpenedPathsList`) |
| Projets de `~/dev` | Scan : enfants directs des dossiers de groupe, dossiers de premier niveau qui sont des dépôts git ou sans sous-dossier, dépôts git jusqu'à 4 niveaux |
| Fenêtres ouvertes | Extension `bridge/` : un fichier JSON par fenêtre dans `~/Library/Application Support/Swide/windows`, un socket Unix pour `close` |
| État de Claude | `Swide --claude-hook`, appelé par les hooks Claude Code, écrit `~/Library/Application Support/Swide/claude/<session>.json` |
| Placement | `NSWorkspace.open` sur le dossier (Cursor focalise la fenêtre existante), puis API d'accessibilité pour agrandir sur l'écran actif |

## Développement

```sh
scripts/test.sh                       # tests de SwideCore (Swift Testing)
swift build && .build/debug/Swide --snapshot /tmp/panel.png   # rendu du panneau sans permissions
```

- `Sources/SwideCore` : logique pure (recherche, index des projets, règle des fenêtres, état de Claude).
- `Sources/Swide` : app AppKit/SwiftUI (raccourci, panneau, placement des fenêtres, intégrations).
- `bridge/` : extension Cursor, en JavaScript sans dépendance, empaquetée par `scripts/package-bridge.sh`.
