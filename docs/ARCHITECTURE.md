# solstice — Architecture (layout restructure 2026-09-18)

## Guiding principle
Top-level directories are named after their role, not their origin. `shell.qml` is
the only file in the root; everything else lives in exactly one zone:

- **UI zones** — `bar/` (the bar), `panels/` (everything that pops out of it),
  `overlays/` (resident fullscreen surfaces: lockscreen, notifications, polkit, OSD).
- **Infrastructure** — `services/` (backends), `themes/` (Theme singleton + presets),
  `ui/` (shared visual toolkit), `util/` (pure helpers).
- **Data & tooling** — `assets/`, `config/` (user settings, stable paths),
  `scripts/`, `docs/`, `logs/`.

## File Tree
```
solstice/
├── shell.qml              — the ONLY file in the root (entry point: UseQApplication,
│                             IconTheme Papirus, activePanel state machine,
│                             closePanels/toggleExclusive, panel morph driver,
│                             IpcHandler solstice)
│
├── bar/                   — top bar (was modules/TopBar + modules/bar)
│   ├── TopBar.qml         — bar shell: layout slots, delegates
│   │                         (`import "./widgets" as Bar`)
│   └── widgets/           — bar atoms: LauncherIcon (OS logo), Workspaces,
│                             Clock, ActiveWindow, SystemTray,
│                             ControlCenterWidget,
│                             BarModule (delegate host) + BarWidgetBase + BarSlot
│
├── panels/                — popout panels (`import "./panels" as Panels`)
│   ├── CalendarPanel.qml  — calendar + notification history (was CalendarMenu)
│   ├── CalendarModel.js
│   ├── LauncherPanel.qml  — app search popup (bar OS icon / SUPER+SPACE)
│   ├── PowerPanel.qml     — Android-style power menu (standalone modal:
│   │                         dimmed + compositor-blurred backdrop, centred
│   │                         card with Lock/Logout/Restart/Shutdown)
│   ├── BluetoothPanel.qml — CC drill-in (showBack mode)
│   ├── SystemTrayPanel.qml, UpdateCenterPanel.qml (+ UpdateCenterView.qml body)
│   ├── controlcenter/     — `import "./panels/controlcenter" as Cc`
│   │   ├── ControlCenterPanel.qml — CC card, tile/slider editing
│   │   ├── AudioPanel.qml         — CC audio drill-in
│   │   ├── MediaPlayerCard.qml, QuickToggle.qml, CcSlider.qml
│   └── settings/          — settings window (`import "./panels/settings" as Settings`)
│       ├── SettingsPanel.qml  — Android 17 / M3E window: nav list with pastel
│       │                         icon badges + page slots (enter/leave hooks)
│       ├── NexusControls.qml  — M3E control kit (grouped cards, icon badges,
│       │                         switches, dropdowns, sliders, SearchBar,
│       │                         PageBase, PreviewTile)
│       ├── ThemeEngine.qml    — preset/monet applies + per-theme wallpaper
│       │                         memory (driven by Wallpaper & style)
│       └── pages/             — one page per section (Wallpaper & style
│                                 (default landing page: recent carousel,
│                                 live preview, Wallpapers/Colours/Fonts
│                                 sub-views), Network, Bluetooth,
│                                 Global, Umbriel, Audio, Apps, Panels
│                                 (taskbar editor incl. M3E module layout,
│                                 Launcher page, Screenshot UI page),
│                                 Workspaces, Calendar, Notifications,
│                                 About, Setup)
│
├── overlays/              — resident surfaces, always instantiated (trigger listeners)
│   ├── Lockscreen.qml     — blurred-wallpaper lock overlay: centered clock+PIN
│   │                         card, merge-morphs out of the power menu card
│   │                         (always mapped, input-masked while unlocked)
│   ├── Notifications.qml (toast shell), Polkit.qml (agent),
│   ├── VolumeOSD.qml      — OSD card: volume + Umbriel layout switches + theme applies
│   └── ScreenshotUI.qml   — bottom pill: region / window / fullscreen capture
│                             (PRINT; backend scripts/screenshot.sh)
│
├── services/              — singletons, no UI (`import "./services"` or "../services")
│   ├── qmldir             — singleton registrations
│   ├── HistoryService.qml — notification history (max 100)
│   ├── LogService.qml     — persistent error log (scripts/log-errors.sh →
│   │                         logs/errors.log; record() for shell-raised errors)
│   ├── UpdateService.qml  — dnf+flatpak polling (scripts/check-updates.sh)
│   ├── NetworkService.qml — nmcli poll every 4s (bar icon only)
│   ├── BluetoothService.qml (+ BluetoothModel.js)
│   ├── VolumeService.qml  — Pipewire.defaultAudioSink + fallback scripts/volume.sh
│   ├── WallpaperService.qml — wallpaper scan, swaybg display switch, recent
│   │                         ring (config/recent_wallpapers.json); used by the
│   │                         Settings Wallpaper & style page
│   ├── VitalsService.qml,
│   ├── SettingsService.qml — config/settings.json persistence + apply scripts
│   ├── I18n.qml           — shell language (JS dictionaries, en/de) + format
│   │                         region (QLocale for date/number labels);
│   │                         config/language.json
│   └── UmbrielService.qml  — Umbriel (niri) integration
│
├── themes/                — Theme singleton + theme-engine data (name kept for
│   │                         snapshot compatibility with install/update scripts)
│   ├── qmldir             — `singleton Theme 1.0 Theme.qml` (filesystem import)
│   ├── Theme.qml          — palette + semantic aliases + persisted UI settings
│   ├── matugen.json       — written by the matugen binary (see ~/.config/matugen)
│   ├── matugen_settings.json, theme_engine.json + preset jsons
│   └── snapshots/         — design-snapshots.py output (preserved on update)
│
├── ui/                    — shared visual toolkit (was Ui/)
│   ├── qmldir             — registrations (BarAnchor, PanelShell, MSlider, …)
│   ├── PanelShell/CaelestiaPopout/PanelSpring/PanelMorph
│   │                         — bar popout open/close + cross-panel morph
│   ├── Motion.qml/Anim.qml — M3 transition patterns (fade through, shared axis)
│   ├── PanelKit.qml, PowerAction.qml, MSlider.qml, ScrollIndicator.qml,
│   └── StateLayer.qml, IslandMorph.qml, BarAnchor.qml
│
├── util/                  — pure helpers (was Commons/): Util singleton
│                             (`import "../util"` → audio-name cleanup, icon source
│                             resolution, shell escaping)
│
├── config/                — canonical user settings & state (FileView watchers)
│   ├── topbar_settings.json, controlcenter.json, vitals.json,
│   │   bar_layout.json, bar_labels.json, bar_backgrounds.json, tray.json,
│   │   notifications.json,
│   │   calendar.json, dnd.json, gamemode.json, font_settings.json,
│   │   settings.json, theming_settings.json, volume.json, language.json,
│   │   screenshot.json,
│   └── current_wallpaper.txt, wallpaper_settings.json, pin
│
├── assets/                — screenshots and images (screenshot.png)
├── scripts/               — shell scripts + python appliers (see scripts/README-less:
│                             solstice CLI, update/update-shell, theming-apply,
│                             umbriel-apply, settings-apply, volume.sh, …)
├── logs/                  — runtime logs (git-ignored): errors.log, startup.log
└── docs/                  — this file
```

