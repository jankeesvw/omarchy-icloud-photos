import QtQuick
import QtQuick.Controls.Basic

// Sign-in card for the empty state and for an expired session: Apple ID and
// password first, then the six-digit code Apple pushes to a trusted device.
// The password goes straight to the helper's stdin and is never stored.
Item {
  id: root

  required property var theme
  property string username: ""
  property string step: "credentials"   // credentials | code | pcs
  property bool busy: false
  property string error: ""

  signal submitCredentials(string username, string password)
  signal submitCode(string code)
  signal retryPcs()

  function reset() {
    step = "credentials";
    busy = false;
    error = "";
    passwordField.text = "";
    codeField.text = "";
  }

  function focusFirst() {
    if (step === "pcs") return;
    if (step === "code") codeField.forceActiveFocus();
    else if (usernameField.text.length === 0) usernameField.forceActiveFocus();
    else passwordField.forceActiveFocus();
  }

  onVisibleChanged: if (visible) focusFirst()
  onStepChanged: focusFirst()

  component Field: TextField {
    id: field
    width: 300
    height: 38
    color: theme.brightForeground
    placeholderTextColor: theme.darkForeground
    font.family: theme.fontFamily
    font.pixelSize: theme.fontSize + 1
    leftPadding: 12
    rightPadding: 12
    selectByMouse: true
    background: Rectangle {
      radius: 6
      color: theme.background
      border.width: field.activeFocus ? 2 : 1
      border.color: field.activeFocus ? theme.accent : theme.lighterBackground
    }
  }

  component Button: Rectangle {
    id: btn
    property string label: ""
    property bool primary: true
    property bool enabled: true
    signal clicked()
    width: 300
    height: 38
    radius: 6
    color: !enabled ? theme.muted : (btnArea.containsMouse ? Qt.lighter(theme.accent, 1.1) : theme.accent)
    Text {
      anchors.centerIn: parent
      text: btn.label
      color: theme.darkerBackground
      font.family: theme.fontFamily
      font.pixelSize: theme.fontSize
      font.bold: true
    }
    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (btn.enabled) btn.clicked()
    }
  }

  Rectangle {
    anchors.centerIn: parent
    width: card.implicitWidth + 64
    height: card.implicitHeight + 56
    radius: 12
    color: theme.darkBackground
    border.color: theme.lighterBackground
    border.width: 1

    Column {
      id: card
      anchors.centerIn: parent
      spacing: 12

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "\uf0c2"
        color: theme.accent
        font.family: theme.fontFamily
        font.pixelSize: 34
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.step === "pcs" ? "Allow access on your iPhone"
              : (root.step === "code" ? "Enter the verification code" : "Sign in to iCloud")
        color: theme.brightForeground
        font.family: theme.fontFamily
        font.pixelSize: 17
        font.bold: true
      }
      Text {
        width: 300
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.step === "pcs"
          ? "Apple sent an access request to your trusted devices. Tap Allow Access. With Advanced Data Protection this lasts about an hour."
          : (root.step === "code"
            ? "Apple sent a six-digit code to your trusted devices."
            : "Your password is only used to open a session and is not stored. The session lasts a few months.")
        color: theme.darkForeground
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
      }

      Item { width: 1; height: 4 }

      Column {
        spacing: 10
        visible: root.step === "credentials"
        Field {
          id: usernameField
          text: root.username
          placeholderText: "Apple ID"
          inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
          onAccepted: passwordField.forceActiveFocus()
        }
        // Password with an eye to show it: a typo is the usual reason for a
        // "wrong password" and there is no other way to see one.
        Item {
          width: 300
          height: 38
          Field {
            id: passwordField
            anchors.fill: parent
            placeholderText: "Password"
            echoMode: showPassword.checked ? TextInput.Normal : TextInput.Password
            rightPadding: 40
            onAccepted: signInButton.clicked()
          }
          Text {
            id: showPassword
            property bool checked: false
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: checked ? "\uf070" : "\uf06e"
            color: eyeArea.containsMouse || checked ? theme.foreground : theme.darkForeground
            font.family: theme.fontFamily
            font.pixelSize: 14
            MouseArea {
              id: eyeArea
              anchors.fill: parent
              anchors.margins: -6
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: { showPassword.checked = !showPassword.checked; passwordField.forceActiveFocus(); }
            }
          }
        }
        Button {
          id: signInButton
          label: root.busy ? "Signing in…" : "Sign in"
          enabled: !root.busy && usernameField.text.trim().length > 0 && passwordField.text.length > 0
          onClicked: {
            root.error = "";
            root.busy = true;
            root.submitCredentials(usernameField.text.trim(), passwordField.text);
          }
        }
      }

      Column {
        spacing: 10
        visible: root.step === "pcs"
        Text {
          visible: root.error.length === 0
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Waiting for your device…"
          color: theme.foreground
          font.family: theme.fontFamily
          font.pixelSize: theme.fontSize
        }
        Button {
          visible: root.error.length > 0
          label: "Try again"
          onClicked: { root.error = ""; root.retryPcs(); }
        }
      }

      Column {
        spacing: 10
        visible: root.step === "code"
        Field {
          id: codeField
          placeholderText: "123456"
          horizontalAlignment: TextInput.AlignHCenter
          font.pixelSize: 22
          font.letterSpacing: 6
          maximumLength: 6
          inputMethodHints: Qt.ImhDigitsOnly
          validator: RegularExpressionValidator { regularExpression: /[0-9]{0,6}/ }
          onTextChanged: if (text.length === 6 && !root.busy) verifyButton.clicked()
          onAccepted: verifyButton.clicked()
        }
        Button {
          id: verifyButton
          label: root.busy ? "Verifying…" : "Verify"
          enabled: !root.busy && codeField.text.length === 6
          onClicked: {
            root.error = "";
            root.busy = true;
            root.submitCode(codeField.text);
          }
        }
      }

      Text {
        visible: root.error.length > 0
        width: 300
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.error
        color: theme.red
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSize - 1
      }
    }
  }
}
