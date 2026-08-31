import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Item {
    id: picker

    required property Window hostWindow
    property int previousVisibility: Window.Windowed

    signal picked(int x, int y)

    function begin() {
        if (picker.visible) {
            return
        }

        previousVisibility = hostWindow.visibility
        picker.visible = true
        hostWindow.showFullScreen()
        hostWindow.raise()
        hostWindow.requestActivate()
        picker.forceActiveFocus()
    }

    function finish() {
        picker.visible = false

        if (previousVisibility === Window.Maximized) {
            hostWindow.showMaximized()
        } else if (previousVisibility === Window.FullScreen) {
            hostWindow.showFullScreen()
        } else {
            hostWindow.showNormal()
        }
    }

    visible: false
    z: 10000
    focus: visible

    Rectangle {
        anchors.fill: parent
        color: "#e6151a20"
    }

    Rectangle {
        anchors.centerIn: parent
        width: message.implicitWidth + Kirigami.Units.gridUnit * 3
        height: message.implicitHeight + Kirigami.Units.gridUnit * 2
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.focusColor

        Controls.Label {
            id: message
            anchors.centerIn: parent
            text: qsTr("Gewünschte Position anklicken\nEsc bricht ab")
            horizontalAlignment: Text.AlignHCenter
            font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.CrossCursor
        onClicked: function(mouse) {
            picker.picked(Math.round(mouse.x), Math.round(mouse.y))
            picker.finish()
        }
    }

    Shortcut {
        enabled: picker.visible
        sequence: StandardKey.Cancel
        onActivated: picker.finish()
    }
}
