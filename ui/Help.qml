import QtQuick

// Keyboard reference, shown with `?`. Closes on `?`, Esc or a click outside.
Rectangle {
  id: root

  required property var theme
  signal requestClose()

  color: Qt.rgba(0, 0, 0, 0.6)

  readonly property var sections: [
    { title: "Grid", keys: [
      ["h j k l  arrows", "move"],
      ["shift + move", "select a range"],
      ["ctrl + click", "add or remove one"],
      ["x  ctrl + space", "tick the one under the cursor"],
      ["ctrl + a", "select everything"],
      ["esc", "clear the selection, or quit"],
      ["enter  space", "open the viewer"],
      ["g  G", "oldest, newest"],
      ["-  +", "smaller, larger thumbnails"],
      ["r", "sync now"],
      ["q", "quit"]
    ]},
    { title: "Everywhere", keys: [
      ["d", "move to Recently Deleted"],
      ["u", "undo the last delete"],
      ["o", "open in the default app"],
      ["ctrl + c  y", "copy the image, or the files"],
      ["right-click", "open the Copy menu"],
      ["Y", "copy the path"],
      ["s", "save to ~/Downloads as JPEG or MP4"],
      ["W", "set as the Omarchy wallpaper"]
    ]},
    { title: "Viewer", keys: [
      ["h l  j k", "previous, next"],
      ["scroll", "previous, next"],
      ["space", "pause or resume a video, play a Live Photo once"],
      ["hover the circle", "play a Live Photo once"],
      ["←  →", "seek 5 seconds"],
      ["i", "camera and file details"],
      ["esc  q", "back to the grid"]
    ]}
  ]

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.requestClose()
  }

  // The card never outgrows the window: the columns wrap when it is
  // narrow, and the body scrolls when it is short.
  Rectangle {
    anchors.centerIn: parent
    width: Math.min(body.implicitWidth + 64, root.width - 32)
    height: Math.min(body.implicitHeight + 56, root.height - 32)
    radius: 12
    color: theme.darkBackground
    border.color: theme.lighterBackground
    border.width: 1
    MouseArea { anchors.fill: parent }

    Flickable {
      anchors.fill: parent
      anchors.margins: 28
      contentWidth: width
      contentHeight: body.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      WheelHandler {
        onWheel: event => {
          var dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : event.angleDelta.y / 120 * 60;
          parent.contentY = Math.max(0, Math.min(parent.contentHeight - parent.height, parent.contentY - dy));
        }
      }

    Column {
      id: body
      width: parent.width
      spacing: 18

      Text {
        text: "Keyboard"
        color: theme.brightForeground
        font.family: theme.fontFamily
        font.pixelSize: 16
        font.bold: true
      }

      Flow {
        width: parent.width
        spacing: 36
        Repeater {
          model: root.sections
          delegate: Column {
            required property var modelData
            spacing: 6
            Text {
              text: modelData.title
              color: theme.accent
              font.family: theme.fontFamily
              font.pixelSize: theme.fontSize
              font.bold: true
              bottomPadding: 4
            }
            Repeater {
              model: modelData.keys
              delegate: Row {
                required property var modelData
                spacing: 14
                Text {
                  width: 130
                  text: modelData[0]
                  color: theme.brightForeground
                  font.family: theme.fontFamily
                  font.pixelSize: theme.fontSize
                }
                Text {
                  text: modelData[1]
                  color: theme.foreground
                  font.family: theme.fontFamily
                  font.pixelSize: theme.fontSize
                }
              }
            }
          }
        }
      }

      Text {
        text: "?  or esc closes this"
        color: theme.darkForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
      }
    }
    }
  }
}
