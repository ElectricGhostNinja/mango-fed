import QtQuick
import Quickshell

// Active connection indicator. The icon says the transport (Wi-Fi bars
// follow signal strength, ethernet, VPN shield) and updates the moment
// NetworkManager changes anything (Sys follows `nmcli monitor`). Two states
// get words, not just a colour: "sign in" when the network wants a login
// page first (hotel, café) and "no internet" when it's connected to
// something that doesn't reach it — both need NetworkManager's
// connectivity check on (Sys.connectivity).
// Click: the login page while "sign in" shows, the quickshell network app
// otherwise. Right click: nm-connection-editor for the deep settings.
BarModule {
    id: root

    readonly property color stateColor: !Sys.online || Sys.noInternet ? Theme.red
                                      : Sys.signInNeeded ? Theme.accent
                                      : Sys.vpnOn ? Theme.green : Theme.cyan

    icon: Sys.netIcon
    iconColor: stateColor
    label: Sys.signInNeeded ? "sign in" : Sys.noInternet ? "no internet" : ""
    labelColor: stateColor

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Quickshell.execDetached(["nm-connection-editor"])
        else if (Sys.signInNeeded)
            // any plain-http page gets redirected to the login page; NM's own
            // check URL is the one it already saw intercepted
            Quickshell.execDetached(["xdg-open", Sys.checkUri || "http://neverssl.com"])
        else
            Quickshell.execDetached([Theme.configDir + "/scripts/network"])
    }
}
