import QtQuick

// Accepts files dragged from Omafile or any other app and hands them up with
// the folder they were dropped on. An empty target turns the area off.
DropArea {
  id: area

  property string target: ""

  signal filesDropped(var urls, string target)

  // drag.urls can come through empty on Wayland even when the drag carries
  // text/uri-list, so read the raw list as well
  function urlsOf(ev) {
    var out = []
    var list = ev.urls || []
    for (var i = 0; i < list.length; i++) out.push(String(list[i]))
    if (out.length === 0 && typeof ev.getDataAsString === "function") {
      var raw = String(ev.getDataAsString("text/uri-list") || "")
      var lines = raw.split(/\r?\n/)
      for (var j = 0; j < lines.length; j++) {
        var line = lines[j].trim()
        if (line && line.charAt(0) !== "#") out.push(line)
      }
    }
    return out
  }

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
    if (!drag.hasUrls || blocked(urlsOf(drag))) {
      drag.accepted = false
      return
    }
    drag.accept(Qt.CopyAction)
  }

  onDropped: function (drop) {
    var urls = urlsOf(drop)
    if (urls.length === 0 || blocked(urls)) return
    drop.accept(Qt.CopyAction)
    area.filesDropped(urls, area.target)
  }
}
