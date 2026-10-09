import QtQuick

// Fedora logo — the command center, no extra buttons needed:
//   left: app launcher (LauncherPopup) · right: wallpaper picker ·
//   middle: random wallpaper
// Both wallpaper paths re-theme the desktop from the image's palette.
// FiraCode NF carries the Font Logos glyph; JetBrainsMono NF here doesn't.
BarModule {
    id: root

    icon: "\uf30a"  // Fedora logo (Font Logos)
    iconFont: "FiraCode Nerd Font"
    iconColor: Theme.accent
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            picker.toggle()
        else if (mouse.button === Qt.MiddleButton)
            picker.applyRandom()
        else
            launcher.visible = !launcher.visible
    }

    LauncherPopup {
        id: launcher
        anchorItem: root
    }

    WallpaperPicker {
        id: picker
        anchorItem: root
    }
}
