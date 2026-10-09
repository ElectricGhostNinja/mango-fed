import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

// Lock screen — scripts/lock starts this (Super+Ctrl+L, the power menu,
// the launcher, idle when "Lock on idle" is on). Session-lock protocol:
// the compositor shows nothing but these surfaces until PAM says the
// password is right. Its own qs instance, so a bar restart can't unlock
// the screen; if it ever dies the compositor stays locked and running
// scripts/lock again (a tty, ssh) brings the prompt back.
// Background: LOCK_STYLE=rain — matrix rain in the theme's accent — or
// blur, the wallpaper blurred (qml6-module-qtquick-effects; without it,
// the wallpaper dimmed).
ShellRoot {
    id: root

    // a running lock must survive its own files changing (an update, a
    // git pull): no live reload here — the compositor keeps the session
    // locked if the lock process dies, and that's a black screen until
    // scripts/lock is run again
    Component.onCompleted: Quickshell.watchFiles = false

    readonly property string style: Quickshell.env("LOCK_STYLE") === "blur" ? "blur" : "rain"
    readonly property string wallpaper: Quickshell.env("LOCK_WALLPAPER")   // scripts/lock finds it
    property bool checking: false
    property bool wrong: false
    property date now: new Date()
    property string _pending: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // the password goes to PAM's conversation and nowhere else
    PamContext {
        id: pam
        config: "login"
        onPamMessage: {
            if (responseRequired)
                respond(root._pending)
        }
        onCompleted: result => {
            root._pending = ""
            root.checking = false
            if (result === PamResult.Success) {
                lock.locked = false
                Qt.quit()
            } else {
                root.wrong = true
            }
        }
        onError: () => {
            root._pending = ""
            root.checking = false
            root.wrong = true
        }
    }

    function submit(pw) {
        if (checking || pw === "")
            return
        wrong = false
        checking = true
        _pending = pw
        if (!pam.start()) {
            _pending = ""
            checking = false
            wrong = true
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        WlSessionLockSurface {
            id: surface
            color: Theme.bg

            // the background, with a plain fallback if the chosen one
            // can't load (blur without the Qt effects module)
            Loader {
                id: bg
                anchors.fill: parent
                source: root.style === "blur" ? "BlurBg.qml" : "RainBg.qml"
                onStatusChanged: if (status === Loader.Error) source = "DimBg.qml"
            }

            Column {
                anchors.centerIn: parent
                spacing: 6

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(root.now, "h:mm AP")
                    font.pixelSize: 84
                    font.bold: true
                    style: Text.Outline
                    styleColor: Qt.alpha(Theme.bg, 0.6)
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(root.now, "dddd, MMMM d")
                    color: Qt.alpha(Theme.fg, 0.8)
                    font.pixelSize: 16
                    style: Text.Outline
                    styleColor: Qt.alpha(Theme.bg, 0.6)
                }

                Item { width: 1; height: 22 }

                // the field: accent while typing, alert + a shake when wrong
                Rectangle {
                    id: box
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 320
                    height: 46
                    radius: Theme.barRadius
                    color: Qt.alpha(Theme.bg, 0.88)
                    border.width: 2
                    border.color: root.wrong ? Theme.alert
                                : root.checking ? Qt.alpha(Theme.accent, 0.5) : Theme.accent
                    property real shake: 0
                    transform: Translate { x: box.shake }

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    SequentialAnimation {
                        id: shakeAnim
                        NumberAnimation { target: box; property: "shake"; to: -10; duration: 40 }
                        NumberAnimation { target: box; property: "shake"; to: 10; duration: 70 }
                        NumberAnimation { target: box; property: "shake"; to: -7; duration: 60 }
                        NumberAnimation { target: box; property: "shake"; to: 7; duration: 60 }
                        NumberAnimation { target: box; property: "shake"; to: 0; duration: 50 }
                    }

                    Txt {
                        id: glyph
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.checking ? "󰔟" : root.wrong ? "󰍁" : "󰌾"
                        color: root.wrong ? Theme.alert : Theme.accent
                        font.pixelSize: 16
                    }

                    TextInput {
                        id: field
                        anchors.left: glyph.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        passwordMaskDelay: 0
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: 15
                        focus: true
                        enabled: !root.checking
                        onAccepted: root.submit(text)
                        Keys.onEscapePressed: text = ""

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: field.text === ""
                            text: root.checking ? "checking…" : "password"
                            color: Qt.alpha(Theme.fg, 0.4)
                            font: field.font
                        }
                    }

                    Connections {
                        target: root
                        function onWrongChanged() {
                            if (root.wrong) {
                                shakeAnim.restart()
                                field.text = ""
                                field.forceActiveFocus()
                            }
                        }
                    }

                    Component.onCompleted: field.forceActiveFocus()
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 20
                    verticalAlignment: Text.AlignBottom
                    text: root.wrong ? "wrong password" : ""
                    color: Theme.alert
                    font.pixelSize: 12
                }
            }

            // who's locked out
            Txt {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.margins: 24
                text: "󰌾  " + Quickshell.env("USER")
                color: Qt.alpha(Theme.fg, 0.5)
                font.pixelSize: 13
                style: Text.Outline
                styleColor: Qt.alpha(Theme.bg, 0.6)
            }

            // and on Butterbian, whose desk this is (scripts/lock sets it)
            Txt {
                visible: Quickshell.env("LOCK_BRAND") === "butterbian"
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 24
                text: "butterbian"
                color: Qt.alpha(Theme.accent, 0.8)
                font.pixelSize: 15
                font.bold: true
                font.letterSpacing: 2
                style: Text.Outline
                styleColor: Qt.alpha(Theme.bg, 0.6)
            }
        }
    }
}
