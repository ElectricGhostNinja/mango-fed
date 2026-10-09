import QtQuick
import Quickshell
import Quickshell.Io

// Three-day forecast under the weather indicator — the calendar idiom:
// click the number, get the picture. Data comes from the same wttr.in
// fetch the bar module already makes; no extra requests.
// Settings live under the forecast: a location field (Enter pins it,
// "auto" unpins it) and °F/°C/auto. They write the weather-location and
// weather-units files Weather.qml watches, so a change refetches at once.
// Right-click on the module opens the card with the field focused.
// "radar" swaps the forecast for the last hour of rain on a map
// (RadarView); the card grows to fit and comes back when you leave.
Popout {
    id: root
    ipcNames: ["weather"]
    function ipc(fn, arg) {
        if (fn === "toggle") root.visible = !root.visible
        else if (fn === "radar") { root.visible = true; root.radar = true }
    }

    property string condition: ""
    property string feels: ""
    property string wind: ""
    property string place: ""
    property var days: []   // {label, glyph, hi, lo, rain}
    property bool failed: false   // last fetch failed (bad location, offline)
    property real lat: 0          // where the forecast is for, for the radar
    property real lon: 0
    property bool radar: false

    // the saved settings, fed by Weather.qml ("" = auto)
    property string location: ""
    property string units: ""

    readonly property string locationFile: Theme.configDir + "/weather-location"
    readonly property string unitsFile: Theme.configDir + "/weather-units"
    readonly property bool localeF: Qt.locale().measurementSystem !== Locale.MetricSystem

    cardWidth: radar ? 420 : 300
    cardHeight: radar ? 380 : 268

    onVisibleChanged: {
        if (visible)
            field.text = location
        else
            radar = false
    }
    onLocationChanged: if (!field.activeFocus) field.text = location

    function openSettings() {
        visible = true
        // after Popout's own focus grab on open
        Qt.callLater(() => {
            field.forceActiveFocus()
            field.selectAll()
        })
    }

    // write or clear a settings file; the value goes in as an argument,
    // never spliced into the shell string
    function save(path, value) {
        if (value === "")
            Quickshell.execDetached(["rm", "-f", path])
        else
            Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" > \"$2\"",
                                     "sh", value, path])
    }

    function saveLocation() {
        const v = field.text.trim()
        field.text = v
        if (v !== location)
            save(locationFile, v)
    }

    // where this forecast is for — also the tell when a VPN exit node is
    // fooling wttr.in's IP geolocation. A failed fetch says so here.
    // forecast ⇄ radar, top right (radar needs a located forecast)
    Rectangle {
        id: radarBtn
        visible: root.lat !== 0 || root.lon !== 0
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: -4
        width: radarText.implicitWidth + 16
        height: 22
        radius: 7
        color: root.radar ? Theme.accent
             : radarMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

        Behavior on color { ColorAnimation { duration: 120 } }

        Txt {
            id: radarText
            anchors.centerIn: parent
            text: root.radar ? "󰖎  forecast" : "󰖎  radar"
            color: root.radar ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
            font.pixelSize: 10
        }
        MouseArea {
            id: radarMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.radar = !root.radar
        }
    }

    Txt {
        id: placeLine
        anchors.left: parent.left
        anchors.right: radarBtn.visible ? radarBtn.left : parent.right
        anchors.rightMargin: radarBtn.visible ? 8 : 0
        anchors.top: parent.top
        visible: root.place !== "" || root.failed
        text: root.failed
            ? "󰅙 couldn't get the weather" + (root.location !== "" ? " for \"" + root.location + "\"" : "")
            : "󰍎 " + root.place
        color: root.failed ? Theme.red : Qt.alpha(Theme.fg, 0.5)
        font.pixelSize: 10
        elide: Text.ElideRight
    }

    // current condition · feels like · wind
    Txt {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: placeLine.visible ? placeLine.bottom : parent.top
        anchors.topMargin: placeLine.visible ? 4 : 0
        text: root.condition
            + (root.feels !== "" ? "  ·  feels " + root.feels + "°" : "")
            + (root.wind !== "" ? "  ·  󰖝 " + root.wind : "")
        font.pixelSize: 12
        font.bold: true
        elide: Text.ElideRight
    }

    RadarView {
        visible: root.radar
        active: root.radar && root.visible
        lat: root.lat
        lon: root.lon
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
    }

    Row {
        visible: !root.radar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.topMargin: 12
        anchors.bottom: settings.top
        anchors.bottomMargin: 12

        Repeater {
            model: root.days

            Column {
                id: day
                required property var modelData
                width: parent.width / Math.max(root.days.length, 1)
                spacing: 5

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: day.modelData.label
                    color: Qt.alpha(Theme.fg, 0.55)
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: day.modelData.glyph
                    color: Theme.yellow
                    font.pixelSize: 22
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: day.modelData.hi + "° / " + day.modelData.lo + "°"
                    font.pixelSize: 12
                }
                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: day.modelData.rain >= 30
                    text: "󰖌 " + day.modelData.rain + "%"
                    color: Theme.cyan
                    font.pixelSize: 10
                }
            }
        }
    }

    Column {
        id: settings
        visible: !root.radar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        spacing: 8

        Rectangle {
            width: parent.width
            height: 1
            color: Qt.alpha(Theme.fg, 0.15)
        }

        // location: type + Enter pins it; "auto" goes back to by-IP
        Row {
            width: parent.width
            spacing: 6

            Rectangle {
                width: parent.width - (autoBtn.visible ? autoBtn.width + parent.spacing : 0)
                height: 30
                radius: 8
                color: Qt.alpha(Theme.fg, 0.06)
                border.width: 1
                border.color: field.activeFocus ? Qt.alpha(Theme.accent, 0.5) : "transparent"

                Txt {
                    id: pin
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰍎"
                    color: Theme.accent
                    font.pixelSize: 13
                }

                // under the field, so a click on the text still places the cursor
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: field.forceActiveFocus()
                }

                TextInput {
                    id: field
                    anchors.left: pin.right
                    anchors.leftMargin: 8
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    color: Theme.fg
                    selectionColor: Qt.alpha(Theme.accent, 0.4)
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    selectByMouse: true
                    clip: true
                    onAccepted: {
                        root.saveLocation()
                        focus = false
                    }
                    // Escape drops an unsaved edit first, then closes (Popout)
                    Keys.onEscapePressed: event => {
                        if (text !== root.location)
                            text = root.location
                        else
                            event.accepted = false
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: field.text === ""
                        text: "auto (by IP) · type a city or zip"
                        color: Qt.alpha(Theme.fg, 0.35)
                        font: field.font
                    }
                }
            }

            Rectangle {
                id: autoBtn
                visible: root.location !== ""
                width: autoText.implicitWidth + 16
                height: 30
                radius: 8
                color: autoMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

                Txt {
                    id: autoText
                    anchors.centerIn: parent
                    text: "auto"
                    color: Qt.alpha(Theme.fg, 0.8)
                }

                MouseArea {
                    id: autoMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        field.text = ""
                        root.save(root.locationFile, "")
                    }
                }
            }
        }

        // units: auto (from the locale) / °F / °C
        Row {
            width: parent.width
            spacing: 6

            Repeater {
                model: [
                    { value: "", label: "auto · " + (root.localeF ? "°F" : "°C") },
                    { value: "f", label: "°F" },
                    { value: "c", label: "°C" }
                ]

                Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool active: root.units === modelData.value
                    width: (parent.width - 2 * parent.spacing) / 3
                    height: 26
                    radius: 8
                    color: active ? Theme.accent
                         : segMa.containsMouse ? Qt.alpha(Theme.fg, 0.14) : Qt.alpha(Theme.fg, 0.06)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Txt {
                        anchors.centerIn: parent
                        text: seg.modelData.label
                        color: seg.active ? Theme.bg : Qt.alpha(Theme.fg, 0.8)
                        font.bold: seg.active
                    }

                    MouseArea {
                        id: segMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.save(root.unitsFile, seg.modelData.value)
                    }
                }
            }
        }
    }
}