## Import system (no root qmldir)
There is no root `qs` module. Singletons are registered per-directory via local
`qmldir` files and imported as filesystem directories:

- `import "./themes"` (or `"../themes"`, `"../../themes"`, …) → `Theme`
- `import "./services"` → `HistoryService`, `UpdateService`, `NetworkService`, …
- `import "./ui"` / `"../ui"` → `BarAnchor`, `PanelShell`, `MSlider`, `Ui.Motion`, …
- `import "../util"` → `Util`
- `import "../bar" as Bar` → `Bar.TopBar`; `import "./widgets" as Bar` inside TopBar
- `import "./panels" as Panels` → `Panels.CalendarPanel`, …
- `import "./panels/controlcenter" as Cc`, `"./panels/settings" as Settings`
- `import "./overlays" as Overlays` → `Overlays.Lockscreen`, …

Rules learned the hard way:
- Never bare-import a directory whose subdirectory is also bare-imported in the same
  file (nondeterministic "X is not a type" in quickshell) — namespace those imports
  (`as Cc`).
- `themes/`, `services/`, `ui/`, `util/` are top-level siblings: safe to bare-import
  everywhere.
- A file can use types from its own directory without an import; that is how
  SettingsPanel reaches NexusControls and its pages reach ThemeEngine via
  `import ".."`.

## Panel pipeline (shell.qml)
- `activePanel` is a single int; visibility booleans of the bar panels derive from
  it. `settingsVisible` is a separate flag: the settings app is a regular
  FloatingWindow, stays open while bar panels open/close, and is hidden only by
  `hideSettings()` (or closing the window itself) — `closePanels()` leaves it alone.
- Every panel gets a `PanelLoader` (Loader with `hold` for the exit animation)
  and a `Component` wiring `showX`/`onDismissed`.
- Bar panels participate in the cross-panel morph via `panelMorphId` +
  `beginPanelMorph()` (ui/PanelMorph + ui/CaelestiaPopout).
- CC drill-ins (audio/bluetooth/updates) open OVER the control center: the CC
  stays mapped as the dimmed backdrop (`ccUnderlay` → `ControlCenterPanel.behind`
  + scrim) while the sub-panel's card grows out of the clicked tile/button
  (`PanelMorph.publishOrigin`/`beginOverlay`) and shrinks back into it on
  back/close (`CaelestiaPopout._tryMorphBack`). The card settles
  `Theme.panelDrillInInset` below the CC anchor (`PanelShell.edgeInset`), so
  the CC header + first tile row stay visible above it.
- The origin button itself hides the moment the card renders at its pose
  (`PanelMorph.originId` + `sourceReveal`, set by CaelestiaPopout.morphFrame)
  and crossfades back as the return run dissolves the card into it; the CC
  reads `sourceReveal` for the tile/audio-button opacity.
- Both directions run a container transform: the content layout scales with
  the frame (`CaelestiaPopout.contentShrink` × `contentScale` in PanelShell,
  TopLeft origin), so the panel is a miniature of itself while it grows out
  of / collapses into the button. The return is driven on the wall clock
  (`morphBackFadeAnim`: solid for 40%, then a soft 60% dissolve) so the
  shrink stays visible instead of vanishing inside the curve's fast start.
