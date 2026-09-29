import QtQuick

// Accepts files dragged from Omafile or any other app and hands them up with
// the folder they were dropped on. An empty target turns the area off.
DropArea {
  id: area

  property string target: ""

  signal filesDropped(var urls, string target)

  function blocked(urls) {
    if (area.target === "") return true
    if (area.target === "trash:") return false
    for (var i = 0; i < urls.length; i++) {
      // A folder can't be dropped onto itself
      if (decodeURIComponent(String(urls[i]).replace(/^file:\/\//, "")) === area.target) return true
    }
    return false
  }

  onEntered: function (drag) {
    if (!drag.hasUrls || blocked(drag.urls)) {
      drag.accepted = false
      return
    }
    drag.accept(Qt.CopyAction)
  }

  onDropped: function (drop) {
    if (!drop.hasUrls || blocked(drop.urls)) return
    var urls = []
    for (var i = 0; i < drop.urls.length; i++) urls.push(String(drop.urls[i]))
    drop.accept(Qt.CopyAction)
    area.filesDropped(urls, area.target)
  }
}
