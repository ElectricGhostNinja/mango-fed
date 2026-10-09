import QtQuick
import Quickshell
import Quickshell.Io

// Weather: condition glyph + temperature from wttr.in (no API key),
// refreshed every 30 minutes. Click for the 3-day forecast card — same
// fetch, no extra requests. Hidden until the first successful fetch, so
// an offline boot just shows no weather.
//
// Location: by default wttr.in locates by IP — which reports the VPN exit
// node's weather when a VPN is up. Pin it from the forecast card's field
// (right-click jumps there), which writes a city/zip to weather-location
// in the config folder (plain text, e.g. "Cleveland" or 44101).
//
// Units: auto — imperial locales get °F/mph, everyone else °C/km/h.
// The card's °F/°C pills write a single "f" or "c" to weather-units.
BarModule {
    id: root

    visible: temp !== ""

    property string temp: ""
    property int code: 113

    property string unitsOverride: ""
    property string location: ""
    readonly property bool useF: unitsOverride === "f" ? true
                               : unitsOverride === "c" ? false
                               : Qt.locale().measurementSystem !== Locale.MetricSystem

    FileView {
        path: Theme.configDir + "/weather-units"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.unitsOverride = text().trim().toLowerCase()
        onLoadFailed: root.unitsOverride = "" // file removed → back to auto
    }

    // pin/unpin location → refetch right away instead of waiting 30 min
    // (deleting the file lands in loadFailed, so cover both paths)
    FileView {
        path: Theme.configDir + "/weather-location"
        watchChanges: true
        onFileChanged: {
            reload()
            fetch.running = false
            fetch.running = true
        }
        onLoaded: root.location = text().trim()
        onLoadFailed: {
            root.location = ""
            fetch.running = false
            fetch.running = true
        }
    }

    property var lastJson: null
    onUseFChanged: if (lastJson) parse(lastJson)

    // WWO condition codes → a handful of glyph buckets
    function glyphFor(c) {
        if ([200, 386, 389, 392, 395].indexOf(c) !== -1) return "󰖓"
        if ([179, 182, 185, 227, 230, 317, 320, 323, 326, 329, 332, 335,
             338, 350, 368, 371, 374, 377].indexOf(c) !== -1) return "󰖘"
        if ([143, 248, 260].indexOf(c) !== -1) return "󰖑"
        if (c === 113) return "󰖙"
        if (c === 116) return "󰖕"
        if (c === 119 || c === 122) return "󰖐"
        return "󰖗"  // everything else in WWO's table is some kind of rain
    }

    icon: glyphFor(code)
    iconColor: Theme.yellow
    label: temp + "°"

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            forecast.openSettings()
        else
            forecast.visible = !forecast.visible
    }

    WeatherPopup {
        id: forecast
        anchorItem: root
        location: root.location
        units: root.unitsOverride
    }

    property string _buf: ""
    Process {
        id: fetch
        command: ["sh", "-c",
            "LOC=$(tr -d '\\n' < \"" + Theme.configDir + "/weather-location\" 2>/dev/null | tr ' ' '+'); " +
            "curl -sf -m 10 \"https://wttr.in/${LOC}?format=j1\""]
        running: true
        stdout: SplitParser {
            onRead: line => root._buf += line
        }
        onRunningChanged: if (running) root._buf = ""
        // st 1 = killed by a restart (a new location): not a failure, the
        // next run answers. Otherwise curl's own verdict counts — an unknown
        // location (404) or no network — and the card says so.
        onExited: (code, st) => {
            if (st !== 0)
                return
            try {
                if (code !== 0)
                    throw new Error("curl " + code)
                root.parse(JSON.parse(root._buf))
                forecast.failed = false
            } catch (e) {
                forecast.failed = true
                retry.start() // try again soon
            }
        }
    }

    function parse(j) {
        lastJson = j
        const f = useF
        const c = j.current_condition[0]
        temp = f ? c.temp_F : c.temp_C
        code = parseInt(c.weatherCode) || 113
        forecast.condition = c.weatherDesc?.[0]?.value ?? ""
        const a = j.nearest_area?.[0]
        forecast.place = a ? [a.areaName?.[0]?.value,
                              a.region?.[0]?.value || a.country?.[0]?.value]
                              .filter(Boolean).join(", ") : ""
        forecast.lat = parseFloat(a?.latitude) || 0
        forecast.lon = parseFloat(a?.longitude) || 0
        forecast.feels = (f ? c.FeelsLikeF : c.FeelsLikeC) ?? ""
        forecast.wind = f ? (c.windspeedMiles ? c.windspeedMiles + "mph" : "")
                          : (c.windspeedKmph ? c.windspeedKmph + "km/h" : "")

        const days = []
        const names = ["today", "tomorrow"]
        for (let i = 0; i < Math.min(3, (j.weather ?? []).length); i++) {
            const d = j.weather[i]
            const noon = d.hourly?.[4] ?? d.hourly?.[0] ?? {}
            let rain = 0
            for (const h of d.hourly ?? [])
                rain = Math.max(rain, parseInt(h.chanceofrain) || 0)
            days.push({
                label: names[i] ?? new Date(d.date + "T12:00").toLocaleDateString(Qt.locale(), "ddd"),
                glyph: glyphFor(parseInt(noon.weatherCode) || 113),
                hi: (f ? d.maxtempF : d.maxtempC) ?? "?",
                lo: (f ? d.mintempF : d.mintempC) ?? "?",
                rain: rain
            })
        }
        forecast.days = days
    }

    Timer {
        interval: 30 * 60 * 1000
        repeat: true
        running: true
        onTriggered: { fetch.running = false; fetch.running = true }
    }
    Timer {
        id: retry
        interval: 3 * 60 * 1000
        onTriggered: { fetch.running = false; fetch.running = true }
    }
}
