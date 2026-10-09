# 🥭 mango-fed

![Made for Fedora](https://img.shields.io/badge/Made%20for-Fedora%2044-294172?style=for-the-badge&logo=fedora&logoColor=white)
![Mango](https://img.shields.io/badge/Mango-Wayland-5294E2?style=for-the-badge&logo=wayland&logoColor=white)
![Ghostty](https://img.shields.io/badge/Terminal-Ghostty-0b1021?style=for-the-badge)

A mangowc-style rice for Fedora 44: mango as the compositor, quickshell as the
bar, ghostty as the terminal, superfile as the file manager, Firefox as the
browser. This is the *mangowc-setup* idea — from
[JustAGuy Linux's Debian setup](https://justaguy.dev/drew/mangowc-setup) —
ported to Fedora, where the newer mango ships in the
[Terra](https://terra.fyralabs.com) repo.

This repository tracks the **live config files in place** — git root is `~/`,
and `.gitignore` whitelists exactly what's below. No copies, no symlinks: edit
in the session, commit from home.

---

## 🤔 What is Mango?

[Mango](https://github.com/mangowm/mango) is a Wayland compositor built on
dwl — dwm's model, brought to Wayland. Tags instead of workspaces. Master and
stack, with a dozen other layouts a keypress away. A flat `key=value` config
that reloads while you watch.

Then it adds the part dwm never had: window animations, blur, shadows and
rounded corners, courtesy of [scenefx](https://github.com/wlrfx/scenefx). The
Fedora build pulls these in directly. Think **dwm's brain with Hyprland's
face**, in a few thousand lines of C, and no Hyprland.

---

## 🚀 Installation

Fedora 44 with the [Terra](https://terra.fyralabs.com) repo added:

```bash
sudo dnf install mango          # the compositor
sudo dnf install quickshell rofi dunst grim slurp swappy \
                 cliphist wl-clipboard swayidle wlopm \
                 xdg-desktop-portal-wlr xdg-desktop-portal-gtk \
                 wlr-randr brightnessctl power-profiles-daemon wlsunset btop \
                 ghostty fastfetch lxpolkit playerctl
```

`awww` (the wallpaper daemon) isn't packaged for Fedora yet; build it the way
it ships:

```bash
sudo dnf install cargo gcc
cargo install --git https://codeberg.org/LGFae/awww awww-daemon
sudo install -Dm755 ~/.cargo/bin/awww /usr/local/bin/awww
sudo install -Dm755 ~/.cargo/bin/awww-daemon /usr/local/bin/awww-daemon
```

File manager is `spf` (superfile), the browser is `firefox`, and `helium` is
the secondary browser. Then clone this repo's contents into `~/` and pick
**Mango** at the login screen. `Super + Shift + P` picks your first wallpaper,
which regenerates the whole colour theme.

> ⚠️ **NVIDIA: untested.** This config has only been run on AMD hardware.
> scenefx — blur, shadows, rounded corners — is unverified on the proprietary
> driver. Virtual machines run, but blur and animations crawl without a real
> GPU; not a supported target.

---

## 📦 What's in the Repo

Mango config, plus the session-local configs that follow its theme:

| Path                      | Purpose                                                        |
|---------------------------|----------------------------------------------------------------|
| `.config/mango`           | compositor, bar, scripts, themes                               |
| `.config/ghostty`         | terminal config + the wallpaper-derived palette include        |
| `.config/fastfetch`       | "About this system" in the launcher                            |
| `.config/fish`            | fish shell                                                     |
| `.zshrc`, `.bashrc`       | shell configs                                                  |

Everything else lives under `.config/mango`:

| Component                     | Purpose                                   |
|-------------------------------|-------------------------------------------|
| `mango` (Terra)               | The compositor — the current Fedora build  |
| `quickshell`                  | The bar and every popup                    |
| `awww`                        | Wallpaper daemon — wallpapers wipe in      |
| `ghostty`                     | Terminal (wallpaper-themed palette)        |
| `dunst`                       | Notifications (layer-shell native)         |
| `grim` + `slurp`              | Screenshots                                |
| `swappy`                      | Screenshot annotate (arrows, text, blur)   |
| `cliphist` + `wl-clipboard`   | Clipboard history                          |
| `swayidle` + `wlopm`          | Monitor power-off after 15 min idle        |
| `rofi`                        | Launcher / power menu when the bar is down |
| `wlr-randr`                   | The Displays card                          |
| `playerctl`                   | Media keys                                 |
| `btop`                        | The metrics card's full view               |
| `fastfetch`                   | The launcher's "About this system"         |

---

## 📊 The Bar

The quickshell shell, with a mango backend. Tags, occupancy, urgency, focused
title and layout come from a single `mmsg watch` stream — no polling, no patch
— and clicks go back through `mmsg dispatch`.

| Module      | Left click               | Right click             | Scroll         |
|-------------|--------------------------|-------------------------|----------------|
| Launcher    | app launcher             | wallpaper picker        | —              |
| Tags        | view                     | —                       | cycle tags     |
| Layout      | layout + tweaks picker   | (empty bar: same)       | cycle layouts  |
| Media       | play / pause             | now-playing popup       | prev / next    |
| Weather     | 3-day forecast + radar   | location / units        | —              |
| CPU / RAM   | meters, temperatures, disks, disk activity, top programs | btop | — |
| Volume      | volume popup: output + picker, microphone + live meter, per-app volume, pavucontrol | mute | ±2% |
| Network     | network app: your connection + ping/speed/IP, VPN, known & other Wi-Fi, Bluetooth (the login page while it says "sign in") | nm-connection-editor | —  |
| Clock       | calendar                 | —                       | —              |
| Screenshot  | region                   | full screen             | —              |
| Commands    | command menu             | —                       | —              |

The **layout picker** shows all the mango layouts as glyph tiles, plus live
sliders for gaps, border width, master width and master count, toggles for
blur, shadows and animations, an unfocused-window opacity slider (they all
change under your cursor and stick), the bar's own height and scale, and
popup size. The **command menu** (far right) is in sections: **Batteries** —
laptop, wireless mice, keyboards and headsets, with a low-battery warning and
power saver switched on by itself when a laptop drops to 20%; **Quick
settings** — power profile, keep awake, microphone, night light, do not
disturb, Bluetooth and a focus timer; **System** — notifications, check
updates, displays, keybindings, restart bar, power menu.

**Displays** draws your outputs on a stage: drag to arrange, pick resolution,
refresh rate, scale, rotation and variable refresh per output, switch one
off, identify them. Every change is a trial: keep it within 15 seconds or it
reverts, so a mode the monitor can't show never leaves you blind.

**Lock screen** (`Super + Ctrl + L`, the power menu, the launcher's Lock
screen): quickshell again, through the session-lock protocol and PAM — no
swaylock or gtklock. The background is Matrix rain in the wallpaper's accent
colour or the wallpaper blurred; "Lock style" in the command menu switches.
"Lock on idle" locks 30 seconds before the 15-minute screen-off.

Details in [`config/quickshell/README.md`](config/quickshell/README.md).

---

## 🎨 Wallpaper-Driven Theming

`Super + Shift + P` opens the wallpaper picker. Pick an image and the desktop
re-colors itself from it: the bar, rofi, dunst, ghostty and mango's own border
colors — then the new wallpaper wipes across the screen. The palette is
extracted right in the picker; nothing to configure. Wallpapers live in
`~/.wallpapers/` (any depth), drop in your own and they show up next time you
open it.

---

## 🔑 Keybindings Overview

Super is the mod key. Same muscle memory as the other setups.

| Key Combo              | Action                                |
|------------------------|----------------------------------------|
| `Super + Return`       | Terminal (ghostty)                     |
| `Super + \``           | Drop-down terminal (scratchpad)        |
| `Super + Space`        | App launcher                           |
| `Super + /`            | Keybind cheatsheet                     |
| `Super + Ctrl + L`     | Lock screen                            |
| `Super + Q`            | Close window                           |
| `Super + Shift + Q`    | Quit mango                             |
| `Super + Shift + R`    | Reload config (live)                   |
| `Super + X`            | Power menu                             |
| `Super + B` / `Super + Shift + B` | Firefox / Firefox private   |
| `Super + C` / `Super + F` / `Super + E` | Helium / superfile / Geany |
| `Super + D` / `Super + G` / `Super + O` | Discord / GIMP / OBS, each on its home tag (8 / 9 / 10) |
| `Super + Shift + Space`| Toggle floating                        |
| `Super + Shift + F`    | Fullscreen                             |
| `Super + T` / `Super + W` | Cycle layouts / Monocle             |
| `Super + Tab`          | Overview of every window               |
| `Alt + Tab`            | Next window                            |
| `Super + H/J/K/L` or arrows | Focus window                      |
| `Super + Shift + H/J/K/L` or arrows | Swap window               |
| `Super + Ctrl + ←/→`   | Master width                           |
| `Super + Ctrl + ↑/↓`   | Master count                           |
| `Super + , / .`        | Focus previous / next monitor          |
| `Super + Shift + , / .`| Send window to previous / next monitor |
| `Super + scroll`       | Walk the tags                          |
| `Super + 1–9/0/-/=`    | View tag 1–12                          |
| `Super + Shift + 1–9/0/-/=` | Send window to tag 1–12           |
| `Super + Shift + P`    | Wallpaper picker                       |
| `Super + Shift + M`    | Command menu                           |
| `Super + Shift + N`    | Network app                            |
| `Super + Shift + T`    | Layout / tweaks picker                 |
| `Super + S` / `Super + Shift + S` | Screenshot full / region (to `~/Screenshots`); `Print` / `Shift + Print` too |
| `Super + Ctrl + S` / `Ctrl + Print` | Screenshot region to the clipboard |
| `Super + Alt + S`      | Screenshot region, annotate in swappy  |

`Super + /` opens the keybinds popup: every bind in `config.conf`, grouped by
the config's `# --- section ---` headers. Type to filter; click a bind to open
`config.conf` in geany at that line. The comment line right above a bind is
its label. Mouse, scroll and touchpad binds are listed too.

**Touchpad:** three fingers swipe through the tags, three up for the overview;
four fingers carry the focused window along. The bottom-left hot corner opens
the overview too.

**Effects:** shadows sit under floating windows and the bar's popups. Blur is
off by default; turn it on in the layout picker and it frosts what's behind
those popups. Tiled windows stay flat and opaque so it's quick on integrated
graphics. Every one of these is a toggle in the picker.

---

## 📂 Configuration Files

```
~/.config/mango/
├── config.conf           # everything: look, input, layouts, autostart, binds, rules
├── theme.conf            # border colors, written by the wallpaper picker (sourced)
├── mango-gaps, mango-effects  # picker state, re-applied by the bar on start
├── env                   # session environment, sourced at login
├── ghostty/              # session-local ghostty theme (wallpaper.conf), see below
├── scripts/
│   ├── bar               # quickshell helper: restart | log | ipc …
│   ├── mango-ipc         # mmsg wrapper that finds the socket
│   ├── wallpaper-theme   # the theming engine
│   ├── screenshot        # grim/slurp: full | region | copy | edit
│   ├── changevolume      # volume + notifications
│   ├── keybinds          # config.conf's binds for the keybinds popup
│   ├── procs             # /proc snapshot for the metrics card
│   ├── sysinfo           # disks, disk activity and temperatures for it
│   ├── displays          # wlr-randr for the Displays card: list | save | apply | forget
│   ├── radar             # map + rain tiles for the weather card's radar
│   ├── launcher          # opens the app grid (rofi if the bar is down)
│   ├── lock              # the lock screen (quickshell-lock) and its style
│   ├── idle              # swayidle policy: screen off, optional lock
│   ├── power / network
├── quickshell/           # the bar (see its README)
├── quickshell-network/   # the network app (its own qs instance)
├── quickshell-lock/      # the lock screen (its own qs instance)
├── rofi/                 # config / power .rasi (colors theme-managed)
├── dunst/                # dunstrc (theme-managed)
├── polybar/colors.ini    # the live palette the bar watches (name is historical)
```

Wallpapers aren't in the repo: they live at `~/.wallpapers/`, scanned
recursively by the picker.

---

## 🖥️ Monitors, Scaling, Refresh Rate

Nothing to configure for most setups: mango picks each monitor's preferred
mode (normally its highest refresh rate) at scale 1. When you need more, open
**Displays** from the command menu: resolution, refresh, scale and rotation
per monitor, drag to arrange, 15-second trial before a change is kept. What
you keep is remembered and comes back at login and on hotplug. The hand-edited
route still works: one `monitorrule` line per output in `config.conf` — two
commented templates are waiting in the outputs section, and `wlr-randr` lists
the names and modes. Tearing is allowed for fullscreen clients that ask for it
(games), nothing else.

Every monitor gets its own bar, showing its own tags and title; a popup opened
from the keyboard appears on the monitor that has focus.

---

## 🐱 Ghostty Is Session-Themed

Ghostty has no session-local config directory the way `KITTY_CONFIG_DIRECTORY`
worked — on this setup it always reads `~/.config/ghostty`, whose
`config.ghostty` ends with:

```
config-file = ~/.config/mango/ghostty/wallpaper.conf
```

`wallpaper-theme` rewrites that file (a full ghostty palette) on every
wallpaper pick, then `pkill -USR2 -x ghostty` reloads already-running
terminals. So every ghostty this session spawns carries the wallpaper's
palette without touching any global config.

---

## 🔢 Why 12 Tags?

The config ships the twelve-tag bind set from the other setups on
`Super + 1–9, 0, -, =`. The bar doesn't hardcode a count — `Wm.qml` reads the
compositor's tag list and draws one pill per tag, so it just follows whatever
the Fedora mango build provides.

---

## 📌 Mango on Fedora: Terra, Not Pinned

The Debian setup pins mangowc 0.14.4 because Debian 13's wlroots 0.18 forces
it. Fedora has no such constraint: Terra's repo builds current mango, with
current wlroots and scenefx, against Fedora's libraries. So there's no pinning
to explain, and no `xhost`/seatd hacks — the compositor is an ordinary package
and logind handles the seat. The trade-off: Terra tracks newer mango, and
mango renames dispatchers between releases, so a config written for 0.14 needs
edits on the current build (e.g. `disable_while_typing` became
`trackpad_disable_while_typing`).

---

## Credits

A config on top of other people's software — and a Fedora port of a Debian
rice. Mango is by [DreamMaoMao](https://github.com/DreamMaoMao) and
[contributors](https://github.com/mangowm/mango), on
[wlroots](https://gitlab.freedesktop.org/wlroots/wlroots) and
[scenefx](https://github.com/wlrfx/scenefx) (wlrfx). Quickshell by
[outfoxxed](https://git.outfoxxed.me/quickshell/quickshell). awww by
[LGFae](https://codeberg.org/LGFae/awww). rofi-wayland by
[lbonn](https://github.com/lbonn/rofi). dunst by the
[dunst project](https://dunst-project.org). Ghostty by
[Mitchell Hashimoto](https://mitchellh.com). Superfile by
[yorukot](https://github.com/yorukot/superfile). The whole base is
[mangowc-setup](https://justaguy.dev/drew/mangowc-setup) by
[JustAGuy Linux](https://justaguy.dev/drew), GPL-2.0.# nixos-mango
