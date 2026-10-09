# mango-fed

My [mangowm](https://github.com/LGFae/swww/wiki) / Wayland setup on Fedora 44,
based on "Just a guy linux" (mangowc) for Debian, adjusted for Fedora: ghostty
terminal, superfile file manager, Firefox browser.

The live files are tracked in place — git root is `~/`, and `.gitignore`
whitelists exactly the paths below.

## What's tracked

| Path | What it is |
|------|-----------|
| `.config/mango` | mangowm compositor config |
| `.config/ghostty` | terminal theme (follows the wallpaper) |
| `.config/fastfetch` | system info config |
| `.config/fish` | fish shell config |
| `.zshrc` / `.bashrc` | shell configs |

### `.config/mango`

- `config.conf` — keybinds, workspace rules, autostart.
- `quickshell/` — the bar (a quickshell shell): tags, layout picker, media,
  weather, network, clipboard, screenshots, volume, tray, and the command
  center (Fedora logo → app launcher / wallpaper picker).
- `quickshell-lock/` — the lock screen shell.
- `quickshell-network/` — the network popup shell.
- `polybar/colors.ini` — the color palette. The bar's `Theme.qml` and
  `scripts/wallpaper-theme` read it, and it is rewritten on every wallpaper
  change so the whole theme (including ghostty, below) recolors with no restart.
  No polybar process runs — it is purely the shared palette file.
- `rofi/`, `dunst/`, `swappy/` — menus, notifications, screenshots.
- `scripts/` — `bar`, `wallpaper-theme`, `mango-reload`, `launcher`, `lock`,
  `screenshot`, `power`, etc.

### Wallpaper theming

Picking a wallpaper (Super+Shift+p) runs `scripts/wallpaper-theme`, which
writes `polybar/colors.ini` and `ghostty/wallpaper.conf` (a ghostty palette),
then `pkill -USR2 -x ghostty` reloads the terminal. The bar recolors itself by
watching the palette file.

## Fedora vs the Debian original

- Default terminal: `ghostty` (Super+Return opens it; `Super+w` scratchpad).
- File manager: `superfile` (`ghostty -e spf`).
- Browser: `firefox` (+ `--private-window` for incognito).
- Launcher logo: Fedora (`U+F30A`) instead of the Debian swirl.
- Nothing here runs the mangowc polybar binary itself.