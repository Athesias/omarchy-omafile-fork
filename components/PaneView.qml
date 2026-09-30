import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "../Model.js" as Model
import "../Icons.js" as Icons

Item {
  id: pane

  property var service: null
  property string path: ""
  property bool showHidden: false
  property string sortBy: "name"
  property bool descending: false
  property bool dirsFirst: true
  property string view: "list"
  property bool thumbnails: true
  property real viewScale: 1
  property var patterns: []

  // Match Nautilus: Adwaita Sans 11pt x 1.1818 text scale ~ 17px.
  property int nameSize: 17
  property int detailSize: Style.font.bodySmall
  // Grid cells grow with the name size so labels keep room
  readonly property real textGrowth: Math.max(1, nameSize / 17)
  readonly property int rowHeight: Math.round((nameSize + Style.space(12)) * viewScale)
  readonly property int listIconSize: Math.round(Style.space(18) * viewScale)
  // Grid cells follow Nautilus's medium zoom at 100%: 96px icons in a 164px cell,
  // names wrapping to at most three lines
  readonly property int gridIconSize: view === "gallery" ? Math.round(Style.space(150) * viewScale)
    : Math.round(96 * viewScale)
  readonly property int gridLabelSize: Math.round(nameSize * viewScale)
  readonly property int gridLabelLines: 3
  readonly property int gridCellWidth: Math.round(164 * viewScale * textGrowth)
  readonly property int gridCellHeight: gridIconSize + Math.ceil(gridLabelSize * 1.3) * gridLabelLines + 22
  readonly property bool compactView: view === "compact"

  function scaled(value) {
    return Math.max(1, Math.round(value * viewScale))
  }
  property bool active: false
  property string filter: ""

  property var entries: []
  property var rows: []
  property var selection: ({})
  property int cursorIndex: -1
  property int anchorIndex: -1
  property bool loading: false
  property string errorMessage: ""
  property int total: 0

  property var history: []
  property int historyIndex: -1

  property bool searching: false
  property bool searchContents: false
  property string searchQuery: ""
  property bool searchTruncated: false
  property int _searchId: 0
  property int _generation: 0
  readonly property bool virtualView: pane.path === "recent:" || pane.path === "starred:"
  property int _listId: 0
  property int _watchId: 0
  property string _watchPath: ""
  property var _pendingChunks: []
  // Search filters (What and When); only apply to search results
  property string searchType: ""
  property int searchDays: 0
  onSearchTypeChanged: if (pane.searching) rebuild()
  onSearchDaysChanged: if (pane.searching) rebuild()

  function searchFiltered(list) {
    return pane.searching ? Model.filterSearch(list, pane.searchType, pane.searchDays, Date.now()) : list
  }

  readonly property bool canGoBack: historyIndex > 0
  readonly property bool canGoForward: historyIndex >= 0 && historyIndex < history.length - 1
  readonly property int selectedCount: countSelection()
  readonly property var selectedEntries: collectSelected()

  signal activated()
  signal navigated(string newPath)
  signal openRequested(var entry)
  signal newTabRequested(string path)
  signal contextRequested(var entry, real sceneX, real sceneY)
  signal statusChanged()
  signal zoomRequested(real delta)
  signal dropRequested(var urls, string dest)
  signal columnsMenuRequested(real x, real y)

  // List view columns; Name takes whatever the others leave
  property var columns: ({ size: true, type: true, modified: true })
  readonly property var baseWeights: ({ size: 0.14, type: 0.16, modified: 0.18 })

  function colWeight(key) {
    if (key !== "name") return pane.columns[key] === false ? 0 : pane.baseWeights[key]
    var used = 0
    for (var k in pane.baseWeights) used += colWeight(k)
    return 1 - used
  }

  // Drag and drop: what a drag started here carries
  property string dragUriList: ""
  // The grab result must stay referenced or its image URL stops resolving
  property var dragGrab: null

  function fileUri(path) {
    return "file://" + encodeURI(String(path)).replace(/#/g, "%23").replace(/\?/g, "%3F")
  }

  function prepareDrag(entry) {
    var paths = selectedPaths()
    if (paths.indexOf(entry.path) < 0) paths = [entry.path]
    var uris = []
    for (var i = 0; i < paths.length; i++) uris.push(fileUri(paths[i]))
    dragUriList = uris.join("\r\n") + "\r\n"
    dragBadgeGlyph.text = Icons.glyphFor(entry)
    dragBadgeLabel.text = paths.length === 1 ? entry.name : Model.formatCount(paths.length, "item", "items")
    Qt.callLater(function () {
      dragBadge.grabToImage(function (result) { pane.dragGrab = result })
    })
  }

  // Press on an item: keep a multi-selection so it can be dragged; a plain
  // click without dragging narrows it to that item on release.
  function pressItem(index, mouse) {
    var extend = (mouse.modifiers & Qt.ShiftModifier) !== 0
    var toggle = (mouse.modifiers & Qt.ControlModifier) !== 0
    if (!extend && !toggle && pane.selection[pane.rows[index][0]]) {
      pane.cursorIndex = index
      return true
    }
    pane.setCursor(index, extend, toggle)
    return false
  }

  // Where a press lands on an item rather than the space around it. Presses
  // elsewhere start a selection box, as in Nautilus.
  function hotIndex(x, y) {
    var index = hitTestIndex(x, y)
    if (index < 0) return -1
    var v = activeView()
    var pt = bandArea.mapToItem(v, x, y)
    if (pane.view === "list") return pt.x < header.width * colWeight("name") ? index : -1
    if (pane.compactView) return index
    var cw = gridView.cellWidth
    var cols = Math.max(1, Math.floor(gridView.width / cw))
    var cx = (pt.x + v.contentX) - (index % cols) * cw
    return (cx > cw * 0.12 && cx < cw * 0.88) ? index : -1
  }

  function countSelection() {
    var n = 0
    for (var k in selection) if (selection[k]) n++
    return n
  }

  function collectSelected() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (selection[rows[i][0]]) out.push(Model.decodeEntry(rows[i], pane.path))
    return out
  }

  function selectedPaths() {
    var out = []
    for (var i = 0; i < rows.length; i++)
      if (selection[rows[i][0]]) out.push(Model.decodeEntry(rows[i], pane.path).path)
    return out
  }

  function activeView() {
    return pane.view === "list" ? listView : gridView
  }

  function columnsPerRow() {
    if (pane.view === "list" || gridView.cellWidth <= 0) return 1
    return Math.max(1, Math.floor(gridView.width / gridView.cellWidth))
  }

  function hitTestIndex(x, y) {
    var v = activeView()
    var pt = bandArea.mapToItem(v, x, y)
    if (pt.x < 0 || pt.y < 0 || pt.x > v.width || pt.y > v.height) return -1
    return v.indexAt(pt.x + v.contentX, pt.y + v.contentY)
  }

  function selectInBand(x1, y1, x2, y2, base) {
    var v = activeView()
    var a = bandArea.mapToItem(v, Math.min(x1, x2), Math.min(y1, y2))
    var b = bandArea.mapToItem(v, Math.max(x1, x2), Math.max(y1, y2))
    var left = a.x + v.contentX
    var top = a.y + v.contentY
    var right = b.x + v.contentX
    var bottom = b.y + v.contentY
    var next = {}
    for (var k in base) if (base[k]) next[k] = true
    if (pane.view === "list") {
      var h = pane.rowHeight
      if (h > 0) {
        var i0 = Math.max(0, Math.floor(top / h))
        var i1 = Math.min(pane.rows.length - 1, Math.floor(bottom / h))
        for (var i = i0; i <= i1; i++) next[pane.rows[i][0]] = true
      }
    } else {
      var cw = gridView.cellWidth
      var chh = gridView.cellHeight
      if (cw > 0 && chh > 0) {
        var cols = Math.max(1, Math.floor(gridView.width / cw))
        var c0 = Math.max(0, Math.floor(left / cw))
        var c1 = Math.min(cols - 1, Math.floor(right / cw))
        var r0 = Math.max(0, Math.floor(top / chh))
        var r1 = Math.floor(bottom / chh)
        for (var r = r0; r <= r1; r++) {
          for (var c = c0; c <= c1; c++) {
            var idx = r * cols + c
            if (idx >= 0 && idx < pane.rows.length) next[pane.rows[idx][0]] = true
          }
        }
      }
    }
    pane.selection = next
    pane.statusChanged()
  }

  function cursorEntry() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return null
    return Model.decodeEntry(rows[cursorIndex], pane.path)
  }

  function navigate(target, recordHistory) {
    var raw = String(target || "")
    var next = raw === "recent:" || raw === "starred:"
      ? raw
      : Model.normalizePath(Model.expandTilde(raw, Quickshell.env("HOME") || ""))
    if (!next) return
    if (pane.searching) {
      if (_searchId && service) service.cancel(_searchId)
      _searchId = 0
      pane.searching = false
      pane.searchQuery = ""
    }
    if (recordHistory !== false) pushHistory(next)
    pane.path = next
    reload()
    pane.navigated(next)
    if (service) service.noteRecent(next)
  }

  function pushHistory(next) {
    var trimmed = history.slice(0, historyIndex + 1)
    if (trimmed.length === 0 || trimmed[trimmed.length - 1] !== next) trimmed.push(next)
    if (trimmed.length > 100) trimmed = trimmed.slice(trimmed.length - 100)
    history = trimmed
    historyIndex = trimmed.length - 1
  }

  function goBack() {
    if (!canGoBack) return
    historyIndex = historyIndex - 1
    pane.path = history[historyIndex]
    reload()
    pane.navigated(pane.path)
  }

  function goForward() {
    if (!canGoForward) return
    historyIndex = historyIndex + 1
    pane.path = history[historyIndex]
    reload()
    pane.navigated(pane.path)
  }

  function goUp() {
    if (pane.virtualView) return
    var parent = Model.parentPath(pane.path)
    if (parent === pane.path) return
    var leaving = Model.basename(pane.path)
    navigate(parent)
    Qt.callLater(function () { focusName(leaving) })
  }

  function focusName(name) {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i][0] === name) {
        setCursor(i, false, false)
        activeView().positionViewAtIndex(i, ListView.Contain)
        return
      }
    }
  }

  function hitToRow(hit) {
    return [
      String(hit.name || ""), String(hit.kind || "f"),
      Number(hit.size) || 0, Number(hit.mtime) || 0,
      Number(hit.mode) || 0, null, String(hit.path || "")
    ]
  }

  function startSearch(query) {
    if (!service || !pane.path) return
    var trimmed = String(query || "").trim()
    pane.searchQuery = trimmed
    if (!trimmed) {
      stopSearch()
      return
    }
    if (_searchId) service.cancel(_searchId)
    if (_listId) service.cancel(_listId)
    pane.searching = true
    pane.searchTruncated = false
    pane.errorMessage = ""
    pane.loading = true
    pane.entries = []
    pane.rows = []
    pane.selection = ({})
    pane.cursorIndex = -1
    pane._pendingChunks = []

    var searchGeneration = ++pane._generation

    _searchId = service.searchFiles(pane.path, trimmed, pane.searchContents ? "content" : "substring", pane.showHidden,
      function (hit) {
        if (searchGeneration !== pane._generation) return
        pane._pendingChunks.push(pane.hitToRow(hit))
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (searchGeneration !== pane._generation) return
        pane.loading = false
        pane.searchTruncated = msg.truncated === true
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (searchGeneration !== pane._generation) return
        pane.loading = false
        if (msg.code !== "ECANCELED")
          pane.errorMessage = String(msg.message || "Search failed")
        pane.statusChanged()
      })
  }

  function stopSearch() {
    if (_searchId && service) service.cancel(_searchId)
    _searchId = 0
    pane.searchQuery = ""
    pane.searchTruncated = false
    if (pane.searching) {
      pane.searching = false
      reload()
    }
  }

  // Starred items, read fresh each time; missing files drop out of the view
  function loadStarred() {
    if (!service) return
    var generation = ++pane._generation
    _pendingChunks = []
    entries = []
    rows = []
    selection = ({})
    cursorIndex = -1
    anchorIndex = -1
    errorMessage = ""
    total = 0
    rebuildTimer.stop()
    if (_watchId) {
      service.unwatch(_watchId, _watchPath)
      _watchId = 0
      _watchPath = ""
    }
    var list = service.starred
    if (list.length === 0) {
      loading = false
      statusChanged()
      return
    }
    loading = true
    service.statPaths(list, function (items) {
      if (generation !== pane._generation) return
      var out = []
      for (var i = 0; i < (items || []).length; i++) {
        var it = items[i]
        if (!it || !it.kind) continue
        out.push([String(it.name), String(it.kind), Number(it.size) || 0, Number(it.mtime) || 0,
          Number(it.mode) || 0, it.linkTarget || null, String(it.path)])
      }
      pane.entries = out
      pane.loading = false
      pane.total = out.length
      pane.rebuild()
    })
  }

  Connections {
    target: pane.service
    function onStarredChanged() { if (pane.path === "starred:") pane.loadStarred() }
  }

  function loadRecent() {
    if (!service) return
    if (_listId) service.cancel(_listId)
    var generation = ++pane._generation
    _pendingChunks = []
    entries = []
    rows = []
    selection = ({})
    cursorIndex = -1
    anchorIndex = -1
    errorMessage = ""
    loading = true
    total = 0
    rebuildTimer.stop()

    if (_watchId) {
      service.unwatch(_watchId, _watchPath)
      _watchId = 0
      _watchPath = ""
    }

    _listId = service.listRecent(
      function (chunk) {
        if (generation !== pane._generation) return
        var acc = pane._pendingChunks
        for (var i = 0; i < chunk.length; i++) acc.push(chunk[i])
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        pane.total = Number(msg.total) || 0
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        if (String(msg.code || "") !== "ECANCELED")
          pane.errorMessage = String(msg.message || "Could not read recent files")
        pane.statusChanged()
      })
  }

  function reload() {
    if (!service || !pane.path) return
    if (pane.virtualView) {
      if (pane.path === "starred:") loadStarred()
      else loadRecent()
      return
    }
    if (pane.searching) return
    if (_listId) service.cancel(_listId)
    _pendingChunks = []
    entries = []
    rows = []
    selection = ({})
    cursorIndex = -1
    anchorIndex = -1
    errorMessage = ""
    loading = true
    total = 0
    rebuildTimer.stop()

    var generation = ++pane._generation

    _listId = service.listDirectory(pane.path, pane.showHidden,
      function (chunk) {
        if (generation !== pane._generation) return
        var acc = pane._pendingChunks
        for (var i = 0; i < chunk.length; i++) acc.push(chunk[i])
        if (!rebuildTimer.running) rebuildTimer.start()
      },
      function (msg) {
        if (generation !== pane._generation) return
        pane.loading = false
        pane.total = Number(msg.total) || pane._pendingChunks.length
        pane.flushChunks()
        pane.statusChanged()
      },
      function (msg) {
        if (generation !== pane._generation) return
        if (String(msg.code || "") === "ECANCELED") return
        pane.loading = false
        pane.errorMessage = String(msg.message || msg.code || "Cannot open this folder")
        pane.statusChanged()
      })

    rewatch()
  }

  function flushChunks() {
    if (_pendingChunks.length === 0 && entries.length === 0) {
      rows = []
      return
    }
    if (_pendingChunks.length > 0) {
      entries = entries.concat(_pendingChunks)
      _pendingChunks = []
    }
    if (loading) {
      rows = searchFiltered(Model.filterByPatterns(pane.filter ? Model.filterRaw(entries, pane.filter) : entries, pane.patterns))
      statusChanged()
      return
    }
    rebuild()
  }

  function rebuild() {
    var filtered = searchFiltered(Model.filterByPatterns(((pane.searching || pane.virtualView) || !pane.filter)
      ? entries : Model.filterRaw(entries, pane.filter), pane.patterns))
    if (pane.virtualView
        || (!pane.searching && Model.isDefaultOrder(pane.sortBy, pane.descending, pane.dirsFirst)))
      rows = filtered
    else
      rows = Model.sortRaw(filtered, pane.sortBy, pane.descending, pane.dirsFirst)
    if (cursorIndex >= rows.length) cursorIndex = rows.length - 1
    statusChanged()
  }

  function rewatch() {
    if (!service) return
    if (_watchId) service.unwatch(_watchId, _watchPath)
    _watchPath = pane.path
    _watchId = service.watchDirectory(pane.path, function () { refreshTimer.restart() })
  }

  function refresh() {
    var keepSelection = ({})
    for (var k in selection) keepSelection[k] = selection[k]
    var keepCursor = cursorIndex
    var restore = function () {
      pane.selection = keepSelection
      if (keepCursor >= 0 && keepCursor < pane.rows.length) pane.cursorIndex = keepCursor
    }
    reload()
    Qt.callLater(restore)
  }

  function setCursor(index, extend, toggle) {
    if (index < 0 || index >= rows.length) return
    cursorIndex = index
    if (toggle) {
      var name = rows[index][0]
      var next = ({})
      for (var k in selection) next[k] = selection[k]
      next[name] = !next[name]
      selection = next
      anchorIndex = index
      return
    }
    if (extend && anchorIndex >= 0) {
      var lo = Math.min(anchorIndex, index)
      var hi = Math.max(anchorIndex, index)
      var range = ({})
      for (var i = lo; i <= hi; i++) range[rows[i][0]] = true
      selection = range
      return
    }
    var single = ({})
    single[rows[index][0]] = true
    selection = single
    anchorIndex = index
  }

  function toggleCursorSelection() {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return
    var name = rows[cursorIndex][0]
    var next = ({})
    for (var k in selection) next[k] = selection[k]
    next[name] = !next[name]
    selection = next
    anchorIndex = cursorIndex
  }

  function invertSelection() {
    var next = ({})
    for (var i = 0; i < rows.length; i++) {
      var name = rows[i][0]
      if (!selection[name]) next[name] = true
    }
    selection = next
  }

  function selectAll() {
    var all = ({})
    for (var i = 0; i < rows.length; i++) all[rows[i][0]] = true
    selection = all
  }

  function clearSelection() {
    selection = ({})
  }

  function jumpCursor(index, extend) {
    if (rows.length === 0) return
    var target = Math.max(0, Math.min(rows.length - 1, index))
    setCursor(target, extend, false)
    activeView().positionViewAtIndex(target, ListView.Contain)
  }

  function moveCursor(delta, extend) {
    if (rows.length === 0) return
    var next = cursorIndex < 0 ? 0 : cursorIndex + delta
    next = Math.max(0, Math.min(rows.length - 1, next))
    setCursor(next, extend, false)
    activeView().positionViewAtIndex(next, ListView.Contain)
  }

  function openEntry(entry) {
    if (!entry) return
    if (entry.isDir && !entry.isBroken) navigate(entry.path)
    else pane.openRequested(entry)
  }

  // Names longer than three wrapped lines lose their middle, keeping the
  // extension in view, as Nautilus does. probe is a hidden Text laid out
  // like the label, so the lines are measured rather than guessed.
  function fitGridLabel(name, probe) {
    var text = String(name || "")
    probe.text = text
    if (probe.lineCount <= pane.gridLabelLines) return text
    var tail = Math.min(8, Math.floor(text.length / 4))
    var head = text.length - tail - 1
    var cut = text
    while (head > 1) {
      head -= 1
      cut = text.substring(0, head).replace(/\s+$/, "") + "\u2026" + text.substring(text.length - tail)
      probe.text = cut
      if (probe.lineCount <= pane.gridLabelLines) return cut
    }
    return cut
  }

  function previewable(entry) {
    if (!pane.thumbnails) return false
    if (entry.isDir || entry.isBroken) return false
    if (entry.size <= 0 || entry.size > 24000000) return false
    var e = entry.ext
    return e === "png" || e === "jpg" || e === "jpeg" || e === "gif"
      || e === "webp" || e === "bmp" || e === "svg" || e === "ico" || e === "avif"
  }

  // Image files load directly; videos and PDFs get a thumbnail from the helper
  function previewSource(entry) {
    if (pane.previewable(entry)) return Util.fileUrl(entry.path)
    if (!pane.thumbnails || !service || !Model.hasThumbnailer(entry)) return ""
    if (service.thumbVersion < 0) return ""
    return service.thumbnailFor(entry.path, entry.mtime)
  }

  // Middle click, as in Nautilus: a folder opens in a new tab, a file opens
  function middleOpen(entry) {
    if (!entry) return
    if (entry.isDir && !entry.isBroken) pane.newTabRequested(entry.path)
    else pane.openRequested(entry)
  }

  function openRow(row) {
    openEntry(Model.decodeEntry(row, pane.path))
  }

  function activateCursor() {
    openEntry(cursorEntry())
  }

  function setSort(column) {
    if (pane.virtualView) return
    if (pane.sortBy === column) pane.descending = !pane.descending
    else {
      pane.sortBy = column
      pane.descending = false
    }
    rebuild()
  }

  function setSortOrder(column, descending) {
    if (pane.virtualView) return
    pane.sortBy = column
    pane.descending = descending === true
    rebuild()
  }

  property bool ready: true

  onServiceChanged: {
    if (service && pane.path && !loading && rows.length === 0) reload()
  }

  onShowHiddenChanged: if (ready) reload()
  onFilterChanged: if (ready) rebuild()
  onPatternsChanged: if (ready) rebuild()
  onDirsFirstChanged: if (ready) rebuild()

  Component.onDestruction: {
    if (service && _watchId) service.unwatch(_watchId, _watchPath)
    if (service && _listId) service.cancel(_listId)
    if (service && _searchId) service.cancel(_searchId)
  }

  Timer {
    id: rebuildTimer
    interval: 120
    repeat: false
    onTriggered: pane.flushChunks()
  }

  Timer {
    id: stallWatchdog
    interval: 6000
    repeat: false
    running: pane.loading && pane.rows.length === 0 && pane.path !== ""
    onTriggered: {
      if (!pane.loading || pane.rows.length > 0) return
      if (!pane.service) return
      if (pane.searching) return
      pane.loading = false
      pane.reload()
    }
  }

  Timer {
    id: refreshTimer
    interval: 180
    repeat: false
    onTriggered: pane.refresh()
  }

  readonly property color fg: Color.foreground
  readonly property color bg: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted

  // Rendered off to the side and grabbed as the picture under the cursor while dragging
  Rectangle {
    id: dragBadge
    z: -1
    width: badgeRow.implicitWidth + Style.space(20)
    height: badgeRow.implicitHeight + Style.space(12)
    radius: Style.cornerRadius
    color: Util.alpha(pane.accent, 0.9)

    Row {
      id: badgeRow
      anchors.centerIn: parent
      spacing: Style.space(8)

      Text {
        id: dragBadgeGlyph
        color: pane.bg
        font.family: Style.font.family
        font.pixelSize: pane.nameSize
      }

      Text {
        id: dragBadgeLabel
        color: pane.bg
        font.family: Style.font.family
        font.pixelSize: pane.nameSize
      }
    }
  }

  Rectangle {
    anchors.fill: parent
    color: paneDrop.containsDrag ? Qt.tint(pane.bg, Util.alpha(pane.accent, 0.08)) : pane.bg
    border.width: Math.max(1, Style.space(1))
    border.color: pane.active
      ? Util.alpha(pane.accent, 0.5) : Util.alpha(pane.fg, 0.15)

    DropTarget {
      id: paneDrop
      anchors.fill: parent
      target: pane.virtualView || pane.searching ? "" : pane.path
      onFilesDropped: function (urls, dest) { pane.dropRequested(urls, dest) }
    }

    MouseArea {
      id: bandArea
      anchors.fill: parent
      z: 10
      acceptedButtons: Qt.LeftButton | Qt.RightButton

      property real originX: 0
      property real originY: 0
      property real currentX: 0
      property real currentY: 0
      property bool banding: false
      property var baseSelection: ({})
      property int pressedIndex: -1
      property bool moved: false
      property int pressModifiers: 0

      onPressed: function (mouse) {
        pane.activated()
        if (pane.view === "list" && mouse.y < header.height + Style.space(1)) {
          mouse.accepted = false
          return
        }
        if (pane.hotIndex(mouse.x, mouse.y) >= 0) {
          mouse.accepted = false
          return
        }
        pressedIndex = pane.hitTestIndex(mouse.x, mouse.y)
        moved = false
        if (mouse.button === Qt.RightButton) {
          if (pressedIndex >= 0) {
            var hit = Model.decodeEntry(pane.rows[pressedIndex], pane.path)
            if (!pane.selection[pane.rows[pressedIndex][0]]) pane.setCursor(pressedIndex, false, false)
            pane.contextRequested(hit, mouse.x, mouse.y)
            return
          }
          pane.clearSelection()
          pane.contextRequested(null, mouse.x, mouse.y)
          return
        }
        pressModifiers = mouse.modifiers
        var additive = (mouse.modifiers & Qt.ControlModifier) !== 0
        baseSelection = additive ? pane.selection : ({})
        if (!additive) pane.clearSelection()
        originX = mouse.x
        originY = mouse.y
        currentX = mouse.x
        currentY = mouse.y
        banding = true
      }

      onPositionChanged: function (mouse) {
        if (!banding) return
        if (!moved && Math.abs(mouse.x - originX) + Math.abs(mouse.y - originY) < Style.space(4)) return
        moved = true
        currentX = mouse.x
        currentY = mouse.y
        pane.selectInBand(originX, originY, currentX, currentY, baseSelection)
      }

      onReleased: {
        // A click beside an item's name still selects that item
        if (banding && !moved && pressedIndex >= 0)
          pane.setCursor(pressedIndex, (pressModifiers & Qt.ShiftModifier) !== 0,
            (pressModifiers & Qt.ControlModifier) !== 0)
        banding = false
      }
      onCanceled: banding = false
      onDoubleClicked: function (mouse) {
        if (pressedIndex >= 0 && pressedIndex < pane.rows.length)
          pane.openEntry(Model.decodeEntry(pane.rows[pressedIndex], pane.path))
      }

      // Ctrl + wheel zooms, like Nautilus; plain wheel scrolls the list below
      onWheel: function (wheel) {
        if ((wheel.modifiers & Qt.ControlModifier) === 0) {
          wheel.accepted = false
          return
        }
        if (wheel.angleDelta.y !== 0) pane.zoomRequested(wheel.angleDelta.y > 0 ? 0.1 : -0.1)
      }

      Rectangle {
        visible: bandArea.banding && bandArea.moved
        x: Math.min(bandArea.originX, bandArea.currentX)
        y: Math.min(bandArea.originY, bandArea.currentY)
        width: Math.abs(bandArea.currentX - bandArea.originX)
        height: Math.abs(bandArea.currentY - bandArea.originY)
        color: Util.alpha(pane.accent, 0.15)
        border.width: 1
        border.color: Util.alpha(pane.accent, 0.6)
      }
    }

    Column {
      anchors.fill: parent
      anchors.margins: Style.space(1)
      spacing: 0

      Row {
        id: header
        width: parent.width
        height: pane.view === "list" ? Math.max(Style.space(22), pane.detailSize + Style.space(9)) : 0
        visible: pane.view === "list"
        spacing: 0

        Repeater {
          model: [
            { key: "name", label: "Name", weight: 0.52 },
            { key: "size", label: "Size", weight: 0.14 },
            { key: "type", label: "Type", weight: 0.16 },
            { key: "modified", label: "Modified", weight: 0.18 }
          ]

          delegate: Item {
            required property var modelData
            objectName: "header-" + modelData.key
            width: header.width * pane.colWeight(modelData.key)
            visible: width > 0
            height: header.height

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              text: modelData.label + ((pane.sortBy === modelData.key && !pane.virtualView)
                ? (pane.descending ? "  " + Icons.actionGlyph("chevronDown")
                  : "  " + Icons.actionGlyph("chevronUp")) : "")
              color: pane.sortBy === modelData.key ? pane.accent : Util.alpha(pane.fg, 0.6)
              font.family: Style.font.family
              font.pixelSize: pane.detailSize
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function (mouse) {
                if (mouse.button === Qt.RightButton) {
                  var pt = mapToItem(pane, mouse.x, mouse.y)
                  pane.columnsMenuRequested(pt.x, pt.y)
                } else pane.setSort(modelData.key)
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: pane.view === "list" ? 1 : 0
        visible: pane.view === "list"
        color: Util.alpha(pane.fg, 0.12)
      }

      ListView {
        id: listView
        width: parent.width
        height: parent.height - header.height - (pane.view === "list" ? 1 : 0)
        clip: true
        model: pane.rows
        cacheBuffer: 400
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: pane.cursorIndex
        visible: pane.view === "list"

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)

          width: listView.width
          height: pane.rowHeight
          color: rowDrop.containsDrag ? Util.alpha(pane.accent, 0.3)
            : pane.selection[modelData[0]]
            ? Util.alpha(pane.accent, Style.selectedFillAlpha)
            : (rowHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent")

          DropTarget {
            id: rowDrop
            anchors.fill: parent
            target: row.entry.isDir && !row.entry.isBroken && !pane.virtualView ? row.entry.path : ""
            onFilesDropped: function (urls, dest) { pane.dropRequested(urls, dest) }
          }

          DragProxy {
            id: rowDrag
            view: pane
            active: rowMouse.drag.active
          }

          Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.width: pane.cursorIndex === index && pane.active ? 1 : 0
            border.color: Util.alpha(pane.accent, 0.8)
          }

          HoverHandler { id: rowHover }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            drag.target: rowDrag
            drag.threshold: Style.space(8)
            property bool narrowOnRelease: false
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[row.modelData[0]]) pane.setCursor(row.index, false, false)
                pane.contextRequested(row.entry, mouse.x + row.x, mouse.y + row.y)
                return
              }
              if (mouse.button === Qt.MiddleButton) { pane.middleOpen(row.entry); return }
              narrowOnRelease = pane.pressItem(row.index, mouse)
              if (mouse.button === Qt.LeftButton) pane.prepareDrag(row.entry)
            }
            onReleased: {
              if (narrowOnRelease && !drag.active) pane.setCursor(row.index, false, false)
              narrowOnRelease = false
            }
            onDoubleClicked: function (mouse) {
              if (mouse.button !== Qt.LeftButton) return
              pane.openEntry(row.entry)
            }
          }

          Row {
            anchors.fill: parent
            spacing: 0

            Item {
              width: header.width * pane.colWeight("name")
              height: parent.height

              Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Item {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  height: pane.listIconSize

                  Text {
                    anchors.centerIn: parent
                    visible: !rowThumb.visible
                    text: Icons.glyphFor(row.entry)
                    color: row.entry.isBroken ? Color.urgent
                      : (row.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.75))
                    font.family: Style.font.family
                    font.pixelSize: pane.scaled(Style.font.icon)
                  }

                  Image {
                    id: rowThumb
                    anchors.fill: parent
                    visible: source != "" && status === Image.Ready
                    source: pane.previewSource(row.entry)
                    sourceSize.width: Style.space(36)
                    sourceSize.height: pane.listIconSize * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                  }
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - Style.space(28)
                  text: row.entry.name
                  color: row.entry.isHidden ? Util.alpha(pane.fg, 0.55) : pane.fg
                  font.family: Style.font.family
                  font.pixelSize: pane.scaled(pane.nameSize)
                  font.italic: row.entry.isLink
                  elide: Text.ElideMiddle
                }
              }
            }

            Text {
              width: header.width * pane.colWeight("size")
              visible: width > 0
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              horizontalAlignment: Text.AlignRight
              rightPadding: Style.space(10)
              text: row.entry.isDir
                ? (row.entry.childCount === null ? "" : Model.formatCount(row.entry.childCount, "item", "items"))
                : Model.formatSize(row.entry.size)
              color: Util.alpha(pane.fg, 0.7)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(pane.detailSize)
            }

            Text {
              width: header.width * pane.colWeight("type")
              visible: width > 0
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.kindLabel(row.entry)
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(pane.detailSize)
              elide: Text.ElideRight
            }

            Text {
              width: header.width * pane.colWeight("modified")
              visible: width > 0
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              leftPadding: Style.space(10)
              text: Model.formatDate(row.entry.mtime, Date.now())
              color: Util.alpha(pane.fg, 0.55)
              font.family: Style.font.family
              font.pixelSize: pane.scaled(pane.detailSize)
              elide: Text.ElideRight
            }
          }
        }
      }

      GridView {
        id: gridView
        width: parent.width
        height: parent.height - header.height
        clip: true
        model: pane.rows
        visible: pane.view !== "list"
        cellWidth: pane.compactView ? Math.round(Style.space(230) * pane.viewScale)
          : pane.view === "gallery" ? Math.round(Style.space(190) * pane.viewScale * pane.textGrowth)
          : pane.gridCellWidth
        cellHeight: pane.compactView ? pane.rowHeight + Style.space(2)
          : pane.view === "gallery" ? Math.round(Style.space(206) * pane.viewScale * pane.textGrowth)
          : pane.gridCellHeight
        cacheBuffer: 600
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
          id: cell
          required property var modelData
          required property int index

          readonly property var entry: Model.decodeEntry(modelData, pane.path)

          width: gridView.cellWidth - (pane.compactView ? Style.space(4) : 0)
          height: gridView.cellHeight
          radius: Style.cornerRadius
          color: cellDrop.containsDrag ? Util.alpha(pane.accent, 0.3)
            : pane.selection[modelData[0]]
            ? Util.alpha(pane.accent, Style.selectedFillAlpha)
            : (cellHover.hovered ? Util.alpha(pane.fg, Style.hoverFillAlpha) : "transparent")
          border.width: pane.cursorIndex === index && pane.active ? 1 : 0
          border.color: Util.alpha(pane.accent, 0.8)

          HoverHandler { id: cellHover }

          DropTarget {
            id: cellDrop
            anchors.fill: parent
            target: cell.entry.isDir && !cell.entry.isBroken && !pane.virtualView ? cell.entry.path : ""
            onFilesDropped: function (urls, dest) { pane.dropRequested(urls, dest) }
          }

          DragProxy {
            id: cellDrag
            view: pane
            active: cellMouse.drag.active
          }

          MouseArea {
            id: cellMouse
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            drag.target: cellDrag
            drag.threshold: Style.space(8)
            property bool narrowOnRelease: false
            onPressed: function (mouse) {
              pane.activated()
              if (mouse.button === Qt.RightButton) {
                if (!pane.selection[cell.modelData[0]]) pane.setCursor(cell.index, false, false)
                pane.contextRequested(cell.entry, mouse.x + cell.x, mouse.y + cell.y)
                return
              }
              if (mouse.button === Qt.MiddleButton) { pane.middleOpen(cell.entry); return }
              narrowOnRelease = pane.pressItem(cell.index, mouse)
              pane.prepareDrag(cell.entry)
            }
            onReleased: {
              if (narrowOnRelease && !drag.active) pane.setCursor(cell.index, false, false)
              narrowOnRelease = false
            }
            onDoubleClicked: function (mouse) {
              if (mouse.button !== Qt.LeftButton) return
              pane.openEntry(cell.entry)
            }
          }

          Row {
            anchors.fill: parent
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)
            visible: pane.compactView

            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              height: pane.listIconSize

              Text {
                anchors.centerIn: parent
                visible: !compactThumb.visible
                text: Icons.glyphFor(cell.entry)
                color: cell.entry.isBroken ? Color.urgent
                  : (cell.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.75))
                font.family: Style.font.family
                font.pixelSize: pane.scaled(Style.font.icon)
              }

              Image {
                id: compactThumb
                anchors.fill: parent
                visible: pane.compactView && source != "" && status === Image.Ready
                source: pane.compactView ? pane.previewSource(cell.entry) : ""
                sourceSize.width: Style.space(36)
                sourceSize.height: pane.listIconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(26)
              text: cell.entry.name
              color: cell.entry.isHidden ? Util.alpha(pane.fg, 0.55) : pane.fg
              font.family: Style.font.family
              font.pixelSize: pane.scaled(pane.nameSize)
              font.italic: cell.entry.isLink
              elide: Text.ElideMiddle
            }
          }

          Column {
            anchors.centerIn: pane.view === "gallery" ? parent : undefined
            anchors.horizontalCenter: pane.view === "gallery" ? undefined : parent.horizontalCenter
            y: pane.view === "gallery" ? 0 : 8
            width: parent.width - Style.space(12)
            spacing: pane.view === "gallery" ? Style.space(6) : 6
            visible: !pane.compactView

            Item {
              anchors.horizontalCenter: parent.horizontalCenter
              width: pane.view === "gallery" ? parent.width : pane.gridIconSize
              height: pane.gridIconSize

              Text {
                anchors.centerIn: parent
                visible: !thumb.visible
                text: Icons.glyphFor(cell.entry)
                color: cell.entry.isBroken ? Color.urgent
                  : (cell.entry.isDir ? pane.accent : Util.alpha(pane.fg, 0.8))
                font.family: Style.font.family
                font.pixelSize: pane.view === "gallery" ? pane.scaled(Style.font.displayLarge * 2)
                  : Math.round(pane.gridIconSize * 0.72)
              }

              Image {
                id: thumb
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                visible: !pane.compactView && source != "" && status === Image.Ready
                source: !pane.compactView ? pane.previewSource(cell.entry) : ""
                sourceSize.width: pane.view === "gallery" ? Style.space(360) : pane.gridIconSize * 2
                sourceSize.height: pane.gridIconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
              }
            }

            Text {
              id: gridName
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              text: pane.view === "gallery" ? cell.entry.name : fitted
              color: pane.fg
              font.family: Style.font.family
              font.pixelSize: pane.view === "gallery" ? pane.scaled(pane.nameSize) : pane.gridLabelSize
              maximumLineCount: pane.view === "gallery" ? 1 : pane.gridLabelLines
              wrapMode: pane.view === "gallery" ? Text.NoWrap : Text.WrapAtWordBoundaryOrAnywhere
              elide: pane.view === "gallery" ? Text.ElideMiddle : Text.ElideRight

              property string fitted: ""
              readonly property string fitName: cell.entry.name
              readonly property int fitSize: pane.gridLabelSize
              readonly property string fitView: pane.view
              function refit() {
                if (pane.view === "grid" && width > 0) fitted = pane.fitGridLabel(fitName, labelProbe)
              }
              onFitNameChanged: refit()
              onFitSizeChanged: refit()
              onFitViewChanged: refit()
              onWidthChanged: refit()
              Component.onCompleted: refit()

              Text {
                id: labelProbe
                visible: false
                width: gridName.width
                font.family: gridName.font.family
                font.pixelSize: gridName.font.pixelSize
                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
              }
            }
          }
        }
      }
    }

    Text {
      anchors.centerIn: parent
      visible: pane.errorMessage !== "" && pane.rows.length === 0
      width: parent.width - Style.space(40)
      horizontalAlignment: Text.AlignHCenter
      text: pane.errorMessage
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    Text {
      anchors.centerIn: parent
      visible: !pane.loading && pane.errorMessage === "" && pane.rows.length === 0
      text: pane.searching ? "No matches"
        : (pane.virtualView ? (pane.path === "starred:" ? "Nothing starred yet. Right click a file and choose Star." : "Nothing opened recently")
          : (pane.filter ? "Nothing matches" : "Empty folder"))
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.centerIn: parent
      visible: pane.loading && pane.rows.length === 0
      text: pane.searching ? "Searching" : "Reading"
      color: Util.alpha(pane.fg, 0.45)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
}
