import QtQuick
import QtQuick.Controls as Controls
import org.kde.kirigami as Kirigami

Window {
    id: picker

    signal picked(int x, int y)

    function begin(targetScreen) {
        // A transient dialog is not reliably promoted to fullscreen by all
        // Wayland compositors. Use a separate modal window on the same screen
        // as the main window and explicitly activate it.
        picker.screen = targetScreen
        picker.showFullScreen()
        picker.raise()
        picker.requestActivate()
    }

    color: "#99151a20"
    flags: Qt.Window | Qt.FramelessWindowHint
    modality: Qt.ApplicationModal
    title: qsTr("Position wählen")

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
            picker.close()
        }
    }

    Shortcut {
        sequence: StandardKey.Cancel
        onActivated: picker.close()
    }
}