- Name → enum maps (`panelForName`, `panelForModule`) are the single source for IPC
  names and bar module ids (settings excluded — it is not part of the exclusive state).

## Settings paths
All FileView watchers and scripts use `~/.config/quickshell/solstice/config/<name>.json`
plus `config/current_wallpaper.txt` and `config/pin`. Theme-engine data stays in
`themes/` (matugen writes `themes/matugen.json` per ~/.config/matugen/config.toml),
snapshots in `themes/snapshots/`.
Init pattern: `mkdir -p ~/.config/quickshell/solstice/config; if [ ! -f … ]; then echo
default; jq '.key //= default' > /tmp/x.json && mv` — never raw echo over existing json.

## Conventions
- New popup → register in shell.qml panel enum + PanelLoader + IpcHandler, then
  `Panels.X { showX }`.
- Colors/radius/anim → only `Theme.*` (never hex literal, no raw `Easing.*`).
- Persistence → FileView + JsonAdapter + `writeAdapter()` + clamp.
- IPC → `quickshell ipc -c solstice call <target> <func>` (or `solstice` CLI).
- DP-1 exclusiveZone only TopBar; others `Theme.isPrimaryScreen(modelData)`.
- Every panel body: `Flickable { clip: true; boundsBehavior: StopAtBounds;
  contentHeight: col.implicitHeight }`.

## History
- 2026-09-01/02: ControlCenter/CalendarPanel/SolsticeMenu split into sections; dead
  network/airplane polling, misc/ wrappers, SearchField/StyledPanel removed.
- 2026-09-10: ControlCenter + MediaPanel/MediaService removed; plugins manifest
  removed; merges: categories 5→MenuCategories, calendar 3→inline in CalendarPanel,
  NotificationCard→inline in Notifications, ListRow+ModuleRow→MenuRow, settings
  primitives 7→SettingsControls (later NexusControls).
- 2026-09-17: dead-code pass (unreachable Commons facades, Ui/AnimLoader,
  Ui/AnchorAnim, services/DesignService); duplicated panel primitives merged into
  ui/PanelKit.qml and settings tiles into NexusControls.PreviewTile; merge pass
  (CAnim folded into ui/Anim.qml, CcSlider inlined → later restored, Launcher
  inlined into BarModule, StatusWidgets merged).
- 2026-09-18: directory restructure — `Ui/`→`ui/`, `Commons/`→`util/`,
  `modules/` split into `bar/` (+`widgets/`), `panels/` (+`controlcenter/`,
  `menu/`, `settings/`), `overlays/`; `CalendarMenu.qml`→`CalendarPanel.qml`;
  dead configs `cc_tiles.json`/`powermode.json` removed; `shot.png`→
  `assets/screenshot.png`. Config/theme paths intentionally unchanged.
- 2026-09-18 (later): Netanjahu module removed end to end — panel
  (`panels/NetanjahuPanel.qml`), bar widget (`StatusWidgets.Netanjahu`), bar
  module wiring (BarModule/DraggableModule/TopBar/shell.qml), Theme module
  metadata, `config/bar_layout.json` entries, and the three asset images.
- 2026-09-18 (later): Weather module removed end to end — `panels/WeatherPanel.qml`,
  `bar/widgets/WeatherWidget.qml`, `panels/settings/pages/WeatherPage.qml`,
  `services/WeatherService.qml` + `WeatherModel.js` (+ qmldir), settings nav/page,
  IPC (`toggle/show/hideWeather`), panel enum/morph maps, Theme layout defaults
  and migration, `config/weather.json`, `scripts/solstice` module case, and the
  Umbriel layer-rule namespace; PanelSpring's unused `offset` shim and
  TogglePill's `offBgAlpha` knob (only the weather pill used them) were dropped.
- 2026-09-18 (later): bar modules Network, Bluetooth, Volume, Updates and Vitals
  removed end to end — bar widgets (`StatusWidgets`, `VolumeWidget`,
  `UpdatesIndicator`, `VitalsWidget`), dead standalone panels
  (`NetworkPanel`, `VolumePanel`, `VitalsPanel`; BluetoothPanel and
  UpdateCenterPanel stay as CC drill-ins), BarModule cases/components,
  DraggableModule signals, TopBar signals/flags/handlers, shell panel
  enum/loaders/IPC/morph maps, Theme module ids/meta/layout defaults, the
  `scripts/solstice` module cases, and stale `config/bar_layout.json` ids.
  Services stay: the Control Center and the Settings pages use them.
- 2026-09-18 (later): bar drag-to-reorder removed — TopBar drag state/functions,
  drop markers + drag-ghost overlay, `BarDropModel.js` and the DraggableModule
  drag logic are gone; `BarSlot` (renamed) keeps anchor publishing, hover
  forwarding and click/wheel routing. Placement/visibility now only happens via
  Settings → Panels or the `bar` IPC (`move`/`hide`/`show`/`reset`).
- 2026-09-18 (later): Taskbar layout editor replaced by a "Components" list in
  Panels → Taskbar — one drill-in per component (Workspaces, Active window,
  Status Icons, Clock) with a "Show in taskbar" toggle and component options
  (style/scale, window title, clock format). The board/editor components were
  deleted from TopBarPage.
