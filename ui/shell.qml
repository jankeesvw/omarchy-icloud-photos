import QtQuick
import QtQuick.Controls.Basic
import Quickshell
import Quickshell.Io

// omarchy-icloud-photos: the last week of an iCloud Photos library in one window.
//
// All data comes from bin/omarchy-icloud-photos-sync, which writes index.json and
// status.json under ~/.cache/omarchy-icloud-photos. This file only renders them and
// can ask the script to run again. Nothing here writes to the library.
ShellRoot {
  id: root

  readonly property string cacheDir:
    (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/omarchy-icloud-photos"
  // Qt.resolvedUrl refuses to leave the shell directory (it returns
  // qrc:/qs-blackhole), so the scripts are found from shellDir instead.
  readonly property string binDir: Quickshell.shellDir + "/../bin"
  readonly property string syncScript: binDir + "/omarchy-icloud-photos-sync"
  readonly property string helperScript: binDir + "/omarchy-icloud-photos-helper"
  readonly property string infoScript: binDir + "/omarchy-icloud-photos-info"
  readonly property string configPath:
    (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy-icloud-photos/config"

  property var items: []
  property var days: []          // [{label, indices: [int]}]
  property int selected: -1
  // OMARCHY_ICLOUD_PHOTOS_TOUR=1: scroll the grid from top to bottom by itself and
  // open one photo at the end. Used to record the demo video.
  readonly property bool tour: Quickshell.env("OMARCHY_ICLOUD_PHOTOS_TOUR") === "1"
  property bool tourStarted: false
  // Multi-selection: ids of the checked items and the index where a shift
  // range starts. The cursor (`selected`) always counts as selected too.
  property var checked: ({})
  property int checkedCount: 0
  property int anchor: -1
  property bool viewerOpen: false
  property bool helpOpen: false
  // Details panel in the viewer (`i`): rows for the item it was fetched for.
  property bool infoOpen: false
  property var infoRows: []
  property string infoForId: ""
  property var status: ({ state: "unknown", message: "", at: "" })
  property bool indexMissing: false
  // Apple ID from the config file; empty until the first sign-in.
  property string appleId: ""
  property int rangeDays: 30
  property bool configLoaded: false
  // The sign-in card shows on first run and whenever the session has expired.
  readonly property bool needLogin: configLoaded && (appleId === "" || status.state === "auth-required")
  // Keep the grid scrolled to the newest items (the bottom) until the user
  // moves away, so a fresh sync lands in view like on the phone.
  // root.tour, not tour: the animation below has id `tour`, and an id wins
  // from a property in the same scope.
  property bool pinBottom: !root.tour   // the tour starts at the top and scrolls down
  // True while the grid is being rebuilt, so a re-created selected thumb
  // does not yank the view towards itself before the layout has settled.
  property bool suppressReveal: false

  // Thumbnail size, driven by the slider in the footer and remembered.
  property int cell: settings.cell
  // Item waiting for a yes in the delete dialog, and the last one that went
  // so it can be undone with the toast button or `u`.
  property var pendingDelete: null
  property var lastDeleted: []
  property int batchTotal: 0
  property int batchDone: 0
  property bool trashBusy: false
  // Queue of {action, item} for the helper, run one at a time. Confirming a
  // delete removes the item from the grid right away and queues the work;
  // the toast at the bottom reports progress and offers Undo when done.
  property var jobs: []
  property bool undoAfterCurrent: false
  property bool reindexDirty: false
  readonly property int gap: 8
  readonly property var current: (selected >= 0 && selected < items.length) ? items[selected] : null

  // Everything an action applies to: the checked items in grid order, or
  // just the cursor when nothing is checked.
  function targets() {
    if (checkedCount === 0) return current ? [current] : [];
    var out = [];
    for (var i = 0; i < items.length; i++) if (checked[items[i].id]) out.push(items[i]);
    return out;
  }

  function clearChecked() {
    checked = ({});
    checkedCount = 0;
    anchor = selected;
  }

  function setChecked(map) {
    var n = 0;
    for (var k in map) n++;
    checked = map;
    checkedCount = n;
  }

  // Shift: check every item between the anchor and the cursor.
  function checkRange(from, to) {
    if (from < 0) from = to;
    var map = {};
    var a = Math.min(from, to), b = Math.max(from, to);
    for (var i = a; i <= b; i++) map[items[i].id] = true;
    setChecked(map);
  }

  function toggleChecked(index) {
    var map = Object.assign({}, checked);
    var id = items[index].id;
    if (map[id]) delete map[id]; else map[id] = true;
    setChecked(map);
    anchor = index;
  }

  function checkAll() {
    var map = {};
    for (var i = 0; i < items.length; i++) map[items[i].id] = true;
    setChecked(map);
  }
  readonly property bool busy: sync.running || status.state === "syncing" || status.state === "indexing"

  Theme { id: appTheme }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: appTheme.apply(text())
    onFileChanged: reload()
  }

  FileView {
    id: indexFile
    path: root.cacheDir + "/index.json"
    watchChanges: true
    printErrors: false
    onLoaded: { root.indexMissing = false; root.applyIndex(text()); if (root.tour && !root.tourStarted) tourKickoff.start(); }
    onLoadFailed: { root.indexMissing = true; if (!sync.running && root.appleId !== "") sync.running = true; }
    onFileChanged: reload()
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: { root.appleId = root.parseAppleId(text()); root.rangeDays = root.parseDays(text()); root.configLoaded = true; }
    onLoadFailed: { root.appleId = ""; root.configLoaded = true; }
    onFileChanged: reload()
  }

  // Sign-in runs the helper with the password on stdin; Apple's 2FA code
  // goes down the same pipe when the helper asks for it.
  Process {
    id: login
    running: false
    stdinEnabled: true
    property string password: ""
    onStarted: { write(password + "\n"); password = ""; }
    stdout: SplitParser {
      onRead: data => root.loginLine(data)
    }
    onExited: (code, status) => {
      if (loginCard.busy) {
        loginCard.busy = false;
        if (loginCard.error === "") loginCard.error = "The sign-in helper stopped without an answer";
      }
    }
  }

  FileView {
    id: statusFile
    path: root.cacheDir + "/status.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.status = JSON.parse(text()); } catch (e) {}
    }
    onFileChanged: reload()
  }

  Process {
    id: sync
    command: [root.syncScript]
    running: false
    onExited: { indexFile.reload(); statusFile.reload(); }
  }

  Process { id: opener }
  Process {
    id: infoProc
    property string forId: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var rows = [];
        try { rows = JSON.parse(text); } catch (e) {}
        if (root.current && root.current.id === infoProc.forId && root.current.shared)
          rows = [["Library", "Shared"]].concat(rows);
        root.infoRows = rows;
        root.infoForId = infoProc.forId;
      }
    }
  }
  Process {
    id: wallpaper
    stdout: StdioCollector {
      onStreamFinished: toast.show(text.trim().length > 0 ? text.trim() : "Set as wallpaper", 2500)
    }
  }
  Process {
    id: saver
    stdout: StdioCollector {
      onStreamFinished: {
        var names = text.trim().split("\n").filter(function (n) { return n.length > 0; });
        if (names.length === 1) toast.show("Saved to ~/Downloads/" + names[0], 3000);
        else if (names.length > 1) toast.show("Saved " + names.length + " files to ~/Downloads", 3000);
      }
    }
  }
  Process { id: copier }

  // Re-index in the background after a delete or restore so index.json
  // matches what is on disk again; the FileView picks the result up.
  Process {
    id: reindex
    command: [root.syncScript, "--index-only"]
    running: false
    onExited: if (root.reindexDirty) { root.reindexDirty = false; running = true; }
  }

  Process {
    id: trash
    running: false
    property string action: ""
    property var subject: null
    stdout: StdioCollector {
      onStreamFinished: root.trashFinished(trash.action, trash.subject, text)
    }
    // If the helper could not start or died without output, stdout never
    // finishes; settle the dialog anyway shortly after the process is gone.
    onRunningChanged: if (!running) settle.restart()
    onStarted: watchdog.restart()
  }
  Timer {
    id: settle
    interval: 700
    onTriggered: if (root.trashBusy) root.trashFinished(trash.action, trash.subject, "")
  }
  Timer {
    id: watchdog
    interval: 120000
    onTriggered: if (root.trashBusy) { trash.running = false; root.trashFinished(trash.action, trash.subject, ""); }
  }

  FileView {
    id: settingsFile
    path: root.cacheDir + "/settings.json"
    printErrors: false
    JsonAdapter {
      id: settings
      property int cell: 176
    }
  }

  function applyIndex(raw) {
    var list;
    try { list = JSON.parse(raw); } catch (e) { return; }
    if (!Array.isArray(list)) return;
    var keepId = current ? current.id : null;
    var idx = -1;
    if (keepId) for (var j = 0; j < list.length; j++) if (list[j].id === keepId) { idx = j; break; }
    rebuild(list, idx >= 0 ? idx : list.length - 1);
  }

  function groupDays(list) {
    var groups = [];
    var byDate = {};
    for (var i = 0; i < list.length; i++) {
      var d = list[i].date;
      if (!byDate[d]) {
        byDate[d] = { label: dayLabel(list[i]), indices: [] };
        groups.push(byDate[d]);
      }
      byDate[d].indices.push(i);
    }
    return groups;
  }

  function dayLabel(it) {
    var d = new Date(it.ts * 1000);
    var today = new Date(); today.setHours(0, 0, 0, 0);
    var day = new Date(d); day.setHours(0, 0, 0, 0);
    var diff = Math.round((today - day) / 86400000);
    if (diff === 0) return "Today";
    if (diff === 1) return "Yesterday";
    var s = d.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM");
    return s.charAt(0).toUpperCase() + s.slice(1);
  }

  function parseDays(raw) {
    var m = String(raw || "").match(/^\s*DAYS=["']?(\d+)/m);
    return m ? parseInt(m[1]) : 30;
  }

  function rangeLabel() {
    var d = rangeDays;
    if (d === 7) return "last week";
    if (d === 14) return "last two weeks";
    if (d >= 28 && d <= 31) return "last month";
    if (d >= 89 && d <= 93) return "last three months";
    return "last " + d + " days";
  }

  function parseAppleId(raw) {
    var m = String(raw || "").match(/^\s*APPLE_ID=["']?([^"'\n]+)/m);
    return m ? m[1].trim() : "";
  }

  function startLogin(username, password) {
    login.password = password;
    login.command = [root.helperScript, "login", "--username", username, "--save-config"];
    login.running = true;
  }

  function loginLine(line) {
    var msg = null;
    try { msg = JSON.parse(String(line).trim()); } catch (e) { return; }
    if (msg.step === "2fa") {
      loginCard.busy = false;
      loginCard.step = "code";
    } else if (msg.step === "retry") {
      loginCard.error = msg.message || "Trying again…";
    } else if (msg.ok) {
      loginCard.busy = false;
      loginCard.reset();
      root.appleId = msg.username;
      root.status = { state: "ok", message: "", at: "" };
      toast.show("Signed in as " + msg.username);
      keys.forceActiveFocus();
      startSync();
    } else if (msg.error) {
      loginCard.busy = false;
      loginCard.error = msg.error;
      if (loginCard.step === "code") loginCard.step = "credentials";
    }
  }

  function syncedLabel() {
    if (busy) {
      // The sync script says what it is doing; the count grows as files land.
      var what = status.state === "indexing" ? (status.message || "Building thumbnails") : "Syncing";
      var n = status.count > 0 ? "  " + status.count : "";
      return what + "…" + n;
    }
    if (!status.at) return "";
    var d = new Date(status.at);
    if (isNaN(d.getTime())) return "";
    var today = new Date(); today.setHours(0, 0, 0, 0);
    var same = d >= today;
    return "synced " + (same ? "" : d.toLocaleDateString(Qt.locale("en_GB"), "d MMM ") + "at ")
      + d.toLocaleTimeString(Qt.locale("en_GB"), "HH:mm");
  }

  function move(delta, extend) {
    if (items.length === 0) return;
    pinBottom = false;
    var next = Math.max(0, Math.min(items.length - 1, selected + delta));
    if (extend) {
      if (anchor < 0 || checkedCount === 0) anchor = selected;
      selected = next;
      checkRange(anchor, selected);
    } else {
      selected = next;
      if (checkedCount > 0) clearChecked();
      anchor = selected;
    }
  }

  function jumpTo(index, extend) {
    if (items.length === 0) return;
    pinBottom = false;
    if (extend) {
      if (anchor < 0 || checkedCount === 0) anchor = selected;
      selected = index;
      checkRange(anchor, selected);
    } else {
      selected = index;
      if (checkedCount > 0) clearChecked();
      anchor = selected;
    }
  }

  function openCurrent() {
    if (!current) return;
    opener.command = ["xdg-open", current.kind === "video" ? current.video : current.path];
    opener.running = true;
  }

  function copyTargets() {
    return viewerOpen ? (current ? [current] : []) : targets();
  }

  function copyCurrent() {
    var list = copyTargets();
    if (list.length === 0) return;
    if (list.length > 1) {
      // A list of files: file managers paste them as copies, chat apps as
      // attachments. Plain text gets the paths, one per line.
      var uris = list.map(function (it) { return "file://" + encodeURI(it.kind === "video" ? it.video : it.path); });
      copier.command = ["bash", "-c", 'printf "%s\n" "$@" | wl-copy --type text/uri-list', "_"].concat(uris);
      copier.running = true;
      toast.show("Copied " + list.length + " files");
      return;
    }
    var it = list[0];
    var src = it.kind === "video" ? it.thumb : it.preview;
    var mime = /\.png$/i.test(src) ? "image/png" : "image/jpeg";
    copier.command = ["bash", "-c", 'wl-copy --type "$1" < "$2"', "_", mime, src];
    copier.running = true;
    toast.show("Copied to clipboard");
  }

  // Save to ~/Downloads in a format anything can open: HEIC becomes a
  // full-size JPEG, HDR video becomes its SDR MP4 copy, other video is
  // remuxed to MP4 without re-encoding, JPEG and PNG are copied as they are.
  // Never overwrites: a taken name gets a numbered suffix.
  function saveToDownloads() {
    var list = targets();
    if (list.length === 0) return;
    var args = [];
    for (var i = 0; i < list.length; i++) {
      var it = list[i];
      if (it.kind === "video") args.push(it.video, /\.mp4$/i.test(it.video) ? "copy" : "remux");
      else if (/\.(heic|heif|tif|tiff|dng)$/i.test(it.path)) args.push(it.path, "jpeg");
      else args.push(it.path, "copy");
    }
    saver.command = ["bash", "-c", '
      mkdir -p "$HOME/Downloads"
      while [ $# -ge 2 ]; do
        src="$1"; how="$2"; shift 2
        name=$(basename "$src"); base="${name%.*}"
        case "$how" in jpeg) ext=jpg ;; remux) ext=mp4 ;; *) ext="${name##*.}" ;; esac
        n=1; dest="$HOME/Downloads/$base.$ext"
        while [ -e "$dest" ]; do dest="$HOME/Downloads/$base-$n.$ext"; n=$((n+1)); done
        case "$how" in
          jpeg)  magick "$src" -auto-orient -quality 92 "$dest" ;;
          remux) ffmpeg -v error -y -i "$src" -c copy -movflags +faststart "$dest" || ffmpeg -v error -y -i "$src" -c:v libx264 -preset veryfast -crf 20 -c:a aac "$dest" ;;
          *)     cp -p "$src" "$dest" ;;
        esac && touch -r "$src" "$dest" && basename "$dest"
      done', "_"].concat(args);
    saver.running = true;
  }

  // W: the current photo becomes the Omarchy background. HEIC first becomes
  // a full-size JPEG in the cache, since the shell cannot decode HEIC.
  function setWallpaper() {
    if (!current || current.kind === "video") return;
    var it = current;
    wallpaper.command = ["bash", "-c", '
      src="$1"; cache="$2"; key="$3"
      case "${src,,}" in
        *.heic|*.heif|*.tif|*.tiff|*.dng)
          mkdir -p "$cache/wallpaper"
          out="$cache/wallpaper/$key.jpg"
          [ -s "$out" ] || magick "$src" -auto-orient -quality 92 "$out" || { echo "Could not convert $src"; exit 0; }
          src="$out" ;;
      esac
      omarchy-theme-bg-set "$src" >/dev/null 2>&1 && echo "Wallpaper set" || echo "Could not set the wallpaper"', "_", it.path, root.cacheDir, it.id];
    wallpaper.running = true;
  }

  // `i` in the viewer: camera and file details for the current item.
  function toggleInfo() {
    infoOpen = !infoOpen;
    if (infoOpen) fetchInfo();
  }

  function fetchInfo() {
    if (!current || infoProc.running) return;
    if (infoForId === current.id) return;
    infoRows = [];
    infoProc.forId = current.id;
    infoProc.command = [root.infoScript, current.kind === "video" ? current.path : current.path];
    infoProc.running = true;
  }

  onCurrentChanged: if (infoOpen && viewerOpen) fetchInfo()
  onViewerOpenChanged: if (!viewerOpen) infoOpen = false

  function copyPath() {
    var list = targets();
    if (list.length === 0) return;
    var paths = list.map(function (it) { return it.path; });
    copier.command = ["bash", "-c", 'printf "%s\n" "$@" | wl-copy', "_"].concat(paths);
    copier.running = true;
    toast.show(list.length === 1 ? "Copied " + paths[0] : "Copied " + list.length + " paths");
  }

  function startSync() {
    if (sync.running) return;
    sync.running = true;
  }

  function setCell(v) {
    v = Math.round(v);
    if (v === settings.cell) return;
    settings.cell = v;
    settingsFile.writeAdapter();
  }

  function askDelete() {
    var list = targets();
    if (list.length === 0) return;
    pendingDelete = list;
  }

  function confirmDelete() {
    var list = pendingDelete;
    if (!list) return;
    pendingDelete = null;
    if (checkedCount > 0) clearChecked();
    // Fresh batch: what Undo brings back is exactly what leaves now.
    lastDeleted = [];
    batchTotal = list.length;
    batchDone = 0;
    for (var i = 0; i < list.length; i++) removeItem(list[i].id);
    var q = jobs.slice();
    for (var j = 0; j < list.length; j++) q.push({ action: "delete", item: list[j] });
    jobs = q;
    runNext();
  }

  function undoDelete() {
    // Queued deletes that have not started are simply dropped.
    var rest = [], kept = 0;
    for (var i = 0; i < jobs.length; i++) {
      if (jobs[i].action === "delete") { insertItem(jobs[i].item); kept++; }
      else rest.push(jobs[i]);
    }
    if (kept > 0) { jobs = rest; batchTotal -= kept; }
    // One in flight gets its restore right behind it.
    if (trashBusy && trash.action === "delete") {
      undoAfterCurrent = true;
      toast.showBusy("Deleting " + trash.subject.name + "…  undo queued");
      return;
    }
    // Everything that already went comes back.
    var back = lastDeleted;
    lastDeleted = [];
    for (var j = 0; j < back.length; j++) enqueue({ action: "restore", item: back[j] });
    if (back.length === 0 && kept > 0) toast.show(kept === 1 ? "Kept " + rest.length : "Kept " + kept + " items");
  }

  function enqueue(job) {
    var q = jobs.slice(); q.push(job); jobs = q;
    runNext();
  }

  function runNext() {
    if (trash.running || jobs.length === 0) return;
    var q = jobs.slice();
    var job = q.shift();
    jobs = q;
    var it = job.item;
    trashBusy = true;
    trash.action = job.action;
    trash.subject = it;
    if (job.action === "delete") {
      var cmd = [root.helperScript, "delete", "--key", it.id, "--file", it.path, "--ts", String(it.ts)];
      if (it.kind === "live" && it.video) cmd.push("--companion", it.video);
      if (it.shared) cmd.push("--shared");
      trash.command = cmd;
      toast.showBusy(batchTotal > 1 ? "Deleting " + (batchDone + 1) + " of " + batchTotal + "…" : "Deleting " + it.name + "…");
    } else {
      trash.command = [root.helperScript, "restore", "--key", it.id];
      toast.showBusy("Restoring " + it.name + "…");
    }
    trash.running = true;
  }

  function trashFinished(action, it, out) {
    trashBusy = false;
    var res = null;
    var lines = String(out || "").trim().split("\n");
    try { res = JSON.parse(lines[lines.length - 1]); } catch (e) {}
    var ok = res && res.ok;
    var moreDeletes = jobs.some(function (j) { return j.action === "delete"; });
    if (action === "delete") {
      batchDone++;
      if (ok) {
        var l = lastDeleted.slice(); l.push(it); lastDeleted = l;
        if (undoAfterCurrent) {
          undoAfterCurrent = false;
          undoDelete();
        } else if (!moreDeletes) {
          toast.showUndo(lastDeleted.length === 1
            ? "Moved " + it.name + " to Recently Deleted"
            : "Moved " + lastDeleted.length + " items to Recently Deleted");
        }
      } else {
        undoAfterCurrent = false;
        insertItem(it);
        toast.show("Could not delete " + it.name + ": " + ((res && res.error) || "no answer from the helper"), 8000);
      }
    } else {
      if (ok) {
        insertItem(it);
        if (!jobs.some(function (j) { return j.action === "restore"; })) toast.show("Restored");
      } else {
        var l2 = lastDeleted.slice(); l2.push(it); lastDeleted = l2;
        toast.show("Could not restore " + it.name + ": " + ((res && res.error) || "no answer from the helper"), 8000);
      }
    }
    if (reindex.running) reindexDirty = true; else reindex.running = true;
    runNext();
  }

  function removeItem(id) {
    var list = items.slice();
    var idx = -1;
    for (var i = 0; i < list.length; i++) if (list[i].id === id) { idx = i; break; }
    if (idx < 0) return;
    list.splice(idx, 1);
    var keepSel = Math.min(idx, list.length - 1);
    rebuild(list, keepSel);
  }

  function insertItem(it) {
    var list = items.slice();
    var pos = list.length;
    for (var i = 0; i < list.length; i++) if (list[i].ts > it.ts) { pos = i; break; }
    list.splice(pos, 0, it);
    rebuild(list, pos);
  }

  // Swap in a new list without the view moving: the Repeater re-creates
  // every delegate, so the scroll position is captured first and pinned
  // again while the new content height settles.
  function rebuild(list, sel) {
    var y = grid.contentY;
    suppressReveal = true;
    grid.restoreY = pinBottom ? -1 : y;
    items = list;
    days = groupDays(list);
    selected = list.length > 0 ? Math.max(0, Math.min(sel, list.length - 1)) : -1;
    if (selected < 0) viewerOpen = false;
    if (checkedCount > 0) {
      var map = {};
      for (var i = 0; i < list.length; i++) if (checked[list[i].id]) map[list[i].id] = true;
      setChecked(map);
    }
    if (pinBottom) grid.scrollToBottom(); else grid.contentY = grid.clampY(y);
    settleTimer.restart();
  }

  // The tour, for the demo clip: scroll down with a bit of pace, open a
  // Live Photo and let it play, show the details, then back to the grid for
  // a delete and its undo. About twenty seconds.
  Timer {
    id: tourKickoff
    interval: 1500
    onTriggered: { root.tourStarted = true; tour.start(); }
  }
  SequentialAnimation {
    id: tour
    NumberAnimation {
      target: grid; property: "contentY"
      from: 0; to: Math.max(0, grid.contentHeight - grid.height)
      duration: 4500; easing.type: Easing.InOutCubic
    }
    PauseAnimation { duration: 600 }
    ScriptAction { script: {
      var last = -1;
      for (var i = root.items.length - 1; i >= 0; i--) if (root.items[i].kind === "live") { last = i; break; }
      root.jumpTo(last >= 0 ? last : root.items.length - 1, false);
    } }
    PauseAnimation { duration: 700 }
    ScriptAction { script: root.viewerOpen = true }
    PauseAnimation { duration: 1200 }
    ScriptAction { script: viewer.playLive() }
    PauseAnimation { duration: 2600 }
    ScriptAction { script: root.toggleInfo() }
    PauseAnimation { duration: 3000 }
    ScriptAction { script: root.infoOpen = false }
    PauseAnimation { duration: 500 }
    ScriptAction { script: root.viewerOpen = false }
    PauseAnimation { duration: 900 }
    ScriptAction { script: root.askDelete() }
    PauseAnimation { duration: 2000 }
    ScriptAction { script: root.confirmDelete() }
    PauseAnimation { duration: 2200 }
    ScriptAction { script: root.undoDelete() }
    PauseAnimation { duration: 2000 }
    // A range selection, then the keys overlay.
    ScriptAction { script: {
      var n = root.items.length;
      root.jumpTo(Math.max(0, n - 9), false);
      root.jumpTo(Math.max(0, n - 4), true);
    } }
    PauseAnimation { duration: 2200 }
    ScriptAction { script: { root.clearChecked(); root.helpOpen = true; } }
    PauseAnimation { duration: 2600 }
    ScriptAction { script: root.helpOpen = false }
    PauseAnimation { duration: 800 }
  }

  Timer {
    id: settleTimer
    interval: 150
    onTriggered: { root.suppressReveal = false; grid.restoreY = -1; }
  }

  FloatingWindow {
    id: win
    visible: true
    // A suffix from the environment lets a window rule single out a capture
    // instance (see omarchy-icloud-photos --demo --tour).
    title: "Omarchy iCloud Photos" + (Quickshell.env("OMARCHY_ICLOUD_PHOTOS_TITLE_SUFFIX") || "")
    implicitWidth: 1180
    implicitHeight: 800
    color: appTheme.background

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Component.onCompleted: forceActiveFocus()

      Keys.onPressed: event => {
        var k = event.key;
        var t = event.text;
        if (root.needLogin) return;
        if (root.helpOpen) {
          if (t === "?" || k === Qt.Key_Escape || t === "q") root.helpOpen = false;
          event.accepted = true;
          return;
        }
        if (t === "?") { root.helpOpen = true; event.accepted = true; return; }
        if (root.pendingDelete) {
          if (k === Qt.Key_Escape || t === "n") root.pendingDelete = null
          else if (k === Qt.Key_Return || k === Qt.Key_Enter || t === "y") root.confirmDelete()
          event.accepted = true;
          return;
        }
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0;
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
        if (t === "d") { root.askDelete(); event.accepted = true; return; }
        if (t === "u") { root.undoDelete(); event.accepted = true; return; }
        if (t === "s") { root.saveToDownloads(); event.accepted = true; return; }
        if (t === "W") { root.setWallpaper(); event.accepted = true; return; }
        if (ctrl && k === Qt.Key_A) { root.checkAll(); event.accepted = true; return; }
        // x, or ctrl+space, ticks the item under the cursor like a ctrl-click.
        if ((t === "x" || (ctrl && k === Qt.Key_Space)) && !root.viewerOpen) {
          if (root.selected >= 0) { root.pinBottom = false; root.toggleChecked(root.selected); }
          event.accepted = true; return;
        }
        if (root.viewerOpen) {
          if (t === "i") root.toggleInfo()
          else if ((k === Qt.Key_Escape || t === "q") && root.infoOpen) root.infoOpen = false
          else if (k === Qt.Key_Escape || t === "q" || k === Qt.Key_Backspace) root.viewerOpen = false
          // Arrows scrub while a video is on screen; h/l always move on.
          else if (k === Qt.Key_Left && viewer.videoShown) viewer.seekBy(-5000)
          else if (k === Qt.Key_Right && viewer.videoShown) viewer.seekBy(5000)
          else if (k === Qt.Key_Left || t === "h" || t === "k" || k === Qt.Key_Up) root.move(-1)
          else if (k === Qt.Key_Right || t === "l" || t === "j" || k === Qt.Key_Down) root.move(1)
          else if (k === Qt.Key_Space) viewer.togglePlay()
          else if (t === "o") root.openCurrent()
          else if (t === "y") root.copyCurrent()
          else if (t === "Y") root.copyPath()
          else return;
          event.accepted = true;
          return;
        }
        if (t === "q") Qt.quit()
        else if (k === Qt.Key_Escape) { if (root.checkedCount > 0) root.clearChecked(); else Qt.quit(); }
        else if (k === Qt.Key_Left || k === Qt.Key_H) root.move(-1, shift)
        else if (k === Qt.Key_Right || k === Qt.Key_L) root.move(1, shift)
        else if (k === Qt.Key_Down || k === Qt.Key_J) root.move(grid.columns, shift)
        else if (k === Qt.Key_Up || k === Qt.Key_K) root.move(-grid.columns, shift)
        else if (t === "g") { root.jumpTo(root.items.length > 0 ? 0 : -1, false); }
        else if (t === "G") { root.jumpTo(root.items.length - 1, false); root.pinBottom = true; grid.scrollToBottom(); }
        else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) { if (root.current) root.viewerOpen = true; }
        else if (t === "o") root.openCurrent()
        else if (t === "y") root.copyCurrent()
        else if (t === "Y") root.copyPath()
        else if (t === "r") root.startSync()
        else if (t === "-" || t === "_") root.setCell(root.cell - 24)
        else if (t === "+" || t === "=") root.setCell(root.cell + 24)
        else return;
        event.accepted = true;
      }

      // ---- Header ---------------------------------------------------------
      Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 56
        color: appTheme.darkBackground

        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 14
          Text {
            text: "Omarchy iCloud Photos"
            color: appTheme.brightForeground
            font.family: appTheme.fontFamily
            font.pixelSize: 17
            font.bold: true
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            text: root.rangeLabel()
            color: appTheme.foreground
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize
          }
          Text {
            anchors.baseline: parent.children[0].baseline
            text: root.items.length > 0 ? root.items.length + " items" : ""
            color: appTheme.darkForeground
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize
          }
        }

        Row {
          anchors.right: parent.right
          anchors.rightMargin: 16
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.syncedLabel()
            color: root.busy ? appTheme.accent : appTheme.darkForeground
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize - 1
          }
          Rectangle {
            width: 34; height: 34; radius: 6
            color: refreshArea.containsMouse ? appTheme.lighterBackground : "transparent"
            Text {
              anchors.centerIn: parent
              text: ""
              color: root.busy ? appTheme.accent : appTheme.foreground
              font.family: appTheme.fontFamily
              font.pixelSize: 15
              RotationAnimation on rotation {
                running: root.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1400
              }
            }
            MouseArea {
              id: refreshArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.startSync()
            }
          }
        }
      }

      // ---- Problem banner -------------------------------------------------
      Rectangle {
        id: banner
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.status.state === "error"
        height: visible ? bannerText.implicitHeight + 20 : 0
        color: Qt.rgba(appTheme.red.r, appTheme.red.g, appTheme.red.b, 0.18)
        Text {
          id: bannerText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 20
          anchors.verticalCenter: parent.verticalCenter
          text: root.status.message
          wrapMode: Text.Wrap
          color: appTheme.brightForeground
          font.family: appTheme.fontFamily
          font.pixelSize: appTheme.fontSize - 1
        }
      }

      // ---- Grid -----------------------------------------------------------
      Flickable {
        id: grid
        anchors.top: banner.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        clip: true
        contentWidth: width
        contentHeight: column.implicitHeight + 32
        boundsBehavior: Flickable.StopAtBounds

        // Flickable turns wheel ticks into flicks with inertia, which feels
        // like scrolling through syrup. Move the content directly instead:
        // pixel deltas from a touchpad as they come, one wheel notch as a
        // fixed step. Dragging with a finger still flicks.
        WheelHandler {
          acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
          onWheel: event => {
            var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 140;
            grid.contentY = Math.max(0, Math.min(grid.contentHeight - grid.height, grid.contentY - dy));
            root.pinBottom = false;
            event.accepted = true;
          }
        }

        readonly property int columns: Math.max(1, Math.floor((width - 40 + root.gap) / (root.cell + root.gap)))

        // Scroll position to hold while a rebuild changes the content height.
        property real restoreY: -1

        function clampY(y) { return Math.max(0, Math.min(contentHeight - height, y)); }
        function scrollToBottom() {
          contentY = Math.max(0, contentHeight - height);
        }
        onContentHeightChanged: {
          if (root.pinBottom) scrollToBottom();
          else if (restoreY >= 0) contentY = clampY(restoreY);
        }
        onHeightChanged: if (root.pinBottom) scrollToBottom()
        onMovementStarted: root.pinBottom = false

        function reveal(thumb) {
          if (root.pinBottom || root.suppressReveal) return;
          var p = thumb.mapToItem(grid.contentItem, 0, 0);
          var top = p.y - 44;      // keep the day label in view when moving up
          var bottom = p.y + thumb.height + 16;
          if (top < contentY) contentY = Math.max(0, top);
          else if (bottom > contentY + height) contentY = Math.min(contentHeight - height, bottom - height);
        }

        Column {
          id: column
          x: 20
          y: 16
          width: grid.width - 40
          spacing: 22

          Repeater {
            model: root.days
            delegate: Column {
              required property var modelData
              width: column.width
              spacing: 10

              Text {
                text: modelData.label + "  "
                color: appTheme.brightForeground
                font.family: appTheme.fontFamily
                font.pixelSize: appTheme.fontSize + 1
                font.bold: true
                Text {
                  anchors.left: parent.right
                  anchors.baseline: parent.baseline
                  text: modelData.indices.length
                  color: appTheme.darkForeground
                  font.family: appTheme.fontFamily
                  font.pixelSize: appTheme.fontSize
                }
              }

              Flow {
                width: parent.width
                spacing: root.gap
                Repeater {
                  model: modelData.indices
                  delegate: Thumb {
                    required property int modelData
                    index: modelData
                    item: root.items[modelData]
                    theme: appTheme
                    size: root.cell
                    selected: root.selected === modelData
                    // items[] can be a step behind the model while a delete
                    // rebuilds the grid, hence the guard.
                    checked: !!root.items[modelData] && root.checked[root.items[modelData].id] === true
                    onSelectedChanged: if (selected) grid.reveal(this)
                    // Click selects, a click on the selected one opens.
                    // Shift-click checks the range from the anchor, ctrl-click
                    // toggles one.
                    onClicked: modifiers => {
                      root.pinBottom = false;
                      if (modifiers & Qt.ShiftModifier) root.jumpTo(index, true);
                      else if (modifiers & Qt.ControlModifier) { root.selected = index; root.toggleChecked(index); }
                      else if (root.selected === index && root.checkedCount === 0) root.viewerOpen = true;
                      else root.jumpTo(index, false);
                    }
                  }
                }
              }
            }
          }
        }

      }

      // Empty / first-run state. A sibling of the grid rather than a child:
      // children of a Flickable live in its content item, which is only as
      // tall as the content, so "centered" would sit at the top.
      Column {
        anchors.centerIn: grid
        spacing: 10
        visible: root.items.length === 0 && !root.needLogin
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.busy ? "First sync…" : (root.indexMissing ? "Nothing synced yet" : "No photos in the " + root.rangeLabel().replace("last ", "last "))
          color: appTheme.foreground
          font.family: appTheme.fontFamily
          font.pixelSize: 16
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.busy ? "This can take a few minutes" : "Press r to sync, ? for the keys"
          color: appTheme.darkForeground
          font.family: appTheme.fontFamily
          font.pixelSize: appTheme.fontSize
        }
      }

      // ---- Footer ---------------------------------------------------------
      Rectangle {
        id: footer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 34
        color: appTheme.darkBackground
        // The filename is a button: click copies the full path.
        Row {
          anchors.left: parent.left
          anchors.leftMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 12
          Text {
            id: footerName
            anchors.verticalCenter: parent.verticalCenter
            text: root.checkedCount > 1 ? root.checkedCount + " selected" : (root.current ? root.current.name : "")
            color: root.checkedCount > 1 ? appTheme.accent : (nameArea.containsMouse ? appTheme.brightForeground : appTheme.darkForeground)
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize - 1
            font.underline: nameArea.containsMouse
            MouseArea {
              id: nameArea
              anchors.fill: parent
              anchors.margins: -4
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.copyPath()
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.checkedCount > 1 ? "esc clears" : (root.current ? root.current.time : "")
            color: appTheme.darkForeground
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize - 1
          }
        }
        Row {
          anchors.right: parent.right
          anchors.rightMargin: 20
          anchors.verticalCenter: parent.verticalCenter
          spacing: 18
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24; radius: 5
            color: helpArea.containsMouse ? appTheme.lighterBackground : "transparent"
            Text {
              anchors.centerIn: parent
              text: "?"
              color: appTheme.darkForeground
              font.family: appTheme.fontFamily
              font.pixelSize: appTheme.fontSize
              font.bold: true
            }
            MouseArea {
              id: helpArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.helpOpen = !root.helpOpen
            }
          }
          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf03e"
              color: appTheme.darkForeground
              font.family: appTheme.fontFamily
              font.pixelSize: 9
            }
            Slider {
              id: zoom
              anchors.verticalCenter: parent.verticalCenter
              width: 140
              from: 100
              to: 400
              stepSize: 4
              value: root.cell
              onMoved: root.setCell(value)
              background: Rectangle {
                x: zoom.leftPadding
                y: zoom.topPadding + zoom.availableHeight / 2 - height / 2
                width: zoom.availableWidth
                height: 3
                radius: 2
                color: appTheme.lighterBackground
                Rectangle {
                  width: zoom.visualPosition * parent.width
                  height: parent.height
                  radius: 2
                  color: appTheme.accent
                }
              }
              handle: Rectangle {
                x: zoom.leftPadding + zoom.visualPosition * (zoom.availableWidth - width)
                y: zoom.topPadding + zoom.availableHeight / 2 - height / 2
                width: 12; height: 12; radius: 6
                color: zoom.pressed ? appTheme.brightForeground : appTheme.foreground
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "\uf03e"
              color: appTheme.darkForeground
              font.family: appTheme.fontFamily
              font.pixelSize: 14
            }
          }
        }
      }

      // ---- Viewer overlay -------------------------------------------------
      Viewer {
        id: viewer
        anchors.fill: parent
        theme: appTheme
        item: root.viewerOpen ? root.current : null
        infoOpen: root.infoOpen
        infoRows: (root.current && root.infoForId === root.current.id) ? root.infoRows : []
        onRequestInfo: root.toggleInfo()
        onRequestNext: root.move(1)
        onRequestPrev: root.move(-1)
        onRequestCopyPath: root.copyPath()
        onRequestSave: root.saveToDownloads()
      }

      // ---- Sign-in ----------------------------------------------------------
      Rectangle {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footer.top
        visible: root.needLogin
        color: appTheme.background
        MouseArea { anchors.fill: parent; hoverEnabled: true }
        Login {
          id: loginCard
          anchors.fill: parent
          theme: appTheme
          username: root.appleId
          onSubmitCredentials: (u, p) => root.startLogin(u, p)
          onSubmitCode: code => login.write(code + "\n")
        }
      }

      // ---- Delete dialog --------------------------------------------------
      ConfirmDelete {
        anchors.fill: parent
        theme: appTheme
        items: root.pendingDelete
        onConfirmed: root.confirmDelete()
        onCancelled: root.pendingDelete = null
      }

      // ---- Help -------------------------------------------------------------
      Help {
        anchors.fill: parent
        theme: appTheme
        visible: root.helpOpen
        onRequestClose: root.helpOpen = false
      }

      // ---- Toast, with an Undo button after a delete ----------------------
      Rectangle {
        id: toast
        property string message: ""
        property bool undo: false
        property bool busy: false
        function show(m, ms) { message = m; undo = false; busy = false; opacity = 1; hide.interval = ms || 1600; hide.restart(); }
        function showUndo(m) { message = m; undo = true; busy = false; opacity = 1; hide.interval = 12000; hide.restart(); }
        function showBusy(m) { message = m; undo = false; busy = true; opacity = 1; hide.stop(); }
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        width: toastRow.implicitWidth + 32
        height: 40
        radius: 8
        color: appTheme.lighterBackground
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Row {
          id: toastRow
          anchors.centerIn: parent
          spacing: 16
          Text {
            visible: toast.busy
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf021"
            color: appTheme.accent
            font.family: appTheme.fontFamily
            font.pixelSize: 13
            RotationAnimation on rotation {
              running: toast.busy; loops: Animation.Infinite; from: 0; to: 360; duration: 1400
            }
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: toast.message
            color: appTheme.brightForeground
            font.family: appTheme.fontFamily
            font.pixelSize: appTheme.fontSize
          }
          Rectangle {
            visible: toast.undo
            anchors.verticalCenter: parent.verticalCenter
            width: undoText.implicitWidth + 20
            height: 26
            radius: 5
            color: undoArea.containsMouse ? Qt.lighter(appTheme.accent, 1.1) : appTheme.accent
            Text {
              id: undoText
              anchors.centerIn: parent
              text: "Undo  u"
              color: appTheme.darkerBackground
              font.family: appTheme.fontFamily
              font.pixelSize: appTheme.fontSize
              font.bold: true
            }
            MouseArea {
              id: undoArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.undoDelete()
            }
          }
        }
        Timer { id: hide; interval: 1600; onTriggered: toast.opacity = 0 }
      }
    }
  }
}
