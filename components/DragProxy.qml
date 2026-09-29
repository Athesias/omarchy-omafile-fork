import QtQuick

// Invisible stand-in that a MouseArea drags. When it becomes active Qt starts a
// real Wayland drag carrying the selected files, so other apps can take them.
Item {
  id: proxy

  property var pane: null
  property bool active: false

  width: 1
  height: 1

  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
  Drag.proposedAction: Qt.MoveAction
  Drag.mimeData: ({ "text/uri-list": pane ? pane.dragUriList : "" })
  Drag.imageSource: pane ? pane.dragImage : ""
  Drag.active: active

  Drag.onDragFinished: function (action) {
    proxy.x = 0
    proxy.y = 0
  }
}