- 2026-09-19: Panels → Taskbar ported to the Caelestia Nexus TaskbarPanel
  (caelestia-dots/shell): sub-page header (round back + title), Behaviour
  (Persistent / Show on hover / Drag threshold stepper), Components drill-ins,
  Scroll actions (workspaces/volume/brightness). Backing behaviour added:
  bar auto-hide (`Theme.barPersistent/barShowOnHover/barDragThreshold`) with
  hover + edge-drag reveal and 2px hidden strip, panel-open keep-alive, and
  bar-background wheel actions (top half volume, bottom half brightness).
- 2026-09-19: Settings app ported 1:1 to the Caelestia Nexus design
  (caelestia-dots/shell). NexusControls rebuilt from upstream sources with the
  exact tokens (rounding/spacing/padding 4/8/12/16/20/28/32/48, fonts
  label.small 11 → title.large 22, icon 20): ConnectedRect (28/4), RowButton/
  NavRow, ToggleRow + StyledSwitch (30x51 track, 26 thumb, 31.2 pressed,
  check/cross morph), SliderRow + StyledSlider (24px track, 4px tall handle),
  StepperRow + StyledSpinBox, SelectRow, TextFieldRow, InfoRow, SearchBar,
  ButtonBase/StateLayer animations. Window chrome: 70% height × 16:9, radius
  16, nav pane width min(600, w/3) with filled NavLocations cards (32/28/4
  radii, press 12), pages capped at 800, StackView-style push/pop transition
  (exit fade 200ms, enter hold 200ms then 300ms fade + 96px slide).
  Icons use the Nerd Font Material glyph set; blob corner shapes and
  VerticalFadeFlickable edge fade are not ported.
- 2026-09-19: Bar Workspaces ported to the Caelestia implementation
  (modules/bar/components/workspaces): M3Shapes MaterialShape indicators
  (focused random shape 2/3, occupied square 1/3, free circle 1/4), rounded
  workspace container, occupied-background bands behind runs of occupied
  workspaces, gap markers for non-consecutive workspaces (showUnoccupied
  off), sliding accent active pill with asymmetric leading/trailing duration
  (activeTrail), displayType shapes/text/icons with active/occupied/label
  glyphs + capitalisation, per-workspace window icons (maxWindowIcons) with
  the app-icon resolver, per-monitor filtering and a `shown` group window
  around the active workspace. Umbriel adaptations: ui ordinals are
  synthesised when the group window reaches beyond existing workspaces,
  window ids map back to ordinals via `UmbrielService.ordinalFor`, horizontal
  bars put window icons next to the shape (vertical bars stack them below),
  and special workspaces/blur are not ported (no Umbriel equivalent).
   Settings: bar.workspaces options from Caelestia Nexus BarWorkspaces in
   WorkspacesSettings.qml, shared by Settings → Workspaces and Taskbar →
   Workspaces. New Theme keys live in config/topbar_settings.json
   (workspaceDisplayType/Shown/ActiveIndicator/ActiveTrail/OccupiedBg/
   ShowUnoccupied/PerMonitor/ShowWindows/MaxWindowIcons/Capitalisation/
   Label/OccupiedLabel/ActiveLabel/Icons/IgnoredTags); workspaceStyle is gone.
   Requires the M3Shapes QML module (github.com/soramanew/m3shapes).
- 2026-09-19 (later): Settings gains a Setup page (panels/settings/pages/
  SetupPage.qml) with appearance and maintenance entries: GTK appearance
  (nwg-look), Audio devices (pavucontrol), Shell update
  (scripts/update-shell.sh) and Reload shell (Quickshell.reload). Registered
  in the nav rail, pageFor and shell.qml openSettings valid sections.
  (Config-file shortcuts Monitors/Keybindings/Autostart/Terminal/Fish were
  later dropped with the launcher.)
- 2026-09-19: Settings gains "Wallpaper & style" as the first nav entry and
  default landing page (Caelestia Nexus WallpaperAndStyle + ColourSelect):
  large current-wallpaper preview on top, below it "Recent" — a nameless row
  of five rounded-square latest-wallpaper previews in a panel card (recents
  first via config/recent_wallpapers.json, topped up from the folder; accent
  border on the one in use, View all into the full grid) — and Wallpapers /
  Colours / Fonts pills opening in-page sub-views (round back row). Wallpapers =
  3-column grid + fit mode/folder rows; Colours = theme presets +
  Monet mode/variant settings via ThemeEngine; Fonts = curated
  typeface list (fc-list + Qt merge). shell.qml openSettings/toggleSettings
  now default to "wallpaper".
- 2026-09-19: Taskbar "Merge background" (Settings → Panels → Taskbar →
  Backgrounds, visible only while a module background is on; stored as
  `merge` in config/bar_backgrounds.json, Theme.barBackgroundMerge/
  setBarBackgroundMerge). BarSlot drops the corner(s) facing a carded
  neighbour and grows ~1px into the module gap, so runs of adjacent cards read
  as one seamless surface. Adjacency uses the live visible sibling slots of
  each zone (TopBar.mergeState revision), so a collapsed empty tray merges
  across. Module cards are also uniform now: the cross axis always spans
  Theme.barCardExtent (bar thickness − 4) instead of the module content, and
  workspaces no longer paints its own content-sized pill — every background
  goes through BarSlot's card, so all taskbar backgrounds are the same size.
