import QtQuick

// Invisible stand-in that a MouseArea drags. When it becomes active Qt starts a
// real Wayland drag carrying the selected files, so other apps can take them.
Item {
  id: proxy

  // The PaneView whose selection is being dragged. Not called `pane`, which
  // would shadow the view's id in the `pane: pane` binding at the use site.
  property var view: null
  property bool active: false

  width: 1
  height: 1

  Drag.dragType: Drag.Automatic
  Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
  Drag.proposedAction: Qt.MoveAction
  Drag.mimeData: ({ "text/uri-list": view ? view.dragUriList : "" })
  Drag.imageSource: view && view.dragGrab ? view.dragGrab.url : ""
  Drag.active: active

  Drag.onDragFinished: function (action) {
    proxy.x = 0
    proxy.y = 0
  }
}
