import QtQuick
import QtQuick.Controls.Basic

Menu {
  id: root

  required property var theme
  property var items: []
  signal requestCopy(var items)

  width: 260
  padding: 4
  margins: 6
  popupType: Popup.Item
  modal: true
  dim: false

  background: Rectangle {
    radius: 8
    color: root.theme.darkBackground
    border.color: root.theme.lighterBackground
    border.width: 1
  }

  MenuItem {
    id: copyItem
    text: root.items.length > 1 ? "Copy " + root.items.length + " files" : "Copy"
    enabled: root.items.length > 0
    implicitHeight: 36
    onTriggered: root.requestCopy(root.items)

    // A modal menu blocks shortcuts on the window underneath it.
    Shortcut {
      sequence: "Ctrl+C"
      enabled: root.visible && copyItem.enabled
      onActivated: {
        root.requestCopy(root.items);
        root.close();
      }
    }

    background: Rectangle {
      radius: 4
      color: copyItem.highlighted ? root.theme.selection : "transparent"
    }

    contentItem: Item {
      implicitHeight: label.implicitHeight
      Text {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: copyItem.text
        color: root.theme.brightForeground
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize
      }
      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: "Ctrl+C"
        color: root.theme.foreground
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.fontSize - 1
      }
    }
  }
}
