import QtQuick

// Matrix rain in the wallpaper's colours: columns of glyphs falling at
// their own speeds, a bright head and a trail in the accent that fades
// into the theme's background. Katakana like the film, with the digits
// and the letters of "butterbian" mixed in for anyone paying attention.
Canvas {
    id: rain

    readonly property int cell: 18
    readonly property string glyphs:
        "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝ0123456789BUTTERIAN"
    property var cols: []
    property bool fresh: true

    onWidthChanged: reset()
    onHeightChanged: reset()
    Component.onCompleted: reset()

    function reset() {
        const n = Math.ceil(width / cell) + 1
        const c = []
        for (let i = 0; i < n; i++)
            c.push({ y: -Math.random() * height / cell, speed: 0.35 + Math.random() * 0.75,
                     glyph: pick() })
        cols = c
        fresh = true
    }
    function pick() {
        return glyphs.charAt(Math.floor(Math.random() * glyphs.length))
    }

    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: rain.requestPaint()
    }

    onPaint: {
        const ctx = getContext("2d")
        const bg = Theme.bg, ink = Theme.accent, head = Theme.fg
        if (fresh) {
            ctx.fillStyle = bg
            ctx.fillRect(0, 0, width, height)
            fresh = false
        }
        // fade what's there a little: that's the trail
        ctx.fillStyle = Qt.rgba(bg.r, bg.g, bg.b, 0.14)
        ctx.fillRect(0, 0, width, height)
        ctx.font = "bold " + (cell - 2) + "px '" + Theme.fontFamily + "'"
        ctx.textBaseline = "top"
        for (let i = 0; i < cols.length; i++) {
            const c = cols[i]
            const x = i * cell
            const y = Math.floor(c.y) * cell
            // last frame's head turns to accent, the new head is bright
            ctx.fillStyle = ink
            ctx.fillText(c.glyph, x, y - cell)
            c.glyph = pick()
            ctx.fillStyle = head
            ctx.fillText(c.glyph, x, y)
            c.y += c.speed
            if (y > height && Math.random() < 0.03) {
                c.y = -Math.random() * 10
                c.speed = 0.35 + Math.random() * 0.75
            }
        }
    }
}
