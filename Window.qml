import QtQuick
import QtQml
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "components"

Item {
  id: host

  property var shell: null
  property var manifest: null
  property var service: null

  readonly property string pluginId: "athesias.omafile"
  // "floating" (and the old "popup" value) floats the window; "window" tiles it
  readonly property string windowMode: service ? service.windowMode : "window"
  readonly property bool floating: windowMode === "floating" || windowMode === "popup"
  readonly property bool asPopup: false

  property bool shown: false
  property bool closingFromHost: false
  property bool switchingSurface: false
  property string pendingPayload: "{}"

  // A named Hyprland rule floats and centres the window. It is redefined on
  // every open so it survives Hyprland config reloads and follows the setting.
  function floatRuleCommand() {
    return "(function() local r = hl.window_rule({ name = \"omafile-float\", "
      + "match = { class = \"^org.quickshell$\", title = \"^Omafile$\" }, "
      + "float = true, size = { 1280, 820 }, center = true }) "
      + "r:set_enabled(" + (host.floating ? "true" : "false") + ") "
      + "return hl.dsp.cursor.move(hl.get_cursor_pos()) end)()"
  }

  function applyFloatRule() {
    Hyprland.dispatch(host.floatRuleCommand())
  }

  onFloatingChanged: applyFloatRule()
  Component.onCompleted: applyFloatRule()

  function open(payloadJson) {
    closingFromHost = false
    pendingPayload = payloadJson && String(payloadJson).length > 0 ? String(payloadJson) : "{}"
    if (!shown) {
      // Let Hyprland take the rule before the window maps
      applyFloatRule()
      showTimer.restart()
      return
    }
    showNow()
  }

  Timer {
    id: showTimer
    interval: 60
    repeat: false
    onTriggered: host.showNow()
  }

  function showNow() {
    shown = true
    Qt.callLater(function () {
      var item = host.activeBrowser()
      if (item) item.open(host.pendingPayload)
      if (!host.asPopup) raiseTimer.restart()
    })
  }

  readonly property string raiseCommand:
    "(function() local p = hl.get_cursor_pos() "
    + "hl.dispatch(hl.dsp.focus({ window = \"title:^Omafile$\" })) "
    + "return hl.dsp.cursor.move(p) end)()"

  function raiseWindow() {
    if (host.asPopup) return
    Hyprland.dispatch(host.raiseCommand)
  }

  function close() {
    closingFromHost = true
    shown = false
    closingFromHost = false
  }

  function requestClose() {
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else shown = false
  }

  function activeBrowser() {
    return windowLoader.item
  }

  Timer {
    id: raiseTimer
    interval: 90
    repeat: false
    onTriggered: host.raiseWindow()
  }

  Component {
    id: browserComponent

    Browser {
      shell: host.shell
      manifest: host.manifest
      service: host.service
      onDismissRequested: host.requestClose()
      onCloseRequested: host.close()
      onNewWindowRequested: function (path) { host.openExtra(path) }
    }
  }

  // Extra windows from New window / Open in new window. A ListModel keeps the
  // existing windows alive when one is added or closed.
  ListModel { id: extraWindows }
  property int nextExtraId: 1

  function openExtra(path) {
    applyFloatRule()
    extraWindows.append({ wid: nextExtraId++, startPath: String(path || "") })
  }

  function closeExtra(wid) {
    for (var i = 0; i < extraWindows.count; i++) {
      if (extraWindows.get(i).wid === wid) {
        extraWindows.remove(i)
        return
      }
    }
  }

  Instantiator {
    model: extraWindows

    delegate: FloatingWindow {
      id: extraWindow
      required property int wid
      required property string startPath
      visible: true
      title: "Omafile"
      color: Color.background
      implicitWidth: 1100
      implicitHeight: 720
      minimumSize: Qt.size(640, 420)

      onVisibleChanged: if (!visible) host.closeExtra(extraWindow.wid)

      Browser {
        anchors.fill: parent
        shell: host.shell
        manifest: host.manifest
        service: host.service
        secondary: true
        secondaryStart: extraWindow.startPath
        onDismissRequested: host.closeExtra(extraWindow.wid)
        onCloseRequested: host.closeExtra(extraWindow.wid)
        onNewWindowRequested: function (path) { host.openExtra(path) }
        Component.onCompleted: open("{}")
      }
    }
  }

  FloatingWindow {
    id: window
    visible: host.shown && !host.asPopup
    title: "Omafile"
    color: Color.background
    implicitWidth: 1100
    implicitHeight: 720
    minimumSize: Qt.size(640, 420)

    onVisibleChanged: {
      if (visible) return
      if (host.closingFromHost || host.switchingSurface || host.asPopup) return
      host.requestClose()
    }

    Loader {
      id: windowLoader
      anchors.fill: parent
      active: window.visible
      sourceComponent: browserComponent
    }
  }
}
