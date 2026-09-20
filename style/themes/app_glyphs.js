.pragma library

// Window-icon glyphs for the bar's workspace module: freedesktop application
// categories and window-class rules map to icon-font ligature names. Pure
// data/matching helpers; the desktop-entry lookup lives in Theme.appGlyphFor.
var categoryGlyphs = {
    WebBrowser: "web",
    Printing: "print",
    Security: "security",
    Network: "chat",
    Archiving: "archive",
    Compression: "archive",
    Development: "code",
    IDE: "code",
    TextEditor: "edit_note",
    Audio: "music_note",
    Music: "music_note",
    Player: "music_note",
    Recorder: "mic",
    Game: "sports_esports",
    FileTools: "files",
    FileManager: "files",
    Filesystem: "files",
    FileTransfer: "files",
    Settings: "settings",
    DesktopSettings: "settings",
    HardwareSettings: "settings",
    TerminalEmulator: "terminal",
    ConsoleOnly: "terminal",
    Utility: "build",
    Monitor: "monitor_heart",
    Midi: "graphic_eq",
    Mixer: "graphic_eq",
    AudioVideoEditing: "video_settings",
    AudioVideo: "music_video",
    Video: "videocam",
    Building: "construction",
    Graphics: "photo_library",
    "2DGraphics": "photo_library",
    RasterGraphics: "photo_library",
    TV: "tv",
    System: "host",
    Office: "content_paste"
}

// Class/regex overrides, checked before the category table.
var windowIconRules = [
    { regex: "steam(_app_(default|[0-9]+))?", flags: "", icon: "sports_esports" }
]

function matchIconRule(name, rule) {
    if (!rule || !rule.icon)
        return false
    if (rule.regex) {
        var re = new RegExp(rule.regex, rule.flags || "")
        if (re.test(name))
            return true
    } else if (rule.name === name) {
        return true
    }
    return false
}

function matchIconRuleList(name, rules) {
    if (!rules)
        return ""
    for (var i = 0; i < rules.length; i++) {
        if (matchIconRule(name, rules[i]))
            return rules[i].icon
    }
    return ""
}

function categoryGlyph(categories, fallback) {
    if (categories) {
        for (var key in categoryGlyphs) {
            if (categories.indexOf(key) !== -1)
                return categoryGlyphs[key]
        }
    }
    return fallback
}
