# quickshell shell for mango

The same desktop shell as the dwm / bspwm / openbox setups — bar, popups,
wallpaper-driven theming, and the network app — with a mango backend.
Nothing here touches X11: mango is a Wayland compositor and the bar is a
wlr-layer-shell panel.

Launch: `scripts/bar start` (config.conf's exec-once), or
`scripts/bar restart|log`, which handle the `-p` flag and pass the GTK
icon theme in as `QS_ICON_THEME` (quickshell doesn't follow it itself).

## WM-specific files (everything else is shared verbatim with the other ports)

- `Wm.qml` — mango backend. One `mmsg watch all-monitors` stream (JSON,
  one line per state change, snapshot on connect) supplies tags,
  occupancy, urgency, focused title and layout. Actions go through
  `mmsg dispatch`. `scripts/mango-ipc` wraps mmsg and finds the socket
  when MANGO_INSTANCE_SIGNATURE is missing from the environment.
- `Bar.qml` — no Follow module (mango has no window-follow toggle).
- `LayoutPicker.qml` — the fourteen mango layouts as glyph tiles
  (`setlayout,<name>`); inner gap via `setoption,gappih/gappiv`
  (persisted to `mango-gaps`, re-applied by Wm.qml on start); outer gaps
  via `setoption,gappoh/gappov`, always equal to the bar's edge inset
  (`Theme.edgeInset`, 8px scaled by `Theme.autoScale` — 1.0 at 1080p,
  1.33 at 1440p, 2.0 at unscaled 4K) so windows float like the bar; a
  config reload resets both to config.conf, so `scripts/mango-reload`
  (Super+Shift+r, wallpaper-theme) reloads and then calls the `wm`
  IpcHandler in shell.qml to push them back;
  master width / count via the relative
  `setmfact` / `incnmaster` dispatches, tracked in Wm.qml since mango
  exposes no getter. Table in Wm.qml mirrors `src/layout/layout.h`.
  Effects toggles (blur / shadows / animations) and the border-width
  and unfocused-opacity sliders (`setoption,borderpx` /
  `setoption,unfocused_opacity`) go through `setoption` and persist
  together to `mango-effects` as key=value lines; with no file the bar
  pushes nothing and config.conf's values stand, so Wm.qml's defaults
  mirror config.conf. `mango-reload` re-applies these after the gaps.
  Unfocused opacity reaching windows that are already open needs
  mangowc 0.14.4-6 or newer (butterrepo; downstream patch) — upstream
  only applies it to windows opened after the change.
- `Popout.qml` — the card goes slightly translucent while blur is on
  (mango's `blur_layer` frosts what's behind it), solid when it's off.
  Centered popups wear mango's window border instead. Every card is
  scaled as a whole by `Theme.popupScale` (the picker's popup size,
  `popup-scale`; not tied to resolution), so popups are written at one
  set of sizes; `fitWidth`/`fitHeight` give screen-sized popups the room
  in those units.
  The network app reads the same setting in its own Theme copy.
- `QuickTile.qml` — the command menu's two-line quick-settings tile
  (name over state, accent when on, red for mic muted / DND).
- `Batteries.qml` — every battery UPower knows, read from `upower -d`
  (mice often report only a coarse level, which Quickshell's UPower
  service hides); warns once when one runs low and puts a laptop on
  power saver at 20% until it charges.
- `TogglePill.qml` — the quick-settings pill, shared by the command
  menu and the picker's Effects row.
- `Sys.qml` — caps lock read from `/sys/class/leds/*capslock`, popups
  always card-only (`composited: false`). Network state follows
  `nmcli monitor` (instant), plus Wi-Fi signal strength and
  NetworkManager's connectivity verdict (sign-in page / no internet),
  which needs its connectivity check on — the installer adds Debian's
  `network-manager-config-connectivity-debian`.
- `Commands.qml` — keep-awake is a `systemd-inhibit --what=idle` holder
  process (swayidle watches logind for idle inhibitors, so this also
  keeps the monitor from powering down); night light is wlsunset; the
  updates terminal is ghostty; screen off is `scripts/screen-off`, a
  one-shot swayidle that powers the outputs down and brings them back on
  the first input (a bare `wlopm --off` would stay dark until the login
  swayidle's own 15-minute resume).
- `Screenshot.qml` — `scripts/screenshot` (grim + slurp, clipboard).
- `KeybindsPopup.qml` — the Super+/ cheatsheet. The popup itself is
  WM-agnostic; `scripts/keybinds` turns config.conf's binds into its rows
  (section, keys, label, line) and opens geany at a bind's line. Opened
  from the command menu or `ipc call keybinds toggle`. Mango only so far.
- `PowerPopup.qml` — screen off / log out / reboot / shut down, the last
  three on a second press. Logout is `Wm.logout()` (mango: `quit`).
  `scripts/power` opens it over IPC and falls back to the old rofi list
  when the bar isn't running. Mango only so far.
- `LauncherPopup.qml` — app grid (Super+space, left-click the swirl):
  search over name / generic name / keywords / program, All · Apps ·
  Settings chips, alphabetical until you type; launch history
  (`launcher-history`) only breaks ties between matches. Terminal apps
  run in ghostty. Actions (power menu, keybindings, wallpaper, layout,
  what's running, screen off, screenshots, updates, restart bar, reload
  config, about) are searchable too and have their own chip; most open
  their popup over IPC, reload goes through `Wm.reloadConfig()`. `scripts/launcher` opens it and falls back to rofi when
  the bar isn't running.
- `MetricsPopup.qml` — click CPU/RAM/disk: CPU and RAM meters, one
  temperature each for CPU / GPU / drive (hwmon: k10temp or coretemp,
  amdgpu, nvme; missing ones skipped), a meter per local disk and its
  read / write rate (`scripts/sysinfo`), network mounts asked separately
  with a time limit (an unreachable NAS says so instead of hanging the
  card), then the busiest programs. `scripts/procs` prints a /proc snapshot (plain awk,
  nothing WM-specific); the card diffs two of them for current CPU, as a
  share of the whole machine, grouped by program. Samples only while
  open. Right-click the module, or the card's button, opens btop.
  Hover a row for ✕ to end that program (second click confirms; SIGTERM,
  then Force quit if it's still there after 3s). Only your own processes,
  never the session's: a shared list in the card plus `Wm.sessionProcs`.
- `VolumePopup.qml` — click on Volume (right-click mutes): a header (output, level,
  mute), Output (slider, every sink, click to make it the default),
  Input (only with a microphone: slider, a live level meter that runs
  only while open, the mics, mute), Apps (each app playing, its streams
  grouped under one slider), pavucontrol. Lists filter on what PipeWire
  announces up front (node type), never on bound-later properties — a
  list that changes as its own nodes bind loops and crashed the bar. The
  default source counts as the mic only if it is one (PipeWire can hand
  back an output there).
- Tail of `scripts/wallpaper-theme` — mango: writes `theme.conf`
  (focus/border/urgent/root colours, sourced by config.conf) and
  `reload_config`; swaybg replaces the wallpaper and the config.conf
  exec-once line is rewritten.

Notifications are dunst (Wayland-native via layer-shell), so the
NotifyPopup / Bell / DND code is byte-identical to the X11 ports.

## Known gaps

- Popups are card-only xdg-popups: click-outside close is not available,
  Escape and the module's own button close them.
- Single-monitor state: Wm.qml follows the focused output.
