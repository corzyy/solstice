pragma Singleton
import QtQuick
import Quickshell

// SettingsRegistry — the settings nav/page registry (id, title, desc, icon,
// category, launcher keywords). Single source for the Settings window's nav
// rail + page lookup (SettingsPanel.navEntries) and for the launcher's
// built-in settings search entries (the settings app is part of the shell
// and deliberately has no .desktop entry, so LauncherPanel surfaces these
// pseudo entries itself).
Singleton {
    readonly property var entries: [
        { id: "wallpaper", title: "Wallpaper & style", icon: "󰋩", desc: "Wallpaper, fonts, colours", category: "appearance",
          keywords: "wallpaper style theme colour color colors colours font fonts image background" },
        { id: "network", title: "Network & internet", icon: "󰖩", desc: "Wi-Fi, Ethernet, DNS", category: "connectivity",
          keywords: "network internet wifi wi-fi ethernet dns connection" },
        { id: "bluetooth", title: "Connected Devices", icon: "󰂯", desc: "Bluetooth devices, pairing, power", category: "connectivity",
          keywords: "bluetooth bt device devices pairing connected" },
        { id: "audio", title: "Sound", icon: "󰕾", desc: "Volume, output & input devices", category: "connectivity",
          keywords: "sound audio volume output input speaker microphone device" },
        { id: "panels", title: "Panels", icon: "󰍹", desc: "Taskbar and shell surfaces", category: "shell",
          keywords: "panels panel bar taskbar shell launcher osd notifications screenshot surfaces" },
        { id: "global", title: "Appearance", icon: "󰔎", desc: "Rounding, animations, fonts", category: "device",
          keywords: "appearance rounding corners animations animation motion fonts" },
        { id: "umbriel", title: "Compositor", icon: "󰖔", desc: "Layout, gaps, borders", category: "device",
          keywords: "compositor umbriel niri layout gaps borders window" },
        { id: "apps", title: "Apps", icon: "󰀻", desc: "Default apps, library, app theming", category: "system",
          keywords: "apps app applications default terminal browser file manager library all apps uninstall remove hide launcher matugen theming theme themes template templates application kitty btop gtk qt colours" },
        { id: "setup", title: "Setup", icon: "󰒓", desc: "Date & time, language, keybinds, renderer, updates", category: "system",
          keywords: "setup date time language region locale keybinds keybindings shortcuts renderer vulkan experimental updates" },
        { id: "about", title: "About", icon: "󰋼", desc: "System information", category: "system",
          keywords: "about system information version specs" }
    ]
}