- 2026-09-19 (later): SolsticeMenu launcher removed end to end — `panels/menu/`
  (SolsticeMenu shell, MenuCategories, views) deleted; ThemeEngine moved to
  `panels/settings/` (its only remaining consumer) and the theme-option list
  inlined into WallpaperStylesPage. Bar launcher module and the menu's
  session/power entry points removed (TopBar/BarSlot/BarModule/
  ControlCenterWidget signals, ControlCenterPanel power button, Theme module
  ids/meta/layout defaults + migration, TopBarPage component, stale
  `config/bar_layout.json`/`bar_backgrounds.json` ids), shell.qml panel
  enum/loader/IPC state (menu/centered/systemTrigger/openSystem) dropped and
  `scripts/solstice` lost its launcher/system modules. Setup page's config-file
  shortcuts (Monitors/Keybindings/Autostart/Terminal/Fish) removed too.
   Launcher-only leftovers followed: Settings → Search page + its
   `search*` toggles in SettingsService/settings.json, and Theme's
   `sharedMenuWidth/Height` + `config/shared_menu.json`.
- 2026-09-19 (later): Launcher re-added as a dedicated popup plus bar OS icon:
   `panels/LauncherPanel.qml` (search field bottom, app list with
   name/description/icon, keyboard up/down + Enter, Esc, outside click,
   centred or icon-anchored via `centered`, morphId "launcher"; the search
   badge background is a random M3Shapes expressive shape, re-rolled per open
   on the spatial morph, like the workspaces focus shape; a leading prefix
   (default `!`, configurable as Theme.launcherMenuPrefix)
   switches the result list to the extra menus, filtered by the rest of the
   query — entries Wallpaper/Calculator/Clipboard/Emoji with Nerd Font
   glyphs, selected via `results`/`menuMode`/`filteredMenus`; the Wallpaper
   entry autocompletes to `<prefix>wallpaper ` and opens the Caelestia wallpaper
   picker: a cover-flow PathView over WallpaperService.files filtered to the
   active engine's set (root files for every engine, the monet folders
   "monet"/"nonthemed" only for the wallpaper engine, preset folders for
   their engine — same rules as firstForTheme) with 264px slots,
   centred/scaled current item, name labels, Left/Right + Up/Down + wheel
   steering, Enter/click commits; it hides the search bar and widens the
   card while active, previews the highlighted wallpaper live
   (WallpaperService.previewWallpaper/endWallpaperPreview — spawnSwaybg
   without committing, reverted on dismiss), and commits on Enter/click
   through the settings contract: setWallpaperDisplay + rememberWallpaper +
   matugen when the wallpaper engine is active. Colour-scheme preview is not
   ported (matugen re-themes apps, so colours apply on commit); ThemeEngine
   gained `autoResync` so the picker's engine instance skips the settings
   page's boot re-sync) and
   `bar/widgets/LauncherIcon.qml` (distro glyph from /etc/os-release, Nerd
   Font nf-linux-* map, Tux fallback; background synced to the Workspaces card
   via Theme.barBackgroundEnabled). Panel state: shell.qml enum `launcher`,
   PanelLoader, `toggleLauncher/showLauncher/hideLauncher` IPC (centered arg),
   `panelForName`/`panelForModule`/`panelMorphId` entries, TopBar
   `launcherOpen`/`toggleLauncher` and BarSlot/BarModule `requestLauncher`.
   Settings: Panels → Launcher (`LauncherSettings.qml`) with taskbar visibility,
   panel width/height, descriptions, result cap and the menu prefix
   (`Theme.launcherMenuPrefix`, 1-4 non-whitespace chars, fallback "!",
   set via the Search section's TextFieldRow) persisted in
   `config/launcher.json` (Theme.launcherWidth/Height/MaxResults/
   ShowDescriptions/MenuPrefix), bar layout v2 migration puts the icon first in the left
   zone. `scripts/solstice` gained the `launcher` module so the existing
   `Mod+Space = spawn:solstice module launcher toggle` keybind opens it centred.
   The OS icon is deliberately not listed in Taskbar → Components.
- 2026-09-19 (later): Settings app decoupled from the exclusive panel state so
   it can stay open together with launcher/control center/drill-ins:
   `settingsVisible` is a shell flag instead of `activePanel === panel.settings`
   (enum slot 2 dropped), `closePanels()` replaces `closeAll()` and closes only
   bar popouts (`onDismissed`, the `hide*` IPC and `hideLauncher` use it), while
   `hideSettings()`/`toggleSettings()`/`openSettings()` drive the window alone
   (`openSettings` from the CC keeps the CC open). `panelForName`/`panelForModule`
   no longer map settings — `scripts/solstice module settings close` closes just the
   window. The bar is not affected by the settings window.
- 2026-09-19 (later): Power menu added as a standalone Android-style modal
   (`panels/PowerPanel.qml`), deliberately NOT a CC drill-in (no morph, no
   anchor, no back header): full-screen overlay with a scrim-dimmed backdrop
   (compositor layer blur via the always-on `powerpanel` namespace rule in
   `~/.config/umbriel/configs/rules.toml`, kept out of the shell namespace
   group so the opaque-shell `blur = false` override can't disable it) and a
   centred card with Lock/Logout/Restart/Shutdown. Buttons are M3Shapes
   MaterialShapes: idle circle, hover morphs into a random expressive shape
   (re-rolled per hover; pool: Square, Slanted, Pill, Pentagon, Gem, Sunny,
   Cookie 4/6/7/9/12-sided, Clover 4/8-leaf) and
   swaps to the matugen accent (primary/onAccent; Shutdown pins the always-red
   error/on_error pair).    Opened from the CC header power
   button (`ControlCenterPanel.powerRequested` → `toggleExclusive`), the
   `solstice` CLI (`scripts/solstice` gained the `power` module: `solstice module power
   toggle`, bound to SUPER+ESCAPE in
   ~/.config/umbriel/configs/keybinds-user.toml) and the raw
   `togglePower/showPower/hidePower` IPC; enum slot 9, `panelForName.power`;
   closed by backdrop click, Escape, an action or the IPC.    Lock routes to the
   lockscreen overlay (`Overlays.Lockscreen` gained `id: lockscreen`), logout
   uses `umbriel msg session-quit:skip-confirmation` with a
   `loginctl terminate-session` fallback, restart/shutdown use systemd.
   The button visual lives in `ui/PowerAction.qml` (registered in ui/qmldir),
   shared with the lockscreen merge replica.
- 2026-09-19 (later): Lockscreen reworked. Background is now the current
   wallpaper blurred on the GPU (hidden Image as the MultiEffect blur source,
   under the same dim scrim); the clock (stacked hours/minutes + date) and the
   PIN box moved into one centered card (power menu surface/rounding/shadow).
   Locking from the power menu runs a merge morph: `PowerPanel` publishes its
   card's window-local rect (`cardRect`, published on geometry change for the
   primary screen), shell.qml hands it to `lockscreen.lockFrom(rect)`, and the
   lock card starts at exactly that pose with a non-interactive replica of the
   power grid (`PowerAction`, `interactive: false`), then interpolates into the
   settled pose while the grid fades out and clock/PIN fade in (M3 emphasized,
   `durMotionSharedAxis`); the wallpaper/scrim catch up over the first third of
   the run. Plain locks (IPC/keybind) keep the FadeThrough enter. The lock
   PanelWindow is now always mapped (transparent + 0x0 input mask when
   unlocked) so the merge does not lose its first frames to a fresh surface
   map; keyboard focus stays Exclusive only while locked. Because the
   permanently-mapped surface sits below panels mapped later, shell.qml
   closes open panels on lock and refuses `openPanel`/`toggleExclusive`
   while locked (a keybind-opened panel would otherwise cover the lock and
   steal its exclusive keyboard focus). Settled box is 440 wide (clock
   `fs(96)`, PIN box 360x60) vs the power card's 400x~356 so the merge
   visibly grows.
- 2026-09-19 (later): Launcher Emoji page made functional
   (`panels/EmojiPage.qml`; data in `assets/emoji_data.js`, generated by
   `scripts/generate-emoji-data.py` from the emojibase EN compact dataset —
   1914 entries as [char, label, tags, group], 9 Unicode groups; components
   and ungrouped indicators dropped). The prefix menu's Emoji entry now
   autocompletes to `<prefix>emoji ` like Wallpaper/Web App;
   `emojiMode`/`emojiQuery`/`emojiCategory`/`emojiResults`/`emojiRecent`
   live in LauncherPanel, the grid view in EmojiPage: category chips
   (Recent + groups, Tab/Shift+Tab or wheel-horizontal for the overflow,
   hidden while a query is active), live search over label + keywords
   (label-prefix > label > tag ranking, AND per word), Up/Down/PageUp/
   PageDown/Tab from the search field (its `Keys.priority: BeforeItem`
   handler wins over the field's own key handling), click/Enter copies via
   `Quickshell.execDetached(["wl-copy", char])`, bumps the 32-entry recents
   in `config/emoji_recent.json` (FileView/JsonAdapter) and dismisses.
   Emoji text always uses `Text.QtRendering` + `Theme.emojiFontFamily`
   ("Noto Color Emoji") — the native raster path drops colour glyphs.
   `scripts/ensure-emoji-font.sh` installs the font user-level into
   ~/.local/share/fonts when no Noto Color Emoji is present (best-effort
   call from install.sh); regenerate the data with
   `python3 scripts/generate-emoji-data.py`.
- 2026-09-19 (later): Workspaces display types reduced to `shapes` and
   `numbers` (workspace ordinals shown as labels); the `text`/`icons` modes
   and the capitalisation option are gone, along with the label/icon-glyph
   Theme keys (`workspaceLabel`/`OccupiedLabel`/`ActiveLabel`/`Icons`/
   `Capitalisation`) and `workspaceIconFor()`. Existing configs fall back to
   `shapes` when `workspaceDisplayType` still holds `text` or `icons`.
- 2026-09-19 (later): Screenshot UI added (`overlays/ScreenshotUI.qml`,
  scripts/screenshot.sh). M3-Expressive bottom pill on the primary screen:
  connected segmented mode switch (Region / Window / Fullscreen) with a
  sliding accent indicator and a springy overshoot open run. No shutter
  button: clicking a segment starts that capture (Enter/Space runs the
  current mode, Left/Right cycle it, Escape/close/toggle dismiss). Opened by
  PRINT (`solstice module screenshot toggle` in keybinds-user.toml), which
  closes the bar popouts first; opening a panel or locking hides it. Capture
  unmaps the pill, then `scripts/screenshot.sh` runs slurp (region; the
  drag release captures, a cancelled selection reopens the pill). slurp is
  invoked with stdin from /dev/null: slurp 1.5+ reads boxes from stdin when
  it is a pipe, and Quickshell hands children an unread stdin pipe, so
  slurp blocked in read(0) and never mapped its selection overlay — region
  mode looked dead until that redirect. Then grim's
  full desktop (fullscreen) or grim -g on the picked window: window mode
  maps a full-screen picker (`screenshotpicker` namespace, all screens,
  `exclusionMode: Ignore` so it spans the bar's exclusive zone) that dims
  the desktop and highlights the window under the pointer via
  `UmbrielService.windowGeometries`/`windowGeometryAt` (windows on hidden
  workspaces excluded). The scrim is an odd-even filled Shape with a hole
  over the top bar, so the bar stays fully visible while picking, and the
  hovered program indicator is a pill the picker draws over the bar
  (z-above it) on the screen that owns the window; releasing the mouse over
  a window captures it, Escape/right click cancels. Saves to `~/Pictures/Screenshots`, copies to
  the clipboard and notifies. IPC: `solstice toggleScreenshot/showScreenshot/
  hideScreenshot` + target `screenshot` (mode/capture/pickAt/status).
- 2026-09-19 (later): Screenshot UI settings page added (Settings > Panels >
   Screenshot UI, `panels/settings/pages/ScreenshotSettings.qml`, registered
   as a `panels` entry in PanelsPage): default mode (the pill resets to it on
   every open), include cursor (`grim -c`), copy to clipboard, show
   notification and save folder (empty = `~/Pictures/Screenshots`, `~`
   expanded by the script). Persisted in `config/screenshot.json` via
   `Theme.screenshot*` (FileView + JsonAdapter); `ScreenshotUI` passes them
   to `scripts/screenshot.sh` through `Process.environment`
   (`SOLSTICE_SHOT_DIR/CURSOR/CLIPBOARD/NOTIFY`).
- 2026-09-19 (later): Setup gains "Language & Region" under Date & Time
   (panels/settings/pages/LanguageRegionPage.qml): system language and
   location via `localectl set-locale` (LANG + LC_TIME/LC_NUMERIC/
   LC_MONETARY/LC_MEASUREMENT, polkit prompt from the resident agent;
   applies after the next login) and a live shell language/region backed by
   the tiny services/I18n.qml (English-keyed JS dictionaries, en/de;
   config/language.json). Shell date labels (Calendar, bar Clock,
   Lockscreen, UpdateCenter) now format through `I18n.formatLocale`, and
   the page mirrors the system LC_TIME into the shell region on load.
- 2026-09-19 (later): Launcher prefix pages now cycle with TAB. TAB
   (Shift+TAB backwards) walks apps -> wallpaper -> webapp -> emoji -> apps
   by autocompleting the page prefix into the search field
   (LauncherPanel `pageOrder`/`pageIndex()`/`cyclePage()`); with no page
   active the first TAB lands on Wallpaper and the step past Emoji returns
   to the plain app list. Both key owners route through one
   `handlePageTab(event)` on the scope: the search field's BeforeItem
   handler and the result area's Keys handler. TAB is reserved for this
   everywhere: the Emoji page's Tab category-chip cycle (and its
   `cycleCategory`) and the Web App add form's `KeyNavigation.tab/backtab`
   field hopping are gone — categories switch by chip click and the three
   form fields carry a BeforeItem handler that routes TAB to the panel
   (Up/Down still hops fields; footer hint now "Tab: next page · Enter:
   install").
- 2026-09-19 (later): Setup gained a Shell section with a Keybinds page
   (`panels/settings/pages/KeybindsPage.qml`, sub-view `"keybinds"` in
   `SetupPage.qml`). The page lists the full catalog of bindable solstice actions
   (launcher, power menu, settings, screenshot, lock, calendar, system tray,
   reload) — the action strings are the `spawn:solstice …` commands from
   `scripts/solstice`, so "all possible keybindings" means every shell capability,
   bound or not, rather than only the currently-bound chords. Each row shows the effective
   Umbriel chord (or "Not bound") and rebinds by click: capture mode enables a
   `ShortcutInhibitor` on the settings `FloatingWindow` (passed down as
   `SetupPage.hostWindow` from `SettingsPanel`'s `setupComp`) so the
   compositor doesn't consume the chord being recorded; Qt key events map to
   XKB keysym names (letters/digits, shifted symbols back to the base key,
   F-keys, nav/edit keys, media/XF86 keys), Escape cancels, auto-repeat is
   ignored, a single modifier tap records a modifier-only bind ("Mod"). While
   the compositor lacks `zwp_keyboard_shortcuts_inhibit_manager_v1` (not in
   the installed Umbriel build; Quickshell logs a warning) capture still sees
   every chord the compositor doesn't already bind. `scripts/umbriel-keybinds.py`
   was extended with `list --json`, `set <action> <chord> [--file <keybinds-*.toml>] [--json]`
   and `unbind <action> [--file <keybinds-*.toml>] [--json]`. The editor
   rewrites only the quoted chord on the matching line of the target file —
   `~/.config/umbriel/configs/keybinds-user.toml` by default, or the file the
   bind currently comes from (see the Compositor entry below). Comments and
   table-form options survive; a chord owned by another bind is disabled with
   a `# solstice-off:` prefix, which `set` reuses/uncomments; an
   action bound in another include is reported via `stale`, a same-chord bind
   in an earlier file via `overrides`, and in a later file via `shadowedBy`;
   the script then runs `umbriel msg config-reload`. Editing the hand-written
   user file is deliberate: Umbriel has no unbind action, so a shell.toml
   override would leave the old chord active alongside the new one.
- 2026-09-19 (later): Setup gained the Compositor keybinds page under the new
   Compositor section (`KeybindsPage` with `scope: "compositor"`, sub-view
   `"compositor"` in `SetupPage.qml`). It lists a curated set of useful
   Umbriel actions grouped like the compositor cheatsheet: Windows (close,
   float, fullscreen, maximize, pin, center), Focus & layout (focus/move
   focus/column, cycle layout), Workspaces (next/previous, move window),
   Overview & scratchpads, Outputs, Media & brightness (volume / mic /
   brightness / playerctl), Session (config-reload, cheatsheet, session-quit).
   Everything else in the two keybind files lands in a trailing "Other binds"
   group (help description as label, raw action as subtext, spawn commands
   shortened, `spawn:solstice …` excluded — those are Shell page rows — and a
   `hiddenActions` list for actions deliberately kept off the page, currently
   `spawn:opencode`; hidden binds stay active in the config), so no other bind
   is unreachable from the UI. Rows are keyed by raw action, so parameterized
   binds (`workspace-switch:1`, `window-modify-width:0.05`, spawn commands)
   match exactly; an action bound several times shows all chords joined with
   " · ".
   Rebinding targets the file the bind lives in (`editSourceFor` → `--file`),
   so system binds are renamed in `keybinds-system.toml` and user binds stay
   in `keybinds-user.toml`; unbound catalog actions are appended to the user
   file. The list is grouped by a flattened `rowGroups` model (outer Repeater
   per group, inner Repeater per row) because delegates cannot see enclosing
   delegate ids; `rows` carries `first`/`last` flags for the card corners.
   Still open: chord-prefixed submaps and `[hot_corners]`, which are separate
   concepts and would be their own Setup pages if ever wanted.
- 2026-09-19 (later): Launcher page switches slide (always left to right),
    and larger pages reposition correctly. The prefix pages live on a page
    strip (slots 0 apps, 1 wallpaper, 2 webapp, 3 emoji): `pageOffset(slot)`
    gives a page's x in card widths (-1 parked left, 0 on screen, +1 parked
    right) and contentRoot clips, so every switch is one horizontal push —
    the incoming page enters from the left while the outgoing leaves to the
    right, whichever way TAB walked. A switch snapshots the current poses
    (`pageStart`) and interpolates them to the targets on the popout's size
    curve (500ms, `curvePanelOpen`, so slide and card resize land together):
    a page caught mid-entry becomes the next outgoing from exactly where it
    is (mashing TAB never snaps), a still-exiting page keeps going, and a
    quick reversal glides the visible page back. Typing over a page is the
    same push, and open/close snaps via `snapPageSlide()` from
    `resetState()`. TAB cycling now skips the web app page (pageOrder is
    wallpaper/emoji; from the web app page TAB steps to emoji, Shift+TAB to
    wallpaper) — it stays reachable by typing `!webapp`. The emoji and web
    app pages dropped their internal `Motion` FadeThrough (now
    `pageVisible(slot)`/`pageX(slot)` from the scope), and the search bar
    fades with `barPage` (app/emoji chrome only) instead of popping. Fixing
    the wallpaper carousel's off-centre growth also needed a popout change:
    `CaelestiaPopout` disables the `perpPos` Behavior while its
    fullWidth/fullHeight Behaviors run (`_resizing`), because `perpTarget`
    already follows the animated size — the old double animation lagged and
    the wide card grew with its old left edge pinned, then slid back to the
    screen centre.
- 2026-09-19 (later): Settings lists scroll further per mouse-wheel notch:
   a `WheelHandler` on the nav and page Flickables (`SettingsPanel`) moves the
   content by `settingsScope.wheelNotchPixels` (180px; Qt's native step is
   `wheelScrollLines * 24` ≈ 72px, with velocity acceleration) per 120
   angleDelta, clamped to the content range. Touchpads keep native pixel
   deltas (the handler only accepts mouse devices) and deeper wheel consumers
   (NexusControls sliders, the wallpaper grid) still receive the event first,
   because delivery walks items deepest-first. Tune via `wheelNotchPixels`.
- 2026-09-19 (later): The Shell and Compositor Keybinds pages were merged into
   one Setup > Shell > Keybinds page: `KeybindsPage` dropped its `scope`
   selector and always concatenates `shellCatalog` + `compositorCatalog` +
   the "Other binds" sweep, so shell actions stay on top, followed by the
   Umbriel groups and the remaining compositor binds. `SetupPage` lost the
   Compositor section, its NavRow and the `"compositor"` sub-view; the shell
   Keybinds row now reads "Shell actions and compositor shortcuts".

## Verification
```
timeout 5 quickshell -p ~/.config/quickshell/solstice/shell.qml --verbose 2>&1 | head -80  # expect "Configuration Loaded", no ERROR
quickshell ipc -c solstice call solstice state
quickshell ipc -c solstice call updates status
```
