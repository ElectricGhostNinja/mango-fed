import QtQuick
import Quickshell
import Quickshell.Io

// Pending-updates indicator, presence-gated: hidden at zero, an icon +
// count pill when apt has upgrades. The check is root-free and lock-free
// (simulated dist-upgrade), run hourly — this is Debian, updates trickle
// in — and the moment the upgrade terminal finishes; middle click
// re-checks now (after an upgrade run from your own terminal, say). The
// count is only as fresh as the last `apt update` — the upgrade terminal
// runs one, and APT::Periodic::Update-Package-Lists "1" makes the system
// do it daily.
BarModule {
    id: root

    property int count: 0
    visible: count > 0
    icon: "󰚰"
    iconColor: Theme.accent
    label: String(count)

    Process {
        id: checkProc
        command: ["sh", "-c",
            "apt-get -s -o Debug::NoLocking=1 dist-upgrade 2>/dev/null | grep -c '^Inst'"]
        stdout: StdioCollector {
            onStreamFinished: root.count = parseInt(text.trim()) || 0
        }
    }

    Timer {
        interval: 3600 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: checkProc.running = true
    }

    // the upgrade terminal says when it's done (below), so the pill
    // clears the moment apt finishes; nothing polls in between.
    // Scriptable too: qs -p ~/.config/mango/quickshell ipc call updates check
    Connections {
        target: BarIpc
        function onCall(target, fn, arg) {
            if (target === "updates" && fn === "check") checkProc.running = true
        }
    }

    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton) {
            checkProc.running = true
        } else {
            Quickshell.execDetached(["ghostty", "-e", "sh", "-c",
                "sudo apt update && sudo apt full-upgrade; " +
                "qs -p \"$0\" ipc call updates check >/dev/null 2>&1; " +
                "printf '\\ndone - press enter to close '; read _",
                Theme.configDir + "/quickshell"])
        }
    }
}
