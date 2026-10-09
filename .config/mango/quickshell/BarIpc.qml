pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// One place for the bar's `qs ipc call` names. Every screen has its own
// bar, and so its own copy of each popup, but an IPC name can be registered
// only once: with the handlers inside the popups, the first bar's copy
// answered whichever monitor you were on. Registered once here and passed
// on, the popup on the focused output answers (Popout.qml's ipcNames).
Singleton {
    id: root

    signal call(string target, string fn, string arg)

    IpcHandler { target: "layouts";    function toggle(): void { root.call("layouts", "toggle", "") } }
    IpcHandler { target: "tweaks";     function toggle(): void { root.call("tweaks", "toggle", "") } }
    IpcHandler { target: "volume";     function toggle(): void { root.call("volume", "toggle", "") } }
    IpcHandler { target: "commands";   function toggle(): void { root.call("commands", "toggle", "") } }
    IpcHandler { target: "displays";   function toggle(): void { root.call("displays", "toggle", "") } }
    IpcHandler { target: "metrics";    function toggle(): void { root.call("metrics", "toggle", "") } }
    IpcHandler { target: "launcher";   function toggle(): void { root.call("launcher", "toggle", "") } }
    IpcHandler { target: "keybinds";   function toggle(): void { root.call("keybinds", "toggle", "") } }
    IpcHandler { target: "power";      function toggle(): void { root.call("power", "toggle", "") } }
    IpcHandler {
        target: "weather"
        function toggle(): void { root.call("weather", "toggle", "") }
        function radar(): void { root.call("weather", "radar", "") }
    }
    IpcHandler {
        target: "wallpapers"
        function toggle(): void { root.call("wallpapers", "toggle", "") }
        function random(): void { root.call("wallpapers", "random", "") }
        function set(path: string): void { root.call("wallpapers", "set", path) }
    }
    // not a popup: every bar's pill recounts
    IpcHandler { target: "updates";    function check(): void { root.call("updates", "check", "") } }
}
