import QtQuick

// Modal question before an item goes to iCloud's Recently Deleted. Shows the
// thumbnail so the wrong photo cannot slip through unnoticed.
Rectangle {
  id: root

  required property var theme
  property var items: null   // list, or null when hidden
  readonly property int count: items ? items.length : 0
  readonly property var item: count > 0 ? items[0] : null
  // Items from the Shared Library go to the Recently Deleted that every
  // participant sees, so the dialog says so.
  readonly property int sharedCount: items ? items.filter(function (i) { return i.shared === true; }).length : 0

  signal confirmed()
  signal cancelled()

  visible: count > 0
  color: Qt.rgba(0, 0, 0, 0.6)

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.cancelled()
  }

  Rectangle {
    anchors.centerIn: parent
    width: 420
    height: card.implicitHeight + 48
    radius: 10
    color: theme.darkBackground
    border.color: theme.lighterBackground
    border.width: 1

    MouseArea { anchors.fill: parent }  // clicks inside do not close

    Column {
      id: card
      anchors.centerIn: parent
      width: parent.width - 48
      spacing: 16

      // One big thumbnail, or a strip of the first few for a batch.
      Image {
        visible: root.count === 1
        anchors.horizontalCenter: parent.horizontalCenter
        width: 200
        height: 200
        source: item ? "file://" + item.thumb : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }
      Row {
        visible: root.count > 1
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 6
        Repeater {
          model: root.count > 1 ? Math.min(root.count, 5) : 0
          delegate: Image {
            required property int index
            width: 68; height: 68
            source: "file://" + root.items[index].thumb
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
          }
        }
        Rectangle {
          visible: root.count > 5
          width: 68; height: 68
          color: theme.lighterBackground
          Text {
            anchors.centerIn: parent
            text: "+" + (root.count - 5)
            color: theme.brightForeground
            font.family: theme.fontFamily
            font.pixelSize: 15
            font.bold: true
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.count > 1 ? "Move " + root.count + " items to Recently Deleted?" : "Move to Recently Deleted?"
        color: theme.brightForeground
        font.family: theme.fontFamily
        font.pixelSize: 15
        font.bold: true
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: root.count === 1 && item ? (item.name + "  ·  " + item.date + " " + item.time) : (root.count > 1 ? root.items[0].date + " to " + root.items[root.count - 1].date : "")
        color: theme.foreground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: (root.count > 1 ? "They disappear" : "It disappears")
          + (root.sharedCount === 0 ? " from your library on every device"
             : root.sharedCount === root.count ? " from the Shared Library, for everyone in it,"
             : " from your library and, for " + root.sharedCount + " of them, from the Shared Library for everyone in it,")
          + " and " + (root.count > 1 ? "stay" : "stays") + " in Recently Deleted for 30 days."
        color: theme.darkForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 12

        Rectangle {
          width: 130; height: 36; radius: 6
          color: cancelArea.containsMouse ? theme.lighterBackground : theme.background
          border.color: theme.lighterBackground
          Text {
            anchors.centerIn: parent
            text: "Cancel  esc"
            color: theme.foreground
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
          }
          MouseArea {
            id: cancelArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancelled()
          }
        }

        Rectangle {
          width: 170; height: 36; radius: 6
          color: okArea.containsMouse ? Qt.lighter(theme.red, 1.1) : theme.red
          Text {
            anchors.centerIn: parent
            text: "Delete  enter"
            color: theme.darkerBackground
            font.family: theme.fontFamily
            font.pixelSize: theme.fontSize
            font.bold: true
          }
          MouseArea {
            id: okArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmed()
          }
        }
      }
    }
  }
}
