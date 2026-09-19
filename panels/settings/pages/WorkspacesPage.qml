pragma ComponentBehavior: Bound
import QtQuick
import ".."

// Workspaces settings. The rows live in WorkspacesSettings (shared with the
// Taskbar > Workspaces drill-in) and are the ported Caelestia
// bar.workspaces options.
NexusControls.PageBase {
    id: root
    title: "Workspaces"

    WorkspacesSettings {}
}
