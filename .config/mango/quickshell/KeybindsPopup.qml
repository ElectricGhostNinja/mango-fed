import QtQuick
import Quickshell
import Quickshell.Io

// Keybinds cheatsheet (Super+/, or Keybindings in the command menu): every
// bind in the WM config, grouped by its sections and laid out in columns.
// Type to filter; click a row to open the config at that line. Rows come
// from scripts/keybinds, re-read on every open so edits show up next time.
// Nothing here is WM-specific: each setup's scripts/keybinds reads its own
// config format and prints the same rows (section, keys, label, line).
Popout {
    id: root
    ipcNames: ["keybinds"]

    property var rows: []   // {section, keys: [["Super", "Q"], ...], desc, line}
    property string query: ""
    // the unfiltered layout's height, so the card doesn't shrink as you type
    property real fullHeight: 0

    readonly property int colSpacing: 24
    readonly property real innerWidth: cardWidth - 2 * cardPadding
    readonly property int columnCount:
        Math.max(1, Math.floor((innerWidth + colSpacing) / (440 + colSpacing)))
    readonly property real columnWidth:
        (innerWidth - (columnCount - 1) * colSpacing) / columnCount
    readonly property int keysWidth: 170
    readonly property var columns: layout(rows, query, columnCount)

    centered: true
    cardWidth: Math.min(1560, fitWidth - 64)
    cardHeight: Math.min(searchBox.height + 14 + fullHeight + 2 * cardPadding,
                         fitHeight * 0.8)

    onVisibleChanged: {
        if (!visible)
            return
        search.text = ""
        loader.running = true
        // after Popout's own focus grab on open
        Qt.callLater(() => search.forceActiveFocus())
    }

    Process {
        id: loader
        command: [Theme.configDir + "/scripts/keybinds"]
        stdout: StdioCollector {
            onStreamFinished: root.rows = root.parse(text)
        }
    }

    function parse(t) {
        const out = []
        for (const l of t.split("\n")) {
            const f = l.split("\t")
            if (f.length < 4)
                continue
            out.push({ section: f[0], desc: f[2], line: parseInt(f[3]),
                       keys: f[1].split("|").map(k => k.split("+")) })
        }
        return out
    }

    function scrollBy(dy) {
        body.contentY = Math.max(0, Math.min(body.contentY + dy,
                                             body.contentHeight - body.height))
    }

    function edit(line) {
        root.visible = false
        Quickshell.execDetached([Theme.configDir + "/scripts/keybinds", "open", String(line)])
    }

    // Filter (every typed word must match the label, keys or section),
    // group by section in config order, then fill the columns masonry-style:
    // each section goes to the currently shortest one.
    function layout(rows, q, n) {
        const words = q.toLowerCase().split(/\s+/).filter(w => w !== "")
        const sections = []
        for (const r of rows) {
            if (words.length) {
                const hay = (r.section + " " + r.desc + " "
                             + r.keys.map(k => k.join(" ")).join(" ")).toLowerCase()
                if (!words.every(w => hay.includes(w)))
                    continue
            }
            let s = sections.find(s => s.title === r.section)
            if (!s) {
                s = { title: r.section, rows: [] }
                sections.push(s)
            }
            s.rows.push(r)
        }
        const cols = [], heights = []
        for (let i = 0; i < n; i++) {
            cols.push([])
            heights.push(0)
        }
        for (const s of sections) {
            let c = 0
            for (let i = 1; i < n; i++)
                if (heights[i] < heights[c])
                    c = i
            cols[c].push(s)
            heights[c] += s.rows.length + 2   // + the header
        }
        return cols
    }

    // keycaps for a row: alternatives that share modifiers show them once
    // (Super ← / H), otherwise each combo in full (Vol Up / Super F12)
    function caps(alts) {
        const out = []
        const mods = a => a.slice(0, -1).join("+")
        if (alts.every(a => mods(a) === mods(alts[0]))) {
            alts[0].slice(0, -1).forEach(k => out.push({ t: k, cap: true }))
            alts.forEach((a, i) => {
                if (i) out.push({ t: "/", cap: false })
                out.push({ t: a[a.length - 1], cap: true })
            })
        } else {
            alts.forEach((a, i) => {
                if (i) out.push({ t: "/", cap: false })
                a.forEach(k => out.push({ t: k, cap: true }))
            })
        }
        return out
    }

    Rectangle {
        id: searchBox
        anchors.left: parent.left
        anchors.right: parent.right
        height: 34
        radius: 8
        color: Qt.alpha(Theme.fg, 0.06)
        border.width: 1
        border.color: search.activeFocus ? Qt.alpha(Theme.accent, 0.5) : "transparent"

        Txt {
            id: searchIcon
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌌"
            color: Theme.accent
            font.pixelSize: 15
        }

        TextInput {
            id: search
            anchors.left: searchIcon.right
            anchors.leftMargin: 10
            anchors.right: hint.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.fg
            selectionColor: Qt.alpha(Theme.accent, 0.4)
            font.family: Theme.fontFamily
            font.pixelSize: 13
            clip: true
            onTextChanged: root.query = text
            // Escape clears the search first, then closes (Popout's handler)
            Keys.onEscapePressed: event => {
                if (text !== "")
                    text = ""
                else
                    event.accepted = false
            }
            // the list scrolls from the keyboard while you type
            Keys.onUpPressed: root.scrollBy(-60)
            Keys.onDownPressed: root.scrollBy(60)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
                    root.scrollBy((event.key === Qt.Key_PageUp ? -1 : 1) * body.height * 0.9)
                    event.accepted = true
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: search.text === ""
                text: "Search keybinds"
                color: Qt.alpha(Theme.fg, 0.35)
                font: search.font
            }
        }

        Txt {
            id: hint
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: "click a bind to edit it · esc to close"
            color: Qt.alpha(Theme.fg, 0.35)
        }
    }

    Flickable {
        id: body
        anchors.top: searchBox.bottom
        anchors.topMargin: 14
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: cols.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        onContentHeightChanged: {
            if (root.query === "")
                root.fullHeight = contentHeight
            contentY = Math.max(0, Math.min(contentY, contentHeight - height))
        }

        Txt {
            visible: root.query !== "" && root.columns.every(c => c.length === 0)
            text: "No keybinds match \"" + root.query + "\""
            color: Qt.alpha(Theme.fg, 0.5)
            font.pixelSize: 12
        }

        Row {
            id: cols
            spacing: root.colSpacing

            Repeater {
                model: root.columns

                Column {
                    id: column
                    required property var modelData
                    width: root.columnWidth
                    spacing: 14

                    Repeater {
                        model: column.modelData

                        Column {
                            id: section
                            required property var modelData
                            width: parent.width
                            spacing: 1

                            Txt {
                                leftPadding: 6
                                bottomPadding: 4
                                text: section.modelData.title
                                color: Theme.accent
                                font.bold: true
                                font.capitalization: Font.AllUppercase
                                font.letterSpacing: 1
                            }

                            Repeater {
                                model: section.modelData.rows

                                Rectangle {
                                    id: bindRow
                                    required property var modelData
                                    width: parent.width
                                    height: Math.max(keycaps.height, label.implicitHeight) + 8
                                    radius: 6
                                    color: rowMa.containsMouse ? Qt.alpha(Theme.fg, 0.08) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Flow {
                                        id: keycaps
                                        x: 6
                                        y: 4
                                        width: root.keysWidth
                                        spacing: 3

                                        Repeater {
                                            model: root.caps(bindRow.modelData.keys)

                                            Rectangle {
                                                id: cap
                                                required property var modelData
                                                height: 20
                                                width: capText.implicitWidth + (modelData.cap ? 12 : 2)
                                                radius: 4
                                                color: modelData.cap ? Qt.alpha(Theme.fg, 0.08) : "transparent"
                                                border.width: modelData.cap ? 1 : 0
                                                border.color: Qt.alpha(Theme.fg, 0.16)

                                                Txt {
                                                    id: capText
                                                    anchors.centerIn: parent
                                                    text: cap.modelData.t
                                                    color: cap.modelData.cap ? Theme.fg : Qt.alpha(Theme.fg, 0.4)
                                                }
                                            }
                                        }
                                    }

                                    Txt {
                                        id: label
                                        x: keycaps.x + root.keysWidth + 10
                                        y: 4 + 2
                                        width: parent.width - x - lineNo.width - 12
                                        text: bindRow.modelData.desc
                                        wrapMode: Text.Wrap
                                        color: Qt.alpha(Theme.fg, 0.9)
                                        font.pixelSize: 12
                                    }

                                    // where it lives, shown on hover
                                    Txt {
                                        id: lineNo
                                        anchors.right: parent.right
                                        anchors.rightMargin: 6
                                        y: 4 + 3
                                        text: "L" + bindRow.modelData.line
                                        opacity: rowMa.containsMouse ? 1 : 0
                                        color: Qt.alpha(Theme.fg, 0.4)
                                        font.pixelSize: 10
                                    }

                                    MouseArea {
                                        id: rowMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.edit(bindRow.modelData.line)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // only on screens too short for the whole list (768p laptops)
    Rectangle {
        visible: body.contentHeight > body.height
        anchors.right: body.right
        anchors.rightMargin: -8
        y: body.y + body.visibleArea.yPosition * body.height
        width: 3
        height: body.visibleArea.heightRatio * body.height
        radius: 2
        color: Qt.alpha(Theme.fg, 0.3)
    }
}
