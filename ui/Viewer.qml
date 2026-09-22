import QtQuick
import QtMultimedia

// Full-window view of one item: a still, a video, or a Live Photo whose
// motion half plays on Space. Navigation and closing are handled by the
// parent's key handler; this renders and drives playback.
Rectangle {
  id: root

  required property var theme
  property var item: null
  // Whether the moving picture is on screen: always for a video, toggled
  // for a Live Photo.
  property bool videoShown: false
  readonly property bool playing: video.playbackState === MediaPlayer.PlayingState
  readonly property bool hasVideo: item !== null && !!item.video

  signal requestClose()
  signal requestNext()
  signal requestPrev()
  signal requestCopyPath()
  signal requestSave()
  signal requestInfo()
  signal contextMenuRequested(real x, real y)

  // Details panel: rows of [label, value] from the info script.
  property bool infoOpen: false
  property var infoRows: []

  color: theme.darkerBackground
  visible: item !== null
  focus: false

  onItemChanged: {
    videoShown = item !== null && item.kind === "video";
  }

  // Space: pause or resume a video; for a Live Photo, play the clip once.
  function togglePlay() {
    if (!hasVideo) return;
    if (item.kind === "live") {
      playLive();
      return;
    }
    if (playing) video.pause(); else video.play();
  }

  // The moving half of a Live Photo plays once and the still comes back,
  // like pressing the picture on the phone.
  function playLive() {
    if (!item || item.kind !== "live" || videoShown) return;
    videoShown = true;
  }

  function seekBy(ms) {
    if (!videoShown || video.duration <= 0) return;
    video.seek(Math.max(0, Math.min(video.duration, video.position + ms)));
  }

  function seekTo(fraction) {
    if (video.duration <= 0) return;
    video.seek(Math.max(0, Math.min(video.duration, fraction * video.duration)));
  }

  function fmt(ms) {
    var s = Math.floor(Math.max(0, ms) / 1000);
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + ":" + (r < 10 ? "0" : "") + r;
  }

  // The grid sits underneath and selects on hover, so swallow every mouse
  // event here or moving the pointer would silently switch the photo.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.AllButtons
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) root.contextMenuRequested(mouse.x, mouse.y);
    }
    onWheel: wheel => {
      if (wheel.angleDelta.y < 0) root.requestNext(); else root.requestPrev();
      wheel.accepted = true;
    }
  }

  Item {
    id: frame
    anchors.fill: parent
    anchors.margins: 12
    anchors.bottomMargin: (root.videoShown && item && item.kind === "video") ? 56 + 44 : 56
  }

  Image {
    id: still
    anchors.fill: frame
    source: (item && item.kind !== "video") ? "file://" + item.preview : ""
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    autoTransform: true
    smooth: true
    mipmap: true
    cache: false
    visible: !root.videoShown
    sourceSize.width: 2400
  }

  Text {
    anchors.centerIn: still
    visible: still.status === Image.Loading
    text: "…"
    color: theme.darkForeground
    font.family: theme.fontFamily
    font.pixelSize: 28
  }

  Video {
    id: video
    anchors.fill: frame
    source: (root.videoShown && item && item.video) ? "file://" + item.video : ""
    fillMode: VideoOutput.PreserveAspectFit
    loops: (item && item.kind === "live") ? 1 : MediaPlayer.Infinite
    visible: root.videoShown
    onSourceChanged: if (source != "") play()
    // A Live Photo clip ends by itself: back to the still.
    onStopped: if (item && item.kind === "live") root.videoShown = false

    // Click the picture to pause or resume.
    MouseArea {
      anchors.fill: parent
      onClicked: root.togglePlay()
    }
  }

  // ---- Live Photo button ---------------------------------------------------
  // The small round button sits top-left on the picture, where the phone
  // puts its mark. Move the pointer over it and the clip plays once, then
  // the still is back. Space does the same.
  Row {
    visible: item !== null && item.kind === "live" && still.paintedWidth > 0
    x: still.x + (still.width - still.paintedWidth) / 2 + 14
    y: still.y + (still.height - still.paintedHeight) / 2 + 14
    spacing: 8
    // One ring with a dot, in whole pixels so nothing lands on a half pixel.
    Rectangle {
      width: 32; height: 32; radius: 16
      color: root.videoShown ? theme.accent : Qt.rgba(0, 0, 0, 0.5)
      border.color: root.videoShown ? theme.accent : "white"
      border.width: 2
      Rectangle {
        x: 11; y: 11
        width: 10; height: 10; radius: 5
        color: root.videoShown ? theme.darkerBackground : "white"
      }
      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.playLive()
        onClicked: root.playLive()
      }
    }
  }

  // ---- Shared Library mark -------------------------------------------------
  // The person top-right on the picture, as in the grid. Hidden while the
  // details panel sits in that corner; the panel has a Library row instead.
  // A video does not report its painted size, so it is worked out from the
  // stream's resolution and rotation the way PreserveAspectFit would.
  readonly property rect paintedVideo: {
    var md = video.metaData;
    var res = md ? md.value(MediaMetaData.Resolution) : undefined;
    if (!res || !res.width || !res.height) return Qt.rect(frame.x, frame.y, frame.width, frame.height);
    var w = res.width, h = res.height;
    var o = md.value(MediaMetaData.Orientation) || 0;
    if (o === 90 || o === 270) { var t = w; w = h; h = t; }
    var k = Math.min(frame.width / w, frame.height / h);
    return Qt.rect(frame.x + (frame.width - w * k) / 2, frame.y + (frame.height - h * k) / 2, w * k, h * k);
  }
  Rectangle {
    visible: item !== null && item.shared === true && !root.infoOpen
      && (root.videoShown || still.paintedWidth > 0)
    x: root.videoShown ? (root.paintedVideo.x + root.paintedVideo.width - width - 14)
                       : (still.x + (still.width + still.paintedWidth) / 2 - width - 14)
    y: root.videoShown ? (root.paintedVideo.y + 14)
                       : (still.y + (still.height - still.paintedHeight) / 2 + 14)
    width: 32; height: 32; radius: 16
    color: Qt.rgba(0, 0, 0, 0.5)
    border.color: "white"
    border.width: 2
    Text {
      anchors.centerIn: parent
      text: "\uf007"
      color: "white"
      font.family: theme.fontFamily
      font.pixelSize: 14
    }
  }

  // ---- Details panel (i) ---------------------------------------------------
  Rectangle {
    visible: root.infoOpen
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: 24
    // Narrow on purpose: long values (lens names) wrap instead of the panel
    // spreading across the picture.
    width: 340
    height: infoColumn.implicitHeight + 28
    radius: 10
    color: Qt.rgba(theme.darkBackground.r, theme.darkBackground.g, theme.darkBackground.b, 0.92)
    border.color: theme.lighterBackground
    border.width: 1
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    Column {
      id: infoColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: 14
      spacing: 6
      Text {
        visible: root.infoRows.length === 0
        text: "Reading…"
        color: theme.darkForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
      }
      Repeater {
        model: root.infoRows
        delegate: Row {
          required property var modelData
          width: infoColumn.width
          spacing: 12
          Text {
            width: 96
            text: modelData[0]
            color: theme.darkForeground
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
          }
          Text {
            width: infoColumn.width - 96 - 12
            text: modelData[1]
            wrapMode: Text.Wrap
            color: theme.brightForeground
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
          }
        }
      }
    }
  }

  // ---- Scrubber ----------------------------------------------------------
  Rectangle {
    id: scrubber
    visible: root.videoShown && item && item.kind === "video"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: caption.top
    height: 44
    color: theme.darkerBackground

    Row {
      anchors.fill: parent
      anchors.leftMargin: 16
      anchors.rightMargin: 16
      spacing: 14

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 30; height: 30; radius: 6
        color: playArea.containsMouse ? theme.lighterBackground : "transparent"
        Text {
          anchors.centerIn: parent
          text: root.playing ? "" : ""
          color: theme.brightForeground
          font.family: theme.fontFamily
          font.pixelSize: 13
        }
        MouseArea {
          id: playArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.togglePlay()
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.fmt(video.position)
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
        width: 40
      }

      // The timeline: click or drag anywhere on it to seek.
      Item {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - 30 - 40 - 40 - 14 * 4
        height: 24
        readonly property real fraction: video.duration > 0 ? video.position / video.duration : 0

        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width
          height: 4
          radius: 2
          color: theme.lighterBackground
          Rectangle {
            width: track.fraction * parent.width
            height: parent.height
            radius: 2
            color: theme.accent
          }
        }
        Rectangle {
          x: track.fraction * (track.width - width)
          anchors.verticalCenter: parent.verticalCenter
          width: trackArea.pressed || trackArea.containsMouse ? 14 : 10
          height: width
          radius: width / 2
          color: theme.brightForeground
          Behavior on width { NumberAnimation { duration: 80 } }
        }
        MouseArea {
          id: trackArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPressed: mouse => root.seekTo(mouse.x / width)
          onPositionChanged: mouse => { if (pressed) root.seekTo(mouse.x / width); }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.fmt(video.duration)
        color: theme.darkForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
        width: 40
        horizontalAlignment: Text.AlignRight
      }
    }
  }

  // ---- Caption: date, time, name and what the keys do ---------------------
  Rectangle {
    id: caption
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 48
    color: theme.darkBackground

    Row {
      id: captionLeft
      anchors.left: parent.left
      anchors.leftMargin: 16
      anchors.verticalCenter: parent.verticalCenter
      spacing: 14

      Text {
        text: item ? root.longDate(item) : ""
        color: theme.brightForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
      }
      Text {
        text: item ? item.time : ""
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
      }
      // The filename copies the full path, like in the grid's footer.
      Text {
        text: item ? item.name : ""
        color: nameArea.containsMouse ? theme.brightForeground : theme.darkForeground
        font.underline: nameArea.containsMouse
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
        MouseArea {
          id: nameArea
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestCopyPath()
        }
      }
    }

    Row {
      anchors.right: parent.right
      anchors.rightMargin: 12
      anchors.verticalCenter: parent.verticalCenter
      spacing: 10

      // Details toggle, same as the i key.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 28; height: 28; radius: 6
        color: root.infoOpen ? theme.lighterBackground : (infoArea.containsMouse ? theme.lighterBackground : "transparent")
        border.color: theme.lighterBackground
        border.width: 1
        Text {
          anchors.centerIn: parent
          text: "i"
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: theme.fontSize
          font.bold: true
        }
        MouseArea {
          id: infoArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestInfo()
        }
      }

      // Download: a copy of the original lands in ~/Downloads.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: saveLabel.implicitWidth + 24
        height: 28
        radius: 6
        color: saveArea.containsMouse ? theme.lighterBackground : "transparent"
        border.color: theme.lighterBackground
        border.width: 1
        Row {
          id: saveLabel
          anchors.centerIn: parent
          spacing: 8
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\uf019"
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: 12
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Download"
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize - 1
          }
        }
        MouseArea {
          id: saveArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.requestSave()
        }
      }
    }
  }

  function longDate(it) {
    var d = new Date(it.ts * 1000);
    return d.toLocaleDateString(Qt.locale("en_GB"), "dddd d MMMM yyyy");
  }
}
